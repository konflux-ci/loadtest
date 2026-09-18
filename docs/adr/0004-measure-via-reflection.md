---
status: Accepted
applies_to: loadtest
---

# 4. Reflection-based Measure() instrumentation

Date: 2024-01-01

## Status

Accepted

## Context

Journey handlers need timing around many API calls. Manual metric names drift
when functions are renamed. Closures and inline funcs produce unstable names.

## Decision

Wrap steps in `logging.Measure()` using named Go functions so
`runtime.FuncForPC` yields stable metric names written to CSV. KPI completeness
in `evaluate.py` keys off those names.

## Consequences

- Positive: adding a named handler automatically produces a timing row
- Positive: package prefixes can be stripped offline for stable KPI JSON keys
- Negative: closures/anonymous funcs must be extracted to named functions
- Neutral: abrupt process kill can lose the last CSV write batch until `MeasurementsStop()`
