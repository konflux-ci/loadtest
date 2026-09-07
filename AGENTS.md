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

## Key Conventions

- Dependencies are vendored (`vendor/` directory). Always run `go mod vendor && go mod tidy` after changing dependencies.
- CSV output files and Python analysis scripts (`evaluate.py`, `errors.py`) are tightly coupled — column names in Go logging must match what Python expects.

## Pattern References

- New journey stage: see `pkg/journey/handle_pipeline.go` for a reference implementation and `loadtest.go` for wiring into the journey
- Resource create/delete lifecycle: create the resource in a journey handler under                                                                                                     
  `pkg/journey/` (e.g. `handle_releases_setup.go`, `handle_image_repository.go`) and mirror                                                                                                
  the teardown in `handle_purge.go` `Purge()` so cleanup stays idempotent.                                                                                                                 
- Probe run scripts: shell logic lives in `ci-scripts/run-probe/` (`run.sh`,                                                                                                           
  `collect-results.sh`, `cluster_read_config.yaml`); mirror changes in the `run-ci/` /                                                                                                     
  `run-cluster/` variants.                                                                                                                                                                 
- Horreum data scripts: scripts in `ci-scripts/utility_scripts/` (e.g.                                                                                                                 
  `postgresql-backfill.sh`, `runs-to-csv.sh`) paired with schemas in                                                                                                                       
  `ci-scripts/config/horreum-*.json`.

## CI

Pull requests are validated by Konflux Tekton pipelines (`.tekton/`) and GitHub Actions (`.github/workflows/`).

## Agent skills

### Issue tracker

Issues are tracked in Jira at redhat.atlassian.net, project KONFLUX, component "Performance". See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context layout (one `CONTEXT.md` at repo root). See `docs/agents/domain.md`.
