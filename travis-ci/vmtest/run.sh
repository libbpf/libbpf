#!/bin/bash

set -uo pipefail
trap 'exit 2' ERR

source $(cd $(dirname $0) && pwd)/helpers.sh

usage () {
	USAGE_STRING="usage: $0 [-k KERNELRELEASE|-b DIR] [[-r ROOTFSVERSION] [-fo]|-I] [-Si] [-d DIR] IMG
       $0 [-k KERNELRELEASE] -l
       $0 -h

Run "${PROJECT_NAME}" tests in a virtual machine.

This exits with status 0 on success, 1 if the virtual machine ran successfully
but tests failed, and 2 if we encountered a fatal error.

This script uses sudo to work around a libguestfs bug.

Arguments:
  IMG                 path of virtual machine disk image to create

Versions:
  -k, --kernel=KERNELRELEASE
                       kernel release to test. This is a glob pattern; the
                       newest (sorted by version number) release that matches
                       the pattern is used (default: newest available release)

  -b, --build DIR      use the kernel built in the given directory. This option
                       cannot be combined with -k

  -r, --rootfs=ROOTFSVERSION
                       version of root filesystem to use (default: newest
                       available version)

Setup:
  -f, --force          overwrite IMG if it already exists

  -o, --one-shot       one-shot mode. By default, this script saves a clean copy
                       of the downloaded root filesystem image and vmlinux and
                       makes a copy (reflinked, when possible) for executing the
                       virtual machine. This allows subsequent runs to skip
                       downloading these files. If this option is given, the
                       root filesystem image and vmlinux are always
                       re-downloaded and are not saved. This option implies -f

  -s, --setup-cmd      setup commands run on VM boot. Whitespace characters
                       should be escaped with preceding '\'.

  -I, --skip-image     skip creating the disk image; use the existing one at
                       IMG. This option cannot be combined with -r, -f, or -o

  -S, --skip-source    skip copying the source files and init scripts

Miscellaneous:
  -i, --interactive    interactive mode. Boot the virtual machine into an
                       interactive shell instead of automatically running tests

  -d, --dir=DIR        working directory to use for downloading and caching
                       files (default: current working directory)

  -l, --list           list available kernel releases instead of running tests.
                       The list may be filtered with -k

  -h, --help           display this help message and exit"

	case "$1" in
		out)
			echo "$USAGE_STRING"
			exit 0
			;;
		err)
			echo "$USAGE_STRING" >&2
			exit 2
			;;
	esac
}

TEMP=$(getopt -o 'k:b:r:fos:ISid:lh' --long 'kernel:,build:,rootfs:,force,one-shot,setup-cmd,skip-image,skip-source:,interactive,dir:,list,help' -n "$0" -- "$@")
eval set -- "$TEMP"
unset TEMP

unset KERNELRELEASE
unset BUILDDIR
unset ROOTFSVERSION
unset IMG
unset SETUPCMD
FORCE=0
ONESHOT=0
SKIPIMG=0
SKIPSOURCE=0
APPEND=""
DIR="$PWD"
LIST=0

# by default will copy all files that aren't listed in git exclusions
# but it doesn't work for entire kernel tree very well
# so for full kernel tree you may need to SOURCE_FULLCOPY=0
SOURCE_FULLCOPY=${SOURCE_FULLCOPY:-1}

while true; do
	case "$1" in
		-k|--kernel)
			KERNELRELEASE="$2"
			shift 2
			;;
		-b|--build)
			BUILDDIR="$2"
			shift 2
			;;
		-r|--rootfs)
			ROOTFSVERSION="$2"
			shift 2
			;;
		-f|--force)
			FORCE=1
			shift
			;;
		-o|--one-shot)
			ONESHOT=1
			FORCE=1
			shift
			;;
		-s|--setup-cmd)
			SETUPCMD="$2"
			shift 2
			;;
		-I|--skip-image)
			SKIPIMG=1
			shift
			;;
		-S|--skip-source)
			SKIPSOURCE=1
			shift
			;;
		-i|--interactive)
			APPEND=" single"
			shift
			;;
		-d|--dir)
			DIR="$2"
			shift 2
			;;
		-l|--list)
			LIST=1
			;;
		-h|--help)
			usage out
			;;
		--)
			shift
			break
			;;
		*)
			usage err
			;;
	esac
done
if [[ -v BUILDDIR ]]; then
	if [[ -v KERNELRELEASE ]]; then
		usage err
	fi
elif [[ ! -v KERNELRELEASE ]]; then
	KERNELRELEASE='*'
fi
if [[ $SKIPIMG -ne 0 && ( -v ROOTFSVERSION || $FORCE -ne 0 ) ]]; then
	usage err
fi
if (( LIST )); then
	if [[ $# -ne 0 || -v BUILDDIR || -v ROOTFSVERSION || $FORCE -ne 0 ||
	      $SKIPIMG -ne 0 || $SKIPSOURCE -ne 0 || -n $APPEND ]]; then
		usage err
	fi
else
	if [[ $# -ne 1 ]]; then
		usage err
	fi
	IMG="${!OPTIND}"
fi
if [[ "${SOURCE_FULLCOPY}" == "1" ]]; then
	img_size=2G
else
	img_size=8G
fi

unset URLS
cache_urls() {
	if ! declare -p URLS &> /dev/null; then
		# This URL contains a mapping from file names to URLs where
		# those files can be downloaded.
		declare -gA URLS
		while IFS=$'\t' read -r name url; do
			URLS["$name"]="$url"
		done < <(cat "${VMTEST_ROOT}/configs/INDEX")
	fi
}

matching_kernel_releases() {
	local pattern="$1"
	{
	for file in "${!URLS[@]}"; do
		if [[ $file =~ ^${ARCH}/vmlinux-(.*).zst$ ]]; then
			release="${BASH_REMATCH[1]}"
			case "$release" in
				$pattern)
					# sort -V handles rc versions properly
					# if we use "~" instead of "-".
					echo "${release//-rc/~rc}"
					;;
			esac
		fi
	done
	} | sort -rV | sed 's/~rc/-rc/g'
}

newest_rootfs_version() {
	{
	for file in "${!URLS[@]}"; do
		if [[ $file =~ ^${ARCH}/${PROJECT_NAME}-vmtest-rootfs-(.*)\.tar\.zst$ ]]; then
			echo "${BASH_REMATCH[1]}"
		fi
	done
	} | sort -rV | head -1
}

download() {
	local file="$1"
	cache_urls
	if [[ ! -v URLS[$file] ]]; then
		echo "$file not found" >&2
		return 1
	fi
	echo "Downloading $file..." >&2
	curl -Lf "${URLS[$file]}" "${@:2}"
}

set_nocow() {
	touch "$@"
	chattr +C "$@" >/dev/null 2>&1 || true
}

cp_img() {
	set_nocow "$2"
	cp --reflink=auto "$1" "$2"
}

create_rootfs_img() {
	local path="$1"
	set_nocow "$path"
	truncate -s "$img_size" "$path"
	mkfs.ext4 -q "$path"
}

download_rootfs() {
	local rootfsversion="$1"
	download "${ARCH}/${PROJECT_NAME}-vmtest-rootfs-$rootfsversion.tar.zst" |
		zstd -d
}

tar_in() {
	local dst_path="$1"
	# guestfish --remote does not forward file descriptors, which prevents
	# us from using `tar-in -` or bash process substitution. We don't want
	# to copy all the data into a temporary file, so use a FIFO.
	tmp=$(mktemp -d)
	mkfifo "$tmp/fifo"
	cat >"$tmp/fifo" &
	local cat_pid=$!
	guestfish --remote tar-in "$tmp/fifo" "$dst_path"
	wait "$cat_pid"
	rm -r "$tmp"
	tmp=
}

if (( LIST )); then
	cache_urls
	matching_kernel_releases "$KERNELRELEASE"
	exit 0
fi

if [[ $FORCE -eq 0 && $SKIPIMG -eq 0 && -e $IMG ]]; then
	echo "$IMG already exists; use -f to overwrite it or -I to reuse it" >&2
	exit 1
fi

# Only go to the network if it's actually a glob pattern.
if [[ -v BUILDDIR ]]; then
	KERNELRELEASE="$(make -C "$BUILDDIR" -s kernelrelease)"
elif [[ ! $KERNELRELEASE =~ ^([^\\*?[]|\\[*?[])*\\?$ ]]; then
	# We need to cache the list of URLs outside of the command
	# substitution, which happens in a subshell.
	cache_urls
	KERNELRELEASE="$(matching_kernel_releases "$KERNELRELEASE" | head -1)"
	if [[ -z $KERNELRELEASE ]]; then
		echo "No matching kernel release found" >&2
		exit 1
	fi
fi
if [[ $SKIPIMG -eq 0 && ! -v ROOTFSVERSION ]]; then
	cache_urls
	ROOTFSVERSION="$(newest_rootfs_version)"
fi

echo "Kernel release: $KERNELRELEASE" >&2
echo

travis_fold start vmlinux_setup "Preparing Linux image"

if (( SKIPIMG )); then
	echo "Not extracting root filesystem" >&2
else
	echo "Root filesystem version: $ROOTFSVERSION" >&2
fi
echo "Disk image: $IMG" >&2

tmp=
ARCH_DIR="$DIR/$ARCH"
mkdir -p "$ARCH_DIR"

cleanup() {
	if [[ -n $tmp ]]; then
		rm -rf "$tmp" || true
	fi
	guestfish --remote exit 2>/dev/null || true
}
trap cleanup EXIT

if [[ -v BUILDDIR ]]; then
	vmlinuz="$BUILDDIR/$(make -C "$BUILDDIR" -s image_name)"
else
	vmlinuz="${ARCH_DIR}/vmlinuz-${KERNELRELEASE}"
	if [[ ! -e $vmlinuz ]]; then
		tmp="$(mktemp "$vmlinuz.XXX.part")"
		download "${ARCH}/vmlinuz-${KERNELRELEASE}" -o "$tmp"
		mv "$tmp" "$vmlinuz"
		tmp=
	fi
fi

# Mount and set up the rootfs image. Use a persistent guestfish session in
# order to avoid the startup overhead.
# Work around https://bugs.launchpad.net/fuel/+bug/1467579.
sudo chmod +r /boot/vmlinuz*
eval "$(guestfish --listen)"
if (( ONESHOT )); then
	rm -f "$IMG"
	create_rootfs_img "$IMG"
	guestfish --remote \
		add "$IMG" label:img : \
		launch : \
		mount /dev/disk/guestfs/img /
	download_rootfs "$ROOTFSVERSION" | tar_in /
else
	if (( ! SKIPIMG )); then
		rootfs_img="${ARCH_DIR}/${PROJECT_NAME}-vmtest-rootfs-${ROOTFSVERSION}.img"

		if [[ ! -e $rootfs_img ]]; then
			tmp="$(mktemp "$rootfs_img.XXX.part")"
			set_nocow "$tmp"
			truncate -s "$img_size" "$tmp"
			mkfs.ext4 -q "$tmp"

			# libguestfs supports hotplugging only with a libvirt
			# backend, which we are not using here, so handle the
			# temporary image in a separate session.
			download_rootfs "$ROOTFSVERSION" |
				guestfish -a "$tmp" tar-in - /

			mv "$tmp" "$rootfs_img"
			tmp=
		fi

		rm -f "$IMG"
		cp_img "$rootfs_img" "$IMG"
	fi
	guestfish --remote \
		add "$IMG" label:img : \
		launch : \
		mount /dev/disk/guestfs/img /
fi

# Install vmlinux.
vmlinux="/boot/vmlinux-${KERNELRELEASE}"
if [[ -v BUILDDIR || $ONESHOT -eq 0 ]]; then
	if [[ -v BUILDDIR ]]; then
		source_vmlinux="${BUILDDIR}/vmlinux"
	else
		source_vmlinux="${ARCH_DIR}/vmlinux-${KERNELRELEASE}"
		if [[ ! -e $source_vmlinux ]]; then
			tmp="$(mktemp "$source_vmlinux.XXX.part")"
			download "${ARCH}/vmlinux-${KERNELRELEASE}.zst" | zstd -dfo "$tmp"
			mv "$tmp" "$source_vmlinux"
			tmp=
		fi
	fi
else
	source_vmlinux="${ARCH_DIR}/vmlinux-${KERNELRELEASE}"
	download "${ARCH}/vmlinux-${KERNELRELEASE}.zst" | zstd -d >"$source_vmlinux"
fi
echo "Copying vmlinux..." >&2
guestfish --remote \
	upload "$source_vmlinux" "$vmlinux" : \
	chmod 644 "$vmlinux"

travis_fold end vmlinux_setup

REPO_PATH="${SELFTEST_REPO_PATH:-travis-ci/vmtest/bpf-next}"
LIBBPF_PATH="${REPO_ROOT}" \
	VMTEST_ROOT="${VMTEST_ROOT}" \
	REPO_PATH="${REPO_PATH}" \
	VMLINUX_BTF=$(realpath ${source_vmlinux}) ${VMTEST_ROOT}/build_selftests.sh

declare -A test_results

travis_fold start bpftool_checks "Running bpftool checks..."
if [[ "${KERNEL}" = 'LATEST' ]]; then
	# "&& true" does not change the return code (it is not executed if the
	# Python script fails), but it prevents the trap on ERR set at the top
	# of this file to trigger on failure.
	"${REPO_ROOT}/${REPO_PATH}/tools/testing/selftests/bpf/test_bpftool_synctypes.py" && true
	test_results["bpftool"]=$?
	if [[ ${test_results["bpftool"]} -eq 0 ]]; then
		echo "::notice title=bpftool_checks::bpftool checks passed successfully."
	else
		echo "::error title=bpftool_checks::bpftool checks returned ${test_results["bpftool"]}."
	fi
else
	echo "Consistency checks skipped."
fi
travis_fold end bpftool_checks

travis_fold start vm_init "Starting virtual machine..."

if (( SKIPSOURCE )); then
	echo "Not copying source files..." >&2
else
	echo "Copying source files..." >&2
	# Copy the source files in.
	guestfish --remote \
		mkdir-p "/${PROJECT_NAME}" : \
		chmod 0755 "/${PROJECT_NAME}"
	if [[ "${SOURCE_FULLCOPY}" == "1" ]]; then
		git ls-files -z | tar --null --files-from=- -c | tar_in "/${PROJECT_NAME}"
	else
		guestfish --remote \
			mkdir-p "/${PROJECT_NAME}/selftests" : \
			chmod 0755 "/${PROJECT_NAME}/selftests" : \
			mkdir-p "/${PROJECT_NAME}/travis-ci" : \
			chmod 0755 "/${PROJECT_NAME}/travis-ci"
		tree --du -shaC "${REPO_ROOT}/selftests/bpf"
		tar -C "${REPO_ROOT}/selftests" -c bpf | tar_in "/${PROJECT_NAME}/selftests"
		tar -C "${REPO_ROOT}/travis-ci" -c vmtest | tar_in "/${PROJECT_NAME}/travis-ci"
	fi
fi

tmp=$(mktemp)
cat <<HERE >"$tmp"
"#!/bin/sh

echo 'Skipping setup commands'
echo 0 > /exitstatus
chmod 644 /exitstatus
HERE

# Create the init scripts.
if [[ ! -z SETUPCMD ]]; then
	# Unescape whitespace characters.
	setup_cmd=$(sed 's/\(\\\)\([[:space:]]\)/\2/g' <<< "${SETUPCMD}")
	kernel="${KERNELRELEASE}"
	if [[ -v BUILDDIR ]]; then kernel='latest'; fi
	setup_envvars="export KERNEL=${kernel}"
	cat <<HERE >"$tmp"
#!/bin/sh
set -eux

echo 'Running setup commands'
${setup_envvars}
set +e; ${setup_cmd}; exitstatus=\$?; set -e
echo \$exitstatus > /exitstatus
chmod 644 /exitstatus
HERE
fi

guestfish --remote \
	upload "$tmp" /etc/rcS.d/S50-run-tests : \
	chmod 755 /etc/rcS.d/S50-run-tests

fold_shutdown="$(travis_fold start shutdown Shutdown)"
cat <<HERE >"$tmp"
#!/bin/sh

echo -e '${fold_shutdown}'

poweroff
HERE
guestfish --remote \
	upload "$tmp" /etc/rcS.d/S99-poweroff : \
	chmod 755 /etc/rcS.d/S99-poweroff
rm "$tmp"
tmp=

guestfish --remote exit

echo "Starting VM with $(nproc) CPUs..."

case "$ARCH" in
s390x)
	qemu="qemu-system-s390x"
	console="ttyS1"
	smp=2
	kvm_accel="-enable-kvm"
	tcg_accel="-machine accel=tcg"
	;;
x86_64)
	qemu="qemu-system-x86_64"
	console="ttyS0,115200"
	smp=$(nproc)
	kvm_accel="-cpu kvm64 -enable-kvm"
	tcg_accel="-cpu qemu64 -machine accel=tcg"
	;;
*)
	echo "Unsupported architecture"
	exit 1
	;;
esac
if kvm-ok ; then
  accel=$kvm_accel
else
  accel=$tcg_accel
fi
"$qemu" -nodefaults -display none -serial mon:stdio \
  ${accel} -smp "$smp" -m 4G \
  -drive file="$IMG",format=raw,index=1,media=disk,if=virtio,cache=none \
  -kernel "$vmlinuz" -append "root=/dev/vda rw console=$console kernel.panic=-1 $APPEND"

if exitstatus="$(guestfish --ro -a "$IMG" -i cat /exitstatus 2>/dev/null)"; then
	printf '\nTests exit status: %s\n' "$exitstatus" >&2
else
	printf '\nCould not read tests exit status\n' >&2
	exitstatus=1
fi

travis_fold end shutdown

test_results["vm_tests"]=$exitstatus

# Final summary - Don't use a fold, keep it visible
echo -e "\033[1;33mTest Results:\033[0m"
for testgroup in ${!test_results[@]}; do
	# Print final result for each group of tests
	if [[ ${test_results[$testgroup]} -eq 0 ]]; then
		printf "%20s: \033[1;32mPASS\033[0m\n" $testgroup
	else
		printf "%20s: \033[1;31mFAIL\033[0m\n" $testgroup
	fi
	# Make exitstatus > 0 if at least one test group has failed
	if [[ ${test_results[$testgroup]} -ne 0 ]]; then
		exitstatus=1
	fi
done

exit "$exitstatus"
