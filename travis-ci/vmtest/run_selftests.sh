#!/bin/bash

set -eux

mount -t bpf bpffs /sys/fs/bpf
mount -t debugfs none /sys/kernel/debug/

configs_path='libbpf/travis-ci/vmtest/configs'
blacklist_path="$configs_path/blacklist/BLACKLIST-${KERNEL}"
if [[ -s "${blacklist_path}" ]]; then
	BLACKLIST=$(cat "${blacklist_path}" | tr '\n' ',')
fi

whitelist_path="$configs_path/whitelist/WHITELIST-${KERNEL}"
if [[ -s "${whitelist_path}" ]]; then
	WHITELIST=$(cat "${whitelist_path}" | tr '\n' ',')
fi

cd libbpf/selftests/bpf

echo TEST_PROGS
./test_progs ${BLACKLIST:+-b$BLACKLIST} ${WHITELIST:+-t$WHITELIST}
