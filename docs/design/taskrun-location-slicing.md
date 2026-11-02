# TaskRun location slicing (KONFLUX-12507)

## Data contract

`evaluate.py` reads the collected TaskRun and Pod manifests after artifact
collection. It writes a `taskrun_locations` object into `load-test-timings.json`,
which becomes `results.measurements.taskrun_locations` in `load-test.json`.
Each key is a TaskRun name. Each value contains the collected namespace,
PipelineRun name, Tekton Task name (`task`), pipeline type, target platform,
Pod name, Kubernetes node name, VM IP, duration in seconds, and success status.
`errors.py` also writes `results.errors.taskrun_errors`, keyed by TaskRun name
with a list of distinct classified reasons for each failed TaskRun.

The node comes from the matching Pod's `spec.nodeName`. The VM IP comes first
from the TaskRun's `build.appstudio.redhat.com/cloud-address` annotation when
it contains a valid IP. Otherwise it is accepted only when that Pod's build
log has exactly one distinct IP in an SSH known-hosts message. An ambiguous
log does not assign a VM. TaskRun duration is measured from creation to
completion, matching the existing duration collector. Platform values are
normalized to `linux/<arch>` (for example `linux-arm64` becomes `linux/arm64`)
so a single run does not split one architecture across two groups.

Labels `__results_measurements_taskrun_locations` and
`__results_errors_taskrun_errors` are defined in
`ci-scripts/config/horreum-schema.json` and computed by `compute-labels.py`
from https://github.com/Appservices-perfscale/horreum-data-mirror, then stored
in Postgres by `ci-scripts/utility_scripts/s3-to-postgresql.sh`
(`load-test-labels.json`).

## Example payload (MultiArch probe)

From
`StoneSoupLoadTestProbe_stone_prd_rh01_MultiArch/run-stone-prd-rh01-2026_11_02T14_01_02_608000000_00_00`:

- 35 TaskRuns across 2 namespaces; `taskrun_locations` ~12 KB
- 19 distinct nodes; VMs resolved for the four MultiArch build Tasks from
  `Permanently added '<ip>'` in the build-step logs
- clean probe: `taskrun_errors == {}`

Example entry shape:

```json
{
  "namespace": "konflux-perfscale-2-tenant",
  "pipelinerun": "psprdrh01cm-app-0-comp-0-on-push-dr8vv",
  "task": "ecosystem-cert-preflight-checks",
  "pipeline_type": "build",
  "platform": "linux/s390x",
  "pod": "psprdrh01cm-app-0-comp-0-onb887945d8c4294868a94ca2097518fe1-pod",
  "node": "ip-10-206-27-121.ec2.internal",
  "vm": null,
  "duration": 22.0,
  "succeeded": true
}
```

## Investigation CLI integration

The investigation CLI fetches the two maps, joins by TaskRun name, and uses
the selected `node` or `vm` value as the group key. Performance comparison
uses each successful TaskRun duration. Error comparison counts each distinct
classified reason once per failed TaskRun and uses the number of collected
TaskRuns in the group as its denominator. PipelineRun-wide errors are not
assigned to every node or VM in the pipeline.

Missing node or VM values appear in an `unknown` group. Older runs without
these labels are omitted from node and VM comparisons, while remaining
queryable for cluster and job comparisons.

## Deployment and validation

Deploy the producing code, then ensure `ci-scripts/config/horreum-schema.json`
includes the two labels above. On a fresh probe run, confirm
`compute-labels.py` / `s3-to-postgresql.sh` populate both object labels and
that a TaskRun joins to its Pod's node and, for a MultiArch build, the VM
address in its annotation or build log. Then verify error and performance
comparison tables against that same run.
