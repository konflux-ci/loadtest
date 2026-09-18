# AGENTS.md

This file follows the [Global Engineering AGENTS.md best practices](https://gitlab.cee.redhat.com/global-engineering/wg-agentic-sdlc/-/tree/main/best-practices/repo-scaffolding?ref_type=heads).

Go-based load testing tool for Konflux CI/CD. For full project documentation, see [README.md](README.md).

## Build & Test Commands

The project uses `pre-commit` for all code checks (Go, Shell, Python, YAML).

Bootstrap development environment:
```bash
make bootstrap
```

Run all checks (includes build and tidy):
```bash
make check-all
```

Verification relies on linting and a successful build as there are no Go unit tests.

After editing files, run checks before pushing:
```bash
make check      # staged changes only
make check-all  # all files
```

## Key Conventions

- Dependencies are vendored (`vendor/` directory). Always run `go mod vendor && go mod tidy` after changing dependencies.
- CSV output files and Python analysis scripts (`evaluate.py`, `errors.py`) are tightly coupled — column names in Go logging must match what Python expects.

## Pattern References

- New journey stage: see `pkg/journey/handle_pipeline.go` and `loadtest.go` for wiring
- Resource create/delete: handlers under `pkg/journey/`; teardown in `handle_purge.go` `Purge()`
- Probe scripts: `ci-scripts/run-probe/`; mirror in `run-ci/` / `run-cluster/` / `run-simple/`
- Horreum scripts: `ci-scripts/utility_scripts/` with schemas in `ci-scripts/config/horreum-*.json`

## CI

PRs are validated by Konflux Tekton (`.tekton/`) and GitHub Actions (`.github/workflows/`).

## Agent skills

### Issue tracker

Jira — KONFLUX / Performance. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context layout (`CONTEXT.md`). See `docs/agents/domain.md`.

### Architecture decisions

ADRs (Status / Context / Decision / Consequences) live in `docs/adr/`.
