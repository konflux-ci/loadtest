.DEFAULT_GOAL := help
.PHONY: help bootstrap check check-all build vendor

# Let Go automatically download the toolchain version required by go.mod.
export GOTOOLCHAIN := auto

help:
	@echo "Available targets:"
	@echo "  help                 - Show this help message"
	@echo "  bootstrap            - Install all development tools"
	@echo "  check                - Run checks on staged changes"
	@echo "  check-all            - Run checks on all files"
	@echo "  build                - Build the loadtest binary"
	@echo "  vendor               - Tidy and vendor Go dependencies"

bootstrap:
	@echo "==> Installing Python 3.12 (via uv)..."
	uv python install 3.12
	@echo "==> Installing pre-commit..."
	uv tool install pre-commit || uv tool upgrade pre-commit
	@echo "==> Installing golangci-lint..."
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	@echo "==> Installing pre-commit hooks..."
	@PATH="$(HOME)/.local/bin:$(PATH)" pre-commit install
	@echo ""
	@echo "==> Bootstrap complete!"
	@echo "    Make sure $(HOME)/.local/bin is on your PATH."

check:
	pre-commit run

check-all:
	pre-commit run --all-files

build:
	go build -o bin/loadtest loadtest.go

vendor:
	go mod tidy
	go mod vendor
