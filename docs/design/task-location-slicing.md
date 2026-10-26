# Task location slicing (KONFLUX-12507)

## Data contract

`evaluate.py` reads the collected TaskRun and Pod manifests after artifact
collection. It writes a `task_locations` object into `load-test-timings.json`,
which becomes `results.measurements.task_locations` in `load-test.json`.
Each key is a TaskRun name. Each value contains the PipelineRun name, Tekton
task and pipeline type, target platform, Pod name, Kubernetes node name, VM IP,
duration in seconds, and success status. `errors.py` also writes
`results.errors.task_errors`, keyed by TaskRun name with a list of distinct
classified reasons for each failed task.

The node comes from the matching Pod's `spec.nodeName`. The VM IP comes first
from the TaskRun's `build.appstudio.redhat.com/cloud-address` annotation when
it contains a valid IP. Otherwise it is accepted only when that Pod's build
log has exactly one distinct IP in an SSH known-hosts message. An ambiguous
log does not assign a VM. TaskRun duration is measured from creation to
completion, matching the existing duration collector. Horreum labels
`__results_measurements_task_locations` and `__results_errors_task_errors`
expose both maps.

## Investigation CLI integration

The investigation CLI fetches the two maps, joins by TaskRun name, and uses
the selected `node` or `vm` value as the group key. Performance comparison
uses each successful TaskRun duration. Error comparison counts each distinct
classified reason once per failed TaskRun and uses the number of collected
TaskRuns in the group as its denominator. PipelineRun-wide errors are not
assigned to every node or VM in the pipeline.

Missing node or VM values appear in an `unknown` group. Older Horreum runs
without these labels are omitted from node and VM comparisons, while remaining
queryable for cluster and job comparisons.

## Deployment and validation

Import `ci-scripts/config/horreum-schema.json` into Horreum schema 169 after
the producing code is deployed. On a fresh probe run, inspect
both new labels and verify that a TaskRun joins to its Pod's node and, for a
MultiArch build, the VM address in its annotation or build log. Then verify
error and performance comparison tables against that same run.
