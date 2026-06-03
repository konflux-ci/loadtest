#!/bin/bash

# shellcheck disable=SC1091
source "$( dirname "$0" )/../utils.sh"
# shellcheck disable=SC1091
source "$( dirname "$0" )/../user-prefix.sh"

timestamp=$(date +%Y_%m_%dT%H_%M_%S)
output_dir=${ARTIFACT_DIR:-/tmp/load-test-$(whoami)-$timestamp}
mkdir -p "$output_dir"

# Options for the load test tool
options=""

if [ -n "${CONCURRENCY}" ]; then
    options="$options --concurrency=${CONCURRENCY}"
fi

if [ -n "${JOURNEY_REPEATS}" ]; then
    options="$options --journey-repeats=${JOURNEY_REPEATS}"
fi

if [ -n "${JOURNEY_DURATION}" ]; then
    options="$options --journey-duration=${JOURNEY_DURATION}"
fi

if [ -n "${APPLICATIONS_COUNT}" ]; then
    options="$options --applications-count=${APPLICATIONS_COUNT}"
fi

if [ -n "${COMPONENTS_COUNT}" ]; then
    options="$options --components-count=${COMPONENTS_COUNT}"
fi

if [ -n "${PIPELINES_WAIT}" ]; then
    options="$options --waitpipelines=${PIPELINES_WAIT}"
fi

if [ -n "${PIPELINES_TIMEOUT}" ]; then
    options="$options --pipelinetimeout=${PIPELINES_TIMEOUT}"
fi

if [ -n "${PURGE}" ]; then
    options="$options --purge=${PURGE}"
fi

# Run the load test
go run loadtest.go \
    --output-dir="$output_dir" \
    --username="$USER_PREFIX" \
    --waitpipelines="${WAIT_PIPELINES:-true}" \
    "$options" \
    2>&1 | tee "$output_dir/load-test.log"

LOADTEST_EXIT_STATUS=${PIPESTATUS[0]}

if [ "${LOADTEST_EXIT_STATUS}" -ne 0 ]; then
    echo "Load test failed with exit status ${LOADTEST_EXIT_STATUS}"
fi

exit "${LOADTEST_EXIT_STATUS}"
