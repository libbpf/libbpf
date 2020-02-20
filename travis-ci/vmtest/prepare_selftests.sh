#!/bin/bash

set -eux

REPO_PATH=$1

${VMTEST_ROOT}/checkout_latest_kernel.sh ${REPO_PATH}
cd ${REPO_PATH}

if [[ "${KERNEL}" = 'LATEST' ]]; then
	cp ${VMTEST_ROOT}/configs/latest.config .config
	make -j $((4*$(nproc))) olddefconfig all
fi

