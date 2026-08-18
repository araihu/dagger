# Reusable Reviewdog Action Design

## Goal

Expose diagnostics produced by repository-specific Dagger CI as GitHub pull
request annotations through one immutable, organization-owned action.

## Boundary

Add `actions/reviewdog` as a third public repository surface beside `images`
and `modules`.

- Dagger runs tools, captures their diagnostics, and exports report files.
- The producer captures tool exit status without aborting before export, writes
  that status beside the reports, and returns successfully to the host runner.
- `actions/reviewdog` validates those files and invokes Reviewdog on the GitHub
  runner.
- A repository-specific status gate remains authoritative for CI success.
- GitHub event metadata and `GITHUB_TOKEN` never enter Dagger containers.
- Existing Dagger modules remain side-effect-free and do not integrate review
  bots.

No new Dagger module is part of this change. A provider-neutral diagnostics
packaging module can be considered later only after repeated consumer code
establishes a stable shared contract.

## Consumer interface

Consumers pin the action to a full reviewed commit:

```yaml
permissions:
  contents: read
  pull-requests: read

steps:
  - name: Run Dagger diagnostics
    run: dagger call diagnostics export --path=.reviewdog

  - name: Annotate pull request
    if: always()
    uses: araihu/dagger/actions/reviewdog@<40-character-commit>
    with:
      manifest: .reviewdog/manifest.json
      token: ${{ github.token }}

  - name: Preserve Dagger gate
    if: always()
    run: test "$(cat .reviewdog/status)" = 0
```

The action exposes two required inputs:

- `manifest`: path to the report manifest in the checked-out workspace.
- `token`: GitHub token used only by Reviewdog to read the pull request diff.

The first release supports only `github-pr-annotations`. It adds no
`pull-requests: write`, `checks: write`, or `security-events: write`
permission.

## Manifest contract

Manifest schema version 1:

```json
{
  "schema": 1,
  "reports": [
    {
      "name": "go-vet",
      "path": "go-vet.txt",
      "format": "govet",
      "level": "error",
      "filter_mode": "added"
    },
    {
      "name": "gofmt",
      "path": "gofmt.diff",
      "format": "diff",
      "diff_strip": 0,
      "level": "warning",
      "filter_mode": "added"
    }
  ]
}
```

Top-level keys are exactly `schema` and `reports`. Each report accepts:

- `name`: required stable annotation name; 1-64 ASCII alphanumeric, `.`, `_`,
  or `-` characters.
- `path`: required relative path below the manifest directory; 1-256 ASCII
  alphanumeric, `.`, `_`, `-`, or `/` characters.
- `format`: required exact parser name reported by pinned Reviewdog
  `reviewdog -list`.
- `level`: optional `info`, `warning`, or `error`; defaults to `warning`.
- `filter_mode`: optional `added`, `diff_context`, `file`, or `nofilter`;
  defaults to `added`.
- `diff_strip`: optional integer from 0 through 10, valid only with `diff`;
  defaults to Reviewdog's own value when absent.

Unknown keys and empty report arrays are errors. One manifest may contain at
most 32 reports.

## Action behavior

1. Install Reviewdog `v0.21.0` through
   `reviewdog/action-setup@d8a7baabd7f3e8544ee4dbde3ee41d0011c3a93f`.
2. Require Linux runner utilities `bash`, `jq`, `realpath`, and `stat`.
3. Resolve the manifest and its containing directory without following a
   manifest symlink.
4. Validate the complete manifest before invoking Reviewdog.
5. Resolve every report path and reject absolute paths, traversal, symlinks,
   non-regular files, and files outside the manifest directory.
6. Reject manifests larger than 64 KiB, individual reports larger than 10 MiB,
   or combined reports larger than 50 MiB.
7. Invoke Reviewdog once per report using fixed
   `-reporter=github-pr-annotations` and `-fail-level=none` arguments.
8. Pass the report through standard input. Manifest data is never evaluated as
   shell code or used to select an executable.

The token is passed only as `REVIEWDOG_GITHUB_API_TOKEN` for the Reviewdog
process. Scripts must not print it or include it in command arguments.

## Failure semantics

- Invalid manifests, missing files, unsupported parser names, setup failures,
  and Reviewdog execution failures fail the action.
- Reported diagnostics do not fail the action because `-fail-level=none` keeps
  presentation separate from policy.
- The `github-pr-annotations` reporter maps both `info` and `warning` findings
  to GitHub warning workflow commands. Reviewdog v0.21.0 fails a process when
  it would emit a tenth annotation; GitHub also enforces aggregate annotation
  limits. Consumers retain complete diagnostics as artifacts or logs.
- Dagger writes the authoritative status before exporting diagnostics. The
  consumer's final gate fails the workflow when that status is nonzero.
- Consumers run annotation and gate steps with `if: always()` so failed checks
  do not hide their diagnostic output.

## Repository changes

- Create `actions/reviewdog/action.yml`: composite action metadata and pinned
  Reviewdog installer.
- Create `actions/reviewdog/run.sh`: manifest validation and Reviewdog
  invocation.
- Create `actions/reviewdog/test.sh` plus committed fixtures: behavior tests
  using a fake `reviewdog` executable.
- Create `.github/workflows/reviewdog-action.yml`: syntax and behavior gate on
  Ubuntu 24.04 without posting annotations.
- Update root `README.md`: document `actions` as a public surface.
- Create `actions/reviewdog/README.md`: consumer contract and Dagger handoff
  example.

## Testing

Tests exercise scripts, not source-text patterns:

- Valid multi-report manifest produces exact Reviewdog arguments and standard
  input for each report.
- Defaults produce `warning` and `added`.
- Diff reports pass an explicit `diff_strip` value.
- Malformed schemas, unknown keys, unsupported enum values, unsupported parser
  names, empty lists, and excessive report counts fail before invocation.
- Absolute paths, traversal, symlinks, missing files, directories, and size
  limit violations fail before invocation.
- Shell metacharacters in manifest values are rejected rather than executed.
- Empty token fails without revealing token content.
- `bash -n` validates both scripts.

Repository verification also reruns all four existing host-only Dagger module
test suites. Real pull-request annotation remains a pilot-repository CI gate;
local tests cannot prove GitHub rendering.

## Non-goals

- Running linters outside Dagger.
- Posting review comments or GitHub Checks.
- Granting write permissions.
- Changing existing Dagger module APIs.
- Making Reviewdog determine CI success.
- Supporting non-Linux or non-GitHub CI providers in the first release.
