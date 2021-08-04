#!/bin/bash
set -euox pipefail

CFLAGS=${CFLAGS:-}

cat << EOF > main.c
#include <bpf/libbpf.h>
int main() {
  return bpf_object__open(0) < 0;
}
EOF

# static linking
${CC:-cc} ${CFLAGS} -o main -I./install/usr/include main.c ./build/libbpf.a -lelf -lz
