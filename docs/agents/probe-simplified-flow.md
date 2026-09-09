# KONFLUX-15732 — Simplified probe (`probetest`): prerequisites, flow, and eliminated steps

The POC reuses the existing loadtest journey/collection code, but strips the rare/one-off
onboarding and setup steps so the test is short and stable while still exercising Konflux core
components (build → snapshot → integration test → release). It adopts a fixed, pre-onboarded
Application + Component (plus the matching IntegrationTestScenario, ReleasePlan, and
ReleasePlanAdmission) as permanent fixtures and never creates or deletes them.

## Prerequisites (all set up once, out-of-band)

The probe requires all of the following to already exist and be in a healthy state before it runs.
They can be provisioned with a single full `loadtest` run or manually with `oc`.

| Scope | Entity | Namespace | Required state |
|---|---|---|---|
| Tenant | Application (`myapp`) | `konflux-perfscale-3-tenant` | CR exists; `spec.appModelRepository.url` / `gitOpsRepository.url` may be empty |
| Tenant | Component (`mycomp`) | `konflux-perfscale-3-tenant` | PaC enabled; `.tekton/` pipeline files present in the repo; `spec.source.git.url` + `.revision` set |
| Tenant | ImageRepository (`mycomp`) | `konflux-perfscale-3-tenant` | `spec.image.visibility: public`; `status.state: ready` (private → EC `builtin.image.accessible` fails) |
| Tenant | IntegrationTestScenario (`myits`) | `konflux-perfscale-3-tenant` | CR exists; only needed when the integration-test stage is awaited |
| Tenant | ReleasePlan (`myrp`) | `konflux-perfscale-3-tenant` | `spec.target: managed-konflux-perfscale-tenant`; `Matched: True` |
| Managed | ReleasePlanAdmission (`myrpa`) | `managed-konflux-perfscale-tenant` | `spec.applications: [myapp]`; `spec.origin: <tenant namespace>`; `Matched: True` |
| Managed | Release service account + token | `managed-konflux-perfscale-tenant` | SA token passed via `--release-managed-token`; access to release PLR |
| Tenant | EC policy (`tmp-onboard-policy`) | referenced by RPA | Component must be **EC-clean**: source image exists, image accessible, and no failed `deprecated-image-check` |
| CI | Run config vars | — | `StoneSoupLoadTestProbe_stone_stg_rh01_TEST.groovy` vars + `ci-scripts/run-simple/run.sh` |

> Discovered during the POC: the adopted component must be EC-clean under the referenced policy.
> The sample repo was made EC-clean by enabling the source image build (`build-source-image: true`,
> fixes `source_image.exists`) and switching the base image from the deprecated `ubi8/nodejs-18` to
> `ubi9/nodejs-22` (fixes `test.no_failed_tests` from `deprecated-image-check`).

## Simplified end-to-end flow

1. **Provision tenant Framework** from the `--stage` user token.
2. **`HandleExistingApplication`** — validate `myapp`; set the ITS name only if that stage is awaited.
3. **`HandleExistingComponent`** — validate `mycomp`; derive the build-trigger repo + revision from
   `Component.spec.source.git` (no `--component-repo` flag needed).
4. **`TriggerComponentBuild`** — `doHarmlessCommit` pushes a trivial change to the component repo, so
   PaC triggers a fresh build PipelineRun.
5. **`HandlePipelineRun`** — wait for the build PLR. In-pipeline checks run here
   (`deprecated-image-check`, clair, sast).
6. **`HandleTest`** — wait for the integration-test PLR; the built image must pass **EC/conforma**
   to be promoted into the Snapshot.
7. **`HandleNewManagedFrameworkForComp`** — provision the managed Framework for the release namespace.
8. **`HandleReleaseRun`** — monitor the **release PLR in the managed namespace**.
9. **Collection** — `HandlePerComponent` / `HandlePerApplication` / `HandlePerUserCollection` gather
   PipelineRun / TaskRun / Pod JSONs and container logs, plus App / Component / IR / Snapshot /
   Release / RP / RPA and Kubernetes Events.

**Created by the probe:** none of the fixtures. Only transient objects produced by the cycle — the
build, integration-test, and release PipelineRuns/TaskRuns/Pods, the Snapshot, the Release, and the
harmless commit/PR in the component repo.

**Pipelines triggered:** build PLR (tenant NS, via PaC), integration-test PLR (tenant NS), release PLR
(managed NS).

## Eliminated steps & rationale

| Step (full `loadtest`) | Rationale for elimination |
|---|---|
| User/account provisioning (`users.json`, usersignup) | Probe runs under a fixed stage token; no per-run user creation. |
| Repo forking (`--fork-target`) | Tests GitHub/GitLab infra, not Konflux core. Probe builds on the component's own repo. |
| Application creation (`HandleApplication`) | One-off onboarding; app is adopted. |
| IntegrationTestScenario creation (`HandleIntegrationTestScenario`) | Setup fixture; adopted. Probe fails fast if the ITS name is missing when the stage is awaited. |
| Component creation (`createComponent`) | One-off onboarding; component adopted. |
| ImageRepository creation (`HandleImageRepository`) | Tied to onboarding; adopted. Needs public visibility. |
| PaC onboarding PR creation + merge (`getPaCPullNumber`) + IR/PR timing check | One-off onboarding artifacts; unnecessary once onboarded. |
| Pipeline image-pull-secret config | Build service account already configured during onboarding. |
| Repo templating / multi-arch (`--pipeline-repo-templating`) | Single-arch build is the minimal happy path; multi-arch is rare. |
| Per-run task-bundle pinning | Reuses the component's existing PaC pipeline config instead of injecting changing bundle refs. |
| ReleasePlan/Admission creation (`HandleReleaseSetup`) | RP/RPA are fixtures; adopted. Avoids churn and guarantees stable RP↔RPA matching. |
| Purge (`HandlePurge`) | Fixtures are permanent — nothing to clean up; the probe never deletes them. |
| Journey loop (`--journey-repeats`/`--journey-duration`, concurrency fan-out) | Single pass/fail shot, not a scale soak. |

## Reuse vs. adaptation

- **Reused as-is:** `HandlePipelineRun`, `HandleTest`, `HandleReleaseRun`,
  `HandleNewManagedFrameworkForComp`, and all `Handle*Collection` handlers, plus the shared
  `types` / `options` / `logging` packages.
- **New / adapted:** `pkg/journey/handle_existing.go` (adopters `HandleExistingApplication`,
  `HandleExistingComponent`, `TriggerComponentBuild`), `options.ProcessOptionsForProbe`,
  `probetest.go` wiring, and `ci-scripts/run-simple/run.sh` + the
  `StoneSoupLoadTestProbe_stone_stg_rh01_TEST.groovy` config vars.
