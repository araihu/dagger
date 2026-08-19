#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'reviewdog-action: %s\n' "$*" >&2
  exit 1
}

for required_command in jq realpath reviewdog stat; do
  command -v "$required_command" >/dev/null 2>&1 ||
    die "required command not found: $required_command"
done

manifest=${REVIEWDOG_MANIFEST:-}
token=${REVIEWDOG_GITHUB_API_TOKEN:-}
test -n "$manifest" || die "manifest input is empty"
test -n "$token" || die "token input is empty"
unset REVIEWDOG_GITHUB_API_TOKEN
test -e "$manifest" || die "manifest does not exist"
test ! -L "$manifest" || die "manifest must not be a symlink"
test -f "$manifest" || die "manifest must be a regular file"

manifest_real=$(realpath -e -- "$manifest")
report_root=$(dirname -- "$manifest_real")
if ! exec {manifest_fd}< "$manifest_real"; then
  die "manifest could not be opened"
fi
manifest_descriptor="/proc/self/fd/$manifest_fd"
opened_manifest_path=$(realpath -e -- "$manifest_descriptor")
test "$opened_manifest_path" = "$manifest_real" ||
  die "opened manifest differs from validated path"
test -f "$manifest_descriptor" || die "opened manifest must be a regular file"
manifest_size=$(stat -Lc %s -- "$manifest_descriptor")
test "$manifest_size" -le 65536 || die "manifest exceeds 65536 bytes"

if ! jq -e '
  type == "object"
  and keys == ["reports", "schema"]
  and .schema == 1
  and (.schema | type) == "number"
  and (.reports | type) == "array"
  and (.reports | length) >= 1
  and (.reports | length) <= 32
  and all(
    .reports[];
    type == "object"
    and ((keys - ["diff_strip", "filter_mode", "format", "level", "name", "path"]) | length) == 0
    and (.name | type) == "string"
    and (.name | test("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"))
    and (.path | type) == "string"
    and (.path | test("^[A-Za-z0-9][A-Za-z0-9._/-]{0,255}$"))
    and (.format | type) == "string"
    and (.format | test("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"))
    and ((has("level") | not) or (.level == "info" or .level == "warning" or .level == "error"))
    and ((has("filter_mode") | not) or (.filter_mode == "added" or .filter_mode == "diff_context" or .filter_mode == "file" or .filter_mode == "nofilter"))
    and (
      (has("diff_strip") | not)
      or (
        .format == "diff"
        and (.diff_strip | type) == "number"
        and .diff_strip == (.diff_strip | floor)
        and .diff_strip >= 0
        and .diff_strip <= 10
      )
    )
  )
' "$manifest_descriptor" >/dev/null; then
  die "manifest does not match schema version 1"
fi

declare -A supported_formats=()
parser_registry=$(reviewdog -list)
while read -r format _; do
  test -n "$format" && supported_formats["$format"]=1
done <<< "$parser_registry"
test "${#supported_formats[@]}" -gt 0 || die "reviewdog parser registry is empty"

declare -a names=()
declare -a report_fds=()
declare -a formats=()
declare -a levels=()
declare -a filter_modes=()
declare -a diff_strips=()
total_report_size=0

while IFS=$'\t' read -r name path format level filter_mode diff_strip; do
  test -n "${supported_formats[$format]:-}" ||
    die "unsupported reviewdog format: $format"
  case "/$path/" in
    *"/../"* | *"/./"*) die "report path contains a traversal segment: $path" ;;
  esac
  candidate_path="$report_root/$path"
  current_path=$report_root
  IFS='/' read -r -a path_segments <<< "$path"
  for path_segment in "${path_segments[@]}"; do
    current_path="$current_path/$path_segment"
    test ! -L "$current_path" || die "report path contains a symlink: $path"
  done
  report_path=$(realpath -e -- "$candidate_path")
  case "$report_path" in
    "$report_root"/*) ;;
    *) die "report escapes manifest directory: $path" ;;
  esac
  test -f "$report_path" || die "report must be a regular file: $path"
  if ! exec {report_fd}< "$report_path"; then
    die "report could not be opened: $path"
  fi
  descriptor_path="/proc/self/fd/$report_fd"
  opened_path=$(realpath -e -- "$descriptor_path")
  case "$opened_path" in
    "$report_root"/*) ;;
    *) die "opened report escapes manifest directory: $path" ;;
  esac
  test -f "$descriptor_path" || die "opened report must be a regular file: $path"
  report_size=$(stat -Lc %s -- "$descriptor_path")
  test "$report_size" -le 10485760 || die "report exceeds 10485760 bytes: $path"
  total_report_size=$((total_report_size + report_size))
  test "$total_report_size" -le 52428800 || die "combined reports exceed 52428800 bytes"
  names+=("$name")
  report_fds+=("$report_fd")
  formats+=("$format")
  levels+=("$level")
  filter_modes+=("$filter_mode")
  diff_strips+=("$diff_strip")
done < <(
  jq -r '
    .reports[]
    | [
        .name,
        .path,
        .format,
        (.level // "warning"),
        (.filter_mode // "added"),
        ((.diff_strip // "") | tostring)
      ]
    | @tsv
  ' "$manifest_descriptor"
)
exec {manifest_fd}<&-

for index in "${!names[@]}"; do
  args=(
    "-name=${names[$index]}"
    "-f=${formats[$index]}"
    "-reporter=github-pr-annotations"
    "-filter-mode=${filter_modes[$index]}"
    "-level=${levels[$index]}"
    "-fail-level=none"
  )
  if test -n "${diff_strips[$index]}"; then
    args+=("-f.diff.strip=${diff_strips[$index]}")
  fi
  report_fd=${report_fds[$index]}
  REVIEWDOG_GITHUB_API_TOKEN="$token" \
    reviewdog "${args[@]}" <&"$report_fd"
  exec {report_fd}<&-
done
