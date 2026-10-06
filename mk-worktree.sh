#!/usr/bin/env bash
#
# mk-worktree.sh — create a git worktree for every repository listed in
# repos.json into <worktree-root>/<repo>.
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOS_FILE="$SCRIPT_DIR/repos.json"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] <base-dir> <worktree-root> [feature-branch]

For each repository in $REPOS_FILE, creates a git worktree from the clone at
<base-dir>/<repo> into <worktree-root>/<repo>, then runs mk-resources.sh to copy
the setup resources into <worktree-root>.

Arguments:
  <base-dir>        Directory that contains the repository clones.
  <worktree-root>   Directory the worktrees are created in (created if missing).
  [feature-branch]  Branch to check out in each worktree, in the form
                    feature/<name> (e.g. feature/f1). Uses the local branch
                    if it exists, otherwise tracks origin/<branch> if present,
                    otherwise creates it from the repo's current HEAD.
                    If omitted, main (or master if there is no main) is used,
                    locally or from origin; if it is already checked out
                    elsewhere, the worktree gets a detached HEAD at that branch.

Options:
  -r, --repos FILE  Use a different repos.json (default: $REPOS_FILE).
  -n, --dry-run     Show what would be done without changing anything.
  -h, --help        Show this help.
EOF
}

dry_run=0
positional=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--repos)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
            REPOS_FILE="$2"; shift 2 ;;
        -n|--dry-run) dry_run=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        --)           shift; positional+=("$@"); break ;;
        -*)           echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)            positional+=("$1"); shift ;;
    esac
done

if [[ ${#positional[@]} -lt 2 || ${#positional[@]} -gt 3 ]]; then
    usage >&2
    exit 2
fi

base_dir="${positional[0]}"
worktree_root="${positional[1]}"
branch="${positional[2]:-}"

command -v jq >/dev/null || { echo "jq is required but not installed." >&2; exit 1; }
[[ -f "$REPOS_FILE" ]] || { echo "Repos file not found: $REPOS_FILE" >&2; exit 1; }
[[ -d "$base_dir" ]] || { echo "Base dir not found: $base_dir" >&2; exit 1; }

base_dir="$(cd -- "$base_dir" && pwd)"
# Must be absolute: git -C changes the working directory.
[[ "$worktree_root" = /* ]] || worktree_root="$PWD/$worktree_root"

if [[ -n "$branch" ]]; then
    feature_re='^feature/[A-Za-z0-9._-]+$'
    [[ "$branch" =~ $feature_re ]] \
        || { echo "Feature branch must match feature/<name>, got: $branch" >&2; exit 2; }
    git check-ref-format --branch "$branch" >/dev/null \
        || { echo "Invalid branch name: $branch" >&2; exit 2; }
fi

run() {
    if (( dry_run )); then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

default_branch() {
    local b
    for b in main master; do
        if git -C "$1" show-ref --verify --quiet "refs/heads/$b" \
            || git -C "$1" show-ref --verify --quiet "refs/remotes/origin/$b"; then
            echo "$b"
            return
        fi
    done
    echo main
}

repos=()
while IFS= read -r line; do repos+=("$line"); done < <(jq -r '.[]' "$REPOS_FILE")

created=0
skipped=0

for repo in "${repos[@]}"; do
    src="$base_dir/$repo"
    dest="$worktree_root/$repo"

    if ! git -C "$src" rev-parse --git-dir >/dev/null 2>&1; then
        echo "warning: $src is not a git repository — skipping" >&2
        skipped=$((skipped + 1))
        continue
    fi

    if [[ -e "$dest" ]]; then
        echo "skip   $repo ($dest already exists)"
        skipped=$((skipped + 1))
        continue
    fi

    target="${branch:-$(default_branch "$src")}"

    if git -C "$src" show-ref --verify --quiet "refs/heads/$target"; then
        # git refuses to check out a branch twice, so fall back to detached.
        if [[ -z "$branch" ]] && grep -qxF "branch refs/heads/$target" \
                < <(git -C "$src" worktree list --porcelain); then
            run git -C "$src" worktree add --detach "$dest" "$target"
        else
            run git -C "$src" worktree add "$dest" "$target"
        fi
    elif git -C "$src" show-ref --verify --quiet "refs/remotes/origin/$target"; then
        run git -C "$src" worktree add --track -b "$target" "$dest" "origin/$target"
    elif [[ -n "$branch" ]]; then
        run git -C "$src" worktree add -b "$branch" "$dest"
    else
        echo "warning: $repo has neither main nor master — skipping" >&2
        skipped=$((skipped + 1))
        continue
    fi

    echo "create $repo -> $dest"
    created=$((created + 1))
done

echo "Done. $created created, $skipped skipped."

setup_args=()
(( dry_run )) && setup_args+=(--dry-run)
"$SCRIPT_DIR/mk-resources.sh" ${setup_args[@]+"${setup_args[@]}"} "$worktree_root"
