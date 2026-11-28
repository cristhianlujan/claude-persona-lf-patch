#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || exit 2
# Historical queue V06 behavior is available; execute it separately as supporting evidence.
# It must NOT be counted as an F1 pass: it restores a reduced historical substrate.
root="$(cd .. && pwd)"
if PGDATABASE=saly_queue_test psql -XAt -v ON_ERROR_STOP=1 -c 'select 1' >/dev/null 2>&1; then
  echo 'T09|SUPPORTING_ONLY: historical V06 substrate exists; requires isolated V06 runner'
fi
printf '%s\n' 'T09|NOT_PROVEN' 'Missing integrated valid LF RUN and real delivery guard fixture'
exit 1
