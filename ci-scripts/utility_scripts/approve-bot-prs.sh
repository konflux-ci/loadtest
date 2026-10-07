#!/bin/bash
# Approve open PRs from the Mintmaker bot author whose CI checks all passed.
# Runs in the konflux-ci/loadtest repository (uses the current git remote).

set -eu

GREEN=$'\033[32m'
RED=$'\033[31m'
RESET=$'\033[0m'

gh pr list --state open --author "app/red-hat-konflux-kflux-prd-rh03" --json number,url,title,statusCheckRollup \
    | jq -c '.[]' \
    | while IFS= read -r pr; do
        number=$(jq -r '.number' <<<"$pr")
        url=$(jq -r '.url' <<<"$pr")
        title=$(jq -r '.title' <<<"$pr")

        # Conclusion/state per context: CheckRun uses .conclusion, StatusContext uses .state
        results=$(jq -r '.statusCheckRollup[]? | (.conclusion // .state // "PENDING")' <<<"$pr")
        total=$(grep -c . <<<"$results" || true)
        passed=$(grep -c '^SUCCESS$' <<<"$results" || true)
        # Any failure or still-pending check blocks approval
        blocked=$(grep -cvE '^(SUCCESS|PENDING)$' <<<"$results" || true)
        pending=$(grep -c '^PENDING$' <<<"$results" || true)

        if (( passed == total && total > 0 && blocked == 0 && pending == 0 )); then
            status="${GREEN}OK${RESET}"
            gh pr review --approve "$number" -b "All checks on this Mintmaker PR passed, approving."
            echo "#${number} ${url} \"${title}\" ${status} ${passed}/${total} Approved"
        else
            reason="Needs inspection"
            (( blocked > 0 )) && reason="Needs inspection (${blocked} failing)"
            (( pending > 0 && blocked == 0 )) && reason="Needs inspection (${pending} pending)"
            echo "#${number} ${url} \"${title}\" ${RED}FAIL${RESET} ${passed}/${total} ${reason}"
        fi
    done
