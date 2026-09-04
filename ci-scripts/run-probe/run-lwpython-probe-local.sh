#!/usr/bin/env bash
# Reproduce Jenkins StoneSoupLoadTestProbe_lightwell_dev_LWPython locally.
# Equivalent to ci-configs runKonfluxProbeTest.groovy + ci-scripts/run-probe/run.sh
#
# Prerequisites:
#   - oc logged in to lightwell-dev with konflux-perfscale-3-tenant access
#   - GITHUB_TOKEN with repo admin on the fork target org (MY_GITHUB_ORG)
#
# Local dev (fork into test-probe):
#   export GITHUB_TOKEN=ghp_...
#   export MY_GITHUB_ORG=test-probe
#   export COMPONENT_REPO=https://github.com/thanujdesu11/lw-pypi.org-ntplib-1
#   ./ci-scripts/run-probe/run-lwpython-probe-local.sh
#
# Jenkins parity:
#   export GITHUB_TOKEN=...   # vault github_token
#   ./ci-scripts/run-probe/run-lwpython-probe-local.sh
#
# Optional:
#   PURGE_ONLY=true ./ci-scripts/run-probe/run-lwpython-probe-local.sh
#   USE_LOADTEST_IMAGE=true ./ci-scripts/run-probe/run-lwpython-probe-local.sh
#   WORKDIR=/tmp/lwpython-probe ./ci-scripts/run-probe/run-lwpython-probe-local.sh
set -euo pipefail

LOADTEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOADTEST_DIR="${LOADTEST_DIR:-$LOADTEST_ROOT}"
SCENARIO_FILE="${SCENARIO_FILE:-$LOADTEST_ROOT/ci-scripts/run-probe/scenarios/lightwell-dev-lwpython.env}"
WORKDIR="${WORKDIR:-$LOADTEST_ROOT/workdir/lwpython-probe-local}"
LOADTEST_IMAGE="${LOADTEST_IMAGE:-quay.io/redhat-user-workloads/konflux-perfscale-tenant/loadtest:latest}"

if [[ -f "$SCENARIO_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCENARIO_FILE"
  set +a
fi

mkdir -p "$WORKDIR"
cd "$WORKDIR"

if ! oc whoami >/dev/null 2>&1; then
  echo "Not logged in. Run: oc login --server=${SERVER_API_URL:-<cluster-api>}" >&2
  exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Set GITHUB_TOKEN (vault github_token for Jenkins parity)." >&2
  exit 1
fi

USER_TOKEN="${USER_TOKEN:-$(oc whoami -t)}"
if [[ -z "$USER_TOKEN" ]]; then
  echo "Could not get oc token. Set USER_TOKEN explicitly." >&2
  exit 1
fi

_component_org="${COMPONENT_REPO#https://github.com/}"
_component_org="${_component_org%%/*}"
export MY_GITHUB_ORG="${MY_GITHUB_ORG:-rhtap-perf-test}"
if [[ "$_component_org" == "$MY_GITHUB_ORG" ]]; then
  echo "COMPONENT_REPO owner ($_component_org) equals fork target ($MY_GITHUB_ORG)." >&2
  echo "GitHub cannot fork into the same org. Use a different MY_GITHUB_ORG (e.g. test-probe)." >&2
  exit 1
fi

cat > users.json <<EOF
[
  {
    "apiurl": "${SERVER_API_URL}",
    "namespace": "${NAMESPACE}",
    "token": "$USER_TOKEN",
    "verified": true
  }
]
EOF

echo "Cleaning ${NAMESPACE} (Applications, etc.)..."
oc -n "$NAMESPACE" delete --all application --wait=false 2>/dev/null || true
oc -n "$NAMESPACE" delete --all integrationtestscenario --wait=false 2>/dev/null || true
oc -n "$NAMESPACE" delete --all imagerepository --wait=false 2>/dev/null || true
oc -n "$NAMESPACE" delete --all release --wait=false 2>/dev/null || true
oc -n "$NAMESPACE" delete --all releaseplan --wait=false 2>/dev/null || true
oc -n "$NAMESPACE" delete --all releaseplanadmission --wait=false 2>/dev/null || true
oc -n "$NAMESPACE" delete repository --all --wait=false 2>/dev/null || true
sleep 5

export CLUSTER NAMESPACE SERVER_API_URL COMPONENT_REPO COMPONENT_REPO_REVISION
export LOGGING_LEVEL RUN_PREFIX PIPELINE_REPO_TEMPLATING PIPELINE_REPO_TEMPLATING_SOURCE
export PIPELINE_REPO_TEMPLATING_SOURCE_DIR TEST_SCENARIO_GIT_URL TEST_SCENARIO_PATH_IN_REPO
export TEST_SCENARIO_REVISION WAIT_INTEGRATION_TESTS WAIT_PIPELINES WAIT_RELEASE RELEASE_POLICY
export OCI_STORAGE QUAY_REPO CONCURRENCY OUTPUT_DIR PURGE PURGE_ONLY MY_GITHUB_ORG

echo "Workdir: $WORKDIR"
echo "Cluster: $CLUSTER  Namespace: $NAMESPACE"
echo "Component: $COMPONENT_REPO"
echo "Fork target org: $MY_GITHUB_ORG"
echo "Template:  $PIPELINE_REPO_TEMPLATING_SOURCE_DIR"
echo "Scenario:  $SCENARIO_FILE"
echo "loadtest:  $LOADTEST_DIR"
echo ""

stamp_utc() {
  if date -Ins --utc >/dev/null 2>&1; then
    date -Ins --utc
  else
    date -u +"%Y-%m-%dT%H:%M:%S+00:00"
  fi
}

run_loadtest_direct() {
  stamp_utc > started
  trap 'stamp_utc > ended' EXIT

  local lt_args=(
    --applications-count "${APPLICATIONS_COUNT:-1}"
    --build-pipeline-selector-bundle "${BUILD_PIPELINE_SELECTOR_BUNDLE:-}"
    --component-repo "${COMPONENT_REPO}"
    --component-repo-revision "${COMPONENT_REPO_REVISION}"
    --components-count "${COMPONENTS_COUNT:-1}"
    --concurrency "${CONCURRENCY:-1}"
    --fork-target "${FORK_TARGET:-}"
    --journey-duration "${JOURNEY_DURATION:-1h}"
    --journey-repeats "${JOURNEY_REPEATS:-1}"
    --log-"${LOGGING_LEVEL:-info}"
    --pipeline-repo-templating="${PIPELINE_REPO_TEMPLATING}"
    --pipeline-repo-templating-source="${PIPELINE_REPO_TEMPLATING_SOURCE}"
    --pipeline-repo-templating-source-dir="${PIPELINE_REPO_TEMPLATING_SOURCE_DIR}"
    --output-dir "${OUTPUT_DIR:-.}"
    --purge="${PURGE:-true}"
    --quay-repo "${QUAY_REPO}"
    --test-scenario-git-url "${TEST_SCENARIO_GIT_URL:-}"
    --test-scenario-path-in-repo "${TEST_SCENARIO_PATH_IN_REPO:-}"
    --test-scenario-revision "${TEST_SCENARIO_REVISION:-main}"
    --release-policy "${RELEASE_POLICY:-}"
    --release-ociStorage "${OCI_STORAGE}"
    --runprefix "${RUN_PREFIX}"
    --waitintegrationtestspipelines="${WAIT_INTEGRATION_TESTS:-false}"
    --waitpipelines="${WAIT_PIPELINES:-true}"
    --waitrelease="${WAIT_RELEASE:-false}"
    --stage
  )
  if [[ "${PURGE_ONLY:-false}" == "true" ]]; then
    lt_args+=(--purge-only)
  fi

  if command -v loadtest >/dev/null 2>&1; then
    echo "Running $(command -v loadtest) (cwd $WORKDIR)"
    loadtest "${lt_args[@]}" 2>&1 | tee load-test-run.log
  elif go help -C >/dev/null 2>&1; then
    echo "Running: go -C $LOADTEST_DIR run . (cwd $WORKDIR)"
    GOFLAGS=-mod=mod go -C "$LOADTEST_DIR" run . "${lt_args[@]}" 2>&1 | tee load-test-run.log
  else
    echo "Building loadtest binary..."
    (cd "$LOADTEST_DIR" && GOFLAGS=-mod=mod go build -o "$WORKDIR/loadtest-bin" .)
    echo "Running $WORKDIR/loadtest-bin"
    "$WORKDIR/loadtest-bin" "${lt_args[@]}" 2>&1 | tee load-test-run.log
  fi
}

run_loadtest() {
  if [[ "${USE_LOADTEST_IMAGE:-false}" == "true" ]]; then
    if ! command -v podman >/dev/null 2>&1 && ! command -v docker >/dev/null 2>&1; then
      echo "Install podman or docker, or unset USE_LOADTEST_IMAGE." >&2
      exit 1
    fi
    local ctr=(podman)
    command -v podman >/dev/null 2>&1 || ctr=(docker)
    echo "Running in container $LOADTEST_IMAGE (same as Jenkins)"
    "${ctr[@]}" run --rm -it \
      -v "$WORKDIR:/work:Z" \
      -w /work \
      -e CLUSTER -e NAMESPACE -e SERVER_API_URL -e MY_GITHUB_ORG \
      -e COMPONENT_REPO -e COMPONENT_REPO_REVISION -e LOGGING_LEVEL -e RUN_PREFIX \
      -e PIPELINE_REPO_TEMPLATING -e PIPELINE_REPO_TEMPLATING_SOURCE \
      -e PIPELINE_REPO_TEMPLATING_SOURCE_DIR \
      -e TEST_SCENARIO_GIT_URL -e TEST_SCENARIO_PATH_IN_REPO -e TEST_SCENARIO_REVISION \
      -e WAIT_INTEGRATION_TESTS -e RELEASE_POLICY -e WAIT_RELEASE -e WAIT_PIPELINES \
      -e OCI_STORAGE -e QUAY_REPO -e CONCURRENCY -e OUTPUT_DIR -e PURGE -e PURGE_ONLY \
      -e GITHUB_TOKEN \
      "$LOADTEST_IMAGE" \
      /opt/app-root/src/ci-scripts/run-probe/run.sh
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    if [[ ! -f "$LOADTEST_DIR/loadtest.go" ]]; then
      echo "loadtest repo not found at $LOADTEST_DIR" >&2
      exit 1
    fi
    run_loadtest_direct
  else
    if [[ ! -f "$LOADTEST_DIR/ci-scripts/run-probe/run.sh" ]]; then
      echo "loadtest run.sh not found at $LOADTEST_DIR/ci-scripts/run-probe/run.sh" >&2
      exit 1
    fi
    stamp_utc > started
    trap 'stamp_utc > ended' EXIT
    bash "$LOADTEST_DIR/ci-scripts/run-probe/run.sh" 2>&1 | tee load-test-run.log
  fi
}

run_loadtest

echo ""
echo "Done. Logs: $WORKDIR/load-test-run.log"
echo "Watch PLR: oc -n $NAMESPACE get pipelinerun | grep ${RUN_PREFIX}"
