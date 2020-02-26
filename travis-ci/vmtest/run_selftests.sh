#!/bin/bash

set -euxo pipefail

test_progs() {
	echo TEST_PROGS
	./test_progs ${BLACKLIST:+-b$BLACKLIST} ${WHITELIST:+-t$WHITELIST}
}

test_maps() {
	echo TEST_MAPS
	# Allow failing on older kernels.
	./test_maps || [ ${KERNEL} != 'LATEST' ]
}

test_verifier() {
	echo TEST_VERIFIER
	./test_verifier
}

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

set +e
exitcode=0
for test_func in test_progs test_maps test_verifier; do
	${test_func}; c=$?
	if [[ $c -ne 0 ]]; then
		exitcode=$c
	fi
done

exit $exitcode
