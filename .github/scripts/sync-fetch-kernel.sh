#!/bin/bash
#
# Set up a Linux repo the way scripts/sync-kernel.sh expects it (see SYNC.md):
# HEAD at bpf-next's master, and a local bpf-master branch at bpf's master.
#
# Both trees are fetched from the kernel-patches/bpf mirror on GitHub, which
# is more reliable than git.kernel.org. The mirror may lag behind, but its
# branches have to be in the history of master branches on git.kernel.org.

usage () {
	echo "USAGE: $0 <libbpf-repo> <linux-repo>"
	echo ""
	echo "<linux-repo> is created and must not exist yet."
	echo "Set MIRROR_URL, BPF_NEXT_URL and BPF_URL to fetch from and check against other repos."
	exit 1
}

set -euo pipefail

LIBBPF_REPO=${1-""}
LINUX_REPO=${2-""}

if [ -z "${LIBBPF_REPO}" ] || [ -z "${LINUX_REPO}" ]; then
	usage
fi

# The mirror's bpf-next and bpf branches track master of the respective trees
MIRROR_URL=${MIRROR_URL:-https://github.com/kernel-patches/bpf.git}
BPF_NEXT_URL=${BPF_NEXT_URL:-https://git.kernel.org/pub/scm/linux/kernel/git/bpf/bpf-next.git}
BPF_URL=${BPF_URL:-https://git.kernel.org/pub/scm/linux/kernel/git/bpf/bpf.git}

die()
{
	echo "Error: $*" >&2
	exit 1
}

# Fetching just the commit by its ID wouldn't do: it's already here, and
# git.kernel.org repos share objects, so it could come from another tree.
# $1 - mirror's branch
# $2 - git.kernel.org repo URL
check_upstream()
{
	git fetch -q --no-tags "$2" refs/heads/master || die "can't fetch master from $2"
	git merge-base --is-ancestor "$1" FETCH_HEAD ||
		die "mirror's $1 ($(git rev-parse --short "$1")) is not in the history of master in $2"
}

[ ! -e "${LINUX_REPO}" ] || die "${LINUX_REPO} already exists"
BPF_NEXT_BASE=$(cat "${LIBBPF_REPO}/CHECKPOINT-COMMIT")
BPF_BASE=$(cat "${LIBBPF_REPO}/BPF-CHECKPOINT-COMMIT")

git init -q -b master "${LINUX_REPO}"
cd "${LINUX_REPO}"
git config gc.auto 0

echo "Fetching bpf-next and bpf from ${MIRROR_URL}..."
git fetch -q --no-tags "${MIRROR_URL}" \
	+refs/heads/bpf-next:refs/remotes/bpf-next/master \
	+refs/heads/bpf:refs/remotes/bpf/master

echo "Checking them against git.kernel.org..."
check_upstream bpf-next/master "${BPF_NEXT_URL}"
check_upstream bpf/master "${BPF_URL}"

git merge-base --is-ancestor "${BPF_NEXT_BASE}" bpf-next/master ||
	die "checkpoint ${BPF_NEXT_BASE} is not in bpf-next's history; if it was rebased away upstream, update the checkpoint manually"
git merge-base --is-ancestor "${BPF_BASE}" bpf/master ||
	die "checkpoint ${BPF_BASE} is not in bpf's history; if it was rebased away upstream, update the checkpoint manually"

git checkout -q -B master bpf-next/master
git branch -q -f bpf-master bpf/master

echo "bpf-next tip: $(git log -n1 --pretty='%h ("%s")' master)"
echo "bpf tip:      $(git log -n1 --pretty='%h ("%s")' bpf-master)"
