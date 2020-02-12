#!/bin/bash

set -eux
GIT_FETCH_DEPTH="${GIT_FETCH_DEPTH}" ${VMTEST_ROOT}/checkout_latest_kernel.sh $1

# Fix runqslower build
# TODO(hex@): remove after the patch is merged from bpf to bpf-next tree
cd $1
wget https://lore.kernel.org/bpf/908498f794661c44dca54da9e09dc0c382df6fcb.1580425879.git.hex@fb.com/t.mbox.gz
gunzip t.mbox.gz
git apply t.mbox
