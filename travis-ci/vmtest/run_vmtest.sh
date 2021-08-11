#!/bin/bash

set -eu

source $(cd $(dirname $0) && pwd)/helpers.sh

VMTEST_SETUPCMD="GITHUB_WORKFLOW=${GITHUB_WORKFLOW:-} PROJECT_NAME=${PROJECT_NAME} ./${PROJECT_NAME}/travis-ci/vmtest/run_selftests.sh"

# if CHECKOUT_KERNEL is 1 code will consider that kernel code lives elsewhere
# if 0 it will consider that REPO_ROOT is a kernel tree
CHECKOUT_KERNEL=${CHECKOUT_KERNEL:-1}

echo "KERNEL: $KERNEL"
echo

# Build latest pahole
${VMTEST_ROOT}/build_pahole.sh travis-ci/vmtest/pahole

travis_fold start install_clang "Installing Clang/LLVM"

wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
sudo add-apt-repository "deb http://apt.llvm.org/focal/ llvm-toolchain-focal main"
sudo apt-get update
sudo apt-get install --allow-downgrades -y libc6=2.31-0ubuntu9.2
sudo aptitude install -y g++ libelf-dev
sudo aptitude install -y clang-14 lld-14 llvm-14

travis_fold end install_clang

# Build selftests (and latest kernel, if necessary)

if [[ "$CHECKOUT_KERNEL" == "1" ]]; then
  ${VMTEST_ROOT}/prepare_selftests.sh travis-ci/vmtest/bpf-next
else
  ${VMTEST_ROOT}/prepare_selftests.sh
fi

# Escape whitespace characters.
setup_cmd=$(sed 's/\([[:space:]]\)/\\\1/g' <<< "${VMTEST_SETUPCMD}")

sudo adduser "${USER}" kvm

if [[ "${KERNEL}" = 'LATEST' ]]; then
  if [[ "$CHECKOUT_KERNEL" == "1" ]]; then
    sudo -E sudo -E -u "${USER}" "${VMTEST_ROOT}/run.sh" -b travis-ci/vmtest/bpf-next -o -d ~ -s "${setup_cmd}" ~/root.img
  else
    sudo -E sudo -E -u "${USER}" "${VMTEST_ROOT}/run.sh" -b "${REPO_ROOT}" -o -d ~ -s "${setup_cmd}" ~/root.img
  fi
else
  sudo -E sudo -E -u "${USER}" "${VMTEST_ROOT}/run.sh" -k "${KERNEL}*" -o -d ~ -s "${setup_cmd}" ~/root.img
fi
