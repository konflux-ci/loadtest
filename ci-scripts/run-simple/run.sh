#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

trap "date -Ins --utc >ended" EXIT

if type probetest &>/dev/null; then
    cmd=("probetest")
    echo "Running probetest from $( type -p probetest ) binary"
else
    cmd=("go" "run" "probetest.go")
    echo "Running probetest from $( pwd ) with '${cmd[*]}' command"
fi

# Output directory must exist so the CSV writers and the options JSON can be created.
OUTPUT_DIR="${OUTPUT_DIR:-.}"
mkdir -p "${OUTPUT_DIR}"

date -Ins --utc >started
"${cmd[@]}" \
    --application "${APPLICATION:-simple-probe-app}" \
    --component "${COMPONENT:-comp}" \
    --component-repo "${COMPONENT_REPO:-https://github.com/jhutar/nodejs-devfile-sample}" \
    --component-repo-revision "${COMPONENT_REPO_REVISION:-main}" \
    --test-scenario-git-url "${TEST_SCENARIO_GIT_URL:-https://github.com/konflux-ci/integration-examples.git}" \
    --release-policy "${RELEASE_POLICY:-}" \
    --waitintegrationtestspipelines="${WAIT_INTEGRATION_TESTS:-true}" \
    --waitpipelines="${WAIT_PIPELINES:-true}" \
    --waitrelease="${WAIT_RELEASE:-true}" \
    --log-"${LOGGING_LEVEL:-info}" \
    --output-dir "${OUTPUT_DIR}" \
    --stage
