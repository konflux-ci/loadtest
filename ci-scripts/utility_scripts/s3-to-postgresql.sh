#!/bin/bash -e

# Pull Kanary probe tarballs from S3 and ingest load-test.json into PostgreSQL (KONFLUX-15648).
#
# Requires: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, POSTGRESQL_PASS,
#           HDM_DIR (horreum-data-mirror checkout), SCHEMA_FILE, jq, uv
#
# S3 object keys recorded in DONE_FILE to avoid duplicates

# --- Constants: bucket/prefix to scan, Horreum test id, done-file, path to s3-artifacts.py ---
S3_BUCKET="konflux-perfscale-artifacts"
S3_PREFIX="run-probe/"
HORREUM_TEST_ID=372
DONE_FILE="${DONE_FILE:-$(pwd)/s3-to-postgresql-done.txt}"
# Resolve s3-artifacts.py relative to this script (ci-scripts/), not cwd.
S3_ARTIFACTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/s3-artifacts.py"

# Freebusy Postgres; only POSTGRESQL_PASS comes from Vault.
POSTGRESQL_HOST="10.1.170.11"
POSTGRESQL_PORT="5432"
POSTGRESQL_USER="freebusy"
POSTGRESQL_DB="freebusy"

# Required env vars (Vault/Jenkins) and paths must exist before any S3 work
: "${POSTGRESQL_PASS:?POSTGRESQL_PASS is required}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${HDM_DIR:?HDM_DIR (horreum-data-mirror checkout) is required}"
: "${SCHEMA_FILE:?SCHEMA_FILE is required}"

[[ -d "${HDM_DIR}" ]] || { echo "ERROR: HDM_DIR does not exist: ${HDM_DIR}"; exit 1; }
[[ -f "${SCHEMA_FILE}" ]] || { echo "ERROR: SCHEMA_FILE not found: ${SCHEMA_FILE}"; exit 1; }
[[ -f "${S3_ARTIFACTS}" ]] || { echo "ERROR: s3-artifacts.py not found: ${S3_ARTIFACTS}"; exit 1; }

# S3 helper: run s3-artifacts.py via uv with ephemeral boto3 (same AWS_* env vars)
s3_tools() {
    uv run --with boto3 python "${S3_ARTIFACTS}" "$@"
}

# Make sure the done-file exists (create its directory if needed)
mkdir -p "$(dirname "${DONE_FILE}")"
touch "${DONE_FILE}"

# Temp folder for this run; delete it when the script exits
tmpdir=$(mktemp -d)
trap 'rm -rf "${tmpdir}"' EXIT

# List S3 keys under run-probe/, keep only .tar.gz
mapfile -t KEYS < <(
    s3_tools list --bucket "${S3_BUCKET}" --prefix "${S3_PREFIX}" \
        | grep '\.tar\.gz$' \
        | sort
)

# Empty bucket / no tarballs → success (nothing to do this hour).
if [[ ${#KEYS[@]} -eq 0 || -z "${KEYS[0]:-}" ]]; then
    echo "No .tar.gz objects under s3://${S3_BUCKET}/${S3_PREFIX}"
    exit 0
fi

echo "Found ${#KEYS[@]} tarball(s)"

for key in "${KEYS[@]}"; do
    echo "=== ${key}"

    # Skip keys already recorded in DONE_FILE
    if grep -qFx "${key}" "${DONE_FILE}"; then
        echo "  SKIP (already processed)"
        continue
    fi

    # Download tarball and extract into a fresh directory
    extract_dir="${tmpdir}/extract"
    rm -rf "${extract_dir}"
    mkdir -p "${extract_dir}"

    s3_tools download --bucket "${S3_BUCKET}" --remote "${key}" --local "${tmpdir}/run.tar.gz"
    tar -xzf "${tmpdir}/run.tar.gz" -C "${extract_dir}"

    # Find load-test.json; skip if missing (do not mark done — retry next run)
    local_file=$(find "${extract_dir}" -name 'load-test.json' -type f | head -1)
    if [[ -z "${local_file}" ]]; then
        echo "  SKIP (no load-test.json)"
        continue
    fi

    # Check that this is a Konflux cluster probe result (matches Horreum test 372).
    # If the name is something else, skip it — we don't want other load tests in this DB.
    if ! jq -r '.name' "${local_file}" | grep -q 'Konflux cluster probe'; then
        echo "  SKIP (unexpected .name)"
        continue
    fi

    # Read .started from the JSON and turn it into IDs we need for Postgres.
    # Probe timestamps look like 2026-09-16T14:45:14,338345249+00:00 — we drop the
    # nanoseconds (after the comma) so `date` can parse it, then build:
    #   start_ts          = start time (ISO-ish)
    #   horreum_run_id    = YYYYMMDD (day of the run)
    #   horreum_dataset_id = HHMMSS (time of day, so multiple runs per day don't collide)
    start_ts=$(jq -r '.started | split(",")[0] + "Z"' "${local_file}")
    horreum_run_id=$(date -u -d "${start_ts}" +%Y%m%d)
    horreum_dataset_id=$(date -u -d "${start_ts}" +%H%M%S)
    labels_file="${tmpdir}/load-test-labels.json"

    echo "  Ingesting start=${start_ts}"

    # Turn load-test.json into a labels JSON file using horreum-data-mirror's
    # compute-labels.py and our Horreum schema (SCHEMA_FILE).
    (cd "${HDM_DIR}" && uv run python compute-labels.py \
        --source "${local_file}" \
        --schema "${SCHEMA_FILE}") >"${labels_file}"

    # Insert those labels into PostgreSQL. If the row is already there ("already exists"),
    # treat that as OK and still mark this S3 key done so we don't keep retrying it.
    if ! out=$(cd "${HDM_DIR}" && uv run python labels-to-postgresql.py \
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
        --debug 2>&1); then
        if echo "${out}" | grep -qi 'already exists'; then
            echo "  WARNING: already in Postgres, marking done"
        else
            echo "  ERROR: labels-to-postgresql.py failed:"
            echo "${out}"
            exit 1
        fi
    fi

    # Record key so future hourly runs skip this object
    echo "${key}" >> "${DONE_FILE}"
    echo "  Done"
done

echo "Finished"
