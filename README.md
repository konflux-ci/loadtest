# Konflux Load Testing Tool

**Summary:** Load testing tool for Konflux CI/CD platform that simulates realistic user journeys (create applications → components → build pipelines → integration tests → releases) across multi-threaded concurrent users. Measures end-to-end duration and failure rates, exporting metrics to Horreum for continuous performance monitoring of production clusters.

**Primary use-case:** This tool runs hourly "probe" tests on 10+ production Konflux clusters, making it a critical observability tool for the platform's performance and reliability. Each test simulates a real developer workflow from application creation to release, measuring lots of distinct stages along the way.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [User Journey Model](#user-journey-model)
- [Quick Start](#quick-start)
- [CLI Usage](#cli-usage)
  - [Common Scenarios](#common-scenarios)
  - [CLI Parameters Reference](#cli-parameters-reference)
- [Metrics & Measurement](#metrics--measurement)
- [Analysis Tools](#analysis-tools)
- [CI/CD Integration](#cicd-integration)
- [Repository Structure](#repository-structure)
- [Configuration](#configuration)
- [Related Projects](#related-projects)

## Overview

**What is Konflux?** Konflux is a CI/CD platform built on OpenShift/Kubernetes that provides application lifecycle management, build pipelines (via OpenShift Pipelines/Tekton), integration testing, scanning and automated releases with enterprise contract validation.

**What does this tool do?** This load testing tool simulates realistic user journeys to measure Konflux's performance and scalability. It creates applications, components, and pipelines, then waits for them to complete while measuring duration and tracking errors. It allows configuring concurrency by various means.

**Primary Use Case:** Konflux performance & scale team runs this tool hourly as "probe tests" with concurrency 1 on production clusters including: `stone-prd-rh01`, `stone-stg-rh01`, `stone-prod-p01/p02`, `kflux-prd-rh02/rh03`, `kflux-rhel-p01`, `kflux-ocp-p01` and `kfluxfedorap01`

**Main Metrics:**
- **KPI mean**: Total duration from application creation through release completion (sum of all workflow stage durations)
- **KPI errors**: Number of journeys that failed (for probe runs this means 0 = success, 1 = failure because these run with concurrency 1 only)

**Test Flavors:** The tool supports custom `.tekton` files that can configure custom types of probe builds. Currently for "probe tests" we are running these:
1. Single-architecture container builds - on all clusters
2. Multi-architecture container builds - on all clusters
3. Multi-architecture RPM builds - on 4 clusters only
4. MS Windows container builds (in development) - on one cluster only

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

**Key Files:**
- `pkg/types/types.go` - Context type definitions
- `pkg/journey/journey.go` - Thread setup and orchestration

## User Journey Model

Each journey executes these stages in sequence, with every stage wrapped in `logging.Measure()` for timing:

### Workflow Stages

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

### Measurement Pattern

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

## Quick Start

### Run Simplest Test

TODO We need to have `users.json` and more.

```bash
# Single user, single app, single component, wait for build only
go run loadtest.go \
  --component-repo "https://github.com/nodeshift-starters/devfile-sample" \
  --waitpipelines \
  --log-info
```

This creates 1 application, 1 component, triggers the build pipeline, waits for completion, and outputs timing measurements to `./load-test-timings.csv`.

## CLI Usage

### Common Scenarios

#### Probe-like Test

Some options for runs with 1 concurrent user, creating 1 app, with 1 component, full workflow:

```
  --concurrency 1 \
  --applications-count 1 \
  --components-count 1 \
  --waitpipelines \
  --waitintegrationtestspipelines \
  --waitrelease \
  --release-policy "tmp-onboard-policy" \
```

#### Load Test (Multiple Users/Apps/Components)

Run with 5 concurrent users, each creating 2 apps with 3 components = 30 total concurrent (started with delays) builds:

```
  --concurrency 5 \
  --applications-count 2 \
  --components-count 3 \
  --waitpipelines \
  --startup-delay 10s \
  --startup-jitter 5s \
```

#### Journey Repeats (Stress Test)

Repeat the journey 10 times or for 2 hours, whichever comes first:

```
  --journey-repeats 10 \
  --journey-duration "2h" \
  --journey-reuse-applications \
```

#### Purge-Only Mode

Clean up resources from previous test without running a new test:

```bash
go run loadtest.go --purge-only
```

### CLI Parameters Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--component-repo` | string | `https://github.com/nodeshift-starters/devfile-sample` | Component repository URL |
| `--component-repo-revision` | string | `main` | Git branch/revision |
| `--component-repo-container-file` | string | `Dockerfile` | Dockerfile path in repo |
| `--component-repo-container-context` | string | `/` | Build context directory |
| `--applications-count` | int | `1` | Applications per user |
| `--components-count` | int | `1` | Components per application |
| `--concurrency`, `-c` | int | `1` | Concurrent user threads |
| `--journey-repeats` | int | `1` | Sequential journey iterations |
| `--journey-duration` | duration | `1h` | Repeat until timeout (alternative to repeats) |
| `--journey-reuse-applications` | bool | `false` | Reuse apps across journey repeats |
| `--journey-reuse-components` | bool | `false` | Reuse components across repeats |
| `--waitpipelines`, `-w` | bool | `false` | Wait for build pipelines to complete |
| `--waitintegrationtestspipelines`, `-i` | bool | `false` | Wait for integration test pipelines |
| `--waitrelease`, `-r` | bool | `false` | Wait for release to complete |
| `--purge`, `-p` | bool | `false` | Delete resources after test |
| `--purge-only`, `-u` | bool | `false` | Only purge, don't run test |
| `--stage`, `-s` | bool | `false` | Run on stage environment |
| `--fork-target` | string | `""` | GitHub org or GitLab namespace for forking repos |
| `--quay-repo` | string | `redhat-user-workloads-stage` | Quay repository for images |
| `--runprefix` | string | `testuser` | Prefix for user names and repo forks |
| `--startup-delay` | duration | `0` | Delay between thread starts |
| `--startup-jitter` | duration | `3s` | Random jitter added to delay |
| `--test-scenario-git-url` | string | `https://github.com/konflux-ci/integration-examples.git` | Integration test repo (empty to disable) |
| `--test-scenario-revision` | string | `main` | Integration test repo branch |
| `--test-scenario-path-in-repo` | string | `pipelines/integration_resolver_pipeline_pass.yaml` | Test pipeline path |
| `--release-policy` | string | `""` | Enterprise contract policy (empty to skip release) |
| `--release-pipeline-url` | string | `https://github.com/konflux-ci/release-service-catalog.git` | Release pipeline repo |
| `--release-pipeline-revision` | string | `production` | Release pipeline branch |
| `--release-pipeline-path` | string | `pipelines/managed/e2e/e2e.yaml` | Release pipeline file |
| `--release-ociStorage` | string | `quay.io/rhtap-perf-test/perf-release-service-trusted-artifacts` | OCI storage for release artifacts |
| `--release-pipeline-service-account` | string | `release-serviceaccount` | ServiceAccount for release pipeline |
| `--pipeline-mintmaker-disabled` | bool | `true` | Disable Mintmaker update PRs |
| `--pipeline-repo-templating` | bool | `false` | Use in-repo pipeline templating (for multi-arch) |
| `--pipeline-repo-templating-source` | string | `""` | Source repo for pipeline templates |
| `--pipeline-repo-templating-source-dir` | string | `""` | Directory in source repo (default: `.template/`) |
| `--pipeline-image-pull-secrets` | []string | `[]` | Secrets for pulling task images (repeatable) |
| `--build-pipeline-selector-bundle` | string | `""` | BuildPipelineSelector bundle for testing |
| `--fail-fast` | bool | `false` | Stop on first failure |
| `--output-dir`, `-o` | string | `.` | Output directory for logs and CSVs |
| `--log-info`, `-v` | bool | `false` | Enable INFO level logging |
| `--log-debug`, `-d` | bool | `false` | Enable DEBUG level logging |
| `--log-trace`, `-t` | bool | `false` | Enable TRACE level logging (everything) |
| `--serialize-component-onboarding` | bool | `false` | Serialize component creation (for debugging) |

## Metrics & Measurement

### KPI Calculation

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

### Measured Metrics

The tool tracks lots of core metrics (from `evaluate.py`):

**User & Repository Setup:**
- `HandleUser` - User/namespace creation (if `--stage` is provided (which is the case for probe runs), these are not created, but loaded from `users.json` file, they need to exist in advance)
- `HandleRepoForking` - Fork component repository

**Application Stage:**
- `createApplication` - Create Application CR
- `validateApplication` - Verify application created successfully
- `createIntegrationTestScenario` - Create integration test scenario (conditional)

**Component Stage:**
- `createComponent` - Create Component CR
- `getPaCPullNumber` - Get PaC pull request number
- `validateComponent` - Verify component onboarded

**Build Pipeline Stage:**
- `validatePipelineRunCreation` - Verify PipelineRun created
- `validatePipelineRunCondition` - Wait for build completion
- `validatePipelineRunSignature` - Verify Tekton Chains signature

**Integration Test Stage (conditional):**
- `validateSnapshotCreation` - Verify snapshot created
- `validateTestPipelineRunCreation` - Verify test PipelineRun created
- `validateTestPipelineRunCondition` - Wait for test completion

**Release Stage (conditional):**
- `createReleasePlan` - Create ReleasePlan CR
- `createReleasePlanAdmission` - Create ReleasePlanAdmission CR
- `validateReleasePlan` - Verify ReleasePlan created
- `validateReleasePlanAdmission` - Verify ReleasePlanAdmission created
- `validateReleaseCreation` - Verify Release CR created
- `validateReleasePipelineRunCreation` - Verify release PipelineRun created
- `validateReleasePipelineRunCondition` - Wait for release completion
- `validateReleaseCondition` - Verify release succeeded

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

**Usage:**
```bash
python3 evaluate.py load-test-options.json load-test-timings.csv load-test-timings.json
```

**What it does:**
1. Parses CSV measurements
2. Groups by journey identifier (per-user, per-app, per-comp, repeat)
3. Computes statistics: mean, median, stddev, min, max, percentiles (25th, 75th, 90th, 95th, 99th)
4. Handles conditional metrics (skips integration/release metrics if not tested)
5. Generates JSON output

**Output Format:**
```json
{
  "KPI_mean": 45.2,
  "KPI_errors": 0,
  "createApplication": {
    "mean": 2.5,
    "p95": 2.6,
    ...
  },
  "validatePipelineRunCondition": {
    "mean": 101.2,
    "p95": 210.5,
    ...
  },
  ...
}
```

### errors.py - Error Categorization

**Purpose:** Investigate test artifacts for error patterns and generate error summary reports

**Usage:**
```bash
python3 errors.py load-test-errors.csv load-test-timings.json load-test-errors.json /collected-data/
```

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

## CI/CD Integration

### Tekton Pipelines

This project uses Konflux itself to build container image used to run the probe tests. This creates chicken/egg refference.

**Pipeline Definitions:**
- `.tekton/loadtest-pull-request.yaml` - PR validation pipeline
- `.tekton/loadtest-push.yaml` - Post-merge pipeline

### GitHub Actions

**Workflow:** `.github/workflows/loadtest.yaml`
- Provides a simplified way to run the loadtest against Stage server

### Jenkins Integration

The tool runs hourly (for probe runs) in Jenkins jobs configured in `ci-configs` repository:
- Job DSL configs: `src/jobs/StoneSoupLoadTestProbe_<cluster>Job.groovy`
- Jenkinsfiles: `jenkins/StoneSoupLoadTestProbe_<cluster>.groovy`
- Shared library: `vars/runKonfluxProbeTest.groovy`

### Horreum Export

Results are collected to single JSON file and uploaded to Horreum (performance benchmarking system) for historical tracking and alerting.

Horreum schema defining important data in the JSON we are uploading (called "labels") is defined in `ci-scripts/config/horreum-schema.json`.

### Grafana Dashboards

Production dashboards at https://grafana.corp.redhat.com/ (Konflux perf&scale organization) are maintainer in https://github.com/redhat-appstudio/perfscale/ repository:
- Single-arch container probe results
- Multi-arch container probe results
- RPM build probe results
- Error trends

## Repository Structure

```
loadtest/
├── loadtest.go                          # Main CLI entry point (426 lines)
├── go.mod, go.sum                       # Go dependencies tracking
├── Containerfile                        # Docker build definition
│
├── pkg/                                 # Core packages
│   ├── journey/                         # User journey handlers (14 files, ~3100 lines)
│   │   ├── journey.go                   # Thread setup and orchestration
│   │   ├── handle_users.go              # User creation
│   │   ├── handle_applications.go       # Application creation
│   │   ├── handle_component.go          # Component creation (532 lines)
│   │   ├── handle_pipeline.go           # Build pipeline tracking
│   │   ├── handle_test_run.go           # Integration test tracking
│   │   ├── handle_integration_test_scenarios.go  # Test scenario setup
│   │   ├── handle_releases_setup.go     # Release plan creation
│   │   ├── handle_releases_run.go       # Release execution
│   │   ├── handle_repo_templating.go    # Multi-arch template handling (326 lines)
│   │   ├── handle_collections.go        # Artifact collection (403 lines)
│   │   ├── handle_persistent_volume_claim.go  # PVC data collection
│   │   └── handle_purge.go              # Resource cleanup
│   │
│   ├── logging/                         # Measurement & logging system
│   │   ├── logging.go                   # Logger implementation
│   │   └── time_and_log.go              # Measurement wrapper, CSV output (365 lines)
│   │
│   ├── options/                         # CLI option parsing (125 lines)
│   │   └── options.go                   # Flag definitions and validation
│   │
│   ├── types/                           # Type definitions (50 lines)
│   │   └── types.go                     # Context types (PerUser, PerApp, PerComp)
│   │
│   └── loadtestutils/                   # Helper utilities (38 lines)
│       └── userutils.go                 # User JSON loader
│
├── evaluate.py                          # Post-test analysis script (600+ lines)
├── errors.py                            # Error categorization script (400+ lines)
│
├── run.sh                               # Main execution script with profiling
├── run-stage.sh                         # Stage environment variant
├── run-max-concurrency.sh               # High-concurrency test script
├── run-stage-max-concurrency.sh         # Stage high-concurrency variant
│
├── cluster_read_config.yaml             # Prometheus queries for monitoring collection (~200 entries)
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

## Configuration

### Environment Variables

Key environment variables (loaded by `pkg/options/options.go`):

- `MY_GITHUB_ORG` - Default GitHub organization for forking repositories
- `QUAY_OAUTH_TOKEN` - Quay.io authentication token
- `KONFLUX_USERS` - Path to users JSON file for stage testing

### User JSON Format

For stage environments, users are loaded from JSON (via `pkg/loadtestutils/userutils.go`):

```json
[
  {
    "username": "testuser",
    "namespace": "testuser-tenant",
    "token": "sha256~...",
    "apiurl": "https://api.cluster.example.com:6443"
  }
]
```

## Related Projects

- **Konflux Perf&Scale team repository**: dashboards definitions and tools - https://github.com/redhat-appstudio/perfscale/
- **Errors catogorizer**: Load Test Probe Error Categorization - https://gitlab.cee.redhat.com/jhutar/probe-errors-detector/
- **e2e-tests Framework**: Konflux end-to-end testing framework (dependency) - https://github.com/konflux-ci/e2e-tests
- **Konflux Platform**: https://github.com/konflux-ci
- **Tekton Pipelines**: https://tekton.dev/
- **Horreum**: Performance benchmarking and analysis - https://horreum.hyperfoil.io/
