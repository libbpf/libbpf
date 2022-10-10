#!/bin/bash
# This script builds a Debian root filesystem image for testing libbpf in a
# virtual machine. Requires debootstrap >= 1.0.95 and zstd.

# Use e.g. ./mkrootfs_debian.sh --arch=s390x to generate a rootfs for a
# foreign architecture. Requires configured binfmt_misc, e.g. using
# Debian/Ubuntu's qemu-user-binfmt package or
# https://github.com/multiarch/qemu-user-static.
# Any arguments that need to be passed to `debootstrap` should be passed after
# `--`, e.g ./mkrootfs_debian.sh --arch=s390x -- --foo=bar

set -e -u -x -o pipefail

# Check whether we are root now in order to avoid confusing errors later.
if [ "$(id -u)" != 0 ]; then
	echo "$0 must run as root" >&2
	exit 1
fi

function usage() {
    echo "Usage: $0 [-a | --arch architecture] [-h | --help]

Build a Debian chroot filesystem image for testing libbbpf in a virtual machine.
By default build an image for the architecture of the host running the script.

    -a | --arch:    architecture to build the image for. Default (amd64)
"
}

arch="amd64"

TEMP=$(getopt  -l "arch:,help" -o "a:h" -- "$@")
if [ $? -ne 0 ]; then
    usage
fi

eval set -- "${TEMP}"
unset TEMP

while true; do
    case "$1" in
        --arch | -a )
            arch="$2"
            shift 2
            ;;
        --help | -h)
            usage
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

# Create a working directory and schedule its deletion.
root=$(mktemp -d -p "$PWD")
trap 'rm -r "$root"' EXIT

# Install packages.
packages=(
	binutils
	busybox
	elfutils
	ethtool
	iproute2
	iptables
	libcap2
	libelf1
	strace
	zlib1g
)
packages=$(IFS=, && echo "${packages[*]}")
debootstrap --include="$packages" --variant=minbase --arch="${arch}" "$@" bookworm "$root"

# Remove the init scripts (tests use their own). Also remove various
# unnecessary files in order to save space.
rm -rf \
	"$root"/etc/rcS.d \
	"$root"/usr/share/{doc,info,locale,man,zoneinfo} \
	"$root"/var/cache/apt/archives/* \
	"$root"/var/lib/apt/lists/*

# Apply common tweaks.
"$(dirname "$0")"/mkrootfs_tweak.sh "$root"

# Save the result.
name="libbpf-vmtest-rootfs-$(date +%Y.%m.%d).tar.zst"
rm -f "$name"
tar -C "$root" -c . | zstd -T0 -19 -o "$name"
