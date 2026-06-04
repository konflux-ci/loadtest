#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# shellcheck disable=SC1090,SC1091
source "/usr/local/ci-secrets/redhat-appstudio-load-test/load-test-scenario.${1:-concurrent}"

echo "[$(date --utc -Ins)] Collecting load test results"

# Setup directories
ARTIFACT_DIR=${ARTIFACT_DIR:-artifacts}
mkdir -p "${ARTIFACT_DIR}"
pushd "${2:-./tests/load-tests}"

{

echo "[$(date --utc -Ins)] Collecting artifacts"
find . -maxdepth 1 -type f -name '*.log' -exec cp -vf {} "${ARTIFACT_DIR}" \;
find . -maxdepth 1 -type f -name '*.csv' -exec cp -vf {} "${ARTIFACT_DIR}" \;
find . -maxdepth 1 -type f -name 'load-test-options.json' -exec cp -vf {} "${ARTIFACT_DIR}" \;
find . -maxdepth 1 -type d -name 'collected-data' -exec cp -r {} "${ARTIFACT_DIR}" \;

echo "[$(date --utc -Ins)] Setting up Python venv"
{
python3 -m venv venv
set +u
# shellcheck source=/dev/null
source venv/bin/activate
set -u
python3 -m pip install -U pip
python3 -m pip install -e "git+https://github.com/redhat-performance/opl.git#egg=opl-rhcloud-perf-team-core&subdirectory=core"
python3 -m pip install tabulate
python3 -m pip install matplotlib
} &>"${ARTIFACT_DIR}/monitoring-setup.log"

echo "[$(date --utc -Ins)] Create summary JSON with timings"
ci-scripts/evaluate.py "${ARTIFACT_DIR}/load-test-options.json" "${ARTIFACT_DIR}/load-test-timings.csv" "${ARTIFACT_DIR}/load-test-timings.json"

echo "[$(date --utc -Ins)] Create summary JSON with errors"
ci-scripts/errors.py "${ARTIFACT_DIR}/load-test-errors.csv" "${ARTIFACT_DIR}/load-test-timings.json" "${ARTIFACT_DIR}/load-test-errors.json"

echo "[$(date --utc -Ins)] Graphing PRs and TRs"
ci-scripts/utility_scripts/show-pipelineruns.py --data-dir "${ARTIFACT_DIR}" &>"${ARTIFACT_DIR}/show-pipelineruns.log"
mv "${ARTIFACT_DIR}/output.svg" "${ARTIFACT_DIR}/show-pipelines.svg"

echo "[$(date --utc -Ins)] Computing duration of PRs, TRs and steps"
ci-scripts/utility_scripts/get-taskruns-durations.py --debug --data-dir "${ARTIFACT_DIR}" --dump-json "${ARTIFACT_DIR}/get-taskruns-durations.json" &>"${ARTIFACT_DIR}/get-taskruns-durations.log"

echo "[$(date --utc -Ins)] Creating main status data file"
STATUS_DATA_FILE="${ARTIFACT_DIR}/load-test.json"
status_data.py \
    --status-data-file "${STATUS_DATA_FILE}" \
    --set "name=Konflux loadtest" "started=$( cat started )" "ended=$( cat ended )" \
    --set-subtree-json "parameters.options=${ARTIFACT_DIR}/load-test-options.json" "results.measurements=${ARTIFACT_DIR}/load-test-timings.json"  "results.errors=${ARTIFACT_DIR}/load-test-errors.json" "results.durations=${ARTIFACT_DIR}/get-taskruns-durations.json"

echo "[$(date --utc -Ins)] Adding monitoring data"
mstarted="$( date -d "$( cat started )" --utc -Iseconds )"
mended="$( date -d "$( cat ended )" --utc -Iseconds )"
mhost="https://$(oc -n openshift-monitoring get route -l app.kubernetes.io/name=thanos-query -o json | jq --raw-output '.items[0].spec.host')"
mrawdir="${ARTIFACT_DIR}/monitoring-raw-data-dir/"
mkdir -p "$mrawdir"
status_data.py \
    --status-data-file "${STATUS_DATA_FILE}" \
    --additional cluster_read_config.yaml \
    --monitoring-start "$mstarted" \
    --monitoring-end "$mended" \
    --prometheus-host "$mhost" \
    --prometheus-port 443 \
    --prometheus-token "$( oc whoami -t )" \
    --monitoring-raw-data-dir "$mrawdir" \
    &>"${ARTIFACT_DIR}/monitoring-collection.log"

deactivate

echo "[$(date --utc -Ins)] Collecting additional info"
mkdir -p "${ARTIFACT_DIR}/collected-data"

## Application service log segments per user app
echo "[$(date --utc -Ins)] Collecting application service log"
application_service_log="${ARTIFACT_DIR}/application-service.log"
oc logs -l "control-plane=controller-manager" --tail=-1 -n application-service >"$application_service_log"

## Collect Tekton profiling data
if [ "${TEKTON_PERF_ENABLE_CPU_PROFILING:-}" == "true" ] || [ "${TEKTON_PERF_ENABLE_MEMORY_PROFILING:-}" == "true" ]; then
    echo "[$(date --utc -Ins)] Collecting profiling data from Tekton"
    find . -name "*.pprof" | while read -r pprof_profile; do
        file=$(basename "$pprof_profile")
        go tool pprof -text "$pprof_profile" >"${ARTIFACT_DIR}/$file.txt" || true
        go tool pprof -svg -output="${ARTIFACT_DIR}/$file.svg" "$pprof_profile" || true
    done
fi

} 2>&1 | tee "${ARTIFACT_DIR}/collect-results.log"

popd
