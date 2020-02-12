#!/bin/bash

LIBBPF_PATH="${REPO_ROOT}"
REPO_PATH="travis-ci/vmtest/bpf-next"
make \
	CLANG=clang-10 \
	LLC=llc-10 \
	LLVM_STRIP=llvm-strip-10 \
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
