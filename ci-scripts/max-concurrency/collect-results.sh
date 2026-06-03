#!/bin/bash

# Collects results for max-concurrency runs

# ARTIFACT_DIR is where results will be stored
ARTIFACT_DIR=${ARTIFACT_DIR:-$(pwd)/artifacts}
mkdir -p "${ARTIFACT_DIR}"

echo "Collecting max-concurrency results to ${ARTIFACT_DIR}..."

# Loop through iterations and collect data
find "$ARTIFACT_DIR/iterations/" -type d -name 'iteration-*' -print0 | while IFS= read -r -d '' iteration_dir; do
    echo "Processing $iteration_dir"
    # ... collection logic ...
done

echo "Max-concurrency results collection complete."
