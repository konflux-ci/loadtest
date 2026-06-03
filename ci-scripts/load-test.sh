#!/bin/bash

# shellcheck disable=SC1091
source "$( dirname "$0" )/user-prefix.sh"

timestamp=$(date +%Y_%m_%dT%H_%M_%S)
output_dir=${ARTIFACT_DIR:-/tmp/load-test-$(whoami)-$timestamp}
mkdir -p "$output_dir"

# Run the load test
go run loadtest.go \
    --output-dir="$output_dir" \
    --username="$USER_PREFIX" \
    --waitpipelines="${WAIT_PIPELINES:-true}" \
    2>&1 | tee "$output_dir/load-test.log"

LOADTEST_EXIT_STATUS=${PIPESTATUS[0]}

exit "${LOADTEST_EXIT_STATUS}"
