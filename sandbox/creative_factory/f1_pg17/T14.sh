#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || exit 2
# The historical exception is present in production migration source; inspect its anchor,
# but static source inspection cannot establish runtime parity.
f=../../../supabase/migrations/20261126153000_lf_saly_creative_replace_attempt3_order22_v1.sql
if [[ -f "$f" ]]; then grep -nE 'p_order_id=22|24 hours' "$f" || true; fi
printf '%s\n' 'T14|NOT_PROVEN' 'Missing historical order22/item26 attempts 3/4 fixture'
exit 1
