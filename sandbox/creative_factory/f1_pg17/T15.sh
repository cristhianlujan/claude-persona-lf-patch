#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || exit 2
printf '%s\n' 'T15|NOT_PROVEN' 'Missing LF two-session seal/RUN fixture'
exit 1
