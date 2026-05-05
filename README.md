# Konflux Load Testing Tool

**Summary:** Load testing tool for Konflux CI/CD platform that simulates realistic user journeys (create applications → components → build pipelines → integration tests → releases) across multi-threaded concurrent users. Measures end-to-end duration and failure rates, exporting metrics to Horreum for continuous performance monitoring of production clusters.

**Primary use-case:** This tool runs hourly "probe" tests on 10+ production Konflux clusters, making it a critical observability tool for the platform's performance and reliability. Each test simulates a real developer workflow from application creation to release, measuring lots of distinct stages along the way.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [User Journey Model](#user-journey-model)
- [CLI Usage](#cli-usage)
- [Metrics & Measurement](#metrics--measurement)
- [Analysis Tools](#analysis-tools)
- [Repository Structure](#repository-structure)
- [Related Projects](#related-projects)

## Overview

**What is Konflux?** Konflux is a CI/CD platform built on OpenShift/Kubernetes that provides application lifecycle management, build pipelines (via OpenShift Pipelines/Tekton), integration testing, scanning and automated releases with enterprise contract validation.

**What does this tool do?** This load testing tool simulates realistic user journeys to measure Konflux's performance and scalability. It creates applications, components, and pipelines, then waits for them to complete while measuring duration and tracking errors. It allows configuring concurrency by various means.

**Primary Use Case:** Konflux performance & scale team runs this tool hourly as "probe tests" with concurrency 1 on production clusters including: `stone-prd-rh01`, `stone-stg-rh01`, `stone-prod-p01/p02`, `kflux-prd-rh02/rh03`, `kflux-rhel-p01`, `kflux-ocp-p01` and `kfluxfedorap01`

**Main Metrics:**
- **KPI mean**: Total duration from application creation through release completion (sum of all workflow stage durations)
- **KPI errors**: Number of journeys that failed (for probe runs this means 0 = success, 1 = failure because these run with concurrency 1 only)

## Architecture

The tool uses a **hierarchical multi-threaded journey model** with three concurrency levels:

```
Per-User Thread (--concurrency)
  ├── Per-Application Thread (--applications-count)
  │     ├── Per-Component Thread (--components-count)
  │     │     └── [Component creation → Build → Test → Release]
  │     ├── Per-Component Thread
  │     └── ...
  ├── Per-Application Thread
  └── ...
```

**Context Types:**
- `PerUserContext` - Manages user creation, namespace, repository forking, and lifecycle
- `PerApplicationContext` - Manages application, integration test scenario, release plan setup
- `PerComponentContext` - Manages component creation, build/test/release pipeline execution

**Concurrency Model:**
- **User threads**: Run in parallel (controlled by `--concurrency`)
- **Application threads**: Run in parallel within each user
- **Component threads**: Run in parallel within each application
- **Journey repeats**: Sequential repetitions controlled by `--journey-repeats` or `--journey-duration`

## User Journey Model

1. **Delete Existing Apps** - Cleanup namespace of any previous test artifacts
2. **Create Application** - Create Konflux Application CR in namespace
3. **Create Integration Test Scenario** - Define integration test pipeline (optional, skipped if `--test-scenario-git-url=""`)
4. **Create Component** - Create Component CR, trigger PaC (Pipeline as Code) PR
5. **Create ReleasePlan + ReleasePlanAdmission** - Set up release configuration (optional, requires `--release-policy`)
6. **Wait for Build Pipeline** - Monitor build pipeline completion (if `--waitpipelines`)
7. **Wait for Integration Test** - Monitor integration test execution (if `--waitintegrationtestspipelines`)
8. **Wait for Release** - Monitor release pipeline completion (if `--waitrelease`)
9. **Collect Artifacts/Logs** - Gather pod logs, PVC data, Kubernetes objects for analysis
10. **Purge Resources** - Delete all created resources (if `--purge`)

All workflow stages use this pattern from `pkg/logging/time_and_log.go`:

```go
_, err = logging.Measure(
    context,           // PerUserContext, PerApplicationContext, or PerComponentContext
    functionToMeasure, // e.g., HandleApplication, HandlePipelineRun
    ...args,           // Arguments passed to the function
)
```

This automatically records:
- Timestamp
- Per-user/application/component thread IDs
- Journey repeat counter
- Metric name (function name)
- Duration
- Parameters (serialized to string)
- Error (if any)

**Output:** Results written to `load-test-timings.csv` and `load-test-errors.csv`

## CLI Usage

Check `go run loadtest.go --help` for all possible options.

## Metrics & Measurement

### KPI Calculation

KPI metrics are calculated post test run using `evaluate.py` script:

**KPI mean** (primary performance metric):
```
KPI_mean = SUM(metric_durations) / COUNT(successful_journeys)

Where metric_durations includes:
  HandleUser + HandleRepoForking + createApplication + validateApplication +
  createIntegrationTestScenario + createComponent + getPaCPullNumber +
  validateComponent + validatePipelineRunCreation + validatePipelineRunCondition +
  validatePipelineRunSignature + validateSnapshotCreation +
  validateTestPipelineRunCreation + validateTestPipelineRunCondition +
  createReleasePlan + createReleasePlanAdmission + validateReleasePlan +
  validateReleasePlanAdmission + validateReleaseCreation +
  validateReleasePipelineRunCreation + validateReleasePipelineRunCondition +
  validateReleaseCondition
```

**KPI errors** (failure rate metric):
```
KPI_errors = COUNT(journeys_with_errors)
```

### CSV Output Format

**load-test-timings.csv:**
```
Timestamp,PerUserID,PerAppID,PerCompID,RepeatsCounter,Metric,Duration,Parameters,Error
2026-04-20T10:15:30Z,0,0,0,0,createApplication,2.5s,"name=myapp",
2026-04-20T10:15:33Z,0,0,0,0,createComponent,5.2s,"name=mycomp,repo=https://...",
...
```

**load-test-errors.csv:**
```
Timestamp,Code,Message
2026-04-20T10:20:15Z,1001,"PipelineRun failed: TaskRunImagePullFailed"
...
```

## Analysis Tools

In Probe runs, these run automatically.

### evaluate.py - Performance Analysis

**Purpose:** Compute KPI statistics based on CSV files created by loadtest and store important metrics in `load-test-timings.json` file.

**What it does:**
1. Parses CSV measurements
2. Groups by journey identifier (per-user, per-app, per-comp, repeat)
3. Computes statistics: mean, median, stddev, min, max, percentiles (25th, 75th, 90th, 95th, 99th)
4. Handles conditional metrics (skips integration/release metrics if not tested)
5. Generates JSON output

### errors.py - Error Categorization

**Purpose:** Investigate test artifacts for error patterns and generate error summary reports

**What it does:**
1. Loads error pattern definitions from YAML
2. Categorizes errors from failed journeys by pattern matching
3. Generates human-readable error summaries
4. Stores summary to JSON file for dashboards

**Error Pattern Configuration:** `ci-scripts/config/errors.yaml` (YAML format with regex patterns). This file together with tests and tooling is managed in https://gitlab.cee.redhat.com/jhutar/probe-errors-detector/ repository.

### Data Flow

```
Loadtest → CSV Files → Python analysis → JSON output → Horreum server → PostgreSQL → Grafana
           (timings,   (evaluate.py,     (metrics,     (dashboards,     (hourly job
            errors)     errors.py,        statistics,   alerts)          syncing data)
                        monitoring data)  parameters)
```

## Repository Structure

```
loadtest/
├── loadtest.go                          # Main CLI entry point
├── go.mod, go.sum                       # Go dependencies tracking
├── Containerfile                        # Docker build definition
│
├── pkg/                                 # Core packages
│   ├── journey/                         # User journey handlers
│   │   ├── journey.go                   # Thread setup and orchestration
│   │   ├── handle_users.go              # User creation
│   │   ├── handle_applications.go       # Application creation
│   │   ├── handle_component.go          # Component creation
│   │   ├── handle_pipeline.go           # Build pipeline tracking
│   │   ├── handle_test_run.go           # Integration test tracking
│   │   ├── handle_integration_test_scenarios.go  # Test scenario setup
│   │   ├── handle_releases_setup.go     # Release plan creation
│   │   ├── handle_releases_run.go       # Release execution
│   │   ├── handle_repo_templating.go    # Multi-arch template handling
│   │   ├── handle_collections.go        # Artifact collection
│   │   ├── handle_persistent_volume_claim.go  # PVC data collection
│   │   └── handle_purge.go              # Resource cleanup
│   │
│   ├── logging/                         # Measurement & logging system
│   │   ├── logging.go                   # Logger implementation
│   │   └── time_and_log.go              # Measurement wrapper, CSV output
│   │
│   ├── options/                         # CLI option parsing
│   │   └── options.go                   # Flag definitions and validation
│   │
│   ├── types/                           # Type definitions
│   │   └── types.go                     # Context types (PerUser, PerApp, PerComp)
│   │
│   └── loadtestutils/                   # Helper utilities
│       └── userutils.go                 # User JSON loader
│
├── evaluate.py                          # Post-test analysis script
├── errors.py                            # Error categorization script
│
├── run.sh                               # Main execution script with profiling
├── run-stage.sh                         # Stage environment variant
├── run-max-concurrency.sh               # High-concurrency test script
├── run-stage-max-concurrency.sh         # Stage high-concurrency variant
│
├── cluster_read_config.yaml             # Prometheus queries for monitoring collection
│
├── ci-scripts/                          # CI/CD support scripts
│   ├── config/
│   │   ├── errors.yaml                  # Error pattern definitions
│   │   ├── horreum-schema.json          # Horreum metric schema
│   │   └── README.md                    # Configuration guide
│   ├── load-test.sh                     # CI test execution
│   ├── collect-results.sh               # Result aggregation
│   ├── merge-json.sh                    # User data merging
│   ├── setup-cluster.sh                 # Cluster setup automation
│   └── utility_scripts/                 # Helper scripts (cleanup, backfill, etc.)
│
├── .tekton/                             # Tekton pipeline definitions
│   ├── loadtest-pull-request.yaml
│   └── loadtest-push.yaml
│
└── .github/workflows/                   # GitHub Actions workflows
    └── loadtest.yaml
```

## Related Projects

- **Konflux Perf&Scale team repository**: dashboards definitions and tools - https://github.com/redhat-appstudio/perfscale/
- **Errors catogorizer**: Load Test Probe Error Categorization - https://gitlab.cee.redhat.com/jhutar/probe-errors-detector/
- **e2e-tests Framework**: Konflux end-to-end testing framework (dependency) - https://github.com/konflux-ci/e2e-tests
- **Konflux Platform**: https://github.com/konflux-ci
- **Tekton Pipelines**: https://tekton.dev/
- **Horreum**: Performance benchmarking and analysis - https://horreum.hyperfoil.io/
