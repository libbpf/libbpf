#!/bin/bash

set -eux

CWD=$(pwd)
LIBBPF_PATH=$(pwd)
REPO_PATH=$1

BPF_NEXT_ORIGIN=https://git.kernel.org/pub/scm/linux/kernel/git/bpf/bpf-next.git
LINUX_SHA=$(cat ${LIBBPF_PATH}/CHECKPOINT-COMMIT)

echo REPO_PATH = ${REPO_PATH}
echo LINUX_SHA = ${LINUX_SHA}

if [ ! -d "${REPO_PATH}" ]; then
	mkdir -p ${REPO_PATH}
	cd ${REPO_PATH}
	git init
	git remote add bpf-next ${BPF_NEXT_ORIGIN}
	for depth in 32 64 128; do
		git fetch --depth ${depth} bpf-next
		git reset --hard ${LINUX_SHA} && break
	done
fi
