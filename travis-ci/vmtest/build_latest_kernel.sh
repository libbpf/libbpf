#!/bin/bash

set -eux

GIT_FETCH_DEPTH="${GIT_FETCH_DEPTH}" ${VMTEST_ROOT}/checkout_latest_kernel.sh $1
cd $1
cp ${VMTEST_ROOT}/configs/latest.config .config
make -j $((4*$(nproc))) olddefconfig all
