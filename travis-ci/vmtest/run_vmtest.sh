#!/bin/bash

set -eux

VMTEST_SETUPCMD="PROJECT_NAME=${PROJECT_NAME} ./${PROJECT_NAME}/travis-ci/vmtest/run_selftests.sh"

echo "KERNEL: $KERNEL"

# Install required packages
wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
echo "deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic-10 main" | sudo tee -a /etc/apt/sources.list
echo "deb http://archive.ubuntu.com/ubuntu eoan main restricted universe multiverse" | sudo tee -a /etc/apt/sources.list
sudo apt-get -qq update
sudo apt-get -y install dwarves=1.15-1
sudo apt-get -qq -y install clang-10 lld-10 llvm-10

# Build selftests (and latest kernel, if necessary)
KERNEL="${KERNEL}" ${VMTEST_ROOT}/prepare_selftests.sh travis-ci/vmtest/bpf-next

# Escape whitespace characters.
setup_cmd=$(sed 's/\([[:space:]]\)/\\\1/g' <<< "${VMTEST_SETUPCMD}")

if [[ "${KERNEL}" = 'LATEST' ]]; then
  sudo -E sudo -E -u "${USER}" "${VMTEST_ROOT}/run.sh" -b travis-ci/vmtest/bpf-next -o -d ~ -s "${setup_cmd}" ~/root.img;
else
  sudo -E sudo -E -u "${USER}" "${VMTEST_ROOT}/run.sh" -k "${KERNEL}*" -o -d ~ -s "${setup_cmd}" ~/root.img;
fi
