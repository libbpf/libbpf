#!/bin/bash

set -euxo pipefail

test_progs() {
	echo TEST_PROGS
	./test_progs ${BLACKLIST:+-b$BLACKLIST} ${WHITELIST:+-t$WHITELIST}
}

test_maps() {
	echo TEST_MAPS
	# Allow failing on older kernels.
	./test_maps
}

test_verifier() {
	echo TEST_VERIFIER
	./test_verifier
}

configs_path='libbpf/travis-ci/vmtest/configs'
blacklist_path="$configs_path/blacklist/BLACKLIST-${KERNEL}"
if [[ -s "${blacklist_path}" ]]; then
	BLACKLIST=$(cat "${blacklist_path}" | cut -d'#' -f1 | tr -s '[:space:]' ',')
fi

whitelist_path="$configs_path/whitelist/WHITELIST-${KERNEL}"
if [[ -s "${whitelist_path}" ]]; then
	WHITELIST=$(cat "${whitelist_path}" | cut -d'#' -f1 | tr -s '[:space:]' ',')
fi

cd libbpf/selftests/bpf

test_progs

if [[ "${KERNEL}" == 'latest' ]]; then
	test_maps
	test_verifier
fi
