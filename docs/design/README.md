# Design intent documentation

This directory documents **why** critical subsystems behave the way they do. Use it together with `CONTEXT.md` (domain glossary) and `README.md` (operator guide).

## Doc map

| Doc | Scope | Key code |
|-----|-------|----------|
| [journey-concurrency.md](journey-concurrency.md) | Parallel user/app/component threads, startup stagger, cleanup | `loadtest.go`, `pkg/journey/` |
| [measurement-and-kpi.md](measurement-and-kpi.md) | Timing CSV, `Measure()`, KPI aggregation | `pkg/logging/`, `ci-scripts/evaluate.py` |
| [results-pipeline.md](results-pipeline.md) | Post-run JSON assembly and Horreum upload | `ci-scripts/run-*/collect-results.sh`, `ci-scripts/config/horreum-*.json` |

## When to update

Review and update the matching design doc when you change thread fan-out, measured function names, CSV column layout, KPI rules, or the `load-test.json` / Horreum schema contract.
