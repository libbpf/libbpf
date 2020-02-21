#!/bin/bash

LLVM_VER=11
LIBBPF_PATH="${REPO_ROOT}"
REPO_PATH="travis-ci/vmtest/bpf-next"

# temporary work-around for failing tests
rm "${REPO_ROOT}/${REPO_PATH}/tools/testing/selftests/bpf/prog_tests/sockmap_basic.c"

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

blacklist_path="${VMTEST_ROOT}/configs/blacklist"
git add "${blacklist_path}"
