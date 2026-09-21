#!/bin/sh

# Create the interactive Pomera user on the first real boot.
# getty@tty1 runs this before agetty, after platform setup has finished.

set -eu

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C

STATE_DIR=/var/lib/pomera
DONE=$STATE_DIR/user-firstboot.done
PENDING_USER=$STATE_DIR/user-firstboot.user
DEFAULT_USER=pomera

fail()
{
	printf '%s\n' "pomera-user-firstboot: ERROR: $*" >&2
	exit 1
}

valid_username()
{
	case "$1" in
		''|root|[!a-z_]*|*[!a-z0-9_-]*) return 1 ;;
	esac
	return 0
}

[ "$(id -u)" -eq 0 ] || fail "must run as root"
mkdir -p "$STATE_DIR" || fail "cannot create $STATE_DIR"

if [ -e "$DONE" ]; then
	printf '%s\n' "pomera-user-firstboot: already completed"
	exit 0
fi

# Use the TTY already owned by getty, rather than opening another console.
# Firmware or earlier console tools can leave noncanonical input/VMIN=0 behind.
# Restore line editing and translate Enter (CR) to newline before reading.
[ -t 0 ] || fail "an interactive terminal is required"

# After= orders the initial attempt only. The platform service may need to
# retry (for example when timedated/RTC is not ready yet). Keep this getty job
# alive without reading input or starting agetty until setup really succeeds.
if [ ! -e "$STATE_DIR/platform-firstboot.done" ]; then
	printf '%s\n' 'Waiting for platform setup to complete (automatic retry)...'
	while [ ! -e "$STATE_DIR/platform-firstboot.done" ]; do
		sleep 1
	done
fi

stty sane icanon icrnl || fail "cannot initialize terminal input"
printf '\n%s\n' 'Pomera first-boot user setup'
printf '%s\n' 'Enter a user name and press Enter to confirm.'

if [ -r "$PENDING_USER" ]; then
	USER_NAME=$(cat "$PENDING_USER")
	valid_username "$USER_NAME" || fail "the pending username is invalid"
	id "$USER_NAME" >/dev/null 2>&1 || fail "the pending user does not exist: $USER_NAME"
else
	while :; do
		printf 'User name [%s]: ' "$DEFAULT_USER"
		IFS= read -r USER_NAME || fail "could not read the username"
		[ -n "$USER_NAME" ] || USER_NAME=$DEFAULT_USER
		if ! valid_username "$USER_NAME"; then
			printf '%s\n' 'Use a lowercase username starting with a letter or underscore.'
			continue
		fi
		if id "$USER_NAME" >/dev/null 2>&1; then
			printf 'The user %s already exists; choose another name.\n' "$USER_NAME"
			continue
		fi
		break
	done

	USER_GROUPS=
	for group in sudo video lp audio input netdev; do
		if grep -q "^${group}:" /etc/group; then
			if [ -n "$USER_GROUPS" ]; then
				USER_GROUPS="$USER_GROUPS,$group"
			else
				USER_GROUPS=$group
			fi
		fi
	done
	if [ -n "$USER_GROUPS" ]; then
		printf '%s\n' "$USER_NAME" > "$PENDING_USER" || fail "could not save the pending username"
		useradd -d "/home/$USER_NAME" -m -k /etc/skel -s /bin/bash \
			-G "$USER_GROUPS" "$USER_NAME" || { rm -f "$PENDING_USER"; fail "could not create $USER_NAME"; }
	else
		printf '%s\n' "$USER_NAME" > "$PENDING_USER" || fail "could not save the pending username"
		useradd -d "/home/$USER_NAME" -m -k /etc/skel -s /bin/bash \
			"$USER_NAME" || { rm -f "$PENDING_USER"; fail "could not create $USER_NAME"; }
	fi
fi

printf 'Set password for %s.\n' "$USER_NAME"
while :; do
	stty sane icanon icrnl || fail "cannot initialize terminal input"
	if passwd "$USER_NAME"; then
		break
	fi
	printf '%s\n' 'Password was not set. Please try again.'
done
stty sane icanon icrnl || fail "cannot restore terminal input"

PRIMARY_GROUP=$(id -gn "$USER_NAME")
HOME_DIR=/home/$USER_NAME
install -d -m 0700 -o "$USER_NAME" -g "$PRIMARY_GROUP" "$HOME_DIR/.config"
if [ ! -f "$HOME_DIR/.bashrc" ]; then
	: > "$HOME_DIR/.bashrc"
fi
if ! grep -q '^alias fbterm=' "$HOME_DIR/.bashrc"; then
	cat >> "$HOME_DIR/.bashrc" <<'EOBASH'

alias fbterm="LANG=ja_JP.UTF-8 fbterm -- uim-fep"

# To launch FbTerm automatically on a virtual console, uncomment this block.
#case "$TERM" in
#  linux*)
#    LANG=ja_JP.UTF-8 fbterm -- uim-fep
#    ;;
#esac
EOBASH
fi
chown -R "$USER_NAME:$PRIMARY_GROUP" "$HOME_DIR"
passwd -l root >/dev/null 2>&1 || true

DONE_TMP=$DONE.$$
trap 'rm -f "$DONE_TMP"' EXIT HUP INT TERM
: > "$DONE_TMP" || fail "cannot create the completion marker"
mv -f "$DONE_TMP" "$DONE" || fail "cannot install the completion marker"
rm -f "$PENDING_USER"
trap - EXIT HUP INT TERM
sync
printf 'pomera-user-firstboot: created %s\n' "$USER_NAME"
