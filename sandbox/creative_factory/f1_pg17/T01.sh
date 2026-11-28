#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || exit 2
printf '%s\n' 'T01|NOT_PROVEN' 'Missing integrated LF L2A/L2C/L3B fixture with actual identity tokens'
exit 1
