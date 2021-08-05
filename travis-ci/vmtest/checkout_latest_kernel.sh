#!/bin/bash

set -eu

source $(cd $(dirname $0) && pwd)/helpers.sh

CWD=$(pwd)
LIBBPF_PATH=$(pwd)
REPO_PATH=$1

KERNEL_ORIGIN=${KERNEL_ORIGIN:-https://git.kernel.org/pub/scm/linux/kernel/git/bpf/bpf-next.git}
KERNEL_BRANCH=${KERNEL_BRANCH:-CHECKPOINT}
if [[ "${KERNEL_BRANCH}" = 'CHECKPOINT' ]]; then
  echo "using CHECKPOINT sha1"
  LINUX_SHA=$(cat ${LIBBPF_PATH}/CHECKPOINT-COMMIT)
else
  echo "using ${KERNEL_BRANCH} sha1"
  LINUX_SHA=$(git ls-remote ${KERNEL_ORIGIN} ${KERNEL_BRANCH} | awk '{print $1}')
fi
SNAPSHOT_URL=${KERNEL_ORIGIN}/snapshot/bpf-next-${LINUX_SHA}.tar.gz

echo REPO_PATH = ${REPO_PATH}

echo KERNEL_ORIGIN = ${KERNEL_ORIGIN}
echo LINUX_SHA = ${LINUX_SHA}
echo SNAPSHOT_URL = ${SNAPSHOT_URL}

if [ ! -d "${REPO_PATH}" ]; then
	echo
	travis_fold start pull_kernel_srcs "Fetching kernel sources"

	mkdir -p $(dirname "${REPO_PATH}")
	cd $(dirname "${REPO_PATH}")
	# attempt to fetch desired bpf-next repo snapshot
	if wget -nv ${SNAPSHOT_URL} && tar xf bpf-next-${LINUX_SHA}.tar.gz --totals ; then
		mv bpf-next-${LINUX_SHA} $(basename ${REPO_PATH})
	else
		# but fallback to git fetch approach if that fails
		mkdir -p $(basename ${REPO_PATH})
		cd $(basename ${REPO_PATH})
		git init
		git remote add bpf-next ${KERNEL_ORIGIN}
		# try shallow clone first
		git fetch --depth 32 bpf-next
		# check if desired SHA exists
		if ! git cat-file -e ${LINUX_SHA}^{commit} ; then
			# if not, fetch all of bpf-next; slow and painful
			git fetch bpf-next
		fi
		git reset --hard ${LINUX_SHA}
	fi

	travis_fold end pull_kernel_srcs
fi
