# Results and Horreum pipeline

## Overview

After loadtest exits, CI scripts transform raw artifacts into a single `load-test.json` status file, enrich it with Prometheus monitoring data, and upload to Horreum for trend analysis. Entry points: `ci-scripts/run-ci/collect-results.sh`, `ci-scripts/run-probe/collect-results.sh`, and `ci-scripts/run-cluster/collect-results.sh` (probe/cluster variants mirror CI logic with environment-specific config).

## Pipeline flow

```
loadtest binary
  → load-test-timings.csv, load-test-errors.csv, load-test-options.json
  → collected-data/{namespace}/{journeyIndex}/   (K8s object dumps)

collect-results.sh
  → evaluate.py        → load-test-timings.json
  → errors.py          → load-test-errors.json
  → get-taskruns-durations.py → get-taskruns-durations.json
  → show-pipelineruns.py      → show-pipelines.svg
  → status_data.py     → load-test.json  (master artifact)
  → monitoring queries → measurements.* in load-test.json

Horreum / PostgreSQL (utility scripts)
  → horreum-backfill.sh / postgresql-backfill.sh
```

## Preconditions

- `started` and `ended` timestamp files exist in the run directory (written by `run.sh` before/after loadtest).
- Raw CSV and `load-test-options.json` are present in the artifact directory before `evaluate.py` runs.
- For monitoring enrichment, `cluster_read_config.yaml` must define Prometheus queries valid for the target cluster window (`started`…`ended`).
- Horreum schema (`ci-scripts/config/horreum-schema.json`, id 169) must be imported in the Horreum instance before new label extractors take effect.

## Invariants

- **`load-test.json` shape**: `status_data.py` sets `parameters.options`, `results.measurements`, `results.errors`, and `results.durations` subtrees from the intermediate JSON files; downstream Horreum extractors use JSONPath labels like `$.results.measurements.KPI.mean`.
- **Evaluation order**: `evaluate.py` runs before `errors.py` because error categorization may reference timing structure.
- **Schema coupling**: changes to KPI JSON keys require updating `horreum-schema.json` and re-importing to Horreum (see `ci-scripts/config/README.md`).
- **Probe exit policy**: `run-probe/collect-results.sh` may fail the job when KPI thresholds are breached; CI daily runs typically record without gating.

## Rationale

- **Separation of concerns**: Go emits raw timings; Python computes KPI semantics; shell orchestrates aggregation and monitoring in the environment where secrets and Prometheus live.
- **Single master JSON** simplifies Horreum upload and historical backfill (`shovel.py`, `horreum-data-mirror`) without re-running cluster queries.
- **Collected Kubernetes JSON** is independent of KPI math — it supports deep dives when CSV aggregates hide failure context.

## Trade-offs

- `errors.yaml` pattern rules are maintained in a separate upstream repo and vendored here; error taxonomy changes happen outside this repo.
- Monitoring queries add cluster-specific noise; probe runs append per-pod step queries dynamically, so schema labels must stay broad enough to absorb new step types.
