#!/bin/bash -e

# Backfill PostgreSQL with load-test.json files from Jenkins artifact storage, no Horreum involved.
# Assumes tools from https://github.com/Appservices-perfscale/horreum-data-mirror (compute-labels.py and labels-to-postgresql.py) are available.

DRY_RUN=false
HORREUM_TEST_ID="${HORREUM_TEST_ID:-372}"
HOURS_AGO="${1:-3}"
DONE_FILE="${DONE_FILE:-$(pwd)/postgresql-backfill-done.txt}"

POSTGRESQL_HOST="${POSTGRESQL_HOST:-10.1.170.11}"
POSTGRESQL_PORT="${POSTGRESQL_PORT:-5432}"
POSTGRESQL_USER="${POSTGRESQL_USER:-freebusy}"
POSTGRESQL_DB="${POSTGRESQL_DB:-freebusy}"

if [[ -z "${POSTGRESQL_PASS}" ]]; then
    echo "ERROR: POSTGRESQL_PASS env variable is required"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA_FILE="${SCRIPT_DIR}/../config/horreum-schema.json"

if [[ ! -f "${SCHEMA_FILE}" ]]; then
    echo "ERROR: Schema file not found: ${SCHEMA_FILE}"
    exit 1
fi

# Create the done file if it doesn't exist
touch "${DONE_FILE}"

ARTIFACTS_BASE="https://workdir-exporter-jenkins-csb-perf.apps.int.gpc.ocp-hub.prod.psi.redhat.com/workspace/ARTIFACTS"
mapfile -t ARTIFACT_URLS < <(
    curl -sS "${ARTIFACTS_BASE}/" \
        | grep -oP 'href="(StoneSoupLoadTestProbe_[^"]+/)"' \
        | sed 's/href="//;s/"//' \
        | while read -r dir; do echo "${ARTIFACTS_BASE}/${dir}"; done
)

cutoff=$(date -u -d "${HOURS_AGO} hours ago" +%s)

tmpdir=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '${tmpdir}'" EXIT

for base_url in "${ARTIFACT_URLS[@]}"; do
    echo "=== $( date --utc -Ins ) Processing ${base_url}"

    # Get list of run directories - extract hrefs ending with /
    curl -sS "${base_url}" \
        | grep -oP 'href="(run-[^"]+/)"' \
        | sed 's/href="//;s/"//' \
        | while read -r run_dir; do

        # Extract timestamp from directory name like run-kflux-rhel-p01-2026_04_15T06_26_24_650000000_00_00/
        # Parse the date part: 2026_04_15T06_26_24
        ts=$(echo "${run_dir}" | grep -oP '\d{4}_\d{2}_\d{2}T\d{2}_\d{2}_\d{2}')
        if [[ -z "${ts}" ]]; then
            echo "  SKIP ${run_dir} (cannot parse timestamp)"
            continue
        fi

        # Convert 2026_04_15T06_26_24 to 2026-04-15T06:26:24
        # shellcheck disable=SC2001
        ts_fmt=$(echo "${ts}" | sed 's/\([0-9]\{4\}\)_\([0-9]\{2\}\)_\([0-9]\{2\}\)T\([0-9]\{2\}\)_\([0-9]\{2\}\)_\([0-9]\{2\}\)/\1-\2-\3T\4:\5:\6/')
        run_epoch=$(date -u -d "${ts_fmt}" +%s)

        if (( run_epoch < cutoff )); then
            continue
        fi

        json_url="${base_url}${run_dir}load-test.json"
        local_file="${tmpdir}/load-test.json"
        labels_file="${tmpdir}/load-test-labels.json"

        echo "  $( date --utc -Ins ) Processing ${run_dir}"

        http_code=$(curl -sS -o "${local_file}" -w "%{http_code}" "${json_url}")
        if [[ "${http_code}" != "200" ]]; then
            echo "    SKIP (load-test.json not found, HTTP ${http_code})"
            continue
        fi

        build_id=$(jq -r '.metadata.env.BUILD_ID // empty' "${local_file}")
        if [[ -z "${build_id}" ]]; then
            echo "    SKIP (BUILD_ID is empty)"
            continue
        fi

        # Skip if already processed
        if grep -qFx "${build_id}" "${DONE_FILE}"; then
            echo "    SKIP ${run_dir} (already processed)"
            continue
        fi

        echo "    $( date --utc -Ins ) BUILD_ID: ${build_id}"

        if $DRY_RUN; then
            echo "    $( date --utc -Ins ) Would work with ${local_file}"
            continue
        fi

        jq '.name = "Konflux cluster probe"' "${local_file}" > "${local_file}.tmp" && mv "${local_file}.tmp" "${local_file}"

        horreum_run_id=$(date -u -d "${ts_fmt}" +%Y%m%d)
        horreum_dataset_id=$(date -u -d "${ts_fmt}" +%H%M%S)

        start_ts=$(jq -r '.started | sub(","; ".")' "${local_file}")

        compute-labels.py \
            --source "${local_file}" \
            --schema "${SCHEMA_FILE}" \
            >"${labels_file}"

        labels_output=$(labels-to-postgresql.py \
            --label-values "${labels_file}" \
            --horreum-test-id "${HORREUM_TEST_ID}" \
            --horreum-run-id "${horreum_run_id}" \
            --horreum-dataset-id "${horreum_dataset_id}" \
            --start "${start_ts}" \
            --postgresql-host "${POSTGRESQL_HOST}" \
            --postgresql-port "${POSTGRESQL_PORT}" \
            --postgresql-user "${POSTGRESQL_USER}" \
            --postgresql-pass "${POSTGRESQL_PASS}" \
            --postgresql-db "${POSTGRESQL_DB}" \
            --check-label .metadata.env.BUILD_ID \
            --debug 2>&1) || {
            if echo "${labels_output}" | grep -q "already exists"; then
                echo "    WARNING: Data already exists for BUILD_ID=${build_id}, skipping"
            else
                echo "    ERROR: labels-to-postgresql.py failed:"
                echo "${labels_output}"
                exit 1
            fi
        }

        echo "${build_id}" >> "${DONE_FILE}"
        echo "    $( date --utc -Ins ) Done"
    done
done
