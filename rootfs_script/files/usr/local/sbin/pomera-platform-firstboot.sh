#!/bin/sh

# One-time DM200 platform setup from the real root filesystem.
# The partition table is changed on the first boot.  After one reboot,
# resize2fs and swap setup complete first, then the RTC mode is configured.

set -u

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C

ROOT_DISK=/dev/mmcblk1
ROOT_PARTITION=/dev/mmcblk1p2
SWAP_PARTITION=/dev/mmcblk1p3
STATE_DIR=/var/lib/pomera
PENDING=$STATE_DIR/platform-firstboot.pending
STORAGE_DONE=$STATE_DIR/platform-storage.done
DONE=$STATE_DIR/platform-firstboot.done
BOOT_ID_FILE=/proc/sys/kernel/random/boot_id
SWAP_SIZE=1GiB
SWAP_SECTORS=2097152

log()
{
	printf '%s\n' "pomera-platform-firstboot: $*"
}

fail()
{
	log "ERROR: $*"
	exit 1
}

save_marker()
{
	MARKER_TMP=$1.$$
	trap 'rm -f "$MARKER_TMP"' EXIT HUP INT TERM
	: > "$MARKER_TMP" || fail "cannot create marker: $1"
	mv -f "$MARKER_TMP" "$1" || fail "cannot install marker: $1"
	trap - EXIT HUP INT TERM
}

read_partition_table()
{
	parted -m -s "$ROOT_DISK" unit s print
}

partition_row()
{
	number=$1
	printf '%s\n' "$PARTITION_TABLE" |
		awk -F: -v number="$number" '$1 == number { print; exit }'
}

partition_field()
{
	number=$1
	field=$2
	printf '%s\n' "$PARTITION_TABLE" |
		awk -F: -v number="$number" -v field="$field" \
			'$1 == number { value = $field; sub(/s$/, "", value); print value; exit }'
}

disk_sector_count()
{
	printf '%s\n' "$PARTITION_TABLE" |
		awk -F: 'NR == 2 { value = $2; sub(/s$/, "", value); print value; exit }'
}

require_number()
{
	name=$1
	value=$2
	case "$value" in
		''|*[!0-9]*) fail "$name is missing or invalid" ;;
	esac
}

request_reboot()
{
	sync
	log "rebooting to reload the SD partition table"
	reboot || fail "reboot request failed"
	exit 0
}

for command_name in parted script resize2fs mkswap swapon swapoff awk reboot timedatectl; do
	command -v "$command_name" >/dev/null 2>&1 ||
		fail "required command is unavailable: $command_name"
done

install_swap_fstab()
{
	if ! grep -q '^[[:space:]]*/dev/mmcblk1p3[[:space:]]' /etc/fstab 2>/dev/null; then
		printf '%s\n' '/dev/mmcblk1p3  none            swap    sw,nofail                                  0   0' >> /etc/fstab ||
			fail "cannot add p3 swap to /etc/fstab"
	fi
}

[ -b "$ROOT_DISK" ] || fail "$ROOT_DISK is unavailable"
[ -b "$ROOT_PARTITION" ] || fail "$ROOT_PARTITION is unavailable"
[ -r "$BOOT_ID_FILE" ] || fail "cannot read $BOOT_ID_FILE"

mkdir -p "$STATE_DIR" || fail "cannot create $STATE_DIR"

if [ -e "$DONE" ]; then
	log "already completed"
	exit 0
fi

CURRENT_BOOT_ID=$(cat "$BOOT_ID_FILE")
[ -n "$CURRENT_BOOT_ID" ] || fail "the current boot ID is empty"

# The second phase runs only after the kernel has reread the new table during
# a reboot.  The boot ID prevents a service retry in the same boot from
# treating the old kernel partition size as current.
if [ -e "$PENDING" ]; then
	PARTITIONING_BOOT_ID=$(cat "$PENDING" 2>/dev/null || true)
	if [ -z "$PARTITIONING_BOOT_ID" ] ||
	   [ "$PARTITIONING_BOOT_ID" = "$CURRENT_BOOT_ID" ]; then
		request_reboot
	fi

	[ -b "$SWAP_PARTITION" ] || fail "$SWAP_PARTITION is unavailable"
	PARTITION_TABLE=$(read_partition_table) || fail "cannot read the partition table"
	P2_END=$(partition_field 2 3)
	P3_START=$(partition_field 3 2)
	P3_END=$(partition_field 3 3)
	P3_SIZE=$(partition_field 3 4)
	DISK_SECTORS=$(disk_sector_count)
	require_number "p2 end" "$P2_END"
	require_number "p3 start" "$P3_START"
	require_number "p3 end" "$P3_END"
	require_number "p3 size" "$P3_SIZE"
	require_number "disk sector count" "$DISK_SECTORS"
	[ $((P2_END + 1)) -eq "$P3_START" ] || fail "p2 is not adjacent to p3"
	[ "$P3_SIZE" -eq "$SWAP_SECTORS" ] || fail "p3 is not exactly $SWAP_SIZE"
	[ "$P3_END" -eq $((DISK_SECTORS - 1)) ] || fail "p3 does not end at the SD-card end"

	if [ ! -e "$STORAGE_DONE" ]; then
		log "growing the mounted p2 ext4 filesystem"
		resize2fs "$ROOT_PARTITION" || fail "resize2fs failed"
		swapoff "$SWAP_PARTITION" >/dev/null 2>&1 || true
		log "initializing and enabling p3 swap"
		mkswap "$SWAP_PARTITION" || fail "mkswap failed"
		swapon "$SWAP_PARTITION" || fail "swapon failed"
		install_swap_fstab
		# A later RTC failure must not reformat an already configured swap.
		save_marker "$STORAGE_DONE"
		sync
	fi

	# RTC setup is deliberately last.  It is persistent and is performed only
	# after partition expansion, filesystem growth, and swap setup all succeed.
	log "configuring the DM200 hardware clock as local time"
	timedatectl set-local-rtc 1 || fail "RTC configuration failed"

	# The tty1 getty runs user setup only after this marker is installed.
	# Retrying password entry must not repeat partition/swap initialization.
	save_marker "$DONE"
	rm -f "$PENDING" "$STORAGE_DONE"
	sync
	log "platform firstboot completed; later boots will skip it"
	exit 0
fi

# First phase: change only p2 and disposable p3.  p1 is recorded solely to
# prove that it remains identical; no mutating parted command refers to p1.
rm -f "$STORAGE_DONE" || fail "cannot clear the old storage marker"
PARTITION_TABLE=$(read_partition_table) || fail "cannot read the partition table"
P1_BEFORE=$(partition_row 1)
P2_START=$(partition_field 2 2)
P2_OLD_END=$(partition_field 2 3)
HAS_P3=$(partition_row 3)
[ -n "$P1_BEFORE" ] || fail "p1 is missing"
require_number "p2 start" "$P2_START"
require_number "p2 end" "$P2_OLD_END"

if [ -n "$HAS_P3" ]; then
	log "removing the existing p3"
	swapoff "$SWAP_PARTITION" >/dev/null 2>&1 || true
	parted -s "$ROOT_DISK" -- rm 3 || true
	PARTITION_TABLE=$(read_partition_table) ||
		fail "cannot reread the partition table after removing p3"
	[ -z "$(partition_row 3)" ] || fail "p3 still exists after parted rm 3"
fi

log "reserving the final $SWAP_SIZE as p3"
parted -s -a optimal "$ROOT_DISK" -- \
	mkpart primary linux-swap "-$SWAP_SIZE" 100% || true

PARTITION_TABLE=$(read_partition_table) || fail "cannot reread the partition table"
P3_START=$(partition_field 3 2)
P3_END=$(partition_field 3 3)
P3_SIZE=$(partition_field 3 4)
DISK_SECTORS=$(disk_sector_count)
require_number "new p3 start" "$P3_START"
require_number "new p3 end" "$P3_END"
require_number "new p3 size" "$P3_SIZE"
require_number "disk sector count" "$DISK_SECTORS"
[ "$P3_SIZE" -eq "$SWAP_SECTORS" ] || fail "p3 is not exactly $SWAP_SIZE"
[ "$P3_END" -eq $((DISK_SECTORS - 1)) ] || fail "p3 does not end at the SD-card end"

P2_END=$((P3_START - 1))
[ "$P2_END" -gt "$P2_START" ] || fail "the SD card is too small"
[ "$P2_OLD_END" -le "$P2_END" ] ||
	fail "p2 would have to shrink to reserve $SWAP_SIZE"

if [ "$P2_OLD_END" -lt "$P2_END" ]; then
	log "expanding p2 through sector $P2_END"
	# Parted 3.6 asks for confirmation because p2 is mounted.  Give it a
	# pseudo-terminal, approve only the requested growth, and ignore the
	# expected failure to notify the running kernel.  The on-disk table is
	# verified below and is not used until after reboot.
	printf 'Yes\nIgnore\nIgnore\nIgnore\n' |
		script -q -e -E never -c \
			"parted $ROOT_DISK resizepart 2 ${P2_END}s" /dev/null || true
fi

PARTITION_TABLE=$(read_partition_table) || fail "cannot verify the updated table"
P1_AFTER=$(partition_row 1)
ACTUAL_P2_END=$(partition_field 2 3)
ACTUAL_P3_START=$(partition_field 3 2)
[ "$P1_AFTER" = "$P1_BEFORE" ] || fail "p1 changed unexpectedly"
[ "$ACTUAL_P2_END" = "$P2_END" ] || fail "p2 did not reach the p3 boundary"
[ "$ACTUAL_P3_START" = "$P3_START" ] || fail "p3 start changed unexpectedly"

printf '%s\n' "$CURRENT_BOOT_ID" > "$PENDING" || fail "cannot create the pending marker"
request_reboot
