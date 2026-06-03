#!/bin/bash

# Utility to backfill Horreum with old results

tmpdir=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf ${tmpdir}" EXIT

# ... logic ...

backfill() {
    local ts=$1
    local ts_fmt
    ts_fmt=${ts//_/-}
    ts_fmt=${ts_fmt/T/ }
    # ...
    echo "Backfilling for $ts_fmt"
}

# ...
