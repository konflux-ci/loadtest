# LWPython probe local run (`pslwdpy`)

Reproduce Jenkins `StoneSoupLoadTestProbe_lightwell_dev_LWPython` on **lightwell-dev** / `konflux-perfscale-3-tenant`.

## Prerequisites

- `oc` logged in to lightwell-dev
- `GITHUB_TOKEN` with admin on the fork org (`MY_GITHUB_ORG`)
- Go 1.26+ (macOS/Linux) or the loadtest container image

## Quick start

```bash
export GITHUB_TOKEN=...
export MY_GITHUB_ORG=test-probe
export COMPONENT_REPO=https://github.com/thanujdesu11/lw-pypi.org-ntplib-1

./ci-scripts/run-probe/run-lwpython-probe-local.sh
```

Jenkins parity (vault bot token, `rhtap-perf-test` forks): use defaults in `scenarios/lightwell-dev-lwpython.env`.

## Files

| File | Purpose |
|------|---------|
| `run-lwpython-probe-local.sh` | Local wrapper (pre-cleanup, `users.json`, invoke loadtest) |
| `scenarios/lightwell-dev-lwpython.env` | Env vars matching the Jenkins job |
| `run.sh` | Entry point used in the loadtest CI image |

Logs and artifacts land in `workdir/lwpython-probe-local/` (gitignored `users*.json` is written there at runtime).

## Notes

- loadtest posts `/ok-to-test` on the PaC PR **after** LWPython template files are pushed (required when `remember-ok-to-test=false`).
- Only `on-push` PipelineRuns are waited on for the build KPI.
