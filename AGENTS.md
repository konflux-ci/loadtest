# AGENTS.md

This file follows the [Global Engineering AGENTS.md best practices](https://gitlab.cee.redhat.com/global-engineering/wg-agentic-sdlc/-/tree/main/best-practices/repo-scaffolding?ref_type=heads).

Go-based load testing tool for Konflux CI/CD. For full project documentation, see [README.md](README.md).

## Build & Test Commands

Go — lint, build, and verify:
```bash
go vet ./...
golangci-lint run ./...
go mod vendor && go mod tidy && go run loadtest.go -h
```

Bash — lint a single script:
```bash
shellcheck <file.sh>
```

Python — lint a single file:
```bash
black --check <file.py>
flake8 <file.py>
```

There are no Go unit tests. Verification relies on linting and a successful build.

## Key Conventions

- Dependencies are vendored (`vendor/` directory). Always run `go mod vendor && go mod tidy` after changing dependencies.
- CSV output files and Python analysis scripts (`evaluate.py`, `errors.py`) are tightly coupled — column names in Go logging must match what Python expects.
- Error pattern matching rules live in `ci-scripts/probe-errors-detector/` as YAML; these are maintained separately from Go code.

## CI

Pull requests are validated by Konflux Tekton pipelines (`.tekton/`) and GitHub Actions (`.github/workflows/`).
