# Reusable Reviewdog Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking. Do not dispatch subagents unless the
> user explicitly authorizes delegation.

**Goal:** Build a SHA-pinned, organization-owned composite action that turns
diagnostic files exported by Dagger CI into GitHub pull request annotations
without making Reviewdog the CI gate.

**Architecture:** Dagger remains responsible for running tools, capturing their
exit status, and exporting diagnostic files. `actions/reviewdog` runs only on
the GitHub host, validates a strict manifest and report boundary, installs
Reviewdog `v0.21.0`, and emits `github-pr-annotations`. Existing Dagger modules
remain side-effect-free and receive no GitHub token.

**Tech Stack:** GitHub composite actions, Bash 5, jq, GNU coreutils,
Reviewdog `v0.21.0`, GitHub Actions on Ubuntu 24.04, existing Go/Dagger module
tests.

**Spec:** `docs/superpowers/specs/2026-08-18-reviewdog-action-design.md`

## Global Constraints

- Base revision is
  `538925606bdde05bf26309900ce05a63942e1c13` from `origin/main`.
- Work occurs in isolated branch `feat/reviewdog-action`; primary checkout
  remains unchanged.
- Reviewdog setup action is pinned to commit
  `d8a7baabd7f3e8544ee4dbde3ee41d0011c3a93f`.
- Installed Reviewdog version is exactly `v0.21.0`; never use `latest`.
- First release supports Linux GitHub Actions and reporter
  `github-pr-annotations` only.
- Consumer permissions are `contents: read` and `pull-requests: read`; no write
  permission is added.
- `GITHUB_TOKEN` stays on the GitHub runner and is never passed into Dagger.
- Reviewdog findings never determine CI success; Dagger's exported `status`
  file remains authoritative.
- Manifest content is untrusted. Never use `eval`, shell interpolation of
  manifest values, manifest-selected executables, absolute report paths, or
  paths outside the manifest directory.
- Validate the complete manifest and every report before the first Reviewdog
  invocation; invalid later entries must not cause partial annotations.
- No existing Dagger module API changes in this implementation.
- No commit, push, PR, merge, tag, release, or pilot-repository mutation without
  separate user authorization for that lifecycle action.

---

## File Map

- Create `actions/reviewdog/action.yml`: public composite-action interface and
  pinned Reviewdog installer.
- Create `actions/reviewdog/run.sh`: complete manifest validation and ordered
  Reviewdog invocation.
- Create `actions/reviewdog/test.sh`: executable behavior test harness using a
  fake Reviewdog binary.
- Create `actions/reviewdog/testdata/valid/manifest.json`: two-report fixture.
- Create `actions/reviewdog/testdata/valid/go-vet.txt`: predefined-errorformat
  fixture.
- Create `actions/reviewdog/testdata/valid/gofmt.diff`: unified-diff fixture.
- Create `actions/reviewdog/testdata/smoke/manifest.json`: real Reviewdog smoke
  fixture.
- Create `actions/reviewdog/testdata/smoke/diagnostics.rdjsonl`: deterministic
  RDJSONL annotation fixture.
- Create `actions/reviewdog/README.md`: contract, permissions, Dagger handoff,
  failure model, and version policy.
- Create `.github/workflows/reviewdog-action.yml`: Linux syntax and behavior
  gate using fake Reviewdog; it must not receive a GitHub token or post an
  annotation from pull-request-authored code.
- Modify `README.md`: list `actions/reviewdog` as third public repository
  surface.
- Retain `docs/superpowers/specs/2026-08-18-reviewdog-action-design.md`: approved
  design and threat boundary.

## Task 1: Freeze Inputs and Revalidate Upstream Pins

**Files:**

- Read: `docs/superpowers/specs/2026-08-18-reviewdog-action-design.md`
- Read: `modules/README.md`
- Read: `README.md`

**Interfaces:**

- Consumes: current worktree, GitHub CLI authentication, approved design.
- Produces: recorded base identity and verified upstream action commit/version.

- [x] **Step 1: Confirm isolated identity and clean ownership boundary**

Run:

```bash
git rev-parse --show-toplevel
git branch --show-current
git rev-parse HEAD
git status --short
git worktree list --porcelain
```

Expected:

- worktree root is the isolated Reviewdog worktree;
- branch is `feat/reviewdog-action`;
- HEAD descends from
  `538925606bdde05bf26309900ce05a63942e1c13`;
- only `goal.md` and approved design artifacts are uncommitted;
- unrelated linked worktrees remain untouched.

- [x] **Step 2: Revalidate remote main without rebasing implementation bytes**

Run:

```bash
REMOTE_MAIN=$(gh api repos/araihu/dagger/commits/main --jq .sha)
printf 'remote_main=%s\n' "$REMOTE_MAIN"
git merge-base --is-ancestor 538925606bdde05bf26309900ce05a63942e1c13 "$REMOTE_MAIN"
```

Expected: ancestor check exits `0`. If remote main advanced, stop and reconcile
the new commits before implementation; do not silently rebase an already
reviewed candidate.

- [x] **Step 3: Revalidate `reviewdog/action-setup` annotated tag**

Run:

```bash
REF_JSON=$(gh api repos/reviewdog/action-setup/git/ref/tags/v1.5.0)
TAG_TYPE=$(printf '%s' "$REF_JSON" | jq -r .object.type)
TAG_SHA=$(printf '%s' "$REF_JSON" | jq -r .object.sha)
test "$TAG_TYPE" = tag
SETUP_SHA=$(gh api "repos/reviewdog/action-setup/git/tags/$TAG_SHA" --jq .object.sha)
test "$SETUP_SHA" = d8a7baabd7f3e8544ee4dbde3ee41d0011c3a93f
```

Expected: all assertions exit `0`.

- [x] **Step 4: Revalidate Reviewdog release version**

Run:

```bash
gh release view v0.21.0 --repo reviewdog/reviewdog \
  --json tagName,isDraft,isPrerelease \
  --jq 'select(.tagName == "v0.21.0" and .isDraft == false and .isPrerelease == false) | .tagName' |
  grep -Fx v0.21.0
```

Expected: published stable release exists and output is exactly `v0.21.0`. A
newer release does not change this plan automatically; version upgrades require
separate review.

- [x] **Step 5: Run fresh baseline module tests**

Run once in each module directory:

```bash
DAGGER_SESSION_PORT=1 DAGGER_SESSION_TOKEN=offline-test go test ./... -count=1
```

Directories:

```text
modules/go
modules/node
modules/generated
modules/verified-download
```

Expected: four commands exit `0`. Stop on any baseline failure.

## Task 2: RED Test Harness and Valid Manifest Contract

**Files:**

- Create: `actions/reviewdog/test.sh`
- Create: `actions/reviewdog/testdata/valid/manifest.json`
- Create: `actions/reviewdog/testdata/valid/go-vet.txt`
- Create: `actions/reviewdog/testdata/valid/gofmt.diff`
- Test: `actions/reviewdog/test.sh`

**Interfaces:**

- Consumes: environment variables `REVIEWDOG_MANIFEST` and
  `REVIEWDOG_GITHUB_API_TOKEN` expected by the future runner.
- Produces: a fake `reviewdog` executable whose `-list` output is fixed and
  whose report calls record one argument per line plus exact standard input.

- [x] **Step 1: Add literal valid fixtures**

`actions/reviewdog/testdata/valid/manifest.json`:

```json
{
  "schema": 1,
  "reports": [
    {
      "name": "go-vet",
      "path": "go-vet.txt",
      "format": "govet",
      "level": "error",
      "filter_mode": "file"
    },
    {
      "name": "gofmt",
      "path": "gofmt.diff",
      "format": "diff",
      "diff_strip": 0
    }
  ]
}
```

`actions/reviewdog/testdata/valid/go-vet.txt`:

```text
internal/sample.go:12:2: fmt.Printf call has arguments but no formatting directives
```

`actions/reviewdog/testdata/valid/gofmt.diff`:

```diff
diff --git a/example.go b/example.go
--- a/example.go
+++ b/example.go
@@ -1,2 +1,2 @@
 package sample
-func Example(){ }
+func Example() {}
```

- [x] **Step 2: Write fake Reviewdog and assertion helpers before production code**

`test.sh` must:

```bash
set -euo pipefail

ACTION_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
RUNNER="$ACTION_DIR/run.sh"
TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$TEST_TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file_contains() {
  local file=$1 literal=$2
  grep -Fqx -- "$literal" "$file" || fail "$file lacks $literal"
}
```

The fake executable must return this exact parser registry for `-list`:

```text
rdjson Reviewdog Diagnostic JSON Format
rdjsonl Reviewdog Diagnostic JSONL Format
diff Unified Diff Format
checkstyle checkstyle XML format
sarif SARIF JSON format
govet Go vet
golangci-lint GolangCI-Lint
eslint ESLint
```

For every non-`-list` call it must create sequential files under
`$REVIEWDOG_TEST_CALLS`:

```text
1.args
1.stdin
2.args
2.stdin
```

- [x] **Step 3: Add first behavior test**

The test invokes missing `run.sh` with:

```bash
PATH="$TEST_TMP/bin:$PATH" \
REVIEWDOG_TEST_CALLS="$TEST_TMP/calls" \
REVIEWDOG_MANIFEST="$ACTION_DIR/testdata/valid/manifest.json" \
REVIEWDOG_GITHUB_API_TOKEN=test-token \
  "$RUNNER"
```

Assertions after implementation:

```text
call 1: -name=go-vet, -f=govet, -reporter=github-pr-annotations,
        -filter-mode=file, -level=error, -fail-level=none
call 2: -name=gofmt, -f=diff, -f.diff.strip=0,
        -reporter=github-pr-annotations, -filter-mode=added,
        -level=warning, -fail-level=none
```

Each `.stdin` file must byte-match its source fixture using `cmp`.

- [x] **Step 4: Run test and verify RED**

Run in pinned Linux environment. Colima cannot bind-mount this `/private/tmp`
worktree, so copy the exact snapshot into a uniquely identified disposable
container:

```bash
IMAGE='ghcr.io/myoung34/docker-github-actions-runner:2.336.0-ubuntu-noble@sha256:2840401868e84feb8e5a45d4ecc1009d66d8b21e7906324cf2a052c42ac79189'
CONTAINER_ID=$(docker create --platform linux/amd64 --entrypoint bash \
  "$IMAGE" -c 'cd /workspace && bash actions/reviewdog/test.sh')
cleanup_container() { docker rm -f "$CONTAINER_ID" >/dev/null 2>&1 || true; }
trap cleanup_container EXIT
docker cp . "$CONTAINER_ID:/workspace"
docker start -a "$CONTAINER_ID"
```

Expected: failure because `actions/reviewdog/run.sh` does not exist. Any other
failure must be corrected before production code.

## Task 3: GREEN Runner for Valid Reports

**Files:**

- Create: `actions/reviewdog/run.sh`
- Test: `actions/reviewdog/test.sh`

**Interfaces:**

- Consumes: `REVIEWDOG_MANIFEST`, `REVIEWDOG_GITHUB_API_TOKEN`, pinned
  Reviewdog available on `PATH`.
- Produces: ordered calls to Reviewdog; no files outside temporary process
  state.

- [x] **Step 1: Implement minimal strict shell frame**

Start `run.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'reviewdog-action: %s\n' "$*" >&2
  exit 1
}

for command in jq realpath stat reviewdog; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

MANIFEST=${REVIEWDOG_MANIFEST:-}
TOKEN=${REVIEWDOG_GITHUB_API_TOKEN:-}
test -n "$MANIFEST" || die "manifest input is empty"
test -n "$TOKEN" || die "token input is empty"
```

Never print `$TOKEN`.

- [x] **Step 2: Resolve manifest and load Reviewdog parser allowlist**

Implementation requirements:

```bash
test -e "$MANIFEST" || die "manifest does not exist"
test ! -L "$MANIFEST" || die "manifest must not be a symlink"
test -f "$MANIFEST" || die "manifest must be a regular file"
MANIFEST_REAL=$(realpath -e -- "$MANIFEST")
REPORT_ROOT=$(dirname -- "$MANIFEST_REAL")
```

Load the first field from `reviewdog -list` into a Bash associative array.
Empty registry is an error.

- [x] **Step 3: Add two-pass report handling**

First pass validates and stores arrays for:

```text
name
resolved path
format
level
filter mode
diff strip
size
```

Second pass invokes Reviewdog only after every entry has passed. Each call uses
an argument array, never a constructed command string:

```bash
args=(
  "-name=$name"
  "-f=$format"
  "-reporter=github-pr-annotations"
  "-filter-mode=$filter_mode"
  "-level=$level"
  "-fail-level=none"
)
if test -n "$diff_strip"; then
  args+=("-f.diff.strip=$diff_strip")
fi
reviewdog "${args[@]}" < "$report_path"
```

- [x] **Step 4: Run valid test and verify GREEN**

Run the same pinned-container command from Task 2.

Expected: exit `0`, two calls in manifest order, exact arguments, exact stdin.

## Task 4: RED/GREEN Strict Schema Validation

**Files:**

- Modify: `actions/reviewdog/test.sh`
- Modify: `actions/reviewdog/run.sh`

**Interfaces:**

- Consumes: schema version 1 JSON.
- Produces: defaults and normalized rows, or one deterministic validation
  failure before any report invocation.

- [x] **Step 1: Add table-driven failing cases**

Create each manifest inside test temporary storage with `jq -n`. Cover:

```text
invalid JSON
top-level array
schema missing
schema other than integer 1
unknown top-level key
reports missing
reports not an array
reports empty
33 reports
report not an object
unknown report key
missing name
invalid name characters
name longer than 64 bytes
missing path
invalid path characters
path longer than 256 bytes
missing format
format absent from fake reviewdog -list
level outside info|warning|error
filter_mode outside added|diff_context|file|nofilter
diff_strip below 0
diff_strip above 10
diff_strip not an integer
diff_strip supplied when format is not diff
```

Every case must assert nonzero exit and zero numbered call files.

- [x] **Step 2: Verify RED**

Run pinned-container test command.

Expected: at least first new malformed manifest reaches the fake Reviewdog or
passes unexpectedly, proving missing validation.

- [x] **Step 3: Add one jq schema predicate and normalized extraction**

Schema predicate must enforce exact keys and all limits in one validation
operation. Extraction emits tab-separated fields only after the predicate
passes:

```jq
[
  .name,
  .path,
  .format,
  (.level // "warning"),
  (.filter_mode // "added"),
  ((.diff_strip // "") | tostring)
] | @tsv
```

Restrict accepted strings before TSV extraction so tabs, newlines, backslashes,
spaces, quotes, shell metacharacters, and control bytes cannot enter Bash field
parsing.

- [x] **Step 4: Verify GREEN**

Run pinned-container test command.

Expected: valid case still passes; all malformed schema cases fail before any
numbered Reviewdog call.

## Task 5: RED/GREEN Filesystem and Resource Limits

**Files:**

- Modify: `actions/reviewdog/test.sh`
- Modify: `actions/reviewdog/run.sh`

**Interfaces:**

- Consumes: manifest directory as sole report root.
- Produces: canonical regular files within root and bounded input sizes.

- [x] **Step 1: Add failing path cases**

Cover these independently:

```text
absolute report path
../ traversal
embedded /../ traversal
missing report
report path naming a directory
report symlink inside root
intermediate directory symlink escaping root
manifest symlink
manifest larger than 65536 bytes
report larger than 10485760 bytes
combined report bytes larger than 52428800 bytes
```

Create large sparse files with GNU `truncate` inside the pinned Linux test
container. Every case asserts nonzero exit and no numbered Reviewdog call.

- [x] **Step 2: Add command-injection canary cases**

Use manifest values containing:

```text
$(touch injection-canary)
`touch injection-canary`
name;touch injection-canary
name with spaces
name<TAB>other
```

Assert the action fails and `$TEST_TMP/injection-canary` does not exist.

- [x] **Step 3: Verify RED**

Run pinned-container test command.

Expected: first unimplemented boundary passes or reaches fake Reviewdog.

- [x] **Step 4: Implement canonical-path and size validation**

Required checks:

```bash
MANIFEST_SIZE=$(stat -c %s -- "$MANIFEST_REAL")
test "$MANIFEST_SIZE" -le 65536 || die "manifest exceeds 65536 bytes"

test "$raw_path" = "${raw_path#/}" || die "report path must be relative"
test ! -L "$REPORT_ROOT/$raw_path" || die "report must not be a symlink"
REPORT_REAL=$(realpath -e -- "$REPORT_ROOT/$raw_path")
case "$REPORT_REAL" in
  "$REPORT_ROOT"/*) ;;
  *) die "report escapes manifest directory" ;;
esac
test -f "$REPORT_REAL" || die "report must be a regular file"
REPORT_SIZE=$(stat -c %s -- "$REPORT_REAL")
test "$REPORT_SIZE" -le 10485760 || die "report exceeds 10485760 bytes"
```

Accumulate total bytes with checked integer arithmetic and reject totals above
`52428800` before invocation.

- [x] **Step 5: Verify GREEN and mutation resistance**

Run pinned-container test command.

Then temporarily change one boundary at a time in the worktree diff, verify its
named test fails, and restore the intended value:

```text
32 reports to 33
65536 manifest bytes to 65537
10485760 report bytes to 10485761
52428800 combined bytes to 52428801
```

Expected: every mutation produces a focused failure; restored implementation
returns full suite to exit `0`.

## Task 6: Composite Action Metadata

**Files:**

- Create: `actions/reviewdog/action.yml`

**Interfaces:**

- Consumes: action inputs `manifest` and `token`.
- Produces: Reviewdog installed on `PATH`, then `run.sh` invoked with two
  environment variables.

- [x] **Step 1: Create exact composite action metadata**

`action.yml` is configuration, not executable behavior. Do not add a
source-text change-detector test. Validate its parsed structure in Step 2 and
its real behavior in Task 9.

```yaml
name: Arai Hû Reviewdog
description: Publish validated Dagger diagnostics as GitHub PR annotations
inputs:
  manifest:
    description: Path to the schema-v1 report manifest
    required: true
  token:
    description: GitHub token used by Reviewdog to read the PR diff
    required: true
runs:
  using: composite
  steps:
    - name: Install pinned Reviewdog
      uses: reviewdog/action-setup@d8a7baabd7f3e8544ee4dbde3ee41d0011c3a93f
      with:
        reviewdog_version: v0.21.0
    - name: Publish annotations
      shell: bash
      env:
        REVIEWDOG_MANIFEST: ${{ inputs.manifest }}
        REVIEWDOG_GITHUB_API_TOKEN: ${{ inputs.token }}
      run: '"$GITHUB_ACTION_PATH/run.sh"'
```

- [x] **Step 2: Parse and assert metadata structure**

Run with Ruby's standard YAML library, already present on the development host
and GitHub-hosted Ubuntu runners:

```bash
set -e
ruby -e '
  require "yaml"
  action = YAML.safe_load(File.read("actions/reviewdog/action.yml"), aliases: false)
  abort "not composite" unless action.dig("runs", "using") == "composite"
  abort "manifest not required" unless action.dig("inputs", "manifest", "required") == true
  abort "token not required" unless action.dig("inputs", "token", "required") == true
  steps = action.dig("runs", "steps")
  abort "wrong setup pin" unless steps[0]["uses"] == "reviewdog/action-setup@d8a7baabd7f3e8544ee4dbde3ee41d0011c3a93f"
  abort "wrong reviewdog version" unless steps[0].dig("with", "reviewdog_version") == "v0.21.0"
  abort "wrong shell" unless steps[1]["shell"] == "bash"
  abort "wrong runner" unless steps[1]["run"] == %q{"$GITHUB_ACTION_PATH/run.sh"}
'
```

Expected: exit `0`, no output.

- [x] **Step 3: Make scripts executable and rerun behavior suite**

Run:

```bash
chmod 0755 actions/reviewdog/run.sh actions/reviewdog/test.sh
git diff --summary
```

Expected: both scripts show executable mode `100755`. Pinned-container tests
exit `0`.

## Task 7: Documentation and Repository CI Gate

**Files:**

- Create: `actions/reviewdog/README.md`
- Create: `actions/reviewdog/testdata/smoke/manifest.json`
- Create: `actions/reviewdog/testdata/smoke/diagnostics.rdjsonl`
- Create: `.github/workflows/reviewdog-action.yml`
- Modify: `README.md`

**Interfaces:**

- Consumes: action interface from Task 6.
- Produces: consumer instructions, deterministic smoke fixture, and safe CI
  validation without passing a token into pull-request-authored scripts.

- [x] **Step 1: Add deterministic real-Reviewdog fixture**

`actions/reviewdog/testdata/smoke/manifest.json`:

```json
{
  "schema": 1,
  "reports": [
    {
      "name": "reviewdog-smoke",
      "path": "diagnostics.rdjsonl",
      "format": "rdjsonl",
      "level": "info",
      "filter_mode": "nofilter"
    }
  ]
}
```

`actions/reviewdog/testdata/smoke/diagnostics.rdjsonl` contains exactly one
JSON object on one line:

```json
{"message":"Arai Hû Reviewdog smoke annotation","location":{"path":"actions/reviewdog/README.md","range":{"start":{"line":1,"column":1}}},"severity":"INFO","code":{"value":"reviewdog-smoke"}}
```

- [x] **Step 2: Write action README**

Document:

```text
immutable uses syntax
required contents:read and pull-requests:read permissions
manifest schema and all limits
supported parser rule: exact `reviewdog -list` names from v0.21.0
fixed github-pr-annotations reporter
token used only for PR diff reads
Dagger ReturnType.Any capture/export/status pattern
if: always() annotation and final status gate
no pull_request_target recommendation
Linux-only first-release boundary
failure behavior and troubleshooting commands
```

The example may use the repository's established `<40-character-commit>`
notation only when adjacent text requires replacement with the reviewed SHA.
Never recommend a branch, moving tag, or latest-version selector.

- [x] **Step 3: Update root README surface list**

Add:

```markdown
- `actions/reviewdog`: validated Reviewdog adapter for diagnostics exported by
  Dagger CI.
```

Keep modules' no-review-bot policy unchanged.

- [x] **Step 4: Add safe workflow gate**

`.github/workflows/reviewdog-action.yml` requirements:

```yaml
name: Reviewdog action

on:
  push:
    branches: [main]
    paths:
      - actions/reviewdog/**
      - .github/workflows/reviewdog-action.yml
  pull_request:
    paths:
      - actions/reviewdog/**
      - .github/workflows/reviewdog-action.yml

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
        with:
          persist-credentials: false
      - name: Validate shell syntax
        run: bash -n actions/reviewdog/run.sh actions/reviewdog/test.sh
      - name: Validate action metadata
        shell: bash
        run: |
          ruby -e '
            require "yaml"
            action = YAML.safe_load(File.read("actions/reviewdog/action.yml"), aliases: false)
            abort "not composite" unless action.dig("runs", "using") == "composite"
            abort "manifest not required" unless action.dig("inputs", "manifest", "required") == true
            abort "token not required" unless action.dig("inputs", "token", "required") == true
            steps = action.dig("runs", "steps")
            abort "wrong setup pin" unless steps[0]["uses"] == "reviewdog/action-setup@d8a7baabd7f3e8544ee4dbde3ee41d0011c3a93f"
            abort "wrong version" unless steps[0].dig("with", "reviewdog_version") == "v0.21.0"
          '
      - name: Run behavior tests
        run: bash actions/reviewdog/test.sh
```

Do not invoke `uses: ./actions/reviewdog` in this PR workflow. That would pass a
GitHub token to action code controlled by the PR head. Real annotation smoke is
performed only from a separately reviewed, immutable action SHA in Task 9.

- [x] **Step 5: Run documentation and workflow checks**

Run:

```bash
bash -n actions/reviewdog/run.sh actions/reviewdog/test.sh
git diff --check
rg -n '@(main|master|latest)|reviewdog_version: latest' \
  actions/reviewdog README.md .github/workflows/reviewdog-action.yml
```

Expected: syntax and diff checks exit `0`; mutable-reference search returns no
matches.

## Task 8: Full Local Verification and Candidate Review

**Files:**

- Verify all changed files.

**Interfaces:**

- Consumes: complete candidate tree.
- Produces: fresh local evidence receipt and frozen diff for review.

- [x] **Step 1: Run Linux behavior suite from clean container**

Run exact pinned-container command from Task 2.

Expected: exit `0`; test harness reports every named case passed.

- [x] **Step 2: Run shell syntax and repository hygiene gates**

Run:

```bash
bash -n actions/reviewdog/run.sh actions/reviewdog/test.sh
git diff --check
git status --short
git diff --stat
git diff -- README.md .github/workflows/reviewdog-action.yml \
  actions/reviewdog docs/superpowers/specs goal.md
```

Expected: only planned files differ; no whitespace errors; executable modes
correct; no secret values or unrelated changes.

- [x] **Step 3: Rerun all existing host-only Dagger module tests**

Run the four commands from Task 1 again with `-count=1`.

Expected: all four module suites exit `0`.

- [x] **Step 4: Verify pinned versions and permission boundary mechanically**

Run:

```bash
rg -n 'reviewdog/action-setup@d8a7baabd7f3e8544ee4dbde3ee41d0011c3a93f' \
  actions/reviewdog/action.yml
rg -n 'reviewdog_version: v0.21.0' actions/reviewdog/action.yml
rg -n 'pull-requests: write|checks: write|security-events: write' \
  actions/reviewdog .github/workflows/reviewdog-action.yml README.md
if rg -n 'pull_request_target:' .github/workflows/reviewdog-action.yml; then
  exit 1
fi
rg -n -F 'Do not use this action from `pull_request_target`.' \
  actions/reviewdog/README.md
```

Expected: first two searches and documentation guard match; forbidden
permissions and forbidden workflow event have no matches.

- [x] **Step 5: Perform manual threat review**

Confirm from diff:

```text
token appears only as environment input
token never appears in command arguments or output
manifest controls no executable
all values are quoted
all parser names come from pinned reviewdog -list
all reports validated before first invocation
canonical path remains below manifest directory
symlinks rejected
size and report-count limits enforced
diagnostics cannot fail CI by severity
Reviewdog execution/setup errors do fail adapter step
```

- [x] **Step 6: Freeze candidate identity**

Run:

Because `git diff` omits untracked files, freeze every changed path as a
sorted content-and-mode manifest without staging the index:

```bash
{
  git diff --name-only
  git ls-files --others --exclude-standard
} | LC_ALL=C sort -u > /private/tmp/araihu-dagger-reviewdog-candidate.paths

while IFS= read -r candidate_path; do
  printf '%s  %s  %s\n' \
    "$(stat -f '%Lp' "$candidate_path")" \
    "$(shasum -a 256 "$candidate_path" | awk '{print $1}')" \
    "$candidate_path"
done < /private/tmp/araihu-dagger-reviewdog-candidate.paths \
  > /private/tmp/araihu-dagger-reviewdog-candidate.manifest

shasum -a 256 /private/tmp/araihu-dagger-reviewdog-candidate.manifest
git status --short
```

Record the manifest hash in handoff. Do not commit until user authorizes
commit.

## Task 9: GitHub PR Smoke Test with Immutable Candidate

**Authorization gate:** Commit, push, PR creation, pilot-repository edits, and
annotation posting are external lifecycle actions. Stop and obtain explicit
authorization before this task.

**Files:**

- Candidate repository: all planned files.
- Pilot repository: one isolated worktree containing
  `.github/workflows/reviewdog-smoke.yml` only.

**Interfaces:**

- Consumes: independently reviewed candidate SHA and pilot PR read token.
- Produces: one GitHub Actions annotation with code `reviewdog-smoke` and an API
  receipt tied to exact candidate SHA.

- [ ] **Step 1: Commit reviewed candidate after authorization**

Run:

```bash
git add README.md goal.md docs/superpowers/specs \
  actions/reviewdog .github/workflows/reviewdog-action.yml
git diff --cached --check
git commit -m "feat: add reusable Reviewdog annotation action"
ACTION_SHA=$(git rev-parse HEAD)
test "${#ACTION_SHA}" -eq 40
```

Expected: one scoped commit; worktree clean; `ACTION_SHA` identifies reviewed
tree.

- [ ] **Step 2: Push candidate branch after authorization**

Because configured SSH remote lacks a usable key, use temporary HTTPS rewriting
without changing repository configuration:

```bash
git -c 'url.https://github.com/.insteadOf=git@github.com:' \
  -c 'credential.helper=!gh auth git-credential' \
  push --set-upstream origin feat/reviewdog-action
```

Expected: remote branch points exactly at `$ACTION_SHA`.

- [ ] **Step 3: Open draft implementation PR after authorization**

Run:

```bash
BASE_SHA=$(gh api repos/araihu/dagger/commits/main --jq .sha)
printf -v PR_BODY '%s\n\n%s\n\n%s\n%s\n' \
  'Adds the reusable Reviewdog PR-annotation adapter for Dagger diagnostics.' \
  'No Dagger module API changes. No GitHub write permissions.' \
  "Base: $BASE_SHA" \
  "Candidate: $ACTION_SHA"
gh pr create --repo araihu/dagger --draft \
  --base main --head feat/reviewdog-action \
  --title "feat: add reusable Reviewdog annotation action" \
  --body "$PR_BODY"
```

PR body records base SHA, candidate SHA, local verification commands, limits,
and remaining live smoke gate. Do not merge.

- [ ] **Step 4: Create isolated pilot worktree from current Goshtoso main**

Run from `/Users/guilhermecastro/repos/araihu/goshtoso`:

```bash
PILOT_BASE=$(gh api repos/araihu/goshtoso/commits/main --jq .sha)
PILOT_PATH=$(mktemp -d /private/tmp/goshtoso-reviewdog-smoke.XXXXXX)
git worktree add -b chore/reviewdog-smoke "$PILOT_PATH" "$PILOT_BASE"
```

Expected: clean isolated worktree at exact remote main.

- [ ] **Step 5: Add pilot workflow with literal candidate SHA**

Create `.github/workflows/reviewdog-smoke.yml` in pilot worktree. Its
`uses:` line must contain the exact 40-character `$ACTION_SHA` value printed in
Step 1, not a branch or tag.

Workflow behavior:

```yaml
name: Reviewdog smoke
on:
  pull_request:
    branches: [main]
permissions:
  contents: read
  pull-requests: read
jobs:
  annotate:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
        with:
          persist-credentials: false
      - name: Prepare synthetic Dagger-compatible reports
        shell: bash
        run: |
          set -euo pipefail
          mkdir -p .reviewdog
          printf '%s\n' '{"schema":1,"reports":[{"name":"reviewdog-smoke","path":"diagnostics.rdjsonl","format":"rdjsonl","level":"info","filter_mode":"nofilter"}]}' > .reviewdog/manifest.json
          printf '%s\n' '{"message":"Arai Hû Reviewdog smoke annotation","location":{"path":"README.md","range":{"start":{"line":1,"column":1}}},"severity":"INFO","code":{"value":"reviewdog-smoke"}}' > .reviewdog/diagnostics.rdjsonl
          printf '0\n' > .reviewdog/status
      - name: Publish smoke annotation
        uses: araihu/dagger/actions/reviewdog@ACTION_SHA
        with:
          manifest: .reviewdog/manifest.json
          token: ${{ github.token }}
      - name: Preserve producer gate
        run: test "$(cat .reviewdog/status)" = 0
```

Replace `ACTION_SHA` in the stored YAML with exact `$ACTION_SHA`, then assert:

```bash
grep -F "uses: araihu/dagger/actions/reviewdog@$ACTION_SHA" \
  .github/workflows/reviewdog-smoke.yml
! rg -n '@(main|master|latest)' .github/workflows/reviewdog-smoke.yml
```

- [ ] **Step 6: Commit, push, and open pilot draft PR after authorization**

Use scoped commit message:

```text
ci: smoke test reusable Reviewdog action
```

Push with temporary HTTPS rewriting. Open draft PR against Goshtoso `main`.
Do not merge.

Exact PR creation command after push:

```bash
PILOT_SHA=$(git rev-parse HEAD)
printf -v PILOT_BODY '%s\n\n%s\n%s\n' \
  'Validates one PR annotation from the immutable Arai Hû Reviewdog action.' \
  "Action: $ACTION_SHA" \
  "Pilot: $PILOT_SHA"
gh pr create --repo araihu/goshtoso --draft \
  --base main --head chore/reviewdog-smoke \
  --title "ci: smoke test reusable Reviewdog action" \
  --body "$PILOT_BODY"
```

- [ ] **Step 7: Watch exact smoke workflow**

Run:

```bash
PILOT_PR=$(gh pr list --repo araihu/goshtoso --state open \
  --head chore/reviewdog-smoke --json number --jq '.[0].number')
test -n "$PILOT_PR"
PILOT_HEAD=$(gh pr view "$PILOT_PR" --repo araihu/goshtoso \
  --json headRefOid --jq .headRefOid)
RUN_ID=$(gh run list --repo araihu/goshtoso \
  --workflow=reviewdog-smoke.yml --branch=chore/reviewdog-smoke \
  --event=pull_request --limit=1 --json databaseId,headSha \
  --jq ".[] | select(.headSha == \"$PILOT_HEAD\") | .databaseId")
test -n "$RUN_ID"
gh run watch "$RUN_ID" --repo araihu/goshtoso --exit-status
```

Expected: run exits `0`; action setup installs `v0.21.0`; annotation step and
producer gate both succeed.

- [ ] **Step 8: Verify annotation through GitHub API**

Run:

```bash
CHECK_ID=$(gh api "repos/araihu/goshtoso/commits/$PILOT_HEAD/check-runs" \
  --jq '.check_runs[] | select(.name == "annotate") | .id')
test -n "$CHECK_ID"
gh api "repos/araihu/goshtoso/check-runs/$CHECK_ID/annotations" \
  --jq '.[] | select(
    .annotation_level == "warning"
    and (.message | contains("[reviewdog-smoke] reported by reviewdog"))
    and (.message | contains("Arai Hû Reviewdog smoke annotation"))
    and .path == "README.md"
    and .start_line == 1
  )'
```

Expected: exactly one matching annotation object. Reviewdog v0.21.0 maps both
`INFO` and `WARNING` diagnostics to GitHub warning workflow commands because
the command form carrying file and line metadata has no info level. The API
message contains Reviewdog's tool prefix and raw-output section; it is not
equal to the RDJSON message alone. Save API response without tokens as smoke
receipt.

- [ ] **Step 9: Verify permission and secret boundaries from logs**

Run:

```bash
gh run view "$RUN_ID" --repo araihu/goshtoso --log > /private/tmp/reviewdog-smoke.log
! rg -n 'gho_|github_pat_|test-token|Authorization: Bearer' \
  /private/tmp/reviewdog-smoke.log
```

Inspect workflow permissions: only `contents: read` and `pull-requests: read`.
Confirm no Dagger command received token environment.

- [ ] **Step 10: Record smoke verdict and stop before cleanup/merge**

Receipt must contain:

```text
araihu/dagger candidate SHA
pilot repository and PR number
pilot head SHA
workflow run ID
check-run ID
annotation path, line, level, code, and message
workflow permission block
all command exit statuses
```

Do not close PRs, delete branches/worktrees, merge, or remove remote state
without explicit cleanup/integration authorization.

## Task 10: Final Acceptance Gate

**Files:**

- Review: complete candidate and smoke receipts.

**Interfaces:**

- Consumes: local test evidence, GitHub smoke evidence, exact identities.
- Produces: ACCEPT or BLOCKED verdict; never implicit merge authority.

- [ ] **Step 1: Revalidate candidate has not moved**

Run:

```bash
test "$(git rev-parse HEAD)" = "$ACTION_SHA"
git status --short
gh api repos/araihu/dagger/git/ref/heads/feat/reviewdog-action --jq .object.sha
```

Expected: local and remote branch SHAs equal reviewed `$ACTION_SHA`; worktree
clean.

- [ ] **Step 2: Re-run local verification at final SHA**

Repeat Task 8 commands after smoke. Previous green evidence is not sufficient
if candidate moved.

- [ ] **Step 3: Apply acceptance checklist**

ACCEPT only when all are true:

```text
all strict-manifest tests pass
all path/resource/adversarial tests pass
both shell files pass bash -n
four existing Dagger module suites pass
action and Reviewdog pins are exact
candidate diff contains only planned files
GitHub smoke annotation exists at exact pilot head
no write permission exists
no token entered Dagger or appeared in logs
consumer reference uses exact 40-character candidate SHA
candidate SHA did not move after review
```

Otherwise report BLOCKED with failing command and smallest decisive output.

- [ ] **Step 4: Hand off lifecycle decisions**

Report candidate SHA, diff hash, checks, smoke receipts, remaining risks, and
explicit options. Merge, pilot cleanup, broader repository rollout, and a
Reviewdog version upgrade remain separate user decisions.
