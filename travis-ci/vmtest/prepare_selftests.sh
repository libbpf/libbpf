#!/bin/bash

set -eux

REPO_PATH=$1

${VMTEST_ROOT}/checkout_latest_kernel.sh ${REPO_PATH}
cd ${REPO_PATH}

if [[ "${KERNEL}" = 'LATEST' ]]; then
	cp ${VMTEST_ROOT}/configs/latest.config .config
	make -j $((4*$(nproc))) olddefconfig all
fi

# Fix runqslower build
# TODO(hex@): remove after the patch is merged from bpf to bpf-next tree
wget https://lore.kernel.org/bpf/908498f794661c44dca54da9e09dc0c382df6fcb.1580425879.git.hex@fb.com/t.mbox.gz
gunzip t.mbox.gz
git apply t.mbox
