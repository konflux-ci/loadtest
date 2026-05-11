# AGENTS.md

For full project documentation, see [README.md](README.md).

## Project overview

Go-based load testing tool for the Konflux CI/CD platform. It simulates
realistic user journeys (create applications, components, build pipelines,
integration tests, releases) with configurable concurrency. Results are
exported as CSV, analysed by Python scripts, and stored in Horreum.

## Repository layout

- `loadtest.go` — CLI entry point
- `pkg/journey/` — user journey handlers (users, apps, components, pipelines, tests, releases)
- `pkg/logging/` — measurement wrappers and CSV output
- `pkg/options/` — CLI flag definitions
- `pkg/types/` — context types (PerUser, PerApp, PerComp)
- `evaluate.py`, `errors.py` — post-run analysis scripts
- `run.sh`, `run-stage.sh` — execution scripts
- `ci-scripts/` — CI helpers and error-pattern config

## Languages and tools

- Go (main codebase), Python (analysis scripts), Bash (execution/CI scripts)

## Build and validate

```bash
go vet ./...
go mod vendor && go mod tidy && go run loadtest.go -h
```

## Linting

```bash
shellcheck <file.sh>          # Bash scripts must pass shellcheck
black --check <file.py>       # Python code must pass black
flake8 <file.py>              # Python code must pass flake8
```

## Testing

There is no unit test suite yet. The build-and-validate command above is the
only automated check to verify code correctness. Functional testing requires
a live Konflux cluster.

## Key patterns

- All timed operations use `logging.Measure()` from `pkg/logging/time_and_log.go`
- Three nested context types drive concurrency: `PerUserContext` → `PerApplicationContext` → `PerComponentContext`
- CLI options are defined in `pkg/options/options.go`

## CI

Pull requests are validated by Tekton pipelines (`.tekton/`) and GitHub
Actions (`.github/workflows/`).
