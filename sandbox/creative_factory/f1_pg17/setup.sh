#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || exit 2
# No integrated catalog restore is available yet. Do not substitute the reduced V02 fixture.
psql -XAt -v ON_ERROR_STOP=1 -c 'show server_version_num' | grep -qE '^17[0-9]{4}$'
[[ -f "$F1_CANDIDATE" ]] || { echo F1_CANDIDATE_NOT_AVAILABLE; exit 3; }
# Record the exact candidate digest. Integrated setup must supply baseline and candidate
# database snapshots, rather than mutate the production catalog or replay production data.
printf '%s  %s\n' "$F1_CANDIDATE_SHA256" "$F1_CANDIDATE" | sha256sum -c -
echo 'F1_SETUP_NOT_PROVEN: integrated real catalog restore and baseline/candidate replay absent'
exit 0
