# Shared modules

Reusable Araihu CI modules live under `modules/<name>`.

Each module owns its `dagger.json`, SDK source, tests, and public function
contract. Toolchains stay inside Dagger containers so pipelines behave the
same on developer machines, GitHub-hosted runners, and the Hostinger runner.

The first shared CI module will use `modules/ci`; it is intentionally not
scaffolded until its cross-repository contract is defined.
