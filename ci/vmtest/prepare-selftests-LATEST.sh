#!/bin/bash

set -euo pipefail

# noop script: it's here as a reminder that we might need it for other kernel versions

# for 4.9.0 and 5.5.0 code was:
# cd "${SELFTESTS_BPF}"
# printf "all:\n\ttouch bpf_testmod.ko\n\nclean:\n" > bpf_testmod/Makefile
# printf "all:\n\ttouch bpf_test_no_cfi.ko\n\nclean:\n" > bpf_test_no_cfi/Makefile

exit 0
