#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

source "$( dirname $0 )/../utils.sh"

echo "[$(date --utc -Ins)] Collecting load test results"

# Setup directories
ARTIFACT_DIR=${ARTIFACT_DIR:-artifacts}
SOURCE_DIR=${SOURCE_DIR:-.}
mkdir -p ${ARTIFACT_DIR}
pushd "${2:-./tests/load-tests}"

# Construct $PROMETHEUS_HOST by extracting BASE_URL from $MEMBER_CLUSTER
BASE_URL=$(echo $MEMBER_CLUSTER | grep -oP 'https://api\.\K[^:]+')
PROMETHEUS_HOST="thanos-querier-openshift-monitoring.apps.$BASE_URL"
TOKEN=${OCP_PROMETHEUS_TOKEN}

{

echo "[$(date --utc -Ins)] Collecting artifacts"
find $SOURCE_DIR -maxdepth 1 -type f -name '*.log' -exec cp -vf {} "${ARTIFACT_DIR}" \;
find $SOURCE_DIR -maxdepth 1 -type f -name '*.csv' -exec cp -vf {} "${ARTIFACT_DIR}" \;
find $SOURCE_DIR -maxdepth 1 -type f -name 'load-test-options.json' -exec cp -vf {} "${ARTIFACT_DIR}" \;
find $SOURCE_DIR -maxdepth 1 -type d -name 'collected-data' -exec cp -r {} "${ARTIFACT_DIR}" \;
time_started="$( cat $SOURCE_DIR/started )"
time_ended="$( cat $SOURCE_DIR/ended )"

echo "[$(date --utc -Ins)] Create summary JSON with timings"
./evaluate.py "${ARTIFACT_DIR}/load-test-options.json" "${ARTIFACT_DIR}/load-test-timings.csv" "${ARTIFACT_DIR}/load-test-timings.json"

echo "[$(date --utc -Ins)] Create summary JSON with errors"
./errors.py "${ARTIFACT_DIR}/load-test-errors.csv" "${ARTIFACT_DIR}/load-test-timings.json" "${ARTIFACT_DIR}/load-test-errors.json" "${ARTIFACT_DIR}/collected-data/" || true

echo "[$(date --utc -Ins)] Graphing PRs and TRs"
ci-scripts/utility_scripts/show-pipelineruns.py --data-dir "${ARTIFACT_DIR}" &>"${ARTIFACT_DIR}/show-pipelineruns.log" || true
mv "${ARTIFACT_DIR}/output.svg" "${ARTIFACT_DIR}/show-pipelines.svg" || true

echo "[$(date --utc -Ins)] Computing duration of PRs, TRs and steps"
ci-scripts/utility_scripts/get-taskruns-durations.py --debug --data-dir "${ARTIFACT_DIR}" --dump-json "${ARTIFACT_DIR}/get-taskruns-durations.json" &>"${ARTIFACT_DIR}/get-taskruns-durations.log"

echo "[$(date --utc -Ins)] Parsing POD, task and step names from collected-taskrun JSON"
CD="${ARTIFACT_DIR}/collected-data"
if [[ -d "$CD" ]]; then
  find "$CD" -name 'collected-taskrun-*.json' -exec jq -r '
    .metadata.namespace as $ns | .status.podName as $pod | .metadata.name as $task |
    (.status.steps // [])[]? | [$ns, $pod, $task, .name] | @tsv
  ' {} \; 2>/dev/null | sort -u -t$'\t' | jq -R -s '
    split("\n") | map(select(length>0) | split("\t")) |
    group_by(.[0] + "\t" + .[1]) |
    map({"namespace": .[0][0], "pod_id": .[0][1], "task_name": .[0][2], "steps": map(.[3])}) |
    sort_by(.namespace + .pod_id) |
    {pods: .}
  ' > "${ARTIFACT_DIR}/get-pod-step-names.json" 2>/dev/null || true
fi
if [[ ! -s "${ARTIFACT_DIR}/get-pod-step-names.json" ]]; then
  echo '{"pods":[]}' > "${ARTIFACT_DIR}/get-pod-step-names.json"
fi

echo "[$(date --utc -Ins)] Appending dynamic monitor_task_step entries and saving as cluster_read_config.yaml_modified"
if [[ -s "${ARTIFACT_DIR}/get-pod-step-names.json" ]] && jq -e '.pods | length > 0' "${ARTIFACT_DIR}/get-pod-step-names.json" >/dev/null 2>&1; then
    python3 ci-scripts/utility_scripts/append-pod-step-monitoring.py \
        --pod-step-json "${ARTIFACT_DIR}/get-pod-step-names.json" \
        --output "${ARTIFACT_DIR}/cluster_read_config.yaml_modified" || true
else
    cp -f ci-scripts/stage/cluster_read_config.yaml "${ARTIFACT_DIR}/cluster_read_config.yaml_modified"
fi

echo "[$(date --utc -Ins)] Creating main status data file"
STATUS_DATA_FILE="${ARTIFACT_DIR}/load-test.json"
status_data.py \
    --status-data-file "${STATUS_DATA_FILE}" \
    --set "name=Konflux loadtest" "started=$time_started" "ended=$time_ended" \
    --set-subtree-json "parameters.options=${ARTIFACT_DIR}/load-test-options.json" "results.measurements=${ARTIFACT_DIR}/load-test-timings.json" "results.errors=${ARTIFACT_DIR}/load-test-errors.json" "results.durations=${ARTIFACT_DIR}/get-taskruns-durations.json"

echo "[$(date --utc -Ins)] Adding monitoring data"
mstarted="$( date -d "$time_started" --utc -Iseconds )"
mended="$( date -d "$time_ended" --utc -Iseconds )"
mhost="https://$PROMETHEUS_HOST"
mrawdir="${ARTIFACT_DIR}/monitoring-raw-data-dir/"
mkdir -p "$mrawdir"
status_data.py \
    --status-data-file "${STATUS_DATA_FILE}" \
    --additional "${ARTIFACT_DIR}/cluster_read_config.yaml_modified" \
    --monitoring-start "$mstarted" \
    --monitoring-end "$mended" \
    --prometheus-host "$mhost" \
    --prometheus-port 443 \
    --prometheus-token "$TOKEN" \
    --monitoring-raw-data-dir "$mrawdir" \
    &>"${ARTIFACT_DIR}/monitoring-collection.log"

} 2>&1 | tee "${ARTIFACT_DIR}/collect-results.log"

popd
