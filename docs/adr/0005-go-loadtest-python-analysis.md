---
status: Accepted
applies_to: loadtest
---

# 5. Go load generator with Python post-run analysis

Date: 2024-01-01

## Status

Accepted

## Context

The load generator must drive Kubernetes/Konflux APIs concurrently with low
overhead. KPI semantics (completeness rules, conditional metric sets, error
pattern matching) change more often and benefit from rapid iteration.

## Decision

Implement the concurrent journey runner in **Go** (`loadtest.go`, `pkg/journey/`)
and perform KPI / error aggregation in **Python** (`ci-scripts/evaluate.py`,
`errors.py`) after the run.

## Consequences

- Positive: Go concurrency and typed clients for the hot path
- Positive: Python analysis can evolve without rebuilding the load binary
- Negative: two-language contract (CSV columns, metric names, options JSON)
- Neutral: pre-commit covers both Go and Python checks in one `make check-all`
