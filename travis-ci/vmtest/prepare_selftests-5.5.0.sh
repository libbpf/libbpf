#!/bin/bash

set -euxo pipefail

# these tests expect vmlinux.h to have latest defiition of bpf_devmap_val xdp_md->egress_ifindex
rm progs/test_xdp_with_devmap_helpers.c
rm progs/test_xdp_devmap_helpers.c
rm prog_tests/xdp_devmap_attach.c

# no BPF_F_NO_PREALLOC in BTF and no sk_msg_md->sk field
rm progs/test_skmsg_load_helpers.c
rm prog_tests/sockmap_basic.c
