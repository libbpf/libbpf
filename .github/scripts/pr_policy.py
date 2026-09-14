import json
import os
import re
import sys

from github import Auth, Github, GithubException

COMMENT_MARKER = "<!-- libbpf-pr-source-routing:v1 -->"
OVERRIDE_LABEL = "github-only"
MAX_FILES = 3000

NOTICE = f"""{COMMENT_MARKER}
Thanks for the contribution. The authoritative libbpf source is maintained in the Linux kernel tree, so changes to the library itself must be submitted to the BPF mailing list instead of through this GitHub mirror.

Please send the patch to **bpf@vger.kernel.org**. See the [BPF development process](https://docs.kernel.org/bpf/bpf_devel_QA.html#q-how-do-i-submit-patches-to-bpf-kernel-trees) and this repository's [README](https://github.com/libbpf/libbpf/blob/master/README.md) for details.

GitHub pull requests remain appropriate for mirror-specific infrastructure, such as CI and `src/Makefile`. This workflow closes pull requests that include kernel-synchronized source, UAPI, documentation, or generated sync state; mixed pull requests should be split before being resubmitted.

If this was misclassified, a maintainer can apply the `{OVERRIDE_LABEL}` label and reopen the pull request."""

GITHUB_ONLY_PREFIXES = (
    ".github/",
    "assets/",
    "ci/",
    "docs/sphinx/",
    "fuzz/",
    "include/asm/",
    "include/linux/",
    "scripts/",
)
GITHUB_ONLY_FILES = {
    ".gitattributes",
    ".readthedocs.yaml",
    "README.md",
    "SYNC.md",
    "LICENSE",
    "docs/.gitignore",
    "docs/api.rst",
    "docs/conf.py",
    "src/.gitignore",
    "src/Makefile",
}
SYNC_ONLY_FILES = {
    ".mailmap",
    "BPF-CHECKPOINT-COMMIT",
    "CHECKPOINT-COMMIT",
    "src/bpf_helper_defs.h",
}
SYNC_BRANCH_RE = re.compile(r"libbpf-sync-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.\d{3}Z")
SYNC_MESSAGE_RES = tuple(
    re.compile(rf"^{label}:\s+[0-9a-f]{{40}}$", re.MULTILINE)
    for label in (
        "Baseline bpf-next commit",
        "Checkpoint bpf-next commit",
        "Baseline bpf commit",
        "Checkpoint bpf commit",
    )
)


def classify_path(path):
    if path in SYNC_ONLY_FILES:
        return "sync-only"
    if path in GITHUB_ONLY_FILES or path.startswith("LICENSE."):
        return "github-only"
    if path.startswith(GITHUB_ONLY_PREFIXES):
        return "github-only"
    if path.startswith(("src/", "include/uapi/", "docs/")):
        return "linux-owned"
    # New path families need a maintainer decision; leave them open meanwhile.
    return "unknown"


def has_override(pr):
    return any(label.name == OVERRIDE_LABEL for label in pr.labels)


def list_files(pr):
    if pr.changed_files > MAX_FILES:
        raise RuntimeError(
            f"#{pr.number} has {pr.changed_files} changed files; "
            f"GitHub exposes at most {MAX_FILES}"
        )

    files = list(pr.get_files())
    if len(files) != pr.changed_files:
        raise RuntimeError(
            f"#{pr.number}: expected {pr.changed_files} changed files, "
            f"received {len(files)}"
        )
    return files


def is_generated_sync(pr, files):
    # This is a triage exemption, not an authorization boundary. Sync PRs still
    # undergo normal review before merge, and either checkpoint can be unchanged.
    has_checkpoint = any(
        file.filename in {"CHECKPOINT-COMMIT", "BPF-CHECKPOINT-COMMIT"}
        and file.status == "modified"
        for file in files
    )
    if not SYNC_BRANCH_RE.fullmatch(pr.head.ref) or not has_checkpoint:
        return False

    commits = list(pr.get_commits())
    if len(commits) != pr.commits:
        raise RuntimeError(
            f"#{pr.number}: expected {pr.commits} commits, received {len(commits)}"
        )
    return any(
        commit.commit.message.startswith("sync: latest libbpf changes from kernel\n")
        and all(pattern.search(commit.commit.message) for pattern in SYNC_MESSAGE_RES)
        for commit in commits
    )


def policy_comments(pr):
    return [
        comment
        for comment in pr.get_issue_comments()
        if comment.user.login == "github-actions[bot]"
        and COMMENT_MARKER in comment.body
    ]


def upsert_notice(pr):
    comments = policy_comments(pr)
    if not comments:
        pr.create_issue_comment(NOTICE)
        comments = policy_comments(pr)
    if not comments:
        return

    # A manual sweep can overlap a per-PR event. Keep the oldest policy comment
    # so concurrent runs converge on one notice rather than leaving duplicates.
    primary = min(comments, key=lambda comment: comment.id)
    if primary.body != NOTICE:
        primary.edit(NOTICE)
    for duplicate in comments:
        if duplicate.id == primary.id:
            continue
        try:
            duplicate.delete()
        except GithubException as error:
            if error.status != 404:  # Another run may have deleted it first.
                raise


def still_current(original, current):
    return (
        current.state == "open"
        and current.base.ref == "master"
        and current.head.sha == original.head.sha
        and not has_override(current)
    )


def route_pull(repo, number, dry_run):
    pr = repo.get_pull(number)
    if pr.state != "open" or pr.base.ref != "master":
        print(f"#{number}: skipped because it is not open against master")
        return
    if has_override(pr):
        print(f"#{number}: allowed by {OVERRIDE_LABEL} label")
        return

    files = list_files(pr)
    if is_generated_sync(pr, files):
        print(f"#{number}: allowed generated sync PR")
        return

    paths = []
    for file in files:
        paths.append(file.filename)
        if file.previous_filename:
            paths.append(file.previous_filename)

    classified = [{"path": path, "category": classify_path(path)} for path in paths]
    routed = [
        item for item in classified if item["category"] in {"linux-owned", "sync-only"}
    ]
    unknown_count = sum(item["category"] == "unknown" for item in classified)
    if not routed:
        print(f"#{number}: left open ({unknown_count} unknown path(s))")
        return
    if dry_run:
        print(
            f"#{number}: dry run would comment and close because of "
            f"{json.dumps(routed)}"
        )
        return

    current = repo.get_pull(number)
    if not still_current(pr, current):
        print(f"#{number}: state changed during classification; leaving open")
        return

    upsert_notice(pr)
    before_close = repo.get_pull(number)
    if not still_current(pr, before_close):
        print(f"#{number}: state changed before closure; leaving open")
        return

    pr.edit(state="closed")
    print(f"#{number}: commented and closed")


def selected_pull_numbers(repo, requested):
    if requested:
        if not re.fullmatch(r"[1-9]\d*", requested):
            raise ValueError(f"invalid PR number: {requested}")
        return [int(requested)]

    return [pr.number for pr in repo.get_pulls(state="open", base="master")]


def main():
    repo_name = os.environ.get("GITHUB_REPOSITORY")
    if not repo_name or "/" not in repo_name:
        raise RuntimeError("GITHUB_REPOSITORY is not set")

    token = os.environ.get("GH_TOKEN")
    if not token:
        raise RuntimeError("GH_TOKEN is not set")

    dry_run = os.environ.get("DRY_RUN", "true").lower() != "false"
    with Github(auth=Auth.Token(token), per_page=100) as github:
        repo = github.get_repo(repo_name)
        numbers = selected_pull_numbers(repo, os.environ.get("PR_NUMBER", "").strip())
        print(
            f"{'Dry run: inspecting' if dry_run else 'Inspecting'} "
            f"{len(numbers)} pull request(s)"
        )

        failures = []
        for number in numbers:
            try:
                route_pull(repo, number, dry_run)
            except Exception as error:  # noqa: BLE001 - continue the manual sweep.
                failures.append(number)
                print(f"#{number}: {error}", file=sys.stderr)

    if failures:
        print(
            f"Failed to process {len(failures)} pull request(s): "
            + ", ".join(map(str, failures)),
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
