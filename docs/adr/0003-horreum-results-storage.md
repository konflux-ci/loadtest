---
status: Accepted
applies_to: loadtest
---

# 3. Horreum as long-term results store

Date: 2024-01-01

## Status

Accepted

## Context

Probe and CI runs produce `load-test.json` with KPI means, errors, and
monitoring measurements. The Performance team needs historical trend analysis
across clusters and time windows, not only one-off CI artifacts.

## Decision

Assemble a single master `load-test.json` in `collect-results.sh`, then upload
to **Horreum** using schemas under `ci-scripts/config/horreum-*.json`. Utility
scripts (`horreum-backfill.sh`, `postgresql-backfill.sh`) support historical
ingest.

## Consequences

- Positive: one artifact shape for upload, backfill, and dashboard labels
- Positive: Go stays free of Horreum credentials; shell/Python run where secrets live
- Negative: KPI JSON key changes require schema updates and Horreum re-import
- Neutral: `errors.yaml` taxonomy is maintained upstream and vendored here
