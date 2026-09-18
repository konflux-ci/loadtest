---
status: Accepted
applies_to: loadtest
---

# 2. Three-level journey concurrency model

Date: 2024-01-01

## Status

Accepted

## Context

Konflux tenants are structured as users owning applications that contain
components. A flat worker pool would not mirror that shape and would make
per-user credentials, namespaces, and cleanup harder to reason about.

## Decision

Structure concurrency as nested goroutines:

```
PerUserSetup → PerApplicationSetup → PerComponentSetup
```

Each application/component thread owns its own `framework.Framework`. Repo
forking stays sequential (GitHub concurrency limits). Startup stagger spreads
initial API load.

## Consequences

- Positive: scales independently along user / application / component axes
- Positive: purge iterates a global list only after all user threads finish
- Negative: high fan-out can overwhelm small clusters; stagger only softens the start
- Neutral: optional `--serialize-component-onboarding` trades throughput for stability
