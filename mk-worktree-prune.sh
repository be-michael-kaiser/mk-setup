#!/usr/bin/env bash
#
# mk-worktree-prune.sh — run `git worktree prune` for every repository listed
# in repos.json under <base-dir>/<repo>.
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOS_FILE="$SCRIPT_DIR/repos.json"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] <base-dir>

For each repository in $REPOS_FILE, runs \`git worktree prune\` in the clone at
<base-dir>/<repo> to remove stale worktree metadata (e.g. for deleted folders).

Arguments:
  <base-dir>        Directory that contains the repository clones.

Options:
  -r, --repos FILE  Use a different repos.json (default: $REPOS_FILE).
  -n, --dry-run     Report what would be pruned without removing anything.
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

if [[ ${#positional[@]} -ne 1 ]]; then
    usage >&2
    exit 2
fi

base_dir="${positional[0]}"

command -v jq >/dev/null || { echo "jq is required but not installed." >&2; exit 1; }
[[ -f "$REPOS_FILE" ]] || { echo "Repos file not found: $REPOS_FILE" >&2; exit 1; }
[[ -d "$base_dir" ]] || { echo "Base dir not found: $base_dir" >&2; exit 1; }

base_dir="$(cd -- "$base_dir" && pwd)"

prune_args=(--verbose)
(( dry_run )) && prune_args+=(--dry-run)

repos=()
while IFS= read -r line; do repos+=("$line"); done < <(jq -r '.[]' "$REPOS_FILE")

pruned=0
skipped=0

for repo in "${repos[@]}"; do
    src="$base_dir/$repo"

    if ! git -C "$src" rev-parse --git-dir >/dev/null 2>&1; then
        echo "warning: $src is not a git repository — skipping" >&2
        skipped=$((skipped + 1))
        continue
    fi

    echo "prune  $repo"
    git -C "$src" worktree prune "${prune_args[@]}"
    pruned=$((pruned + 1))
done

echo "Done. $pruned pruned, $skipped skipped."
