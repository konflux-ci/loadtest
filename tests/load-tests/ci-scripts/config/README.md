Various configurations needed for our tests
===========================================

Horreum schema
--------------

Defines labels we are interested in.

Link to the schema in Horreum: https://horreum.corp.redhat.com/schema/169

To import modified versions, follow this guide: https://horreum.hyperfoil.io/docs/tasks/import-export/#import-or-export-using-the-api

To list existing label names:

    jq -r '.labels[] | [.name, .extractors[0].jsonpath] | @tsv' ci-scripts/config/horreum-schema.json | column --separator "	" --table

To delete a label by it's name:

    label_del="__results_durations_stats_taskruns__build_calculate_deps__passed_duration_mean"
    jq 'del(.labels[] | select(.name == "'"$label_del"'"))' ci-scripts/config/horreum-schema.json > tmp-$$.json && mv tmp-$$.json ci-scripts/config/horreum-schema.json

To add a label given it's JSONPath expression:

    jsonpath_add='$.results.durations.stats.taskruns."build/calculate-deps".passed.duration.mean'
    label_add="$( echo "$jsonpath_add" | sed 's/[^a-zA-Z0-9]/_/g' )"
    jq '.labels += [{"access": "PUBLIC", "owner": "hybrid-cloud-experience-perfscale-team", "name": "'"$label_add"'", "extractors": [{"name": "'"$label_add"'", "jsonpath": "'"$( echo "$jsonpath_add" | sed 's/"/\\\"/g' )"'", "isarray": false}], "_function": "", "filtering": false, "metrics": true, "schemaId": 169}]' ci-scripts/config/horreum-schema.json > tmp-$$.json && mv tmp-$$.json ci-scripts/config/horreum-schema.json

Task/step memory and CPU labels
-------------------------------

Per-step metrics are under ``measurements.steps`` with key ``"<task_name>/<step_name>"``
(e.g. ``$.measurements.steps."build/buildah-oci-ta/build".memory.mean``).
Per-task (whole task) metrics are under ``measurements.taskruns`` with key ``"<task_name>"``
(e.g. ``$.measurements.taskruns."build/buildah-oci-ta".memory.mean`` or ``$.measurements.taskruns."test/test-output".cpu.mean``).
``task_name`` in get-pod-step-names.json is ``<pipeline-type>/<pipelineTask>`` (e.g. ``build/build-container``),
using ``tekton.dev/pipelineTask`` so keys are stable across runs.

Label name = JSONPath with every non-alphanumeric character replaced by ``_``
(consecutive replacements become multiple underscores, e.g.
``__measurements_steps__build_buildah_oci_ta_build__memory_mean``).

To regenerate labels (no extra scripts needed), use only the **latest run** per probe
(one ``get-pod-step-names.json`` per ``ARTIFACTS/StoneSoupLoadTestProbe_*/``). Then:

**1. Collect path fragments** from each latest run's ``get-pod-step-names.json`` (four metric types).
   Run these four jq expressions on each file; concatenate and sort -u:

   - Step memory mean: ``jq -r '.pods[]? | .task_name as $task | .steps[]? | ".measurements.steps.\"" + $task + "/" + . + "\".memory.mean"' FILE``
   - Step CPU mean: ``jq -r '.pods[]? | .task_name as $task | .steps[]? | ".measurements.steps.\"" + $task + "/" + . + "\".cpu.mean"' FILE``
   - Task memory mean: ``jq -r '.pods[]? | .task_name | select(length > 0) | ".measurements.taskruns.\"" + . + "\".memory.mean"' FILE``
   - Task CPU mean: ``jq -r '.pods[]? | .task_name | select(length > 0) | ".measurements.taskruns.\"" + . + "\".cpu.mean"' FILE``

**2. Filter** out lines with an empty key or a key containing ``//`` (invalid, e.g. old ``"managed/"`` bug).

**3. For each remaining path fragment** ``P``: full JSONPath = ``$`` + ``P``; label_name = ``echo "$jsonpath" | sed 's/[^a-zA-Z0-9]/_/g'``.

**4. Update the schema:** delete the four old ``stable_task_steps`` labels (see "To delete a label" above; names contain ``stable_task_steps``). Then for each (jsonpath, label_name), use the "To add a label" recipe above (set ``jsonpath_add`` and ``label_add``, run the jq ``.labels += [...]``).

Example to collect unique path fragments (latest run per probe only):

```bash
ARTIFACTS_DIR=/path/to/jenkins_artifacts/ARTIFACTS
for d in "$ARTIFACTS_DIR"/StoneSoupLoadTestProbe_*/; do
  f="$(ls -1d "$d"/run-* 2>/dev/null | sort -r | head -1)/get-pod-step-names.json"
  [ -f "$f" ] || continue
  jq -r '.pods[]? | .task_name as $t | .steps[]? | ".measurements.steps.\"" + $t + "/" + . + "\".memory.mean"' "$f"
  jq -r '.pods[]? | .task_name as $t | .steps[]? | ".measurements.steps.\"" + $t + "/" + . + "\".cpu.mean"' "$f"
  jq -r '.pods[]? | .task_name | select(length>0) | ".measurements.taskruns.\"" + . + "\".memory.mean"' "$f"
  jq -r '.pods[]? | .task_name | select(length>0) | ".measurements.taskruns.\"" + . + "\".cpu.mean"' "$f"
done | sort -u | grep -v '\.measurements\.\(steps\|taskruns\)\.""' | grep -v '//'
```

Then for each line (path fragment ``P``), set ``jsonpath_add='$'+P`` and ``label_add="$(echo "$jsonpath_add" | sed 's/[^a-zA-Z0-9]/_/g')"`` and run the add-label jq from above (once per label).

After changing the schema, re-import it in Horreum (see import guide above).

Local verification
------------------

- Validate schema and test JSON: ``jq empty horreum-schema.json horreum-test-ci.json``
- List task/step labels: ``jq -r '.labels[] | select(.extractors[0].jsonpath | test("measurements\\.(steps|taskruns)")) | [.name, .extractors[0].jsonpath] | @tsv' horreum-schema.json``
- Check a path in load-test.json: ``jq '.measurements.steps."build/buildah-oci-ta/build".memory.mean' load-test.json``
