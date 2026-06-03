#!/bin/bash

# High-concurrency test script

source "$( dirname "$0" )/user-prefix.sh"

timestamp=$(date +%Y_%m_%dT%H_%M_%S)
workdir=${ARTIFACT_DIR:-/tmp/load-test-max-concurrency-$(whoami)-$timestamp}
mkdir -p "$workdir"

load_test() {
    local concurrency=$1
    local repeats=$2
    local output_dir=$3
    local options=$4

    echo "Running load test with concurrency $concurrency and $repeats repeats"
    mkdir -p "$output_dir"

    go run loadtest.go \
        --output-dir="$output_dir" \
        --username="$USER_PREFIX" \
        --concurrency="$concurrency" \
        --journey-repeats="$repeats" \
        --waitpipelines="${WAIT_PIPELINES:-true}" \
        "$options" \
        2>&1 | tee "$output_dir/load-test.log"

    LOADTEST_EXIT_STATUS=${PIPESTATUS[0]}
    if [ "${LOADTEST_EXIT_STATUS}" -ne 0 ]; then
        echo "Load test failed with exit status ${LOADTEST_EXIT_STATUS}"
        return "${LOADTEST_EXIT_STATUS}"
    fi
}

# Main loop for max concurrency testing
max_concurrency_test() {
    local steps=${MAX_CONCURRENCY_STEPS:-"1 5 10 25 50 100"}
    local repeats=${JOURNEY_REPEATS:-1}

    for c in $steps; do
        iteration_dir="$workdir/iteration-$c"
        load_test "$c" "$repeats" "$iteration_dir" "$LOADTEST_OPTIONS"
    done
}

max_concurrency_test

# Collect results
if [ -f "ci-scripts/max-concurrency/collect-results.sh" ]; then
    bash ci-scripts/max-concurrency/collect-results.sh "$workdir"
fi

exit 0
