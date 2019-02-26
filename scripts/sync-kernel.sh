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

echo "WORKDIR:         ${WORKDIR}"
echo "LINUX REPO:      ${LINUX_REPO}"
echo "LIBBPF REPO:     ${LIBBPF_REPO}"

SUFFIX=$(date --utc +%Y-%m-%dT%H-%M-%S.%3NZ)
BASELINE_COMMIT=${3-$(cat ${LIBBPF_REPO}/CHECKPOINT-COMMIT)}

# Use current kernel repo HEAD as a source of patches
cd ${LINUX_REPO}
TIP_SYM_REF=$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)
TIP_COMMIT=$(git rev-parse HEAD)
BASELINE_TAG=libbpf-baseline-${SUFFIX}
TIP_TAG=libbpf-tip-${SUFFIX}
VIEW_TAG=libbpf-view-${SUFFIX}
LIBBPF_SYNC_TAG=libbpf-sync-${SUFFIX}

# Squash state of kernel repo at baseline into single commit
SQUASH_BASE_TAG=libbpf-squash-base-${SUFFIX}
SQUASH_TIP_TAG=libbpf-squash-tip-${SUFFIX}
SQUASH_COMMIT=$(git commit-tree ${BASELINE_COMMIT}^{tree} -m "BASELINE SQUASH ${BASELINE_COMMIT}")

echo "SUFFIX:          ${SUFFIX}"
echo "BASELINE COMMIT: $(git log --pretty=oneline --no-walk ${BASELINE_COMMIT})"
echo "TIP COMMIT:      $(git log --pretty=oneline --no-walk ${TIP_COMMIT})"
echo "SQUASH COMMIT:   ${SQUASH_COMMIT}"
echo "BASELINE TAG:    ${BASELINE_TAG}"
echo "TIP TAG:         ${TIP_TAG}"
echo "SQUASH BASE TAG: ${SQUASH_BASE_TAG}"
echo "SQUASH TIP TAG:  ${SQUASH_TIP_TAG}"
echo "VIEW TAG:        ${VIEW_TAG}"
echo "LIBBPF SYNC TAG: ${LIBBPF_SYNC_TAG}"

TMP_DIR=$(mktemp -d)
echo "TEMP DIR:        ${TMP_DIR}"
echo "PATCHES+COVER:   ${TMP_DIR}/patches"
echo "PATCHSET:        ${TMP_DIR}/patchset.patch"

git branch ${BASELINE_TAG} ${BASELINE_COMMIT}
git branch ${TIP_TAG} ${TIP_COMMIT}
git branch ${SQUASH_BASE_TAG} ${SQUASH_COMMIT}
git checkout -b ${SQUASH_TIP_TAG} ${SQUASH_COMMIT}

# Cherry-pick new commits onto squashed baseline commit
LIBBPF_PATHS=(tools/lib/bpf tools/include/uapi/linux/{bpf_common.h,bpf.h,btf.h,if_link.h,netlink.h} tools/include/tools/libc_compat.h)
LIBBPF_NEW_COMMITS=$(git rev-list --topo-order --reverse ${BASELINE_TAG}..${TIP_TAG} ${LIBBPF_PATHS[@]})
for LIBBPF_NEW_COMMIT in ${LIBBPF_NEW_COMMITS}; do
	git cherry-pick ${LIBBPF_NEW_COMMIT}
done

LIBBPF_TREE_FILTER='												      \
    mkdir -p __libbpf/include/uapi/linux __libbpf/include/tools &&						      \
    git mv -kf tools/lib/bpf __libbpf/src &&									      \
    git mv -kf tools/include/uapi/linux/{bpf_common.h,bpf.h,btf.h,if_link.h,netlink.h} __libbpf/include/uapi/linux && \
    git mv -kf tools/include/tools/libc_compat.h __libbpf/include/tools &&					      \
    git rm --ignore-unmatch -f __libbpf/src/{Makefile,Build,test_libbpf.cpp,.gitignore}				      \
'
# Move all libbpf files into __libbpf directory.
git filter-branch --prune-empty -f --tree-filter "${LIBBPF_TREE_FILTER}" ${SQUASH_TIP_TAG} ${SQUASH_BASE_TAG}
# Make __libbpf a new root directory
git filter-branch --prune-empty -f --subdirectory-filter __libbpf ${SQUASH_TIP_TAG} ${SQUASH_BASE_TAG}

# If there are no new commits with  libbpf-related changes, bail out
COMMIT_CNT=$(git rev-list --count ${SQUASH_BASE_TAG}..${SQUASH_TIP_TAG})
if ((${COMMIT_CNT} <= 0)); then
    echo "No new changes to apply, we are done!"
    exit 2
fi

# Exclude baseline commit and generate nice cover letter with summary
git format-patch ${SQUASH_BASE_TAG}..${SQUASH_TIP_TAG} --cover-letter -o ${TMP_DIR}/patches
# Now generate single-file patchset w/o cover to apply on top of libbpf repo
git format-patch ${SQUASH_BASE_TAG}..${SQUASH_TIP_TAG} --stdout > ${TMP_DIR}/patchset.patch

# Now is time to re-apply libbpf-related linux  patches to libbpf repo
cd ${WORKDIR} && cd ${LIBBPF_REPO}
git checkout -b ${LIBBPF_SYNC_TAG}
git am --committer-date-is-author-date ${TMP_DIR}/patchset.patch

# Use generated cover-letter as a template for "sync commit" with
# baseline and checkpoint commits from kernel repo (and leave summary
# from cover letter intact, of course)
echo ${TIP_COMMIT} > CHECKPOINT-COMMIT &&					      \
git add CHECKPOINT-COMMIT &&							      \
awk '/\*\*\* BLURB HERE \*\*\*/ {p=1} p' ${TMP_DIR}/patches/0000-cover-letter.patch | \
sed "s/\*\*\* BLURB HERE \*\*\*/\
sync: latest libbpf changes from kernel\n\
\n\
Syncing latest libbpf commits from kernel repository.\n\
Baseline commit:   ${BASELINE_COMMIT}\n\
Checkpoint commit: ${TIP_COMMIT}/" |						      \
git commit --file=-

echo "SUCCESS! ${COMMIT_CNT} commits synced."

echo "Verifying Linux's and Github's libbpf state"
LIBBPF_VIEW_PATHS=(src include/uapi/linux/{bpf_common.h,bpf.h,btf.h,if_link.h,netlink.h} include/tools/libc_compat.h)
LIBBPF_VIEW_EXCLUDE_REGEX='^src/(Makefile|Build|test_libbpf.cpp|\.gitignore)$'

cd ${WORKDIR} && cd ${LINUX_REPO}
LINUX_ABS_DIR=$(pwd)
git checkout -b ${VIEW_TAG} ${TIP_COMMIT}
git filter-branch -f --tree-filter "${LIBBPF_TREE_FILTER}" ${VIEW_TAG}^..${VIEW_TAG}
git filter-branch -f --subdirectory-filter __libbpf ${VIEW_TAG}^..${VIEW_TAG}
git ls-files -- ${LIBBPF_VIEW_PATHS[@]} > ${TMP_DIR}/linux-view.ls

cd ${WORKDIR} && cd ${LIBBPF_REPO}
GITHUB_ABS_DIR=$(pwd)
git ls-files -- ${LIBBPF_VIEW_PATHS[@]} | grep -v -E "${LIBBPF_VIEW_EXCLUDE_REGEX}" > ${TMP_DIR}/github-view.ls

echo "Comparing list of files..."
diff ${TMP_DIR}/linux-view.ls ${TMP_DIR}/github-view.ls
echo "Comparing file contents..."
for F in $(cat ${TMP_DIR}/linux-view.ls); do
	diff "${LINUX_ABS_DIR}/${F}" "${GITHUB_ABS_DIR}/${F}"
done
echo "Contents appear identical!"

echo "Cleaning up..."
rm -r ${TMP_DIR}
cd ${WORKDIR} && cd ${LINUX_REPO}
git checkout ${TIP_SYM_REF}
git branch -D ${BASELINE_TAG} ${TIP_TAG} ${SQUASH_BASE_TAG} ${SQUASH_TIP_TAG} ${VIEW_TAG}

cd ${WORKDIR}
echo "DONE."

