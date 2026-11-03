# Onboard a cluster for probe Vault tokens

How to seed OpenShift service-account tokens into AppSRE Vault so Jenkins
`StoneSoupLoadTestProbe_*` jobs can log into a Konflux cluster and collect results.

Example work: [KONFLUX-16595](https://redhat.atlassian.net/browse/KONFLUX-16595)
(kflux-stg-p02), unblocking [KONFLUX-16553](https://redhat.atlassian.net/browse/KONFLUX-16553).

## Background

Jenkins `runKonfluxProbeTest` reads from the `stonesoup` KV mount:

| Vault path | Keys (typical) | Used for |
|---|---|---|
| `{env}/perfscale/shared/{cluster}/{namespace}` | `token` | `oc login` as loadtest SA |
| `{env}/perfscale/shared/{cluster}` | `managed_sa_token`, `prometheus_token` | managed ops / **Collect results** |
| `{env}/perfscale/shared` | git, Horreum, OCI robot, etc. | shared across clusters (usually already present) |

`{env}` is **`staging`** when the cluster name contains `-stg-`, `-stage-`, or
`-dev`; otherwise **`production`**. That matches `VAULT_ENV` in
`ci-configs` `runKonfluxProbeTest.groovy`.

Example: `kflux-stg-p02` → `staging/...`; `kflux-lw-p01` → `production/...`.

Minting and writing cluster/tenant tokens is automated by:

[`ci-scripts/utility_scripts/update-vault-tokens.sh`](../ci-scripts/utility_scripts/update-vault-tokens.sh)

Related one-time / ExternalSecret context (do not redo unless missing):

- [KONFLUX-11975](https://redhat.atlassian.net/browse/KONFLUX-11975) — Vault + ExternalSecret pattern
- [konflux-release-data !13968](https://gitlab.cee.redhat.com/releng/konflux-release-data/-/merge_requests/13968) — example ExternalSecret in tenants-config

Tenant ExternalSecrets (e.g. `pipelines-as-code-secret`) sync *other* secrets into
the namespace. They are **separate** from the Jenkins kube / prometheus tokens this
script manages.

## Prerequisites

- Working reachability to Vault (`https://vault.devshift.net/`). If `vault login`
  fails with TLS handshake timeout, fix VPN / corp network first — the script
  cannot proceed.
- `vault` CLI and OIDC access with write to
  `stonesoup/{staging|production}/perfscale/...`
- `oc` and a cluster login helper (`oclogin` or equivalent) that knows the
  cluster **name**, console URL, and API URL (the script calls `oclogin <cluster>`).
- On the target cluster, SAs the script mints from must exist:
  - `serviceaccount-loadtest` in `konflux-perfscale-{1,2,3,4}-tenant`
  - `managed-konflux-perfscale-sa` in `managed-konflux-perfscale-tenant` (if `UPDATE_MANAGED`)
  - `perf-team-prometheus-reader-cluster-sa` in `perf-team-prometheus-reader` (if `UPDATE_PROMETHEUS`)

If `serviceaccount-loadtest` is missing, install it from the
`perf-team-prometheus-reader` component in
[infra-deployments](https://github.com/redhat-appstudio/infra-deployments)
(`components/perf-team-prometheus-reader/.../serviceaccount-loadtest.yaml`) via
GitOps/Argo, or apply those manifests if that is how your team bootstraps a new
cluster.

Minting `perf-team-prometheus-reader-cluster-sa` tokens usually requires
`konflux-performance` / `perf-team-sa-token-creator` RBAC. Without it you get:

```text
User "…" cannot create resource "serviceaccounts/token" in the namespace "perf-team-prometheus-reader"
```

Ask someone with that access to seed `prometheus_token`, or get the RBAC and
re-run the script with `UPDATE_PROMETHEUS=true`.

## Steps

1. **Confirm ExternalSecret wiring** for the tenant (11975 / !13968 pattern), e.g.:
   ```bash
   oc -n konflux-perfscale-3-tenant get externalsecret
   ```
   Expect `SecretSynced` / `READY=True` for PaC / OCI secrets if the probe needs them.

2. **Add the cluster to** `update-vault-tokens.sh` under the correct block:
   - Staging: `update_tokens "staging" "<cluster>"` (e.g. `kflux-stg-p02`)
   - Production: add the name to the `UPDATE_PRODUCTION` loop

3. **Ensure `oclogin` (or your login helper) lists the cluster** so the script can
   switch context by name.

4. **Edit the flags** at the top of the script for this run (keep them `false` in git):
   ```bash
   UPDATE_PROMETHEUS=true   # cluster prometheus_token (Collect results)
   UPDATE_MANAGED=true      # cluster managed_sa_token
   UPDATE_LOADTEST=true     # per-tenant token (required for oc login)
   UPDATE_STAGING=true      # or UPDATE_PRODUCTION / UPDATE_FEDORA
   ```
   Tip: for a first pass on one new cluster, temporarily comment out other
   clusters in that block so you are not forced to log into every cluster in the list.

5. **Run**:
   ```bash
   export VAULT_ADDR=https://vault.devshift.net/
   ./ci-scripts/utility_scripts/update-vault-tokens.sh
   ```
   First-time paths often print `Patch failed, creating secret…` then succeed —
   that is normal when the KV path did not exist yet.

6. **Verify** (do not paste secret values into tickets/chat):
   ```bash
   vault kv get -mount stonesoup -field=token \
     staging/perfscale/shared/<cluster>/konflux-perfscale-3-tenant >/dev/null && echo token_ok

   vault kv get -mount stonesoup -field=managed_sa_token \
     staging/perfscale/shared/<cluster> >/dev/null && echo managed_ok

   vault kv get -mount stonesoup -field=prometheus_token \
     staging/perfscale/shared/<cluster> >/dev/null && echo prometheus_ok
   ```
   Adjust `staging` → `production` when applicable.

7. **Revert flags to `false`**, commit the new cluster line(s) + this doc, open a PR.

8. **Re-run the Jenkins probe job.**

## After Vault: Jenkins still cannot `oc login`

Vault success only means Jenkins can **read** the token. The agent must also
**reach** the cluster API.

If the job fails during cleanup / login with something like:

```text
dial tcp 10.x.x.x:30486: i/o timeout
```

then fix **TenantEgress** on the Jenkins agents namespace (not Vault):

- RDU3 agents (`hceperf--runtime-int`): see
  [`ci-configs` jenkins-agents README](https://gitlab.cee.redhat.com/redhat-performance/ci-configs/-/blob/master/infra/jenkins-agents/README.md)
  and `infra/jenkins-agents/tenantegress-default-rdu3.yaml`.
- Add an Allow for the cluster API DNS name (and monitoring host if needed)
  **before** the final Deny rule.
- Rules in git are not always live — confirm in the OpenShift console TenantEgress
  YAML after save. You may not have permission to list `EgressFirewall`; that is
  OK. If allows are live and the timeout persists, escalate to platform (agent
  network path to the API).

## Checklist

- [ ] Cluster listed in `update-vault-tokens.sh` (staging vs production correct)
- [ ] `oclogin` / login helper knows the cluster
- [ ] Required SAs exist; prometheus mint RBAC available if seeding that key
- [ ] ExternalSecrets for the tenant synced (if probe needs them)
- [ ] Ran script; `token` (+ managed/prometheus as needed) present in Vault
- [ ] Jenkins agent TenantEgress allows API DNS; probe job can `oc login`
- [ ] PR: script cluster line + doc; flags left `false`

## Links

- Script: https://github.com/konflux-ci/loadtest/blob/main/ci-scripts/utility_scripts/update-vault-tokens.sh
- Vault UI: https://vault.devshift.net/
- KONFLUX-11975: https://redhat.atlassian.net/browse/KONFLUX-11975
- ExternalSecret MR: https://gitlab.cee.redhat.com/releng/konflux-release-data/-/merge_requests/13968
- Example ticket: https://redhat.atlassian.net/browse/KONFLUX-16595
- Probe ticket example: https://redhat.atlassian.net/browse/KONFLUX-16553
