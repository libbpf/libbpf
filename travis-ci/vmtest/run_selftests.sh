#!/bin/bash

set -euo pipefail

source $(cd $(dirname $0) && pwd)/helpers.sh

ARCH=$(uname -m)

STATUS_FILE=/exitstatus

read_lists() {
	(for path in "$@"; do
		if [[ -s "$path" ]]; then
			cat "$path"
		fi;
	done) | cut -d'#' -f1 | tr -s ' \t\n' ','
}

test_progs() {
	if [[ "${KERNEL}" != '4.9.0' ]]; then
		foldable start test_progs "Testing test_progs"
		# "&& true" does not change the return code (it is not executed
		# if the Python script fails), but it prevents exiting on a
		# failure due to the "set -e".
		./test_progs ${DENYLIST:+-d$DENYLIST} ${ALLOWLIST:+-a$ALLOWLIST} && true
		echo "test_progs:$?" >> "${STATUS_FILE}"
		foldable end test_progs
	fi

	foldable start test_progs-no_alu32 "Testing test_progs-no_alu32"
	./test_progs-no_alu32 ${DENYLIST:+-d$DENYLIST} ${ALLOWLIST:+-a$ALLOWLIST} && true
	echo "test_progs-no_alu32:$?" >> "${STATUS_FILE}"
	foldable end test_progs-no_alu32
}

test_maps() {
	foldable start test_maps "Testing test_maps"
	./test_maps && true
	echo "test_maps:$?" >> "${STATUS_FILE}"
	foldable end test_maps
}

test_verifier() {
	foldable start test_verifier "Testing test_verifier"
	./test_verifier && true
	echo "test_verifier:$?" >> "${STATUS_FILE}"
	foldable end test_verifier
}

foldable end vm_init

configs_path=${PROJECT_NAME}/vmtest/configs
DENYLIST=$(read_lists "$configs_path/DENYLIST-${KERNEL}" "$configs_path/DENYLIST-${KERNEL}.${ARCH}")
ALLOWLIST=$(read_lists "$configs_path/ALLOWLIST-${KERNEL}" "$configs_path/ALLOWLIST-${KERNEL}.${ARCH}")

cd ${PROJECT_NAME}/selftests/bpf

test_progs

if [[ "${KERNEL}" == 'latest' ]]; then
	# test_maps
	test_verifier
fi
