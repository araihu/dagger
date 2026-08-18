# Arai Hû Reviewdog action

Publishes diagnostics already produced by Dagger CI as GitHub pull request
annotations. Dagger remains the CI gate; this action is a presentation adapter.

## Usage

Pin the action to a full reviewed commit. Replace `<40-character-commit>` only
with the immutable commit reviewed in `araihu/dagger`:

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

Do not use this action from `pull_request_target`. Do not pass the token to a
Dagger function or container. Reviewdog uses it on the runner only to read the
pull request diff; the action needs no GitHub write permission.

## Dagger producer contract

The repository-specific Dagger function must capture tool failures without
aborting before export, write reports plus an authoritative `status`, and
return the output directory successfully. TypeScript SDK functions can use the
same pattern already used by Arai Hû test pipelines:

```typescript
return container
  .withExec(["bash", "-c", script], { expect: ReturnType.Any })
  .directory("/out")
```

The script writes reports and `/out/status`; the final host step propagates
that status after annotations have been attempted.

## Manifest schema

Schema version 1 contains one through 32 reports:

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
      "diff_strip": 0
    }
  ]
}
```

Report fields:

- `name`: required, 1-64 ASCII alphanumeric, `.`, `_`, or `-` characters.
- `path`: required, 1-256 ASCII alphanumeric, `.`, `_`, `-`, or `/`
  characters; relative to the manifest directory.
- `format`: required exact parser name from Reviewdog v0.21.0
  `reviewdog -list`, including `rdjson`, `rdjsonl`, `diff`, `checkstyle`,
  `sarif`, `govet`, `golangci-lint`, and `eslint`.
- `level`: optional `info`, `warning`, or `error`; default `warning`.
- `filter_mode`: optional `added`, `diff_context`, `file`, or `nofilter`;
  default `added`.
- `diff_strip`: optional integer 0-10 for `diff` only.

Unknown keys fail validation.

## Safety limits

Before invoking Reviewdog, the action validates the complete manifest and all
reports. It rejects:

- manifest symlinks or manifests larger than 64 KiB;
- absolute paths, traversal segments, or any symlink in a report path;
- missing files, directories, or files outside the manifest directory;
- individual reports larger than 10 MiB;
- combined report data larger than 50 MiB;
- parser names absent from the pinned Reviewdog registry;
- shell metacharacters and control characters in manifest fields.

Manifest values are arguments and paths only. They never select an executable
and are never evaluated as shell code.

## Failure behavior

Invalid input, missing tools, Reviewdog setup errors, and Reviewdog execution
errors fail the action. Diagnostics themselves do not: every invocation uses
the fixed `github-pr-annotations` reporter and `-fail-level=none`.

Reviewdog v0.21.0 emits this reporter through GitHub workflow commands. Both
`info` and `warning` diagnostics therefore appear as GitHub warning
annotations. One Reviewdog process can successfully emit at most nine
annotations; its tenth annotation triggers Reviewdog's workflow-command limit
error. GitHub also applies aggregate annotation limits per step, job, and run.
Keep PR diagnostics focused and preserve complete tool output separately as a
workflow artifact or log.

The action is Linux-only in its first release and requires Bash 5, `jq`, GNU
`realpath`, and GNU `stat`. GitHub-hosted Ubuntu 24.04 provides these tools.

## Troubleshooting

Run the behavior suite in the repository's pinned Linux runner image:

```bash
IMAGE='ghcr.io/myoung34/docker-github-actions-runner:2.336.0-ubuntu-noble@sha256:2840401868e84feb8e5a45d4ecc1009d66d8b21e7906324cf2a052c42ac79189'
CONTAINER_ID=$(docker create --platform linux/amd64 --entrypoint bash \
  "$IMAGE" -c 'cd /workspace && bash actions/reviewdog/test.sh')
cleanup_container() { docker rm -f "$CONTAINER_ID" >/dev/null 2>&1 || true; }
trap cleanup_container EXIT
docker cp . "$CONTAINER_ID:/workspace"
docker start -a "$CONTAINER_ID"
```

An empty parser registry normally means Reviewdog was not installed correctly.
A pull request diff error normally means `token` or `pull-requests: read` is
missing. A path error is relative to the directory containing `manifest`.

## Version policy

The composite action pins `reviewdog/action-setup` by full commit and installs
Reviewdog v0.21.0 explicitly. Version changes require a reviewed dependency
change plus the complete behavior and pull request smoke gates.
