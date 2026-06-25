#!/bin/sh

set -euo pipefail

UPDATE_PROMETHEUS=true
UPDATE_MANAGED=true
UPDATE_LOADTEST=true
UPDATE_STAGING=true
UPDATE_PRODUCTION=true

export VAULT_ADDR=https://vault.devshift.net/
vault login -method=oidc

update_tokens() {
    local base_vault_path="$1"
    local cluster="$2"

    oclogin "$cluster"

    if [ "$UPDATE_PROMETHEUS" = true ]; then
        echo "Updating prometheus_token for $cluster in $base_vault_path"
        p="$(oc -n perf-team-prometheus-reader create token perf-team-prometheus-reader-cluster-sa --duration "$((24*365))h")"
        vault kv patch -mount stonesoup "/$base_vault_path/perfscale/shared/$cluster" "prometheus_token=$p"
    fi

    if [ "$UPDATE_MANAGED" = true ]; then
        echo "Updating managed_sa_token for $cluster in $base_vault_path"
        m="$(oc -n managed-konflux-perfscale-tenant create token managed-konflux-perfscale-sa --duration "$((24*365))h")"
        vault kv patch -mount stonesoup "/$base_vault_path/perfscale/shared/$cluster" "managed_sa_token=$m"
    fi

    if [ "$UPDATE_LOADTEST" = true ]; then
        for n in 1 2 3 4; do
            echo "Updating loadtest token for $cluster/konflux-perfscale-${n}-tenant in $base_vault_path"
            t="$(oc -n "konflux-perfscale-${n}-tenant" create token serviceaccount-loadtest --duration "$((24*365))h")"
            vault kv patch -mount stonesoup "/$base_vault_path/perfscale/shared/$cluster/konflux-perfscale-${n}-tenant" "token=$t"
        done
    fi
}

if [ "$UPDATE_STAGING" = true ]; then
    for c in stone-stg-rh01 stone-stage-p01; do
        update_tokens "staging" "$c"
    done
fi

if [ "$UPDATE_PRODUCTION" = true ]; then
    for c in stone-prd-rh01 stone-prod-p01 stone-prod-p02 kflux-ocp-p01 kflux-osp-p01 kflux-prd-rh02 kflux-prd-rh03 kflux-rhel-p01 kflux-fedora-01; do
        update_tokens "production" "$c"
    done
fi
