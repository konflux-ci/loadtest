#!/bin/bash

# Collects results from a load test run

# shellcheck disable=SC1091
source "$( dirname "$0" )/utils.sh"
# shellcheck disable=SC1091
source "$( dirname "$0" )/user-prefix.sh"

# ARTIFACT_DIR is where results will be stored
ARTIFACT_DIR=${ARTIFACT_DIR:-$(pwd)/artifacts}
mkdir -p "${ARTIFACT_DIR}"

echo "Collecting results to ${ARTIFACT_DIR}..."

# Move CSV files to artifact directory
mv load-test-timings.csv "${ARTIFACT_DIR}/" 2>/dev/null
mv load-test-errors.csv "${ARTIFACT_DIR}/" 2>/dev/null
mv load-test-options.json "${ARTIFACT_DIR}/" 2>/dev/null

# Collect Kubernetes objects
mkdir -p "${ARTIFACT_DIR}/kubernetes-objects"
oc get pipelineruns -A -o json > "${ARTIFACT_DIR}/kubernetes-objects/pipelineruns.json" 2>/dev/null
oc get taskruns -A -o json > "${ARTIFACT_DIR}/kubernetes-objects/taskruns.json" 2>/dev/null
oc get applications -A -o json > "${ARTIFACT_DIR}/kubernetes-objects/applications.json" 2>/dev/null
oc get components -A -o json > "${ARTIFACT_DIR}/kubernetes-objects/components.json" 2>/dev/null

# Run analysis scripts
if [ -f "evaluate.py" ]; then
    python3 evaluate.py "${ARTIFACT_DIR}/load-test-timings.csv" "${ARTIFACT_DIR}/load-test-options.json" > "${ARTIFACT_DIR}/evaluation.txt" 2>/dev/null
fi

if [ -f "errors.py" ]; then
    # shellcheck disable=SC2034
    application_stub="${ARTIFACT_DIR}/collected-data/collected-applications.appstudio.redhat.com"
    # shellcheck disable=SC2034
    component_stub="${ARTIFACT_DIR}/collected-data/collected-components.appstudio.redhat.com"
    # shellcheck disable=SC2034
    node_stub="${ARTIFACT_DIR}/collected-data/collected-nodes"

    python3 errors.py "${ARTIFACT_DIR}" "ci-scripts/config/errors.yaml" "${ARTIFACT_DIR}/error-summary.json" > "${ARTIFACT_DIR}/errors-analysis.txt" 2>/dev/null
fi

# Collect pprof profiles
mkdir -p "${ARTIFACT_DIR}/profiles"
find . -name "*.pprof" -exec mv {} "${ARTIFACT_DIR}/profiles/" \;

echo "Results collection complete."
