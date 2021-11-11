#!/bin/bash
# This script builds a Debian root filesystem image for testing libbpf in a
# virtual machine. Requires debootstrap >= 1.0.95 and zstd.

set -e -u -x -o pipefail

# Check whether we are root now in order to avoid confusing errors later.
if [ "$(id -u)" != 0 ]; then
	echo "$0 must run as root" >&2
	exit 1
fi

# Create a working directory and schedule its deletion.
root=$(mktemp -d -p "$PWD")
trap 'rm -r "$root"' EXIT

# Install packages.
packages=binutils,busybox,elfutils,iproute2,libcap2,libelf1,strace,zlib1g
debootstrap --include="$packages" --variant=minbase bullseye "$root"

# Remove the init scripts (tests use their own). Also remove various
# unnecessary files in order to save space.
rm -rf \
	"$root"/etc/rcS.d \
	"$root"/usr/share/{doc,info,locale,man,zoneinfo} \
	"$root"/var/cache/apt/archives/* \
	"$root"/var/lib/apt/lists/*

# Save some more space by removing coreutils - the tests use busybox. Before
# doing that, delete the buggy postrm script, which uses the rm command.
rm -f "$root/var/lib/dpkg/info/coreutils.postrm"
chroot "$root" dpkg --remove --force-remove-essential coreutils

# Apply common tweaks.
"$(dirname "$0")"/mkrootfs_tweak.sh "$root"

# Save the result.
name="libbpf-vmtest-rootfs-$(date +%Y.%m.%d).tar.zst"
rm -f "$name"
tar -C "$root" -c . | zstd -T0 -19 -o "$name"
