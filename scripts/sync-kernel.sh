#!/bin/bash

usage () {
    echo "USAGE: ./sync-kernel.sh <kernel-repo> <libbpf-repo> [<baseline-commit>]"
    echo ""
    echo "If <baseline-commit> is not specified, it's read from <libbpf-repo>/CHECKPOINT-COMMIT."
    echo "Set MANUAL_MODE envvar to 1 to manually control every cherry-picked commita."
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

declare -A PATH_MAP
PATH_MAP=(									\
	[tools/lib/bpf]=src							\
	[tools/include/uapi/linux/bpf_common.h]=include/uapi/linux/bpf_common.h	\
	[tools/include/uapi/linux/bpf.h]=include/uapi/linux/bpf.h		\
	[tools/include/uapi/linux/btf.h]=include/uapi/linux/btf.h		\
	[tools/include/uapi/linux/if_link.h]=include/uapi/linux/if_link.h	\
	[tools/include/uapi/linux/if_xdp.h]=include/uapi/linux/if_xdp.h		\
	[tools/include/uapi/linux/netlink.h]=include/uapi/linux/netlink.h	\
	[tools/include/tools/libc_compat.h]=include/tools/libc_compat.h		\
)

LIBBPF_PATHS="${!PATH_MAP[@]}"
LIBBPF_VIEW_PATHS="${PATH_MAP[@]}"
LIBBPF_VIEW_EXCLUDE_REGEX='^src/(Makefile|Build|test_libbpf.cpp|\.gitignore)$'

LIBBPF_TREE_FILTER="mkdir -p __libbpf/include/uapi/linux __libbpf/include/tools && "$'\\\n'
for p in "${!PATH_MAP[@]}"; do
	LIBBPF_TREE_FILTER+="git mv -kf ${p} __libbpf/${PATH_MAP[${p}]} && "$'\\\n'
done
LIBBPF_TREE_FILTER+="git rm --ignore-unmatch -f __libbpf/src/{Makefile,Build,test_libbpf.cpp,.gitignore}"

cd_to()
{
	cd ${WORKDIR} && cd "$1"
}

# Output brief single-line commit description
# $1 - commit ref
commit_desc()
{
	git log -n1 --pretty='%h ("%s")' $1
}

# Create commit single-line signature, which consists of:
# - full commit hash
# - author date in ISO8601 format
# - full commit body with newlines replaced with vertical bars (|)
# - shortstat appended at the end
# The idea is that this single-line signature is good enough to make final
# decision about whether two commits are the same, across different repos.
# $1 - commit ref
commit_signature()
{
	git log -n1 --pretty='("%s")|%aI|%b' --shortstat $1 | tr '\n' '|'
}

# Validate there are no non-empty merges (we can't handle them)
# $1 - baseline tag
# $2 - tip tag
validate_merges()
{
	local baseline_tag=$1
	local tip_tag=$2
	local new_merges
	local merge_change_cnt

	new_merges=$(git rev-list --merges --topo-order --reverse ${baseline_tag}..${tip_tag} ${LIBBPF_PATHS[@]})
	for new_merge in ${new_merges}; do
		printf "MERGE:\t" && commit_desc ${new_merge}
		merge_change_cnt=$(git log --format='' -n1 ${new_merge} | wc -l)
		if ((${merge_change_cnt} > 0)); then
			echo "Merge $(commit_desc ${new_merge}) is non-empty, aborting!.."
			exit 3
		fi
	done
}

# Cherry-pick commits touching libbpf-related files
# $1 - baseline_tag
# $2 - tip_tag
cherry_pick_commits()
{
	local manual_mode=${MANUAL_MODE:-0}
	local baseline_tag=$1
	local tip_tag=$2
	local new_commits
	local signature
	local should_skip
	local synced_cnt
	local manual_check
	local desc

	new_commits=$(git rev-list --no-merges --topo-order --reverse ${baseline_tag}..${tip_tag} ${LIBBPF_PATHS[@]})
	for new_commit in ${new_commits}; do
		desc="$(commit_desc ${new_commit})"
		signature="$(commit_signature ${new_commit})"
		synced_cnt=$(grep -F "${signature}" ${TMP_DIR}/libbpf_commits.txt | wc -l)
		manual_check=0
		if ((${synced_cnt} > 0)); then
			# commit with the same subject is already in libbpf, but it's
			# not 100% the same commit, so check with user
			echo "Commit '${desc}' is synced into libbpf as:"
			grep -F "${signature}" ${TMP_DIR}/libbpf_commits.txt | \
				cut -d'|' -f1 | sed -e 's/^/- /'
			if ((${manual_mode} != 1 && ${synced_cnt} == 1)); then
				echo "Skipping '${desc}' due to unique match..."
				continue
			fi
			if ((${synced_cnt} > 1)); then
				echo "'${desc} matches multiple commits, please, double-check!"
				manual_check=1
			fi
		fi
		if ((${manual_mode} == 1 || ${manual_check} == 1)); then
			read -p "Do you want to skip '${desc}'? [y/N]: " should_skip
			case "${should_skip}" in
				"y" | "Y")
					echo "Skipping '${desc}'..."
					continue
					;;
			esac
		fi
		# commit hasn't been synced into libbpf yet
		echo "Picking '${desc}'..."
		if ! git cherry-pick ${new_commit} &>/dev/null; then
			read -p "Error! Cherry-picking '${desc}' failed, please fix manually and press <return> to proceed..."
		fi
	done
}

TMP_DIR=$(mktemp -d)

cd_to ${LIBBPF_REPO}

SUFFIX=$(date --utc +%Y-%m-%dT%H-%M-%S.%3NZ)
BASELINE_COMMIT=${3-$(cat CHECKPOINT-COMMIT)}

echo "Dumping existing libbpf commit signatures..."
for h in $(git log --pretty='%h' -n500); do
	echo $h "$(commit_signature $h)" >> ${TMP_DIR}/libbpf_commits.txt
done

# Use current kernel repo HEAD as a source of patches
cd_to ${LINUX_REPO}
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

echo "WORKDIR:         ${WORKDIR}"
echo "LINUX REPO:      ${LINUX_REPO}"
echo "LIBBPF REPO:     ${LIBBPF_REPO}"
echo "TEMP DIR:        ${TMP_DIR}"
echo "SUFFIX:          ${SUFFIX}"
echo "BASELINE COMMIT: '$(commit_desc ${BASELINE_COMMIT})'"
echo "TIP COMMIT:      '$(commit_desc ${TIP_COMMIT})'"
echo "SQUASH COMMIT:   ${SQUASH_COMMIT}"
echo "BASELINE TAG:    ${BASELINE_TAG}"
echo "TIP TAG:         ${TIP_TAG}"
echo "SQUASH BASE TAG: ${SQUASH_BASE_TAG}"
echo "SQUASH TIP TAG:  ${SQUASH_TIP_TAG}"
echo "VIEW TAG:        ${VIEW_TAG}"
echo "LIBBPF SYNC TAG: ${LIBBPF_SYNC_TAG}"
echo "PATCHES+COVER:   ${TMP_DIR}/patches"
echo "PATCHSET:        ${TMP_DIR}/patchset.patch"

git branch ${BASELINE_TAG} ${BASELINE_COMMIT}
git branch ${TIP_TAG} ${TIP_COMMIT}
git branch ${SQUASH_BASE_TAG} ${SQUASH_COMMIT}
git checkout -b ${SQUASH_TIP_TAG} ${SQUASH_COMMIT}

# Validate there are no non-empty merges in bpf-next and bpf trees
validate_merges ${BASELINE_TAG} ${TIP_TAG}

# Cherry-pick new commits onto squashed baseline commit
cherry_pick_commits ${BASELINE_TAG} ${TIP_TAG}

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
cd_to ${LIBBPF_REPO}
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

cd_to ${LINUX_REPO}
LINUX_ABS_DIR=$(pwd)
git checkout -b ${VIEW_TAG} ${TIP_COMMIT}
git filter-branch -f --tree-filter "${LIBBPF_TREE_FILTER}" ${VIEW_TAG}^..${VIEW_TAG}
git filter-branch -f --subdirectory-filter __libbpf ${VIEW_TAG}^..${VIEW_TAG}
git ls-files -- ${LIBBPF_VIEW_PATHS[@]} > ${TMP_DIR}/linux-view.ls

cd_to ${LIBBPF_REPO}
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
cd_to ${LINUX_REPO}
git checkout ${TIP_SYM_REF}
git branch -D ${BASELINE_TAG} ${TIP_TAG} ${SQUASH_BASE_TAG} ${SQUASH_TIP_TAG} ${VIEW_TAG}

cd_to .
echo "DONE."

