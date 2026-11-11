#!/bin/sh

set -eu

usage()
{
    cat <<EOF
Usage: $0

Clone the Pomera Linux and U-Boot branches with depth 1, or fast-forward
existing clones to their latest remote commits. Then build the shared
toolchain image and open an interactive shell with both trees mounted.
Local changes are kept; conflicting changes or diverged history stop the update.

Environment overrides:
  POMERA_LINUX_REPOSITORY  Git repository URL
  POMERA_LINUX_BRANCH      Git branch to clone/update
  POMERA_LINUX_DIR         Host directory for the Linux source tree
  POMERA_UBOOT_REPOSITORY  U-Boot Git repository URL
  POMERA_UBOOT_BRANCH      U-Boot Git branch to clone/update
  POMERA_UBOOT_DIR         Host directory for the U-Boot source tree
  POMERA_BUILD_IMAGE       Docker image tag (POMERA_KERNEL_IMAGE is retained)

The shell starts in /workspace/linux.  U-Boot is mounted at /workspace/u-boot;
change to that directory to run its build commands.  Leave the container with
exit.
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    "")
        ;;
    *)
        echo "Error: unknown argument: $1" >&2
        usage >&2
        exit 2
        ;;
esac

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY=${POMERA_LINUX_REPOSITORY:-https://github.com/ichinomoto/linux}
BRANCH=${POMERA_LINUX_BRANCH:-pomera/linux-6.18.63}
LINUX_DIR=${POMERA_LINUX_DIR:-$SCRIPT_DIR/linux}
UBOOT_REPOSITORY=${POMERA_UBOOT_REPOSITORY:-https://github.com/ichinomoto/u-boot}
UBOOT_BRANCH=${POMERA_UBOOT_BRANCH:-pomera/v2026.07}
UBOOT_DIR=${POMERA_UBOOT_DIR:-$SCRIPT_DIR/u-boot}
IMAGE_NAME=${POMERA_BUILD_IMAGE:-${POMERA_KERNEL_IMAGE:-pomera-kernel-build:trixie}}

for command in docker git; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Error: required command not found: $command" >&2
        exit 1
    fi
done

clone_or_update()
{
    name=$1
    repository=$2
    branch=$3
    directory=$4

    if [ -e "$directory" ]; then
        if [ ! -d "$directory" ]; then
            echo "Error: $name source path is not a directory: $directory" >&2
            exit 1
        fi
        if [ ! -e "$directory/.git" ] ||
           [ "$(git -C "$directory" rev-parse --is-inside-work-tree 2>/dev/null)" != true ]; then
            echo "Error: $name source directory is not a Git working tree: $directory" >&2
            exit 1
        fi
        current_branch=$(git -C "$directory" symbolic-ref --quiet --short HEAD) || {
            echo "Error: $name is in detached HEAD state; switch to $branch before updating." >&2
            exit 1
        }
        if [ "$current_branch" != "$branch" ]; then
            echo "Error: $name is on $current_branch, expected $branch; switch branches before updating." >&2
            exit 1
        fi
        origin_url=$(git -C "$directory" remote get-url origin) || {
            echo "Error: $name has no origin remote: $directory" >&2
            exit 1
        }
        if [ "$origin_url" != "$repository" ]; then
            echo "Error: $name origin differs from the configured repository; check POMERA_*_REPOSITORY." >&2
            exit 1
        fi
        echo "Updating $name from origin/$branch: $directory"
        # Keep ancestry during updates so --ff-only can check shallow clones.
        # Fetching with --depth 1 here would hide the old tip from that check.
        git -C "$directory" -c merge.autostash=false -c rebase.autoStash=false \
            pull --ff-only --no-rebase --no-tags origin "$branch" || {
            echo "Error: $name update failed; resolve the Git error above and rerun this script." >&2
            exit 1
        }
    else
        echo "Cloning $repository ($branch) into $directory"
        git clone --branch "$branch" --single-branch --depth 1 "$repository" "$directory"
    fi
}

clone_or_update Linux "$REPOSITORY" "$BRANCH" "$LINUX_DIR"
clone_or_update U-Boot "$UBOOT_REPOSITORY" "$UBOOT_BRANCH" "$UBOOT_DIR"

echo "Building Docker image: $IMAGE_NAME"
docker build --tag "$IMAGE_NAME" "$SCRIPT_DIR"

echo "Entering the kernel build environment."
echo "The host source directory is mounted at /workspace/linux."
echo "The host U-Boot directory is mounted at /workspace/u-boot."
exec docker run --rm --interactive --tty \
    --user "$(id -u):$(id -g)" \
    --env HOME=/tmp \
    --env KBUILD_BUILD_USER=builder \
    --env KBUILD_BUILD_HOST=pomera-kernel-builder \
    --hostname pomera-kernel-builder \
    --volume "$LINUX_DIR:/workspace/linux" \
    --volume "$UBOOT_DIR:/workspace/u-boot" \
    --workdir /workspace \
    "$IMAGE_NAME" \
    bash
