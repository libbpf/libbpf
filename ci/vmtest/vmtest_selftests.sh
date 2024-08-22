#!/bin/bash

# run_selftest.sh will run the tests within /${PROJECT_NAME}/selftests/bpf
# If no specific test names are given, all test will be ran, otherwise, it will
# run the test passed as parameters.
# There is 2 ways to pass test names.
# 1) command-line arguments to this script
# 2) a comma-separated list of test names passed as `run_tests` boot parameters.
# test names passed as any of those methods will be ran.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/helpers.sh"

ARCH=$(uname -m)
DEPLOYMENT=$(if [[ "$GITHUB_REPOSITORY" == *"-rc" ]]; then echo "rc"; else echo "prod"; fi)

STATUS_FILE=/mnt/vmtest/exitstatus
OUTPUT_DIR=/mnt/vmtest

WORKING_DIR="/${PROJECT_NAME}"
BPF_SELFTESTS_DIR="${WORKING_DIR}/selftests/bpf"
VMTEST_CONFIGS_PATH="${WORKING_DIR}/ci/vmtest/configs"

read_lists() {
	(for path in "$@"; do
		if [[ -s "$path" ]]; then
			cat "$path"
		fi;
	done) | cut -d'#' -f1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -s '\n' ','
}

DENYLIST=$(read_lists \
	"$BPF_SELFTESTS_DIR/DENYLIST" \
	"$BPF_SELFTESTS_DIR/DENYLIST.${ARCH}" \
	"$VMTEST_CONFIGS_PATH/DENYLIST" \
	"$VMTEST_CONFIGS_PATH/DENYLIST.${ARCH}" \
	"$VMTEST_CONFIGS_PATH/DENYLIST.${DEPLOYMENT}" \
)
ALLOWLIST=$(read_lists \
	"$BPF_SELFTESTS_DIR/ALLOWLIST" \
	"$BPF_SELFTESTS_DIR/ALLOWLIST.${ARCH}" \
	"$VMTEST_CONFIGS_PATH/ALLOWLIST" \
	"$VMTEST_CONFIGS_PATH/ALLOWLIST.${ARCH}" \
)

declare -a TEST_NAMES=()

read_test_names() {
    foldable start read_test_names "Reading test names from boot parameters and command line arguments"
    # Check if test names were passed as boot parameter.
    # We expect `run_tests` to be a comma-separated list of test names.
    IFS=',' read -r -a test_names_from_boot <<< \
        "$(sed -n 's/.*run_tests=\([^ ]*\).*/\1/p' /proc/cmdline)"

    echo "${#test_names_from_boot[@]} tests extracted from boot parameters: ${test_names_from_boot[*]}"
    # Sort and only keep unique test names from both boot params and arguments
    # TEST_NAMES will contain a sorted list of uniq tests to be ran.
    # Only do this if any of $test_names_from_boot[@] or $@ has elements as
    # "printf '%s\0'" will otherwise generate an empty element.
    if [[ ${#test_names_from_boot[@]} -gt 0 || $# -gt 0 ]]
    then
        readarray -t TEST_NAMES < \
            <(printf '%s\0' "${test_names_from_boot[@]}" "$@" | \
                sort --zero-terminated --unique | \
                xargs --null --max-args=1)
    fi
    foldable end read_test_names
}

test_progs_helper() {
  local selftest="test_progs${1}"
  local args="$2"

  json_file=${selftest/-/_}
  if [ "$2" == "-j" ]
  then
    json_file+="_parallel"
  fi
  json_file="${OUTPUT_DIR}/${json_file}.json"

  foldable start ${selftest} "Testing ${selftest}"
  # "&& true" does not change the return code (it is not executed
  # if the Python script fails), but it prevents exiting on a
  # failure due to the "set -e".
  ./${selftest} ${args} ${DENYLIST:+-d"$DENYLIST"} ${ALLOWLIST:+-a"$ALLOWLIST"} --json-summary "${json_file}" && true
  echo "${selftest}:$?" >>"${STATUS_FILE}"
  foldable end ${selftest}
}

test_progs() {
  test_progs_helper "" ""
}

test_progs_parallel() {
  test_progs_helper "" "-j"
}

test_progs_no_alu32() {
  test_progs_helper "-no_alu32" ""
}

test_progs_no_alu32_parallel() {
  test_progs_helper "-no_alu32" "-j"
}

test_progs_cpuv4() {
  test_progs_helper "-cpuv4" ""
}

test_maps() {
  foldable start test_maps "Testing test_maps"
  taskset 0xF ./test_maps && true
  echo "test_maps:$?" >>"${STATUS_FILE}"
  foldable end test_maps
}

test_verifier() {
  foldable start test_verifier "Testing test_verifier"
  ./test_verifier && true
  echo "test_verifier:$?" >>"${STATUS_FILE}"
  foldable end test_verifier
}

run_veristat_helper() {
  local mode="${1}"

  # Make veristat commands visible in the log
  if [ -o xtrace ]; then
      xtrace_was_on="1"
  else
      xtrace_was_on=""
      set -x
  fi

  (
    # shellcheck source=ci/vmtest/configs/run_veristat.default.cfg
    # shellcheck source=ci/vmtest/configs/run_veristat.meta.cfg
    source "${VMTEST_CONFIGS_PATH}/run_veristat.${mode}.cfg"
    pushd "${VERISTAT_OBJECTS_DIR}"

    "${BPF_SELFTESTS_DIR}/veristat" -o csv -q -e file,prog,verdict,states ${VERISTAT_OBJECTS_GLOB} > \
      "${OUTPUT_DIR}/${VERISTAT_OUTPUT}"

    echo "run_veristat_${mode}:$?" >> ${STATUS_FILE}
    popd
  )

  # Hide commands again
  if [ -z "$xtrace_was_on" ]; then
      set +x
  fi

}

run_veristat_kernel() {
  foldable start run_veristat_kernel "Running veristat.kernel"
  run_veristat_helper "kernel"
  foldable end run_veristat_kernel
}

run_veristat_meta() {
  foldable start run_veristat_meta "Running veristat.meta"
  run_veristat_helper "meta"
  foldable end run_veristat_meta
}

foldable end vm_init

foldable start kernel_config "Kconfig"

zcat /proc/config.gz

foldable end kernel_config

echo "DENYLIST: ${DENYLIST}"
echo "ALLOWLIST: ${ALLOWLIST}"

cd ${PROJECT_NAME}/selftests/bpf

# populate TEST_NAMES
read_test_names "$@"
# if we don't have any test name provided to the script, we run all tests.
if [ ${#TEST_NAMES[@]} -eq 0 ]; then
	test_progs
	test_progs_no_alu32
	test_progs_cpuv4
	test_maps
	test_verifier
else
	# else we run the tests passed as command-line arguments and through boot
	# parameter.
	for test_name in "${TEST_NAMES[@]}"; do
		"${test_name}"
	done
fi
