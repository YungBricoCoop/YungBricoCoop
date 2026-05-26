#!/usr/bin/env zsh
set -euo pipefail

# cron setup:
# 0 10 */2 * * monthly-cleanup.sh >> /tmp/cleanup.out.log 2>> /tmp/cleanup.err.log

path_to_clean=~/GitHub
days_without_updates=30

target_names=(
  "venv"
  ".venv"
  "__pycache__"
  "pycache"
  "node_modules"
  "nodemodules"
)

human_size() {
  local size_kb="$1"

  LC_ALL=C awk -v size="$size_kb" '
    BEGIN {
      split("KB MB GB TB", units)

      unit_index = 1
      while (size >= 1024 && unit_index < 4) {
        size = size / 1024
        unit_index++
      }

      printf "%.2f %s", size, units[unit_index]
    }
  '
}

path_size() {
  du -sk "$1" 2>/dev/null | awk '{ print $1 }'
}

resolve_path() {
  local path="$1"

  (cd -P "$path" && pwd)
}

deleted_percent() {
  local before_kb="$1"
  local after_kb="$2"

  LC_ALL=C awk -v before="$before_kb" -v after="$after_kb" '
    BEGIN {
      if (before <= 0) {
        printf "0.00%%"
        exit
      }

      deleted = ((before - after) / before) * 100
      if (deleted < 0) {
        deleted = 0
      }

      printf "%.2f%%", deleted
    }
  '
}

find_targets() {
  local project_path="$1"
  local minimum_mtime_days=$((days_without_updates - 1))
  local -a target_find_args=()

  for target_name in "${target_names[@]}"; do
    if (( ${#target_find_args[@]} > 0 )); then
      target_find_args+=(-o)
    fi

    target_find_args+=(-name "$target_name")
  done

  find "$project_path" \
    \( -type d -name ".git" -prune \) -o \
    \( -type d \( "${target_find_args[@]}" \) -prune -mtime "+$minimum_mtime_days" -print0 \)
}

if [[ ! -d "$path_to_clean" ]]; then
  echo "cleanup skipped: $path_to_clean does not exist"
  exit 1
fi

clean_root="$(resolve_path "$path_to_clean")"

echo "starting cleanup in $clean_root"

space_before_kb="$(path_size "$clean_root")"
cleaned_count=0

while IFS= read -r -d "" project_path; do
  while IFS= read -r -d "" target_path; do
    [[ -d "$target_path" ]] || continue

    if rm -rf -- "$target_path"; then
      cleaned_count=$((cleaned_count + 1))
    fi
  done < <(find_targets "$project_path")
done < <(find "$clean_root" -mindepth 1 -maxdepth 1 -type d -print0)

space_after_kb="$(path_size "$clean_root")"

echo "cleaned: $cleaned_count folders"
echo "space before: $(human_size "$space_before_kb")"
echo "space after: $(human_size "$space_after_kb")"
echo "deleted: $(deleted_percent "$space_before_kb" "$space_after_kb")"
