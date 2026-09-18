---
status: Accepted
applies_to: loadtest
---

# 1. Positional CSV for timing measurements

Date: 2024-01-01

## Status

Accepted

## Context

loadtest records thousands of timing rows per run. Agents and CI need a stable
contract between the Go writer (`pkg/logging`) and Python analysis
(`ci-scripts/evaluate.py`, `errors.py`). A headered or schema-versioned format
would add per-row overhead and more branching in the hot path.

## Decision

Emit timing rows as a **positional CSV** with a fixed 9-column layout and no
header row. Column indices are part of the public analysis contract.

## Consequences

- Positive: append-friendly hot path; simple offline Python aggregation
- Positive: metric names stay short (function names via reflection)
- Negative: renaming columns or inserting fields requires coordinated Go + Python changes
- Neutral: `load-test-options.json` must accompany the CSV so expected metrics match flags
