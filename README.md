# Konflux Load Testing Tool

[![Go](https://img.shields.io/badge/Go-1.25-blue.svg)](https://golang.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

**AI-Optimized Summary:** Load testing tool for Konflux CI/CD platform that simulates realistic user journeys (create applications → components → build pipelines → integration tests → releases) across multi-threaded concurrent users. Measures end-to-end duration and failure rates, exporting metrics to Horreum for continuous performance monitoring of production clusters.

> **Key Insight:** This tool runs hourly "probe" tests on 10+ production Konflux clusters, making it a critical observability tool for the platform's performance and reliability. Each test simulates a real developer workflow from application creation to release, measuring 22+ distinct stages along the way.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [User Journey Model](#user-journey-model)
- [Test Types Supported](#test-types-supported)
- [Quick Start](#quick-start)
- [CLI Usage](#cli-usage)
  - [Common Scenarios](#common-scenarios)
  - [CLI Parameters Reference](#cli-parameters-reference)
- [Metrics & Measurement](#metrics--measurement)
- [Analysis Tools](#analysis-tools)
- [CI/CD Integration](#cicd-integration)
- [Repository Structure](#repository-structure)
- [Configuration](#configuration)
- [Development Guide](#development-guide)
- [Related Projects](#related-projects)

## Overview

**What is Konflux?** Konflux is a CI/CD platform built on OpenShift/Kubernetes that provides application lifecycle management, build pipelines (via Tekton), integration testing, and automated releases with enterprise contract validation.

**What does this tool do?** This load testing tool simulates realistic user journeys to measure Konflux's performance and scalability. It creates applications, components, and pipelines, then waits for them to complete while measuring duration and tracking errors.

**Primary Use Case:** Konflux performance & scale team runs this tool hourly as "probe tests" on production clusters including:
- `stone-prd-rh01`, `stone-stg-rh01`, `stone-prod-p01/p02`
- `kflux-prd-rh02/rh03`, `kflux-rhel-p01`, `kflux-ocp-p01`
- `kfluxfedorap01`

**Main Metrics:**
- **KPI mean**: Total duration from application creation through release completion (sum of all workflow stage durations)
- **KPI errors**: Binary error count per journey (0 = success, 1 = failure)

**Test Flavors:** The tool supports three types of probe builds:
1. Single-architecture container builds
2. Multi-architecture container builds
3. RPM/source builds

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
- `pkg/journey/journey.go` - Thread setup and orchestration (lines 12-175)

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

## Test Types Supported

| Test Type | Description | Key CLI Flags |
|-----------|-------------|---------------|
| **Single-Arch Container** | Standard Docker/OCI container builds | `--component-repo`, `--component-repo-container-file` |
| **Multi-Arch Container** | Multi-platform builds (ARM64, etc.) via remote host pools | `--pipeline-repo-templating`, `--pipeline-repo-templating-source` |
| **RPM/Source Builds** | Source image builds for reproducibility, RPM packages | Custom component repo with RPM pipeline definitions |
| **Integration Tests** | Component integration test scenarios | `--test-scenario-git-url`, `--waitintegrationtestspipelines` |
| **Release Testing** | End-to-end release with enterprise contract validation | `--release-policy`, `--waitrelease` |

## Quick Start

### Build the Tool

```bash
cd /home/jhutar/Checkouts/refactor/loadtest
go build -o loadtest loadtest.go
```

### Run Simplest Test

```bash
# Single user, single app, single component, wait for build only
./loadtest \
  --component-repo "https://github.com/nodeshift-starters/devfile-sample" \
  --waitpipelines \
  --log-info
```

This creates 1 application, 1 component, triggers the build pipeline, waits for completion, and outputs timing measurements to `./load-test-timings.csv`.

## CLI Usage

### Common Scenarios

#### Hourly Probe Test (Production Usage)

```bash
# Simulates hourly probe: 1 user, 1 app, 1 component, full workflow
./loadtest \
  --component-repo "https://github.com/konflux-ci/loadtest-sample" \
  --applications-count 1 \
  --components-count 1 \
  --concurrency 1 \
  --waitpipelines \
  --waitintegrationtestspipelines \
  --waitrelease \
  --release-policy "tmp-onboard-policy" \
  --purge \
  --output-dir "./results" \
  --log-info
```

#### Load Test (Multiple Users/Apps/Components)

```bash
# 5 concurrent users, each creating 2 apps with 3 components = 30 total components
./loadtest \
  --concurrency 5 \
  --applications-count 2 \
  --components-count 3 \
  --component-repo "https://github.com/nodeshift-starters/devfile-sample" \
  --waitpipelines \
  --startup-delay 10s \
  --startup-jitter 5s \
  --output-dir "./load-test-results"
```

#### Pipeline-Only Test (Skip Integration/Release)

```bash
# Test only build pipeline performance, skip integration tests and releases
./loadtest \
  --component-repo "https://github.com/konflux-ci/loadtest-sample" \
  --waitpipelines \
  --test-scenario-git-url "" \
  --release-policy "" \
  --log-debug
```

#### Multi-Arch Container Build Test

```bash
# Test multi-architecture builds with in-repo pipeline templating
./loadtest \
  --component-repo "https://github.com/konflux-ci/multi-arch-sample" \
  --pipeline-repo-templating \
  --pipeline-repo-templating-source "https://github.com/konflux-ci/build-templates" \
  --waitpipelines \
  --log-info
```

#### Journey Repeats (Stress Test)

```bash
# Repeat the journey 10 times or for 2 hours, whichever comes first
./loadtest \
  --journey-repeats 10 \
  --journey-duration "2h" \
  --journey-reuse-applications \
  --component-repo "https://github.com/nodeshift-starters/devfile-sample" \
  --waitpipelines
```

#### Purge-Only Mode

```bash
# Clean up resources from previous test without running a new test
./loadtest --purge-only --runprefix "mytest"
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
| `--release-ociStorage` | string | `quay.io/rhtap-test-local/perf-release-service-trusted-artifacts` | OCI storage for release artifacts |
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
KPI_errors = COUNT(journeys_with_errors) / COUNT(total_journeys)
```

### Measured Metrics

The tool tracks 22 core metrics (from `evaluate.py:24-47`):

**User & Repository Setup:**
- `HandleUser` - User/namespace creation
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

### evaluate.py - Performance Analysis

**Purpose:** Compute KPI statistics and export results to Horreum (performance benchmarking system)

**Usage:**
```bash
python3 evaluate.py load-test-timings.csv > results.json
```

**What it does:**
1. Parses CSV measurements
2. Groups by journey identifier (per-user, per-app, per-comp, repeat)
3. Computes statistics: mean, median, stddev, min, max, percentiles (25th, 75th, 90th, 95th, 99th)
4. Handles conditional metrics (skips integration/release metrics if not tested)
5. Generates Horreum-compatible JSON output

**Output Format:**
```json
{
  "KPI_mean": 45.2,
  "KPI_errors": 0,
  "createApplication_mean": 2.5,
  "createComponent_mean": 5.1,
  "validatePipelineRunCondition_mean": 180.3,
  ...
  "validatePipelineRunCondition_p95": 210.5,
  ...
}
```

### errors.py - Error Categorization

**Purpose:** Parse error patterns and generate error summary reports

**Usage:**
```bash
python3 errors.py load-test-errors.csv ci-scripts/config/errors.yaml > error-report.txt
```

**What it does:**
1. Loads error pattern definitions from YAML
2. Categorizes errors by pattern matching
3. Generates human-readable error summaries
4. Provides error code mapping for dashboards

**Error Pattern Configuration:** `ci-scripts/config/errors.yaml` (YAML format with regex patterns)

### Data Flow

```
Loadtest Execution → CSV Files → Python Analysis → JSON Output → Horreum/Grafana
                     (timings,       (evaluate.py,    (metrics,      (dashboards,
                      errors)         errors.py)        statistics)    alerts)
```

## CI/CD Integration

### Tekton Pipelines

**Pipeline Definitions:**
- `.tekton/loadtest-pull-request.yaml` - PR validation pipeline
- `.tekton/loadtest-push.yaml` - Post-merge pipeline

### GitHub Actions

**Workflow:** `.github/workflows/loadtest.yaml`
- Triggers on PR and push events
- Runs unit tests
- Builds container image

### Jenkins Integration

The tool runs hourly in Jenkins jobs configured in `ci-configs` repository:
- Job DSL configs: `src/jobs/StoneSoupLoadTestProbe_<cluster>Job.groovy`
- Jenkinsfiles: `jenkins/StoneSoupLoadTestProbe_<cluster>.groovy`
- Shared library: `vars/runKonfluxProbeTest.groovy`

### Horreum Export

Results are automatically exported to Horreum (performance benchmarking system) for historical tracking and alerting. Schema defined in `ci-scripts/config/horreum-schema.json`.

### Grafana Dashboards

Production dashboards at https://grafana.corp.redhat.com/ (Konflux perf&scale organization):
- Single-arch container probe results
- Multi-arch container probe results
- RPM build probe results

## Repository Structure

```
loadtest/
├── loadtest.go                          # Main CLI entry point (426 lines)
├── go.mod, go.sum                       # Go dependencies
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
├── cluster_read_config.yaml             # Prometheus queries (~200 entries)
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
├── .github/workflows/                   # GitHub Actions workflows
│   └── loadtest.yaml
│
└── internal/                            # Internal implementation details (e2e-tests dependency)
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
    "token": "sha256~...",
    "apiurl": "https://api.cluster.example.com:6443"
  }
]
```

### Error Pattern Configuration

`ci-scripts/config/errors.yaml` defines regex patterns for error categorization:

```yaml
patterns:
  - code: 1001
    pattern: "TaskRunImagePullFailed"
    category: "Build Failure"
  - code: 1002
    pattern: "PipelineRunTimeout"
    category: "Timeout"
```

## Development Guide

### Building

```bash
go build -o loadtest loadtest.go
```

### Running Unit Tests

```bash
go test ./... -v
```

### Adding New Metrics

1. **Add measurement in journey handler** (`pkg/journey/handle_*.go`):
   ```go
   _, err = logging.Measure(ctx, myNewFunction, args...)
   ```

2. **Add metric to evaluation** (`evaluate.py:24-47`):
   ```python
   METRICS = [
       ...,
       "myNewMetricName",
   ]
   ```

3. **Update Horreum schema** (`ci-scripts/config/horreum-schema.json`) if needed

### Debugging

**Enable verbose logging:**
```bash
./loadtest --log-debug ...
```

**Enable trace logging (everything):**
```bash
./loadtest --log-trace ...
```

**Inspect CSV output:**
```bash
column -t -s, load-test-timings.csv | less -S
```

**Test without waiting for pipelines:**
```bash
# Creates resources but doesn't wait, useful for quick testing
./loadtest --component-repo "..." --log-debug
```

## Related Projects

- **e2e-tests Framework**: Konflux end-to-end testing framework (dependency) - `github.com/konflux-ci/e2e-tests`
- **Konflux Platform**: https://github.com/konflux-ci
- **Tekton Pipelines**: https://tekton.dev/
- **Horreum**: Performance benchmarking and analysis - https://horreum.hyperfoil.io/

---

**Maintained by:** Konflux Performance & Scale Team  
**Contact:** jhutar@redhat.com for probe test issues and errors
