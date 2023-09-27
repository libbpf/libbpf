#!/bin/bash

set -euo pipefail

THISDIR="$(cd $(dirname $0) && pwd)"

source "${THISDIR}"/../helpers.sh

KERNEL="$1"
TOOLCHAIN="$2"
export KBUILD_OUTPUT="$3"

LLVM_VER="$(llvm_version $TOOLCHAIN)" && :
if [ $? -eq 0 ]; then
	export LLVM="-$LLVM_VER"
fi

foldable start build_selftests "Building selftests with $TOOLCHAIN"

LIBBPF_PATH="${REPO_ROOT}"

PREPARE_SELFTESTS_SCRIPT=${THISDIR}/prepare_selftests-${KERNEL}.sh
if [ -f "${PREPARE_SELFTESTS_SCRIPT}" ]; then
	(cd "${REPO_ROOT}/${REPO_PATH}/tools/testing/selftests/bpf" && ${PREPARE_SELFTESTS_SCRIPT})
fi

if [[ "${KERNEL}" = 'LATEST' ]]; then
	VMLINUX_H=
else
	VMLINUX_H=${THISDIR}/vmlinux.h
fi

cd ${REPO_ROOT}/${REPO_PATH}
make \
	CLANG=clang-${LLVM_VER} \
	LLC=llc-${LLVM_VER} \
	LLVM_STRIP=llvm-strip-${LLVM_VER} \
	VMLINUX_BTF="${KBUILD_OUTPUT}/vmlinux" \
	VMLINUX_H="${VMLINUX_H}" \
	-C "${REPO_ROOT}/${REPO_PATH}/tools/testing/selftests/bpf" \
	-j $(kernel_build_make_jobs)
cd -
mkdir "${LIBBPF_PATH}"/selftests
cp -R "${REPO_ROOT}/${REPO_PATH}/tools/testing/selftests/bpf" \
  "${LIBBPF_PATH}"/selftests
cd "${LIBBPF_PATH}"

foldable end build_selftests
