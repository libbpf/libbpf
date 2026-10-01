#!/bin/bash
#
# Run scripts/sync-kernel.sh non-interactively: with stdin at EOF, any prompt
# asking for human input fails the sync. If the sync went through, <out-dir>
# gets everything needed to publish it: a bundle with the sync branch,
# patches, and a pull request description including the sync log.
#
# Exits with 0 if the sync went through or there was nothing to sync.

usage () {
	echo "USAGE: $0 <libbpf-repo> <linux-repo> <out-dir>"
	echo ""
	echo "<linux-repo> is expected to be set up by sync-fetch-kernel.sh."
	exit 1
}

set -euo pipefail

if [ $# -ne 3 ]; then
	usage
fi

LIBBPF_REPO=$(realpath "$1")
LINUX_REPO=$(realpath "$2")
OUT_DIR=$(realpath -m "$3")
GITHUB_OUTPUT=${GITHUB_OUTPUT:-/dev/null}
GITHUB_STEP_SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
# Pull request descriptions are limited to 65536 characters
PR_LOG_MAX=60000

cd "${LIBBPF_REPO}"
base_sha=$(git rev-parse HEAD)
old_next=$(cat CHECKPOINT-COMMIT)
old_bpf=$(cat BPF-CHECKPOINT-COMMIT)

mkdir -p "${OUT_DIR}/tmp"
# Keep sync-kernel.sh's temporary files around for post-mortem
export TMPDIR="${OUT_DIR}/tmp"
log="${OUT_DIR}/sync.log"

# The exit code of sync-kernel.sh can't be trusted (e.g., it exits with 0 when
# interrupted), so tell from its output how it went
"${LIBBPF_REPO}/scripts/sync-kernel.sh" "${LIBBPF_REPO}" "${LINUX_REPO}" bpf-master \
	< /dev/null 2>&1 | tee "${log}" || true
# Drop progress output overwritten with carriage returns
sed -i 's/^.*\r//' "${log}"

if grep -qF 'No new changes to apply, we are done!' "${log}"; then
	echo "::notice::No new libbpf changes since bpf-next ${old_next:0:12} and bpf ${old_bpf:0:12}"
	exit 0
fi
if ! grep -qF 'Great! Content is identical!' "${log}"; then
	echo "::error::Sync needs a human, see SYNC.md. The sync log and leftovers are in the run's artifact."
	exit 1
fi

branch=$(git symbolic-ref --short HEAD)
git format-patch -q -o "${OUT_DIR}/patches" "${base_sha}..HEAD"
git bundle create -q "${OUT_DIR}/sync.bundle" "${base_sha}..refs/heads/${branch}"

if [ -n "${GITHUB_RUN_ID:-}" ]; then
	origin="[workflow run](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID})"
else
	origin="a local run"
fi
new_files=$(git diff --name-only --diff-filter=A "${base_sha}" HEAD -- src include)

{
	echo "Automated libbpf sync from bpf-next and bpf trees, created by ${origin}."
	echo ""
	echo "| Tree | Baseline | Checkpoint |"
	echo "| --- | --- | --- |"
	echo "| bpf-next | ${old_next} | $(cat CHECKPOINT-COMMIT) |"
	echo "| bpf | ${old_bpf} | $(cat BPF-CHECKPOINT-COMMIT) |"
	echo ""
	echo "CI runs for this pull request have to be approved by a maintainer. If CI needs" \
	     "adjustments (allow/deny lists, \`ci/diffs\`, \`src/Makefile\`, see SYNC.md), push them to" \
	     "this branch."
	if [ -n "${new_files}" ]; then
		echo ""
		echo "New files were synced, check if \`src/Makefile\` needs updating:"
		echo ""
		# shellcheck disable=SC2016
		sed 's/^/- `/; s/$/`/' <<< "${new_files}"
	fi
	echo ""
	echo "<details>"
	echo "<summary>sync-kernel.sh output</summary>"
	echo ""
	echo '````'
	head -c "${PR_LOG_MAX}" "${log}"
	if (($(wc -c < "${log}") > PR_LOG_MAX)); then
		echo ""
		echo "[... truncated, the full log is in the workflow run's artifact ...]"
	fi
	echo '````'
	echo ""
	echo "</details>"
} > "${OUT_DIR}/pr-body.md"

cat "${OUT_DIR}/pr-body.md" >> "${GITHUB_STEP_SUMMARY}"
{
	echo "branch=${branch}"
	echo "head_sha=$(git rev-parse HEAD)"
} >> "${GITHUB_OUTPUT}"

echo "Synced $(git rev-list --count "${base_sha}..HEAD") commits into ${branch}"
