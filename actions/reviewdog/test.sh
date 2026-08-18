#!/usr/bin/env bash
set -euo pipefail

ACTION_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
RUNNER="$ACTION_DIR/run.sh"
TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$TEST_TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1 literal=$2
  grep -Fqx -- "$literal" "$file" || fail "$file lacks $literal"
}

assert_file_lacks() {
  local file=$1 literal=$2
  if grep -Fqx -- "$literal" "$file"; then
    fail "$file unexpectedly contains $literal"
  fi
}

FAKE_BIN="$TEST_TMP/bin"
CALLS="$TEST_TMP/calls"
mkdir -p "$FAKE_BIN" "$CALLS"

printf '%s\n' '#!/usr/bin/env bash' > "$FAKE_BIN/reviewdog"
printf '%s\n' 'set -euo pipefail' >> "$FAKE_BIN/reviewdog"
printf '%s\n' 'if [[ ${1:-} == -list ]]; then' >> "$FAKE_BIN/reviewdog"
printf '%s\n' "  printf '%s\\n' \\" >> "$FAKE_BIN/reviewdog"
printf '%s\n' "    'rdjson Reviewdog Diagnostic JSON Format' \\" >> "$FAKE_BIN/reviewdog"
printf '%s\n' "    'rdjsonl Reviewdog Diagnostic JSONL Format' \\" >> "$FAKE_BIN/reviewdog"
printf '%s\n' "    'diff Unified Diff Format' \\" >> "$FAKE_BIN/reviewdog"
printf '%s\n' "    'checkstyle checkstyle XML format' \\" >> "$FAKE_BIN/reviewdog"
printf '%s\n' "    'sarif SARIF JSON format' \\" >> "$FAKE_BIN/reviewdog"
printf '%s\n' "    'govet Go vet' \\" >> "$FAKE_BIN/reviewdog"
printf '%s\n' "    'golangci-lint GolangCI-Lint' \\" >> "$FAKE_BIN/reviewdog"
printf '%s\n' "    'eslint ESLint'" >> "$FAKE_BIN/reviewdog"
printf '%s\n' '  exit 0' >> "$FAKE_BIN/reviewdog"
printf '%s\n' 'fi' >> "$FAKE_BIN/reviewdog"
printf '%s\n' 'index=1' >> "$FAKE_BIN/reviewdog"
printf '%s\n' 'while [[ -e "$REVIEWDOG_TEST_CALLS/$index.args" ]]; do index=$((index + 1)); done' >> "$FAKE_BIN/reviewdog"
printf '%s\n' 'printf "%s\\n" "$@" > "$REVIEWDOG_TEST_CALLS/$index.args"' >> "$FAKE_BIN/reviewdog"
printf '%s\n' 'cat > "$REVIEWDOG_TEST_CALLS/$index.stdin"' >> "$FAKE_BIN/reviewdog"
chmod 0755 "$FAKE_BIN/reviewdog"

PATH="$FAKE_BIN:$PATH" \
REVIEWDOG_TEST_CALLS="$CALLS" \
REVIEWDOG_MANIFEST="$ACTION_DIR/testdata/valid/manifest.json" \
REVIEWDOG_GITHUB_API_TOKEN=test-token \
  "$RUNNER"

test -f "$CALLS/1.args" || fail "first report was not invoked"
test -f "$CALLS/2.args" || fail "second report was not invoked"
test ! -e "$CALLS/3.args" || fail "unexpected third report invocation"

assert_file_contains "$CALLS/1.args" "-name=go-vet"
assert_file_contains "$CALLS/1.args" "-f=govet"
assert_file_contains "$CALLS/1.args" "-reporter=github-pr-annotations"
assert_file_contains "$CALLS/1.args" "-filter-mode=file"
assert_file_contains "$CALLS/1.args" "-level=error"
assert_file_contains "$CALLS/1.args" "-fail-level=none"
assert_file_lacks "$CALLS/1.args" "-f.diff.strip=0"
cmp "$ACTION_DIR/testdata/valid/go-vet.txt" "$CALLS/1.stdin"
printf '%s\n' \
  '-name=go-vet' \
  '-f=govet' \
  '-reporter=github-pr-annotations' \
  '-filter-mode=file' \
  '-level=error' \
  '-fail-level=none' > "$TEST_TMP/expected-1.args"
cmp "$TEST_TMP/expected-1.args" "$CALLS/1.args"

assert_file_contains "$CALLS/2.args" "-name=gofmt"
assert_file_contains "$CALLS/2.args" "-f=diff"
assert_file_contains "$CALLS/2.args" "-reporter=github-pr-annotations"
assert_file_contains "$CALLS/2.args" "-filter-mode=added"
assert_file_contains "$CALLS/2.args" "-level=warning"
assert_file_contains "$CALLS/2.args" "-fail-level=none"
assert_file_contains "$CALLS/2.args" "-f.diff.strip=0"
cmp "$ACTION_DIR/testdata/valid/gofmt.diff" "$CALLS/2.stdin"
printf '%s\n' \
  '-name=gofmt' \
  '-f=diff' \
  '-reporter=github-pr-annotations' \
  '-filter-mode=added' \
  '-level=warning' \
  '-fail-level=none' \
  '-f.diff.strip=0' > "$TEST_TMP/expected-2.args"
cmp "$TEST_TMP/expected-2.args" "$CALLS/2.args"

printf 'PASS: valid manifest invokes ordered reports with exact arguments and stdin\n'

new_case() {
  local name=$1
  CASE_DIR="$TEST_TMP/cases/$name"
  mkdir -p "$CASE_DIR"
  cp "$ACTION_DIR/testdata/valid/go-vet.txt" "$CASE_DIR/go-vet.txt"
  cp "$ACTION_DIR/testdata/valid/gofmt.diff" "$CASE_DIR/gofmt.diff"
  CASE_MANIFEST="$CASE_DIR/manifest.json"
}

jq_case() {
  local name=$1 filter=$2
  new_case "$name"
  jq "$filter" "$ACTION_DIR/testdata/valid/manifest.json" > "$CASE_MANIFEST"
}

expect_failure() {
  local label=$1 manifest=$2
  local token=${3-test-token}
  local stdout_file="$TEST_TMP/${label//[^A-Za-z0-9_.-]/_}.stdout"
  local stderr_file="$TEST_TMP/${label//[^A-Za-z0-9_.-]/_}.stderr"
  rm -rf -- "$CALLS"
  mkdir -p "$CALLS"
  if PATH="$FAKE_BIN:$PATH" \
    REVIEWDOG_TEST_CALLS="$CALLS" \
    REVIEWDOG_MANIFEST="$manifest" \
    REVIEWDOG_GITHUB_API_TOKEN="$token" \
      "$RUNNER" > "$stdout_file" 2> "$stderr_file"; then
    fail "$label unexpectedly succeeded"
  fi
  if find "$CALLS" -type f -name '*.args' -print -quit | grep -q .; then
    fail "$label invoked reviewdog before rejecting input"
  fi
  printf 'PASS: %s rejected before report invocation\n' "$label"
}

jq_case schema_missing 'del(.schema)'
expect_failure schema_missing "$CASE_MANIFEST"

jq_case schema_wrong_type '.schema = "1"'
expect_failure schema_wrong_type "$CASE_MANIFEST"

jq_case schema_wrong_value '.schema = 2'
expect_failure schema_wrong_value "$CASE_MANIFEST"

jq_case unknown_top_level_key '.unexpected = true'
expect_failure unknown_top_level_key "$CASE_MANIFEST"

jq_case reports_missing 'del(.reports)'
expect_failure reports_missing "$CASE_MANIFEST"

jq_case reports_wrong_type '.reports = {}'
expect_failure reports_wrong_type "$CASE_MANIFEST"

jq_case reports_empty '.reports = []'
expect_failure reports_empty "$CASE_MANIFEST"

jq_case reports_over_limit '.reports = [range(0; 33) as $i | {name: ("tool-" + ($i | tostring)), path: "go-vet.txt", format: "govet"}]'
expect_failure reports_over_limit "$CASE_MANIFEST"

jq_case report_wrong_type '.reports = ["not-an-object"]'
expect_failure report_wrong_type "$CASE_MANIFEST"

jq_case unknown_report_key '.reports[0].unexpected = true'
expect_failure unknown_report_key "$CASE_MANIFEST"

jq_case name_missing 'del(.reports[0].name)'
expect_failure name_missing "$CASE_MANIFEST"

jq_case name_invalid '.reports[0].name = "go vet; false"'
expect_failure name_invalid "$CASE_MANIFEST"

jq_case name_too_long '.reports[0].name = ("a" * 65)'
expect_failure name_too_long "$CASE_MANIFEST"

jq_case path_missing 'del(.reports[0].path)'
expect_failure path_missing "$CASE_MANIFEST"

jq_case path_invalid '.reports[0].path = "go vet.txt"'
expect_failure path_invalid "$CASE_MANIFEST"

jq_case path_too_long '.reports[0].path = (("a" * 253) + ".txt")'
expect_failure path_too_long "$CASE_MANIFEST"

jq_case format_missing 'del(.reports[0].format)'
expect_failure format_missing "$CASE_MANIFEST"

jq_case format_unsupported '.reports[0].format = "unknown-parser"'
expect_failure format_unsupported "$CASE_MANIFEST"

jq_case later_format_unsupported '.reports[1].format = "unknown-parser"'
expect_failure later_format_unsupported "$CASE_MANIFEST"

jq_case level_invalid '.reports[0].level = "fatal"'
expect_failure level_invalid "$CASE_MANIFEST"

jq_case filter_mode_invalid '.reports[0].filter_mode = "changed"'
expect_failure filter_mode_invalid "$CASE_MANIFEST"

jq_case diff_strip_negative '.reports[1].diff_strip = -1'
expect_failure diff_strip_negative "$CASE_MANIFEST"

jq_case diff_strip_too_large '.reports[1].diff_strip = 11'
expect_failure diff_strip_too_large "$CASE_MANIFEST"

jq_case diff_strip_not_integer '.reports[1].diff_strip = 1.5'
expect_failure diff_strip_not_integer "$CASE_MANIFEST"

jq_case diff_strip_non_diff '.reports[0].diff_strip = 0'
expect_failure diff_strip_non_diff "$CASE_MANIFEST"

new_case invalid_json
printf '{' > "$CASE_MANIFEST"
expect_failure invalid_json "$CASE_MANIFEST"

new_case top_level_array
printf '[]\n' > "$CASE_MANIFEST"
expect_failure top_level_array "$CASE_MANIFEST"

jq_case absolute_report_path '.reports = [{name: "absolute", path: "/etc/passwd", format: "govet"}]'
expect_failure absolute_report_path "$CASE_MANIFEST"

jq_case parent_traversal '.reports = [{name: "parent", path: "../go-vet.txt", format: "govet"}]'
expect_failure parent_traversal "$CASE_MANIFEST"

jq_case embedded_traversal '.reports = [{name: "embedded", path: "nested/../go-vet.txt", format: "govet"}]'
mkdir -p "$CASE_DIR/nested"
expect_failure embedded_traversal "$CASE_MANIFEST"

jq_case missing_report '.reports = [{name: "missing", path: "missing.txt", format: "govet"}]'
expect_failure missing_report "$CASE_MANIFEST"

jq_case report_is_directory '.reports = [{name: "directory", path: "reports", format: "govet"}]'
mkdir -p "$CASE_DIR/reports"
expect_failure report_is_directory "$CASE_MANIFEST"

jq_case report_symlink '.reports = [{name: "symlink", path: "alias.txt", format: "govet"}]'
ln -s go-vet.txt "$CASE_DIR/alias.txt"
expect_failure report_symlink "$CASE_MANIFEST"

jq_case later_report_symlink '.reports[1].path = "alias.txt"'
ln -s gofmt.diff "$CASE_DIR/alias.txt"
expect_failure later_report_symlink "$CASE_MANIFEST"

new_case intermediate_symlink_escape
printf 'outside diagnostic\n' > "$TEST_TMP/outside.txt"
ln -s "$TEST_TMP" "$CASE_DIR/escape"
jq '.reports = [{name: "escape", path: "escape/outside.txt", format: "govet"}]' \
  "$ACTION_DIR/testdata/valid/manifest.json" > "$CASE_MANIFEST"
expect_failure intermediate_symlink_escape "$CASE_MANIFEST"

new_case manifest_symlink
cp "$ACTION_DIR/testdata/valid/manifest.json" "$CASE_DIR/manifest-target.json"
ln -s manifest-target.json "$CASE_MANIFEST"
expect_failure manifest_symlink "$CASE_MANIFEST"

new_case manifest_too_large
cp "$ACTION_DIR/testdata/valid/manifest.json" "$CASE_MANIFEST"
padding=$((65537 - $(stat -c %s -- "$CASE_MANIFEST")))
test "$padding" -gt 0
head -c "$padding" /dev/zero | tr '\0' ' ' >> "$CASE_MANIFEST"
test "$(stat -c %s -- "$CASE_MANIFEST")" -eq 65537
expect_failure manifest_too_large "$CASE_MANIFEST"

jq_case report_too_large '.reports = [{name: "large", path: "go-vet.txt", format: "govet"}]'
truncate -s 10485761 "$CASE_DIR/go-vet.txt"
expect_failure report_too_large "$CASE_MANIFEST"

new_case reports_total_too_large
for index in 0 1 2 3 4; do
  truncate -s 10485760 "$CASE_DIR/report-$index.txt"
done
truncate -s 1 "$CASE_DIR/report-5.txt"
jq -n '{
  schema: 1,
  reports: [
    range(0; 6) as $index
    | {
        name: ("report-" + ($index | tostring)),
        path: ("report-" + ($index | tostring) + ".txt"),
        format: "govet"
      }
  ]
}' > "$CASE_MANIFEST"
expect_failure reports_total_too_large "$CASE_MANIFEST"

printf -v substitution_injection '\$(touch %s)' "$TEST_TMP/injection-canary"
printf -v backtick_injection '`touch %s`' "$TEST_TMP/injection-canary"
printf -v semicolon_injection 'name;touch %s' "$TEST_TMP/injection-canary"
for injection_name in \
  "$substitution_injection" \
  "$backtick_injection" \
  "$semicolon_injection" \
  'name with spaces'; do
  new_case command_injection
  jq --arg value "$injection_name" '.reports[0].name = $value' \
    "$ACTION_DIR/testdata/valid/manifest.json" > "$CASE_MANIFEST"
  expect_failure command_injection "$CASE_MANIFEST"
  test ! -e "$TEST_TMP/injection-canary" ||
    fail "command injection created canary"
done

new_case tab_injection
jq --arg value $'name\tother' '.reports[0].name = $value' \
  "$ACTION_DIR/testdata/valid/manifest.json" > "$CASE_MANIFEST"
expect_failure tab_injection "$CASE_MANIFEST"
test ! -e "$TEST_TMP/injection-canary" ||
  fail "tab injection created canary"

expect_failure empty_token "$ACTION_DIR/testdata/valid/manifest.json" ""

jq_case secret_redaction '.schema = 2'
secret_value='super-secret-value-that-must-not-appear'
expect_failure secret_redaction "$CASE_MANIFEST" "$secret_value"
if grep -Fq -- "$secret_value" \
  "$TEST_TMP/secret_redaction.stdout" "$TEST_TMP/secret_redaction.stderr"; then
  fail "token content appeared in action output"
fi
printf 'PASS: token content absent from action output\n'
