#!/usr/bin/env bash
# Runs a command unchanged. On GitHub Actions, a failure's key lines are re-emitted as `::error`
# annotations: they show inline on the PR and are readable through the public API, unlike job logs.
set -uo pipefail

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

if [[ $status -ne 0 && "${GITHUB_ACTIONS:-}" == "true" ]]; then
    title="${MISE_TASK_NAME:-$1}"
    # CoreData lines are excluded: the suite opens broken stores on purpose and logs them as errors.
    grep -E "error:|✘|Fatal error|fatal error|error while loading|Testing failed|BUILD FAILED|command not found" "$log" \
        | grep -v "CoreData:" \
        | awk '!seen[$0]++' \
        | head -n 10 \
        | while IFS= read -r line; do
            line="${line//'%'/'%25'}"
            line="${line//$'\r'/'%0D'}"
            printf '::error title=%s::%s\n' "$title" "$line"
        done
fi

exit "$status"
