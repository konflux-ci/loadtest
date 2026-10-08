#!/bin/bash -e

# Pull Kanary probe tarballs from S3 and ingest load-test.json into PostgreSQL (KONFLUX-15648).
#
# Requires: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, POSTGRESQL_PASS,
#           SCHEMA_FILE, jq, (WORKDIR_ROOT optional, defaults to /home/jenkins/workspace)
#
# Artifacts are extracted to ${WORKDIR_ROOT}/ARTIFACTS/StoneSoupLoadTestFromS3_probe_<cluster>_<type>/<rundir>/
# so workdir-exporter serves them for investigate.py (KONFLUX-16245). WORKDIR_ROOT must be
# the directory the exporter serves at /workspace — the probe Jenkins jobs hardcode
# /home/jenkins/workspace/ARTIFACTS/... and investigate.py builds URLs from the last path
# element of ARTIFACT_DIR, so the job's own ${WORKSPACE} (a per-job subdir) would 404.
# Missing JOB_NAME / ARTIFACT_DIR labels in load-test.json are filled in before label
# computation.
#
# After a successful ingest (or a permanent skip), the S3 object is deleted so we do not
# rely on a local done-file on Jenkins (workspaces get cleaned). Failed ingests leave the
# object in place for the next hourly run. Bucket lifecycle still expires anything left.

# --- Constants: bucket/prefix to scan, Horreum test id, path to s3-artifacts.py ---
S3_BUCKET="konflux-perfscale-artifacts"
S3_PREFIX="run-probe/"
HORREUM_TEST_ID=372
# Resolve s3-artifacts.py relative to this script (ci-scripts/), not cwd.
S3_ARTIFACTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/s3-artifacts.py"

# Freebusy Postgres; only POSTGRESQL_PASS comes from Vault.
POSTGRESQL_HOST="10.1.93.176"
POSTGRESQL_PORT="5432"
POSTGRESQL_USER="freebusy"
POSTGRESQL_DB="freebusy"

# Required env vars (Vault/Jenkins) and paths must exist before any S3 work
: "${POSTGRESQL_PASS:?POSTGRESQL_PASS is required}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${SCHEMA_FILE:?SCHEMA_FILE is required}"
# Dir served by workdir-exporter at /workspace (same root the probe Jenkins jobs write to).
WORKDIR_ROOT="${WORKDIR_ROOT:-/home/jenkins/workspace}"
[[ -d "${WORKDIR_ROOT}" ]] || { echo "ERROR: WORKDIR_ROOT does not exist (is this the workdir-exporter agent?): ${WORKDIR_ROOT}"; exit 1; }

[[ -f "${SCHEMA_FILE}" ]] || { echo "ERROR: SCHEMA_FILE not found: ${SCHEMA_FILE}"; exit 1; }
[[ -f "${S3_ARTIFACTS}" ]] || { echo "ERROR: s3-artifacts.py not found: ${S3_ARTIFACTS}"; exit 1; }

s3_tools() {
    "${S3_ARTIFACTS}" "$@"
}

# Remove the object from S3 once we are done with it (success or permanent skip).
s3_delete() {
    local key="$1"
    echo "  Deleting s3://${S3_BUCKET}/${key}"
    s3_tools delete --bucket "${S3_BUCKET}" --remote "${key}"
}

# Temp folder for this run; delete it when the script exits
# (workspace ARTIFACTS dirs are intentionally NOT cleaned up — they are the
# persistent copy of the artifacts, see KONFLUX-16245)
tmpdir=$(mktemp -d)
trap 'rm -rf "${tmpdir}"' EXIT

# Prioritize newest uploads across all clusters/scenarios; preserve S3 helper order.
# Older objects not reached before bucket lifecycle expiry may remain un-ingested.
# List failure (auth/network) must abort — an empty result only means "nothing to do".
list_out=$(s3_tools list --bucket "${S3_BUCKET}" --prefix "${S3_PREFIX}" --newest-first) \
    || { echo "ERROR: failed to list s3://${S3_BUCKET}/${S3_PREFIX}"; exit 1; }
mapfile -t KEYS < <(printf '%s\n' "${list_out}" | grep '\.tar\.gz$' || true)

# Empty bucket / no tarballs → success (nothing to do this hour).
if [[ ${#KEYS[@]} -eq 0 || -z "${KEYS[0]:-}" ]]; then
    echo "No .tar.gz objects under s3://${S3_BUCKET}/${S3_PREFIX}"
    exit 0
fi

echo "Found ${#KEYS[@]} tarball(s)"

for key in "${KEYS[@]}"; do
    echo "=== ${key}"

    # Derive job name and run dir from the S3 key: run-probe/<cluster>/<type>/<file>.tar.gz
    # Components become directory names that get rm -rf'ed, so each must be a plain name —
    # this rejects empty, ".", ".." and any other path tricks (KONFLUX-16245 review).
    name_re='^[A-Za-z0-9][A-Za-z0-9._-]*$'
    rel="${key#"${S3_PREFIX}"}"
    IFS='/' read -r cluster rtype rest <<<"${rel}"
    if [[ -z "${rest}" || "${rest}" == */* || "${rest}" != *.tar.gz ||
          ! "${cluster}" =~ ${name_re} || ! "${rtype}" =~ ${name_re} || ! "${rest}" =~ ${name_re} ]]; then
        echo "  ERROR: unexpected S3 key layout: ${key}"
        exit 1
    fi
    job_name="StoneSoupLoadTestFromS3_probe_${cluster}_${rtype}"
    rundir="${rest%.tar.gz}"
    dest_dir="${WORKDIR_ROOT}/ARTIFACTS/${job_name}/${rundir}"

    # Download tarball and extract it into a staging dir first; the published dir is
    # replaced only after extraction succeeds, so a failed retry cannot destroy an
    # already-published copy (KONFLUX-16245 review). Staging lives in tmpdir and is
    # cleaned by the EXIT trap.
    stage_dir="${tmpdir}/stage"
    rm -rf "${stage_dir}"
    mkdir -p "${stage_dir}"

    s3_tools download --bucket "${S3_BUCKET}" --remote "${key}" --local "${tmpdir}/run.tar.gz"
    tar -xzf "${tmpdir}/run.tar.gz" -C "${stage_dir}"

    # Find load-test.json; if missing, delete the object (timestamped keys are not re-uploaded).
    local_file=$(find "${stage_dir}" -name 'load-test.json' -type f | head -1)
    if [[ -z "${local_file}" ]]; then
        echo "  SKIP (no load-test.json)"
        s3_delete "${key}"
        continue
    fi

    # Check that this is a Konflux cluster probe result (matches Horreum test 372).
    # If the name is something else, skip and delete — that object will not change.
    if ! jq -r '.name' "${local_file}" | grep -q 'Konflux cluster probe'; then
        echo "  SKIP (unexpected .name)"
        s3_delete "${key}"
        continue
    fi

    # Read .started from the JSON and turn it into IDs we need for PostgreSQL.
    # Probe timestamps look like 2026-09-16T14:45:14,338345249+00:00 — we drop the
    # nanoseconds (after the comma) so `date` can parse it, then build:
    #   start_ts          = start time (ISO-ish)
    #   horreum_run_id    = YYYYMMDD (day of the run)
    #   horreum_dataset_id = HHMMSS (time of day, so multiple runs per day don't collide)
    start_ts=$(jq -r '.started | split(",")[0] + "Z"' "${local_file}")
    horreum_run_id=$(date -u -d "${start_ts}" +%Y%m%d)
    horreum_dataset_id=$(date -u -d "${start_ts}" +%H%M%S)
    labels_file="${tmpdir}/load-test-labels.json"

    # Overwrite JOB_NAME / ARTIFACT_DIR with where this script publishes the artifacts:
    # any values from the source run refer to the in-cluster pod, not the served files,
    # and investigate.py must build its URL from the published location (KONFLUX-16245 review).
    jq --arg job_name "${job_name}" --arg artifact_dir "${dest_dir}" '
        .metadata.env = (.metadata.env // {})
        | .metadata.env.JOB_NAME = $job_name
        | .metadata.env.ARTIFACT_DIR = $artifact_dir
    ' "${local_file}" >"${tmpdir}/load-test-enriched.json"
    mv "${tmpdir}/load-test-enriched.json" "${local_file}"

    # Publish: replace the served run dir only now that the replacement is complete
    # (KONFLUX-16245 review). mv requires the destination's parent dir to exist —
    # Jenkins workspaces ship without ARTIFACTS/ — so create it first.
    mkdir -p "$(dirname "${dest_dir}")"
    rm -rf "${dest_dir}"
    mv "${stage_dir}" "${dest_dir}"
    local_file=$(find "${dest_dir}" -name 'load-test.json' -type f | head -1)
    # Fail fast if the publish step failed instead of feeding an empty path into
    # compute_labels (KONFLUX-16245: cascaded into confusing downstream errors).
    if [[ -z "${local_file}" ]]; then
        echo "  ERROR: artifact publish failed for ${key}"
        exit 1
    fi

    echo "  Ingesting start=${start_ts}"

    # Turn load-test.json into a labels JSON file using horreum-data-mirror's
    # compute_labels and our Horreum schema (SCHEMA_FILE).
    (compute_labels \
        --source "${local_file}" \
        --schema "${SCHEMA_FILE}") >"${labels_file}"

    # Insert those labels into PostgreSQL. If the row is already there ("already exists"),
    # treat that as OK and still delete the S3 object.
    if ! out=$(labels_to_postgresql \
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
            echo "  WARNING: already in PostgreSQL, deleting S3 object"
        else
            echo "  ERROR: labels_to_postgresql failed:"
            echo "${out}"
            exit 1
        fi
    fi

    # Ingest succeeded (or already in DB) — remove from S3 so the next run won't see it.
    s3_delete "${key}"
    echo "  Done"
done

echo "Finished"
