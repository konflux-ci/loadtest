#!/bin/bash

# Stage high-concurrency variant

# shellcheck disable=SC1091
source "$( dirname "$0" )/user-prefix.sh"

timestamp=$(date +%Y_%m_%dT%H_%M_%S)
workdir=${ARTIFACT_DIR:-/tmp/load-test-stage-max-concurrency-$(whoami)-$timestamp}
mkdir -p "$workdir"

load_test() {
    local concurrency=$1
    local repeats=$2
    local output_dir=$3
    local options=$4

    echo "Running stage load test with concurrency $concurrency and $repeats repeats"
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
        echo "Stage load test failed with exit status ${LOADTEST_EXIT_STATUS}"
        return "${LOADTEST_EXIT_STATUS}"
    fi
}

# Main loop
max_concurrency_test() {
    local steps=${MAX_CONCURRENCY_STEPS:-"1 5 10 25 50 100"}
    local repeats=${JOURNEY_REPEATS:-1}
    # shellcheck disable=SC2034
    local iteration iteration_index

    for c in $steps; do
        iteration_dir="$workdir/iteration-$c"
        load_test "$c" "$repeats" "$iteration_dir" "$LOADTEST_OPTIONS"
    done
}

max_concurrency_test

exit 0
