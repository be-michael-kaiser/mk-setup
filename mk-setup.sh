#!/usr/bin/env bash
#
# mk-setup.sh — copy the .devcontainer directory and the apm files
# (apm.yml, apm.lock.yaml) from this repository into a target folder.
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

RESOURCES=(".devcontainer" "apm.yml" "apm.lock.yaml")

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] <target-folder>

Copies the following resources from $SCRIPT_DIR into <target-folder>:
  ${RESOURCES[*]}

Options:
  -f, --force     Overwrite existing files in the target folder.
  -n, --dry-run   Show what would be copied without changing anything.
  -h, --help      Show this help.
EOF
}

force=0
dry_run=0
target=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)   force=1; shift ;;
        -n|--dry-run) dry_run=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        --)           shift; break ;;
        -*)           echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [[ -n "$target" ]]; then
                echo "Only one target folder may be given." >&2
                exit 2
            fi
            target="$1"; shift ;;
    esac
done

[[ -z "$target" && $# -gt 0 ]] && target="$1"

if [[ -z "$target" ]]; then
    usage >&2
    exit 2
fi

if [[ ! -d "$target" ]]; then
    if (( dry_run )); then
        echo "[dry-run] mkdir -p $target"
    else
        mkdir -p "$target"
    fi
fi

target_abs="$(cd -- "$target" 2>/dev/null && pwd || echo "$target")"

if [[ "$target_abs" == "$SCRIPT_DIR" ]]; then
    echo "Target folder is the source folder; nothing to do." >&2
    exit 1
fi

copied=0
skipped=0

for resource in "${RESOURCES[@]}"; do
    src="$SCRIPT_DIR/$resource"
    dest="$target_abs/$resource"

    if [[ ! -e "$src" ]]; then
        echo "warning: missing resource '$resource' in $SCRIPT_DIR — skipping" >&2
        continue
    fi

    if [[ -e "$dest" && $force -eq 0 ]]; then
        echo "skip   $resource (already exists, use --force to overwrite)"
        skipped=$((skipped + 1))
        continue
    fi

    if (( dry_run )); then
        echo "[dry-run] copy $src -> $dest"
    else
        rm -rf "$dest"
        cp -R "$src" "$dest"
        echo "copy   $resource -> $dest"
    fi
    copied=$((copied + 1))
done

echo "Done. $copied copied, $skipped skipped."
