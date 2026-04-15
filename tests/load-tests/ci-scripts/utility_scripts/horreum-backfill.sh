#!/bin/bash -e

# Backfill Horreum with load-test.json files from Jenkins artifact storage.
# Assumes shovel.py, status_data.py and HORREUM_API_TOKEN env var are available.

DRY_RUN=false
HORREUM_HOST="${HORREUM_HOST:-https://horreum.corp.redhat.com}"
HOURS_AGO="${1:-3}"

ARTIFACTS_BASE="https://workdir-exporter-jenkins-csb-perf.apps.int.gpc.ocp-hub.prod.psi.redhat.com/workspace/ARTIFACTS"
mapfile -t ARTIFACT_URLS < <(
    curl -sS "${ARTIFACTS_BASE}/" \
        | grep -oP 'href="(StoneSoupLoadTestProbe_[^"]+/)"' \
        | sed 's/href="//;s/"//' \
        | while read -r dir; do echo "${ARTIFACTS_BASE}/${dir}"; done
)

cutoff=$(date -u -d "${HOURS_AGO} hours ago" +%s)

tmpdir=$(mktemp -d)
trap "rm -rf ${tmpdir}" EXIT

for base_url in "${ARTIFACT_URLS[@]}"; do
    echo "=== Processing ${base_url}"

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
        ts_fmt=$(echo "${ts}" | sed 's/\([0-9]\{4\}\)_\([0-9]\{2\}\)_\([0-9]\{2\}\)T\([0-9]\{2\}\)_\([0-9]\{2\}\)_\([0-9]\{2\}\)/\1-\2-\3T\4:\5:\6/')
        run_epoch=$(date -u -d "${ts_fmt}" +%s)

        if (( run_epoch < cutoff )); then
            continue
        fi

        json_url="${base_url}${run_dir}load-test.json"
        local_file="${tmpdir}/load-test.json"

        echo "  Processing ${run_dir}"

        http_code=$(curl -sS -o "${local_file}" -w "%{http_code}" "${json_url}")
        if [[ "${http_code}" != "200" ]]; then
            echo "    SKIP (load-test.json not found, HTTP ${http_code})"
            continue
        fi

        if $DRY_RUN; then
            echo "    Would work with ${local_file}"
            continue
        fi

        test_job_matcher=".metadata.env.BUILD_ID"
        test_job_matcher_label=".metadata.env.BUILD_ID"

        test_matcher=$(status_data.py --status-data-file "${local_file}" --get "${test_job_matcher}")
        echo "    Matcher: ${test_matcher}"

        status_data.py --status-data-file "${local_file}" --set "name=Konflux cluster probe" "\$schema=urn:rhtap-perf-team-load-test:1.0"

        shovel.py horreum \
            --base-url "${HORREUM_HOST}" \
            --api-token "${HORREUM_API_TOKEN}" \
            upload \
            --test-name "@name" \
            --input-file "${local_file}" \
            --matcher-field "${test_job_matcher}" \
            --matcher-label "${test_job_matcher_label}" \
            --start "@started" \
            --end "@ended"
            ###--trashed \
            ###--trashed-workaround-count 96

        ###shovel.py horreum \
        ###    --base-url "${HORREUM_HOST}" \
        ###    --api-token "${HORREUM_API_TOKEN}" \
        ###    result \
        ###    --test-name "@name" \
        ###    --output-file "${local_file}" \
        ###    --start "@started" \
        ###    --end "@ended"

        echo "    Done"
    done
done
