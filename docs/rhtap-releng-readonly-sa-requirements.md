# RBAC requirements: read-only SA for `rhtap-releng-tenant`

Ask for releng, to support loadtest's read-only managed-namespace mode
(`--release-managed-readonly`). See [CONTEXT.md](../CONTEXT.md) for the
namespace terminology used below.

## What's needed

A ServiceAccount in `rhtap-releng-tenant`, with a Role/RoleBinding granting
only the following — no `create`/`update`/`patch`/`delete` on anything:

| Resource | Verbs | Why |
|---|---|---|
| `releaseplanadmissions.appstudio.redhat.com` | `get`, `list`, `watch` | Validate the pre-existing RPA is present and matched (`validateReleasePlanAdmission`), and collect its JSON (`collectReleasePlanAdmissionJSON`) |
| `pipelineruns.tekton.dev` | `get`, `list`, `watch` | Wait for the release PipelineRun to appear and finish (`validateReleasePipelineRunCreation`, `validateReleasePipelineRunCondition`), collect its JSON |
| `taskruns.tekton.dev` | `get`, `list`, `watch` | Collect TaskRun JSONs for the release PipelineRun's child references |
| `pods` | `get`, `list`, `watch` | List pods by `appstudio.openshift.io/application` label (`ListPods`), fetch Pod JSON |
| `pods/log` | `get` | Fetch container logs from those pods (`GetPodLogs`) |

## Not needed

- `releases.appstudio.redhat.com` and `snapshots.appstudio.redhat.com` — these
  stay in the tenant namespace and are read via the tenant Framework, not the
  managed one.
- Anything in `rhtap-releng-tenant` beyond the five resource types above.
- Any write verb, anywhere.

## Static RPA

Alongside the SA/Role/RoleBinding, releng creates the RPA itself once:

- `spec.applications`: `["{runPrefix}-app-0"]` (deterministic name, index
  always `0` since this mode requires `--concurrency 1`)
- `spec.data.mapping.components`: `[{"name": "{runPrefix}-app-0-comp-0"}, ...]`
  — one entry per component, matching `--components-count`
- `spec.origin`: the specific tenant namespace loadtest will run against
  (required for the release controller to match the ReleasePlan loadtest
  creates in that tenant namespace to this RPA)

`{runPrefix}` is loadtest's `--runprefix` value, agreed with releng ahead of
the run.

## Scaling beyond one tenant namespace

`--release-managed-readonly` currently rejects `--concurrency > 1`. A single
RPA has a single `spec.origin`, so one RPA only matches one tenant namespace.
Supporting more concurrency means asking releng for one RPA (with a distinct
`spec.origin`) per tenant namespace, plus a way for loadtest to know which
RPA name goes with which tenant namespace — not yet designed.
