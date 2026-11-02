Various configurations needed for our tests
===========================================

Horreum schema
--------------

Defines labels we are interested in. The file is still named for the former
Horreum schema 169; labels are now computed offline (see below), not imported
into a Horreum UI.

To list existing label names:

    jq -r '.labels[] | [.name, .extractors[0].jsonpath] | @tsv' ci-scripts/config/horreum-schema.json | column --separator "	" --table

To sort ``labels`` alphabetically by ``name`` (deterministic order; no semantic change — only reordering):

    jq '.labels |= sort_by(.name)' ci-scripts/config/horreum-schema.json > tmp-$$.json && mv tmp-$$.json ci-scripts/config/horreum-schema.json

To delete a label by name:

    jq 'del(.labels[] | select(.name == "LABEL_NAME"))' ci-scripts/config/horreum-schema.json > tmp-$$.json && mv tmp-$$.json ci-scripts/config/horreum-schema.json

To add a label:

    jq '.labels += [{"access": "PUBLIC", "owner": "hybrid-cloud-experience-perfscale-team", "name": "LABEL_NAME", "extractors": [{"name": "LABEL_NAME", "jsonpath": "JSONPATH", "isarray": false}], "filtering": false, "metrics": true, "schemaId": 169}]' ci-scripts/config/horreum-schema.json > tmp-$$.json && mv tmp-$$.json ci-scripts/config/horreum-schema.json

After changing the schema, labels are recomputed by ``compute-labels.py`` from
https://github.com/Appservices-perfscale/horreum-data-mirror against this file
and stored in Postgres by ``ci-scripts/utility_scripts/s3-to-postgresql.sh``
(writes ``load-test-labels.json``). No Horreum UI import is required.

The ``__results_measurements_taskrun_locations`` label extracts
``$.results.measurements.taskrun_locations``, an object keyed by TaskRun name::

    "<taskrun>": {"pipelinerun": ..., "task": ..., "pipeline_type": ...,
                  "platform": ..., "pod": ..., "node": ..., "vm": ...,
                  "duration": <seconds>, "succeeded": <bool>}

``node`` and ``vm`` are null when unknown. ``task`` is the Tekton Task name,
not the TaskRun name. The value is a JSON object (not an array), so SQL against
``label_values`` should treat it as JSONB.

The ``__results_errors_taskrun_errors`` label extracts
``$.results.errors.taskrun_errors``, an object mapping failed TaskRun name to a
list of classified reasons. Runs collected before this change have neither
field.

Local verification
------------------

- Validate schema and test JSON: ``jq empty ci-scripts/config/horreum-schema.json ci-scripts/config/horreum-test-ci.json ci-scripts/config/horreum-test-probes.json``
- List task/step labels: ``jq -r '.labels[] | select(.extractors[0].jsonpath | test("measurements\\.(steps|taskruns)")) | [.name, .extractors[0].jsonpath] | @tsv' ci-scripts/config/horreum-schema.json``
- Check a path in load-test.json: ``jq '.measurements.steps."build/buildah-oci-ta/build".memory.mean' load-test.json``
