Various configurations needed for our tests
===========================================

Horreum schema
--------------

Defines labels we are interested in.

Link to the schema in Horreum: https://horreum.corp.redhat.com/schema/169

To import modified versions, follow this guide: https://horreum.hyperfoil.io/docs/tasks/import-export/#import-or-export-using-the-api

To list existing label names:

    jq -r '.labels[] | [.name, .extractors[0].jsonpath] | @tsv' ci-scripts/config/horreum-schema.json | column --separator "	" --table

To sort ``labels`` alphabetically by ``name`` (deterministic order; no semantic change — only reordering):

    jq '.labels |= sort_by(.name)' ci-scripts/config/horreum-schema.json > tmp-$$.json && mv tmp-$$.json ci-scripts/config/horreum-schema.json

To delete a label by name:

    jq 'del(.labels[] | select(.name == "LABEL_NAME"))' ci-scripts/config/horreum-schema.json > tmp-$$.json && mv tmp-$$.json ci-scripts/config/horreum-schema.json

To add a label:

    jq '.labels += [{"access": "PUBLIC", "owner": "hybrid-cloud-experience-perfscale-team", "name": "LABEL_NAME", "extractors": [{"name": "LABEL_NAME", "jsonpath": "JSONPATH", "isarray": false}], "filtering": false, "metrics": true, "schemaId": 169}]' ci-scripts/config/horreum-schema.json > tmp-$$.json && mv tmp-$$.json ci-scripts/config/horreum-schema.json

After changing the schema, re-import it in Horreum (see import guide above).

Local verification
------------------

- Validate schema and test JSON: ``jq empty ci-scripts/config/horreum-schema.json ci-scripts/config/horreum-test-ci.json ci-scripts/config/horreum-test-probes.json``
- List task/step labels: ``jq -r '.labels[] | select(.extractors[0].jsonpath | test("measurements\\.(steps|taskruns)")) | [.name, .extractors[0].jsonpath] | @tsv' ci-scripts/config/horreum-schema.json``
- Check a path in load-test.json: ``jq '.measurements.steps."build/buildah-oci-ta/build".memory.mean' load-test.json``
