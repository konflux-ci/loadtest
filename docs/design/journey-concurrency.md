# Journey concurrency model

## Overview

loadtest simulates many Konflux users in parallel. Concurrency is structured in three nested levels:

```
main → PerUserSetup (× concurrency)
         → PerApplicationSetup (× applications-count)
              → PerComponentSetup (× components-count)
```

Each component thread runs one full journey: create resources, wait for pipelines, release, collect artifacts. See `loadtest.go` for thread entry points and `pkg/journey/journey.go` for setup orchestration.

## Preconditions

- `MeasurementsStart(outputDir)` has run before any journey thread starts.
- When `--stage` is set, `users.json` must contain at least `concurrency` entries; thread `N` uses `stageUsers[N]`.
- Repo forking (`HandleRepoForking`) requires a valid `--fork-target` or `MY_GITHUB_ORG`.
- `--release-managed-readonly` requires `--concurrency 1` and a pre-existing ReleasePlanAdmission name (releng-owned static RPA).
- `--release-managed-namespace` with a managed token requires both namespace and token flags.

## Invariants

- **Per-thread Framework isolation**: each application and component thread provisions its own `framework.Framework` (and `ManagedFramework` when release-managed mode is enabled). API clients are never shared across sibling threads.
- **Sequential repo forking**: `HandleRepoForking` runs sequentially across users because GitHub allows at most three concurrent forks.
- **Startup stagger**: thread index `0` never sleeps; later threads wait `startup-delay ± jitter/2` to spread API load.
- **WaitGroup nesting**: `PerUserWG`, `PerApplicationWG`, and `PerComponentWG` each gate their child goroutines; parents block until all children call `Done()`.
- **Global purge list**: `journey.PerUserContexts` accumulates every user context during setup; `Purge()` iterates it only after all user threads finish.
- **Collection is best-effort**: `HandlePerUser/Application/ComponentCollection` run in `defer` at thread exit; failures are logged but do not stop sibling threads.
- **Journey termination**: the user loop stops when `--journey-repeats` is exhausted or `JourneyUntil` (from `--journey-duration`) is reached, whichever comes first.
- **Reuse flags**: `JourneyReuseComponents` implies `JourneyReuseApplications` (enforced in `ProcessOptions()`).

## Rationale

- **Three-level fan-out** mirrors real tenant structure (user → application → component) and lets load tests scale independently along each axis.
- **Sequential forking** avoids GitHub rate-limit failures that would otherwise poison KPI data with setup errors unrelated to Konflux.
- **Separate managed Framework** keeps release-pipeline operations in the managed namespace without widening tenant-namespace RBAC on the main client.
- **Deferred collection** captures partial state even when a journey fails mid-way, which aids post-run debugging in `collected-data/`.

## Trade-offs

- Optional `--serialize-component-onboarding` reduces parallel component churn at the cost of throughput; lock wait time is intentionally outside `Measure()` so it does not affect KPI timings.
- High `concurrency × applications-count × components-count` can overwhelm small clusters; startup delay only smooths the initial wave, not sustained load.
