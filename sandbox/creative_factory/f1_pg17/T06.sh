#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || exit 2
printf '%s\n' 'T06|NOT_PROVEN' 'Missing LF reservation fixture with candidate applied'
exit 1
