#!/bin/bash

set -euo pipefail

THISDIR="$(cd $(dirname $0) && pwd)"

source ${THISDIR}/helpers.sh

foldable start prepare_selftests "Building selftests"

LIBBPF_PATH="${REPO_ROOT}"

llvm_latest_version() {
	echo "19"
}

if [[ "${LLVM_VERSION}" == $(llvm_latest_version) ]]; then
	REPO_DISTRO_SUFFIX=""
else
	REPO_DISTRO_SUFFIX="-${LLVM_VERSION}"
fi

DISTRIB_CODENAME="noble"
test -f /etc/lsb-release && . /etc/lsb-release
echo "${DISTRIB_CODENAME}"

echo "deb https://apt.llvm.org/${DISTRIB_CODENAME}/ llvm-toolchain-${DISTRIB_CODENAME}${REPO_DISTRO_SUFFIX} main" \
	| sudo tee /etc/apt/sources.list.d/llvm.list

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
make headers
make \
	CLANG=clang-${LLVM_VERSION} \
	LLC=llc-${LLVM_VERSION} \
	LLVM_STRIP=llvm-strip-${LLVM_VERSION} \
	VMLINUX_BTF="${VMLINUX_BTF}" \
	VMLINUX_H=${VMLINUX_H} \
	-C "${REPO_ROOT}/${REPO_PATH}/tools/testing/selftests/bpf" \
	-j $((4*$(nproc))) > /dev/null
cd -
mkdir ${LIBBPF_PATH}/selftests
cp -R "${REPO_ROOT}/${REPO_PATH}/tools/testing/selftests/bpf" \
	${LIBBPF_PATH}/selftests
cd ${LIBBPF_PATH}
rm selftests/bpf/.gitignore
git add selftests

foldable end prepare_selftests
