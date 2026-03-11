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

Task/step memory and CPU labels (stable keys)
---------------------------------------------

Per-task, per-step memory and CPU are stored under root ``measurements`` with
run-specific keys ``tasks[<taskname>]`` (e.g. ``tasks[ocpp01cs-app-xaean-...-build-container]``).
Task names change every run, so Horreum cannot use a fixed JSONPath on those keys.

To fix this, the collect-results probe runs ``get-task-step-resources.py``, which
injects ``measurements.stable_task_steps``: a stable view that maps logical task
types (e.g. ``build-container``, ``collect-data``) and step names to the same
metric dicts. Task type is derived from the run-specific task name by suffix
(e.g. ``*-build-container`` → ``build-container``). Horreum labels use paths like
``$.measurements.stable_task_steps["build-container"]["build"].memory.mean`` so
the same path works every run. Add more labels with
``$.measurements.stable_task_steps["<task-type>"]["<step-name>"].memory.mean`` or
``.cpu.mean``. After changing the schema, re-import it in Horreum.

Local verification
------------------

You can validate config and jsonpaths locally (full Horreum extraction still
requires uploading a run from Jenkins or re-importing the schema in Horreum):

- Validate schema and test JSON are valid: ``jq empty horreum-schema.json horreum-test-ci.json``
- List stable task/step labels: ``jq -r '.labels[] | select(.name | startswith(".measurements.stable_task_steps")) | [.name, .extractors[0].jsonpath] | @tsv' horreum-schema.json``
- After running get-task-step-resources.py on a run artifact dir, check stable path
  extracts: ``jq '.measurements.stable_task_steps["build-container"]["build"].memory.mean' load-test.json``
