# Measurement and KPI system

## Overview

Every journey step is wrapped in `logging.Measure()`, which records duration and outcome to CSV. Post-run, `ci-scripts/evaluate.py` groups rows into per-journey KPIs. The Go writer and Python evaluator share a positional CSV contract — there is no header row.

## Preconditions

- `MeasurementsStart(outputDir)` must run before threads start; `MeasurementsStop()` flushes writers after `Purge()`.
- Measured functions must be passed as named Go functions (not closures) so `runtime.FuncForPC` yields stable metric names.
- `load-test-options.json` (written by `Opts.ProcessOptions()`) must accompany the CSV when running `evaluate.py`, because KPI expectations depend on flags like `--stage`, reuse modes, and skipped release/ITS paths.

## Invariants

- **`load-test-timings.csv` column order** (9 columns, index-based in `evaluate.py`):
  1. Timestamp (RFC3339Nano)
  2. PerUserID
  3. PerAppID
  4. PerCompID
  5. RepeatsCounter
  6. Metric (short function name, e.g. `createApplication`)
  7. Duration (seconds, float)
  8. Parameters (sorted `type:value` pairs; `*framework.Framework` redacted)
  9. Error (`<nil>` or `%v` text)
- **Thread ID `-1`** means the measurement applies at a parent scope (e.g. repo forking at user level); `evaluate.py` treats incomplete IDs as wildcards when merging rows into a complete journey pass.
- **KPI completeness**: a journey pass counts toward `KPI.mean` only when every expected metric for that options profile is present without error. Expected metrics are listed in `evaluate.py` `METRICS` and conditional subsets (`METRICS_CI`, `METRICS_ITS`, `METRICS_RELEASE`, reuse lists).
- **Metric rename coupling**: renaming a measured function or changing CSV column positions breaks `evaluate.py` and `errors.py` without coordinated updates.
- **Async writers**: measurements and errors are sent on channels and batched (size 3) to CSV by background goroutines; callers must not read CSV files until `MeasurementsStop()` returns.

## Rationale

- **Reflection-based `Measure()`** keeps journey handlers free of manual instrumentation; adding a new handler automatically creates a timing row when wrapped.
- **Positional CSV** keeps the hot path simple and append-friendly for long runs; Python analysis runs offline in CI.
- **Short metric names** (package prefix stripped in `evaluate.py`) keep KPI JSON stable even if internal package paths move.
- **Separate `load-test-errors.csv`** (`Logger.Fail()`) captures categorized failure codes for `errors.py` pattern matching against `ci-scripts/config/errors.yaml`.

## Trade-offs

- Batched CSV writes may lose the last partial batch on abrupt process kill; graceful shutdown via `MeasurementsStop()` is required for complete data.
- Reflection cannot capture closure names or inline funcs reliably — new steps should be extracted to named functions in `pkg/journey/`.
