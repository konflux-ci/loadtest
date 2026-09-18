# AGENTS.md

This file follows the [Global Engineering AGENTS.md best practices](https://gitlab.cee.redhat.com/global-engineering/wg-agentic-sdlc/-/tree/main/best-practices/repo-scaffolding?ref_type=heads).

Go-based load testing tool for Konflux CI/CD. For full project documentation, see [README.md](README.md).

## Build & Test Commands

The project uses `pre-commit` for all code checks (Go, Shell, Python, YAML).

Bootstrap: `make bootstrap`. Full checks: `make check-all`. Staged only: `make check`.

Verification relies on linting and a successful build as there are no Go unit tests.

## Key Conventions

- Dependencies are vendored (`vendor/`). Run `go mod vendor && go mod tidy` after dependency changes.
- CSV output and Python analysis (`evaluate.py`, `errors.py`) are tightly coupled — column names must match.

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

### Design docs

Preconditions, invariants, rationale: `docs/design/`. Update when changing concurrency, CSV, or Horreum.

### Architecture decisions

ADRs (Status / Context / Decision / Consequences): `docs/adr/`.
