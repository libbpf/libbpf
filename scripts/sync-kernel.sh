#!/bin/bash

usage () {
    echo "USAGE: ./sync-kernel.sh <kernel-repo> <libbpf-repo> [<baseline-commit>]"
    echo ""
    echo "If <baseline-commit> is not specified, it's read from <libbpf-repo>/CHECKPOINT-COMMIT"
    exit 1
}

LINUX_REPO=${1-""}
LIBBPF_REPO=${2-""}

if [ -z "${LINUX_REPO}" ]; then
    usage
fi
if [ -z "${LIBBPF_REPO}" ]; then
    usage
fi

set -eu

WORKDIR=$(pwd)
trap "cd ${WORKDIR}; exit" INT TERM EXIT

echo "WORKDIR:     ${WORKDIR}"
echo "LINUX REPO:  ${LINUX_REPO}"
echo "LIBBPF REPO: ${LIBBPF_REPO}"

SUFFIX=$(date --utc +%Y-%m-%dT%H-%M-%S.%3NZ)
BASELINE_COMMIT=${3-$(cat ${LIBBPF_REPO}/CHECKPOINT-COMMIT)}

# Use current kernel repo HEAD as a source of patches
cd ${LINUX_REPO}
CHECKPOINT_COMMIT=$(git rev-parse HEAD)
git branch libbpf-${SUFFIX} HEAD

echo "SUFFIX: ${SUFFIX}"
echo "BASELINE COMMIT: ${BASELINE_COMMIT}"
echo "CHECKPOINT COMMIT: ${CHECKPOINT_COMMIT}"

# Squash state of kernel repo at baseline into single commit
SQUASHED_BASELINE_COMMIT=$(git commit-tree ${BASELINE_COMMIT}^{tree} -m "BASELINE ${BASELINE_COMMIT}")
echo "SQUASHED BASELINE COMMIT: ${SQUASHED_BASELINE_COMMIT}"

# Re-apply the rest of commits
git rebase --onto ${SQUASHED_BASELINE_COMMIT} ${BASELINE_COMMIT} libbpf-${SUFFIX}

# Move all libbpf files into libbpf-projection directory
git filter-branch --prune-empty -f --tree-filter '                                                                             \
    mkdir -p libbpf-projection/include/uapi/linux libbpf-projection/include/tools &&                                           \
    git mv -kf tools/lib/bpf libbpf-projection/src &&                                                                          \
    git mv -kf tools/include/uapi/linux/{bpf_common.h,bpf.h,btf.h,if_link.h,netlink.h} libbpf-projection/include/uapi/linux && \
    git mv -kf tools/include/tools/libc_compat.h libbpf-projection/include/tools &&                                            \
    git rm --ignore-unmatch -f libbpf-projection/src/{Makefile,Build,test_libbpf.cpp,.gitignore}                               \
  ' libbpf-${SUFFIX}

# Make libbpf-projection a new root directory
git filter-branch --prune-empty -f --subdirectory-filter libbpf-projection libbpf-${SUFFIX}

# We don't want to include SQUASHED_BASELINE_COMMIT into patch set,
# but git doesn't allow to exclude rev A in A..B rev range, so instead
# we calculate number of patches to include
COMMIT_CNT=$(($(git rev-list --count ${SQUASHED_BASELINE_COMMIT}..libbpf-${SUFFIX}) - 1))

# If baseline is the only commit with libbpf-related changes, bail out
if ((${COMMIT_CNT} <= 0)); then
    echo "No new changes to apply, we are done!"
    exit 2
fi

# Exclude baseline commit and generate nice cover letter with summary
git format-patch -${COMMIT_CNT} --cover-letter -o /tmp/libbpf-${SUFFIX}.patches

# Now generate single-file patchset to apply on top of libbpf repo,
# this time including "sync commit" as well
git format-patch -${COMMIT_CNT} --stdout > /tmp/libbpf-${SUFFIX}.patchset
echo "PATCHSET: /tmp/libbpf-${SUFFIX}.patchset"

cd ${WORKDIR}
cd ${LIBBPF_REPO}
git checkout -b libbpf-sync-${SUFFIX}
git am /tmp/libbpf-${SUFFIX}.patchset

# Use generated cover-letter as a template for "sync commit" with
# baseline and checkpoint commits from kernel repo (and leave summary
# from cover letter intact, of course)
echo ${CHECKPOINT_COMMIT} > CHECKPOINT-COMMIT &&                                                 \
git add CHECKPOINT-COMMIT &&                                                                     \
awk '/\*\*\* BLURB HERE \*\*\*/ {p=1} p' /tmp/libbpf-${SUFFIX}.patches/0000-cover-letter.patch | \
sed "s/\*\*\* BLURB HERE \*\*\*/\
sync: latest libbpf changes from kernel\n\
\n\
Syncing latest libbpf commits from kernel repository.\n\
Baseline commit:   ${BASELINE_COMMIT}\n\
Checkpoint commit: ${CHECKPOINT_COMMIT}/" |                                                      \
git commit --file=-

# Clean up a bit after ourselvest
rm -r /tmp/libbpf-${SUFFIX}.patches /tmp/libbpf-${SUFFIX}.patchset

echo "Success! ${COMMIT_CNT} commits applied."
