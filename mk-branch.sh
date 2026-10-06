#!/usr/bin/env bash
#
# mk-branch.sh — freshly clone every repository listed in repos.json into
# <base-dir>/<repo> and check out a feature branch.
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOS_FILE="$SCRIPT_DIR/repos.json"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] <url-base> <base-dir> <feature-branch>

For each repository in $REPOS_FILE, clones <url-base>/<repo>.git into
<base-dir>/<repo> and checks out <feature-branch>, then runs mk-resources.sh to
copy the setup resources into <base-dir>.

Arguments:
  <url-base>        Clone URL prefix, e.g. https://github.com/<owner>.
  <base-dir>        Directory the clones are created in (created if missing).
                    Repositories that already exist there are skipped.
  <feature-branch>  Branch in the form feature/<name> (e.g. feature/f1). Tracks
                    origin/<branch> if it exists, otherwise creates it from
                    main (or master if there is no main).

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

if [[ ${#positional[@]} -ne 3 ]]; then
    usage >&2
    exit 2
fi

URL_BASE="${positional[0]%/}"
base_dir="${positional[1]}"
branch="${positional[2]}"

command -v jq >/dev/null || { echo "jq is required but not installed." >&2; exit 1; }
[[ -f "$REPOS_FILE" ]] || { echo "Repos file not found: $REPOS_FILE" >&2; exit 1; }

# Must be absolute: git -C changes the working directory.
[[ "$base_dir" = /* ]] || base_dir="$PWD/$base_dir"

feature_re='^feature/[A-Za-z0-9._-]+$'
[[ "$branch" =~ $feature_re ]] \
    || { echo "Feature branch must match feature/<name>, got: $branch" >&2; exit 2; }
git check-ref-format --branch "$branch" >/dev/null \
    || { echo "Invalid branch name: $branch" >&2; exit 2; }

run() {
    if (( dry_run )); then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

# has_head <ls-remote-output> <branch>
has_head() {
    awk -v r="refs/heads/$2" '$2 == r { f = 1 } END { exit !f }' <<<"$1"
}

repos=()
while IFS= read -r line; do repos+=("$line"); done < <(jq -r '.[]' "$REPOS_FILE")

cloned=0
skipped=0

for repo in "${repos[@]}"; do
    url="$URL_BASE/$repo.git"
    dest="$base_dir/$repo"

    if [[ -e "$dest" ]]; then
        echo "skip   $repo ($dest already exists)"
        skipped=$((skipped + 1))
        continue
    fi

    if ! heads="$(git ls-remote --heads "$url")"; then
        echo "warning: cannot reach $url — skipping" >&2
        skipped=$((skipped + 1))
        continue
    fi

    if has_head "$heads" "$branch"; then
        run git clone --branch "$branch" "$url" "$dest"
    elif has_head "$heads" main; then
        run git clone --branch main "$url" "$dest"
        run git -C "$dest" checkout -b "$branch"
    elif has_head "$heads" master; then
        run git clone --branch master "$url" "$dest"
        run git -C "$dest" checkout -b "$branch"
    else
        echo "warning: $repo has neither main nor master — skipping" >&2
        skipped=$((skipped + 1))
        continue
    fi

    echo "clone  $repo -> $dest ($branch)"
    cloned=$((cloned + 1))
done

echo "Done. $cloned cloned, $skipped skipped."

setup_args=()
(( dry_run )) && setup_args+=(--dry-run)
"$SCRIPT_DIR/mk-resources.sh" ${setup_args[@]+"${setup_args[@]}"} "$base_dir"
