#!/bin/bash

set -euxo pipefail

LLVM_VER=11
LIBBPF_PATH="${REPO_ROOT}"
REPO_PATH="travis-ci/vmtest/bpf-next"

PREPARE_SELFTESTS_SCRIPT=${VMTEST_ROOT}/prepare_selftests-${KERNEL}.sh
if [ -f "${PREPARE_SELFTESTS_SCRIPT}" ]; then
	(cd "${REPO_ROOT}/${REPO_PATH}/tools/testing/selftests/bpf" && ${PREPARE_SELFTESTS_SCRIPT})
fi

make \
	CLANG=clang-${LLVM_VER} \
	LLC=llc-${LLVM_VER} \
	LLVM_STRIP=llvm-strip-${LLVM_VER} \
	VMLINUX_BTF="${VMLINUX_BTF}" \
	-C "${REPO_ROOT}/${REPO_PATH}/tools/testing/selftests/bpf" \
	-j $((4*$(nproc)))
mkdir ${LIBBPF_PATH}/selftests
cp -R "${REPO_ROOT}/${REPO_PATH}/tools/testing/selftests/bpf" \
	${LIBBPF_PATH}/selftests
cd ${LIBBPF_PATH}
rm selftests/bpf/.gitignore
git add selftests

git add "${VMTEST_ROOT}/configs/blacklist"
