#!/bin/bash

set -eu

source $(cd $(dirname $0) && pwd)/helpers.sh

REPO_PATH=${1:-}

if [[ ! -z "$REPO_PATH" ]]; then
	${VMTEST_ROOT}/checkout_latest_kernel.sh ${REPO_PATH}
	cd ${REPO_PATH}
fi

if [[ "${KERNEL}" = 'LATEST' ]]; then
	travis_fold start build_kernel "Kernel build"

	cp ${VMTEST_ROOT}/configs/latest.config .config
	make -j $((4*$(nproc))) olddefconfig all >/dev/null
	travis_fold end build_kernel
fi

