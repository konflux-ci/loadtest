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

## Testing

For Go code, we do not have any tests, but linting and build needs to pass:

```bash
go vet ./...
golangci-lint run ./...
go mod vendor && go mod tidy && go run loadtest.go -h
```

Bash scripts must pass `shellcheck`:

```bash
shellcheck <file.sh>
```

Python code has to pass `black` and `flake8`:

```bash
black --check <file.py>
flake8 <file.py>
```

## CI

Pull requests are validated by Konflux Tekton pipelines (`.tekton/`)
and GitHub Actions (`.github/workflows/`).
