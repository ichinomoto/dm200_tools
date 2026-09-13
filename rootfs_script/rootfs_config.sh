#!/bin/sh
# Shared host-side configuration/helpers. Sourcing this file has no side effects.

# Git checkouts belong to the builder, but files installed into the OS must not.
# Fix only paths supplied by our overlays, preserving package/service accounts.
# Symlinks are chowned themselves; never chmod their (possibly absolute) target.
normalize_rootfs_permissions()
{
    permissions_root=$1
    shift
    chown -h 0:0 "$permissions_root" || return "$?"
    chmod 0755 "$permissions_root" || return "$?"
    for permissions_overlay in "$@"; do
        [ -d "$permissions_overlay" ] || continue
        find -H "$permissions_overlay" -exec sh -ec '
            source_root=$1
            target_root=$2
            shift 2
            for source_path in "$@"; do
                target_path=$target_root${source_path#"$source_root"}
                if [ -e "$target_path" ] || [ -L "$target_path" ]; then
                    chown -h 0:0 "$target_path"
                    if [ ! -L "$target_path" ]; then
                        chmod go-w "$target_path"
                    fi
                fi
            done
        ' sh "$permissions_overlay" "$permissions_root" {} + || return "$?"
    done
}

configure_rootfs()
{
    ARCH=${POMERA_ROOTFS_ARCH:-armhf}
    VARIANT=${POMERA_ROOTFS_VARIANT:-minbase}
    LOCALE_PACKAGES=
    LEGACY_WIRELESS_PACKAGE=,wireless-tools
    case "$DISTRO" in
        debian)
            SUITE=${REQUESTED_SUITE:-${POMERA_DEBIAN_SUITE:-trixie}}
            COMPONENTS=${POMERA_DEBIAN_COMPONENTS:-main,contrib,non-free,non-free-firmware}
            MIRROR=${POMERA_DEBIAN_MIRROR:-https://deb.debian.org/debian}
            SECURITY_MIRROR=${POMERA_DEBIAN_SECURITY_MIRROR:-https://security.debian.org/debian-security}
            ARCHIVE_KEYRING_PACKAGE=debian-archive-keyring
            TARGET_KEYRING=/usr/share/keyrings/debian-archive-keyring.gpg
            NETWORK_APPLET_PACKAGE=network-manager-applet
            DEFAULT_ROOTFS=$SCRIPT_DIR/rootfs
            ;;
        ubuntu)
            SUITE=${REQUESTED_SUITE:-${POMERA_UBUNTU_SUITE:-resolute}}
            case "$SUITE" in
                26.04|resolute) SUITE=resolute ;;
                *) echo "Error: supported Ubuntu suite: resolute (26.04)" >&2; return 2 ;;
            esac
            COMPONENTS=${POMERA_UBUNTU_COMPONENTS:-main,restricted,universe,multiverse}
            MIRROR=${POMERA_UBUNTU_MIRROR:-https://ports.ubuntu.com/ubuntu-ports}
            SECURITY_MIRROR=${POMERA_UBUNTU_SECURITY_MIRROR:-$MIRROR}
            ARCHIVE_KEYRING_PACKAGE=ubuntu-keyring
            TARGET_KEYRING=/usr/share/keyrings/ubuntu-archive-keyring.gpg
            NETWORK_APPLET_PACKAGE=network-manager-applet
            LOCALE_PACKAGES=,language-pack-ja
            # Removed from 26.04; iw/NetworkManager provide wireless control.
            LEGACY_WIRELESS_PACKAGE=
            DEFAULT_ROOTFS=$SCRIPT_DIR/rootfs-ubuntu-$SUITE
            ;;
        *) echo "Error: unsupported distribution: $DISTRO (use debian or ubuntu)" >&2; return 2 ;;
    esac
    case "$SUITE" in
        ''|*[!a-z0-9-]*) echo "Error: invalid suite: $SUITE" >&2; return 2 ;;
    esac
    if [ "$ARCH" != armhf ]; then
        echo "Error: Pomera rootfs builds require POMERA_ROOTFS_ARCH=armhf" >&2
        return 2
    fi
    KEYRING=${POMERA_ROOTFS_KEYRING:-$TARGET_KEYRING}
    ROOTFS=${ROOTFS:-$DEFAULT_ROOTFS}
    CACHE_DIR=${POMERA_ROOTFS_CACHE_DIR:-$SCRIPT_DIR/cache/$DISTRO-$SUITE-$ARCH}
    BASE_PACKAGES="apt-utils,ca-certificates,$ARCHIVE_KEYRING_PACKAGE,systemd,systemd-resolved,systemd-timesyncd,dbus,systemd-sysv,udev,kmod,passwd"
    NETWORK_PACKAGES="cifs-utils,keyutils,netbase,iproute2,bind9-dnsutils,net-tools,isc-dhcp-client,openssh-server,iputils-ping,wget,network-manager"
    WIRELESS_PACKAGES="bluetooth,iw,rfkill,wireless-regdb,wpasupplicant$LEGACY_WIRELESS_PACKAGE"
    CONSOLE_PACKAGES="console-setup,sudo,psmisc,locales,keyboard-configuration,dialog,parted,gdisk,e2fsprogs,util-linux,bsdutils,less,lv,unar,evtest,fbset,i2c-tools"
    JAPANESE_PACKAGES="fbterm,fbi,screen,tmux,fontconfig,fonts-unifont,fonts-vlgothic,fonts-ricty-diminished,fonts-noto-cjk-extra"
    INPUT_PACKAGES="keyd,uim-mozc,uim-fep$LOCALE_PACKAGES"
    # pipewire-audio depends on the Bluetooth/ALSA plugins, PulseAudio-compatible
    # server and WirePlumber even with --no-install-recommends.  Keep audio and the
    # user session bus available on the local console as well as under Xfce.
    AUDIO_PACKAGES="alsa-utils,pipewire-audio,pulseaudio-utils,dbus-user-session"
    UTILITY_PACKAGES="man-db,python3,vim-tiny,emacs-nox,unzip,bzip2,libcap2-bin"
    PACKAGE="$BASE_PACKAGES,$NETWORK_PACKAGES,$WIRELESS_PACKAGES,$CONSOLE_PACKAGES,$JAPANESE_PACKAGES,$INPUT_PACKAGES,$AUDIO_PACKAGES,$UTILITY_PACKAGES"

    if [ "$ENABLE_X" -eq 1 ]; then
        # Keep the desktop and its applets together: debootstrap does not install
        # Recommends, and --no-x must not pull these GUI packages into the rootfs.
        X_PACKAGES="xorg,vim-gtk3,emacs,netsurf-gtk,gir1.2-freedesktop"
        XFCE_PACKAGES="xfce4,dbus-x11,gvfs,xfce4-power-manager,xfce4-terminal"
        XFCE_PACKAGES="$XFCE_PACKAGES,xfce4-power-manager-plugins,$NETWORK_APPLET_PACKAGE,blueman,xfce4-notifyd"
        XFCE_PACKAGES="$XFCE_PACKAGES,polkitd,lxpolkit,thunar-volman"
        XFCE_PACKAGES="$XFCE_PACKAGES,pavucontrol,xfce4-pulseaudio-plugin"
        X_INPUT_PACKAGES="ibus-mozc,libglib2.0-bin"
        PACKAGE="$PACKAGE,$X_PACKAGES,$XFCE_PACKAGES,$X_INPUT_PACKAGES"
    fi

}

# Run after debootstrap stage 2, BEFORE the first apt-get update/install.
# The base system already contains the matching archive keyring and TLS roots.
write_rootfs_sources()
{
    target=$1
    apt_components=$(printf '%s' "$COMPONENTS" | tr ',' ' ')
    mkdir -p "$target/etc/apt/sources.list.d"
    rm -f "$target/etc/apt/sources.list.d/debian.sources" \
        "$target/etc/apt/sources.list.d/ubuntu.sources"
    cat > "$target/etc/apt/sources.list" <<EOF
deb [signed-by=$TARGET_KEYRING] $MIRROR $SUITE $apt_components
deb [signed-by=$TARGET_KEYRING] $MIRROR ${SUITE}-updates $apt_components
deb [signed-by=$TARGET_KEYRING] $SECURITY_MIRROR ${SUITE}-security $apt_components
EOF
}
