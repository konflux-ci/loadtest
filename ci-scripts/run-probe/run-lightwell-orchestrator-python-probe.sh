#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="${SCRIPT_DIR}/lightwell-orchestrator-python"

function log() {
  echo "[$(date --utc -Ins)] $*"
}

function require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: ${name} is required" >&2
    exit 2
  fi
}

function finish() {
  date -Ins --utc >ended
  if [[ -n "${KUBECONFIG:-}" ]]; then
    rm -f "${KUBECONFIG}" || true
  fi
  if [[ "${ORCHESTRATOR_WORKDIR_CREATED:-false}" == "true" && -n "${ORCHESTRATOR_WORKDIR:-}" ]]; then
    rm -rf "${ORCHESTRATOR_WORKDIR}" || true
  fi
}

trap finish EXIT

date -Ins --utc >started

CLUSTER="${CLUSTER:-kflux-lw-p01}"
NAMESPACE="${NAMESPACE:-konflux-perfscale-3-tenant}"
PACKAGE_REF="${PACKAGE_REF:-ntplib==0.4.0}"
PYTHON_TARGET="${PYTHON_TARGET:-REMEDIATED}"
BUILD_TYPE="${BUILD_TYPE:-Novel}"
BUILDS_TAG="${BUILDS_TAG:-ntplib/0.4.0-probe1}"
LIGHTWELL_BUILDS_REPO_URL="${LIGHTWELL_BUILDS_REPO_URL:-https://gitlab.cee.redhat.com/jhutar/lw-pypi.org-ntplib-1}"
POLL_INTERVAL="${POLL_INTERVAL:-30}"
MAX_RETRIES="${MAX_RETRIES:-0}"
ORCHESTRATOR_GIT_URL="${ORCHESTRATOR_GIT_URL:-https://github.com/konflux-lightwell/lightwell-konflux-orchestrator.git}"
ORCHESTRATOR_GIT_REF="${ORCHESTRATOR_GIT_REF:-main}"
ORCHESTRATOR_WORKDIR_CREATED="false"
if [[ -z "${ORCHESTRATOR_WORKDIR:-}" ]]; then
  ORCHESTRATOR_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/lightwell-orchestrator-python-probe.XXXXXX")"
  ORCHESTRATOR_WORKDIR_CREATED="true"
fi
ORCHESTRATOR_DIR="${ORCHESTRATOR_DIR:-${ORCHESTRATOR_WORKDIR}/lightwell-konflux-orchestrator}"
TEKTON_PIPELINE_DIR="${TEKTON_PIPELINE_DIR:-${ORCHESTRATOR_DIR}/tekton}"
ORCHESTRATOR_RESULT_JSON="${ORCHESTRATOR_RESULT_JSON:-orchestrator-result.json}"
ORCHESTRATOR_VENV="${ORCHESTRATOR_VENV:-${ORCHESTRATOR_WORKDIR}/.orchestrator-venv}"
BOOTSTRAP_MANIFEST="${BOOTSTRAP_MANIFEST:-${OVERLAY_DIR}/bootstrap-remediated-build.yaml}"
APPLY_PERFSCALE_OVERRIDES="${APPLY_PERFSCALE_OVERRIDES:-true}"
BOOTSTRAP_SA="${BOOTSTRAP_SA:-build-pipeline-remediated-build}"
BOOTSTRAP_WAIT_SECONDS="${BOOTSTRAP_WAIT_SECONDS:-300}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
PIP_BIN="${PIP_BIN:-python3 -m pip}"

# Required by upstream orchestrator when building the PipelineRun params.
export BUILD_CONFIGS_REPO_URL="${BUILD_CONFIGS_REPO_URL:-https://gitlab.cee.redhat.com/redhat-performance/lightwell/calunga-python-build-configs}"
export BUILD_CONFIGS_REVISION="${BUILD_CONFIGS_REVISION:-main}"
# Empty default: packages.redhat.com is not reachable / usable on this probe path.
export WHEEL_SERVER_URL="${WHEEL_SERVER_URL:-}"
export TEKTON_PIPELINE_DIR

require_env SERVER_API_URL
require_env USER_TOKEN

export KUBECONFIG="${KUBECONFIG:-$(pwd)/kubeconfig}"
rm -f "${KUBECONFIG}"

log "Logging into ${CLUSTER} (${SERVER_API_URL})"
oc login --token="${USER_TOKEN}" --server="${SERVER_API_URL}"
oc project "${NAMESPACE}"

log "Preflight: durable probe secrets/configmaps"
oc -n "${NAMESPACE}" get secret probe-build-configs-git-auth >/dev/null
oc -n "${NAMESPACE}" get configmap trusted-ca >/dev/null

if [[ -n "${BOOTSTRAP_MANIFEST}" ]]; then
  log "Applying bootstrap manifest: ${BOOTSTRAP_MANIFEST}"
  oc -n "${NAMESPACE}" apply -f "${BOOTSTRAP_MANIFEST}"
  log "Waiting up to ${BOOTSTRAP_WAIT_SECONDS}s for ServiceAccount ${BOOTSTRAP_SA}"
  deadline=$((SECONDS + BOOTSTRAP_WAIT_SECONDS))
  until oc -n "${NAMESPACE}" get sa "${BOOTSTRAP_SA}" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "ERROR: timed out waiting for ServiceAccount ${BOOTSTRAP_SA}" >&2
      oc -n "${NAMESPACE}" get application,component,imagerepository remediated-build -o wide || true
      exit 1
    fi
    sleep 5
  done
  log "Bootstrap SA ready: ${BOOTSTRAP_SA}"
else
  log "No BOOTSTRAP_MANIFEST configured; assuming required Application/ImageRepository/SA resources already exist"
fi

if ! command -v import-orchestrator >/dev/null 2>&1; then
  log "import-orchestrator not found; installing from ${ORCHESTRATOR_GIT_URL}@${ORCHESTRATOR_GIT_REF}"
  rm -rf "${ORCHESTRATOR_DIR}" "${ORCHESTRATOR_VENV}"
  git clone "${ORCHESTRATOR_GIT_URL}" "${ORCHESTRATOR_DIR}"
  git -C "${ORCHESTRATOR_DIR}" checkout "${ORCHESTRATOR_GIT_REF}"
  if [[ "${APPLY_PERFSCALE_OVERRIDES}" == "true" ]]; then
    log "Applying perfscale overlays (KONFLUX-16318)"
    "${PYTHON_BIN}" "${OVERLAY_DIR}/apply-perfscale-overrides.py" "${ORCHESTRATOR_DIR}"
  else
    log "APPLY_PERFSCALE_OVERRIDES=false; installing orchestrator sources unchanged"
  fi
  "${PYTHON_BIN}" -m venv "${ORCHESTRATOR_VENV}"
  # shellcheck disable=SC1091
  source "${ORCHESTRATOR_VENV}/bin/activate"
  python -m pip install --upgrade pip
  python -m pip install "./${ORCHESTRATOR_DIR}"
else
  log "Using import-orchestrator from $(command -v import-orchestrator)"
  log "WARNING: preinstalled binary may lack perfscale overlays; set PATH clear to force git install"
fi

log "Running Lightwell orchestrator Python probe"
log "Package=${PACKAGE_REF} target=${PYTHON_TARGET} build_type=${BUILD_TYPE} builds_tag=${BUILDS_TAG} namespace=${NAMESPACE}"
log "BUILD_CONFIGS_REPO_URL=${BUILD_CONFIGS_REPO_URL} BUILD_CONFIGS_REVISION=${BUILD_CONFIGS_REVISION}"

set +o errexit
import-orchestrator python run "${PACKAGE_REF}" \
  --target "${PYTHON_TARGET}" \
  --build-type "${BUILD_TYPE}" \
  --lightwell-builds-repo-url "${LIGHTWELL_BUILDS_REPO_URL}" \
  --builds-tag "${BUILDS_TAG}" \
  --poll-interval "${POLL_INTERVAL}" \
  --max-retries "${MAX_RETRIES}" \
  --output-json "${ORCHESTRATOR_RESULT_JSON}" \
  2>&1 | tee orchestrator.log
orchestrator_rc=${PIPESTATUS[0]}
set -o errexit

if [[ ! -s "${ORCHESTRATOR_RESULT_JSON}" ]]; then
  echo "ERROR: orchestrator did not write ${ORCHESTRATOR_RESULT_JSON}" >&2
  exit 1
fi

status="$(jq -r '.status // "unknown"' "${ORCHESTRATOR_RESULT_JSON}")"
pipelinerun_name="$(jq -r '.pipelinerun_name // empty' "${ORCHESTRATOR_RESULT_JSON}")"
snapshot_name="$(jq -r '.snapshot_name // empty' "${ORCHESTRATOR_RESULT_JSON}")"

log "Orchestrator rc=${orchestrator_rc} status=${status} pipelinerun=${pipelinerun_name:-<none>} snapshot=${snapshot_name:-<none>}"

if [[ -n "${pipelinerun_name}" ]]; then
  log "PipelineRun summary"
  oc -n "${NAMESPACE}" get pipelinerun "${pipelinerun_name}" -o wide || true
  oc -n "${NAMESPACE}" get taskruns -l "tekton.dev/pipelineRun=${pipelinerun_name}" -o wide || true
fi

if [[ "${orchestrator_rc}" -ne 0 || "${status}" != "success" ]]; then
  log "Probe failed; dumping debug data"
  if [[ -n "${pipelinerun_name}" ]]; then
    oc -n "${NAMESPACE}" get pipelinerun "${pipelinerun_name}" -o yaml >"pipelinerun-${pipelinerun_name}.yaml" || true
    oc -n "${NAMESPACE}" get taskruns -l "tekton.dev/pipelineRun=${pipelinerun_name}" -o yaml >"taskruns-${pipelinerun_name}.yaml" || true
  fi
  exit 1
fi

log "Probe passed"
