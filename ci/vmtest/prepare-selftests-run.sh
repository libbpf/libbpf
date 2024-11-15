#!/bin/bash

set -euo pipefail

function append_into() {
    local out="$1"
    shift
    local files=("$@")
    echo -n > "$out"
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            echo "cat $file >> $out"
            cat "$file" >> "$out"
        fi
    done
}

allowlists=(
    "${SELFTESTS_BPF}/ALLOWLIST"
    "${SELFTESTS_BPF}/ALLOWLIST.${ARCH}"
    "${VMTEST_CONFIGS}/ALLOWLIST"
    "${VMTEST_CONFIGS}/ALLOWLIST-${KERNEL}"
    "${VMTEST_CONFIGS}/ALLOWLIST-${KERNEL}.${ARCH}"
)

append_into "${ALLOWLIST_FILE}" "${allowlists[@]}"

denylists=(
    "${SELFTESTS_BPF}/DENYLIST"
    "${SELFTESTS_BPF}/DENYLIST.${ARCH}"
    "${VMTEST_CONFIGS}/DENYLIST"
    "${VMTEST_CONFIGS}/DENYLIST-${KERNEL}"
    "${VMTEST_CONFIGS}/DENYLIST-${KERNEL}.${ARCH}"
)

append_into "${DENYLIST_FILE}" "${denylists[@]}"

if [[ "${LLVM_VERSION}" -lt 18 ]]; then
    echo "KERNEL_TEST=test_progs test_progs_no_alu32 test_maps test_verifier" >> $GITHUB_ENV
else # all
    echo "KERNEL_TEST=test_progs test_progs_cpuv4 test_progs_no_alu32 test_maps test_verifier" >> $GITHUB_ENV
fi

echo "cp -R ${SELFTESTS_BPF} ${GITHUB_WORKSPACE}/selftests"
mkdir -p "${GITHUB_WORKSPACE}/selftests"
cp -R "${SELFTESTS_BPF}" "${GITHUB_WORKSPACE}/selftests"

