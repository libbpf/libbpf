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

# shared linking
${CC:-cc} ${CFLAGS} -o main_shared -I./install/usr/include main.c -L./install/usr/lib64 -L./install/usr/lib -lbpf
ldd main_shared
if ! ldd main_shared | grep -q libbpf; then
    echo "FAIL: No reference to libbpf.so in main!"
    exit 1
fi
