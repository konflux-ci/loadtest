#!/bin/bash

set -euo pipefail

UPDATE_PROMETHEUS=false
UPDATE_MANAGED=false
UPDATE_LOADTEST=false
UPDATE_STAGING=false
UPDATE_PRODUCTION=false
UPDATE_FEDORA=false

trap 'sed "s/^/> /" "$log"; echo "ERROR: Script failed"' ERR

export VAULT_ADDR=https://vault.devshift.net/
log="$(mktemp)"
echo "Logging in to Vault $VAULT_ADDR (log: $log)"
vault login -method=oidc &>"$log"

update_tokens() {
    local base_vault_path="$1"
    local cluster="$2"

    log="$(mktemp)"
    echo "Logging in to OpenShift $cluster (log: $log)"
    oclogin "$cluster" &>"$log"

    if [ "$UPDATE_PROMETHEUS" = true ]; then
        log="$(mktemp)"
        echo "Updating prometheus_token for $cluster in $base_vault_path (log: $log)"
        p="$(oc -n perf-team-prometheus-reader create token perf-team-prometheus-reader-cluster-sa --duration "$((24*365))h")"
        vault kv patch -mount stonesoup "/$base_vault_path/perfscale/shared/$cluster" "prometheus_token=$p" &>"$log"
    fi

    if [ "$UPDATE_MANAGED" = true ]; then
        log="$(mktemp)"
        echo "Updating managed_sa_token for $cluster in $base_vault_path (log: $log)"
        m="$(oc -n managed-konflux-perfscale-tenant create token managed-konflux-perfscale-sa --duration "$((24*365))h")"
        vault kv patch -mount stonesoup "/$base_vault_path/perfscale/shared/$cluster" "managed_sa_token=$m" &>"$log"
    fi

    if [ "$UPDATE_LOADTEST" = true ]; then
        for n in 1 2 3 4; do
            log="$(mktemp)"
            echo "Updating loadtest token for $cluster/konflux-perfscale-${n}-tenant in $base_vault_path (log: $log)"
            t="$(oc -n "konflux-perfscale-${n}-tenant" create token serviceaccount-loadtest --duration "$((24*365))h")"
            vault kv patch -mount stonesoup "/$base_vault_path/perfscale/shared/$cluster/konflux-perfscale-${n}-tenant" "token=$t" &>"$log"
        done
    fi
}

if [ "$UPDATE_STAGING" = true ]; then
    update_tokens "staging" "stone-stg-rh01"
    update_tokens "staging" "stone-stage-p01"
fi

if [ "$UPDATE_PRODUCTION" = true ]; then
    for c in stone-prod-p01 stone-prod-p02 kflux-ocp-p01 kflux-osp-p01 kflux-prd-rh02 kflux-prd-rh03 kflux-rhel-p01; do
        update_tokens "production" "$c"
    done
fi

if [ "$UPDATE_FEDORA" = true ]; then
    update_tokens "production" "kflux-fedora-01"
fi

echo "Done"
