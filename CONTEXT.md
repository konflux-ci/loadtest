# CONTEXT.md

## Domain glossary

- **Tenant namespace** -- the namespace where the user's Application, Component, IntegrationTestScenario, ReleasePlan, Snapshot, and Release CRs live. Assigned to each user thread from `stageUsers[UserIndex].Namespace` (which already ends in `-tenant`). Example: `konflux-perfscale-3-tenant`.

- **Managed namespace** -- a separate namespace where the ReleasePlanAdmission CR and release pipeline PipelineRuns/TaskRuns/Pods execute. Controlled by `--release-managed-namespace`. Two operational modes exist:
  - **Read-write mode** (current default): loadtest creates and deletes the RPA here each run. SA token needs full CRUD. Example namespace: `managed-konflux-perfscale-tenant`.
  - **Read-only mode** (planned, `--release-managed-readonly`): a pre-existing RPA created by releng is reused. SA token needs only read access. Example namespace: `rhtap-releng-tenant`.

- **Origin namespace** -- the value of `spec.origin` on a ReleasePlanAdmission CR. Must match the tenant namespace of the ReleasePlan for the release controller to match RP to RPA. Set via the `originNamespace` parameter to `createReleasePlanAdmission()`, which passes `ctx.ParentContext.Namespace` (the tenant namespace). In read-only mode, releng must set this when creating the static RPA.

- **Framework** -- a `github.com/konflux-ci/e2e-tests/pkg/framework.Framework` instance. Each thread (user, application, component) provisions its own via `provisionFramework()`. Carries API client and RBAC identity scoped to the tenant namespace.

- **ManagedFramework** -- a Framework instance authenticated with `--release-managed-token`, used for operations in the managed namespace. Separate from the tenant Framework. Both `PerApplicationContext` and `PerComponentContext` carry their own instance, provisioned in `HandleNewManagedFrameworkForApp()` and `HandleNewManagedFrameworkForComp()`.

- **Journey** -- one full cycle: create Application, create Component, build (PipelineRun), test (IntegrationTestScenario pipeline), release, collect artifacts. Controlled by `--journey-repeats` (count) and `--journey-duration` (timeout); whichever limit is reached first stops the loop.

- **Purge** -- cleanup phase: delete Application, Component, ReleasePlan, and (in read-write mode) ReleasePlanAdmission. Runs after all journeys complete. Controlled by `--purge` (enable) and `--purge-only` (skip journeys, just clean up; implies `--purge`).

- **ReleasePlan (RP)** -- CR in tenant namespace, created by loadtest via `createReleasePlan()`, targeting the managed namespace (or the tenant namespace itself when no managed namespace is configured). Name pattern: `{appName}-rp`.

- **ReleasePlanAdmission (RPA)** -- CR in managed namespace (or tenant namespace when no managed namespace is configured). In read-write mode, created and deleted by loadtest via `createReleasePlanAdmission()` (name pattern: `{appName}-rpa`). In read-only mode, pre-existing, created once by releng.

- **Collection** -- the artifact-gathering phase after a journey. Collects PipelineRun, TaskRun, and Pod JSONs plus container logs from the tenant namespace, and (when a managed namespace is configured) from the managed namespace as well. Also collects Application, Component, Snapshot, Release, ReleasePlan, and ReleasePlanAdmission JSONs, plus Kubernetes Events. Output lands under `{outputDir}/collected-data/{namespace}/{journeyIndex}/`.

- **StageUsers** -- a JSON array (`users.json`) of pre-created user credentials, each with `namespace`, `token`, and `apiurl` fields. Loaded at startup when `--stage` is set. Thread `N` uses `stageUsers[N]`.

- **Concurrency** -- the number of parallel user threads (`--concurrency`). Each user thread runs its own journey loop independently. Within each user, `--applications-count` and `--components-count` control further fan-out.

- **RunPrefix** -- identifier (`--runprefix`, default `testuser`) used as a prefix for Application names (`{runPrefix}-app-{index}`) and as a suffix when forking component repos.

- **Startup delay / jitter** -- per-thread stagger before beginning work. `--startup-delay` sets the base interval between thread launches; `--startup-jitter` adds random noise (plus or minus half the jitter value). First thread always starts immediately.
