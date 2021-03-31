#!/bin/bash

set -x

source $(cd $(dirname $0) && pwd)/helpers.sh

VMTEST_SETUPCMD="PROJECT_NAME=${PROJECT_NAME} ./${PROJECT_NAME}/travis-ci/vmtest/run_selftests.sh"

echo "KERNEL: $KERNEL"
echo

# Build latest pahole
${VMTEST_ROOT}/build_pahole.sh travis-ci/vmtest/pahole

travis_fold start install_clang "Installing Clang/LLVM"

wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
sudo add-apt-repository "deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic main"
sudo apt-get update
sudo apt-cache policy clang-13 || true
sudo dpkg -l | grep clang || true
sudo dpkg -l | grep lld || true
sudo dpkg -l | grep llvm || true
sudo apt-get install -y clang-13=13~++20210321100630+2554b95db57c-1~exp1~20210321211340.3856 \
			lld-13=13~++20210321100630+2554b95db57c-1~exp1~20210321211340.3856 \
			llvm-13=13~++20210321100630+2554b95db57c-1~exp1~20210321211340.3856

llvm-toolchain-snapshot/clang-13_13~%2b%2b20210321100630%2b2554b95db57c-1~exp1~20210321211340.3856_i386.deb
travis_fold end install_clang

# Build selftests (and latest kernel, if necessary)
KERNEL="${KERNEL}" ${VMTEST_ROOT}/prepare_selftests.sh travis-ci/vmtest/bpf-next

# Escape whitespace characters.
setup_cmd=$(sed 's/\([[:space:]]\)/\\\1/g' <<< "${VMTEST_SETUPCMD}")

sudo adduser "${USER}" kvm

if [[ "${KERNEL}" = 'LATEST' ]]; then
  sudo -E sudo -E -u "${USER}" "${VMTEST_ROOT}/run.sh" -b travis-ci/vmtest/bpf-next -o -d ~ -s "${setup_cmd}" ~/root.img;
else
  sudo -E sudo -E -u "${USER}" "${VMTEST_ROOT}/run.sh" -k "${KERNEL}*" -o -d ~ -s "${setup_cmd}" ~/root.img;
fi
