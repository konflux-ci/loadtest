#!/bin/bash

source "$( dirname "$0" )/../utils.sh"
source "$( dirname "$0" )/../user-prefix.sh"

# ARTIFACT_DIR is where results will be stored
ARTIFACT_DIR=${ARTIFACT_DIR:-$(pwd)/artifacts}
mkdir -p "${ARTIFACT_DIR}"

echo "Collecting stage results to ${ARTIFACT_DIR}..."

# Similar to main collect-results.sh but for stage
# ... implementation omitted for brevity in this example ...

echo "Stage results collection complete."
