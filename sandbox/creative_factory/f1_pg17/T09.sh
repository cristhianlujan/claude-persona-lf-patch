#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
[[ "$PGHOST" == 127.0.0.1 && "$PGDATABASE" == lf_creative_f1_ci && "$PGUSER" == postgres ]] || { echo 'T09|FAIL unsafe target'; exit 2; }

root="$(cd ../../.. && pwd)"
migration="$root/supabase/migrations/20261124222001_lf_saly_creative_serial_loop_v1.sql"
test_sql="$root/supabase/tests/saly_creative_serial_loop_v1_pg17_rollback.sql"
[[ -f "$migration" && -f "$test_sql" ]] || { echo 'T09|FAIL exact source/test missing'; exit 2; }

tmp="$(mktemp -d)"
db="lf_f1_t09_$$"
cleanup(){
  PGDATABASE=postgres dropdb --if-exists "$db" >/dev/null 2>&1 || true
  rm -rf "$tmp"
  rm -f /tmp/saly_serial_loop_body.sql
}
trap cleanup EXIT
PGDATABASE=postgres createdb "$db"
export PGDATABASE="$db"

sed '/^BEGIN;$/d; /^COMMIT;$/d' "$migration" > /tmp/saly_serial_loop_body.sql
out="$(psql -X -v ON_ERROR_STOP=1 -f "$test_sql" 2>&1)"
printf '%s\n' "$out" | grep -Fq 'PASS_SERIAL_CLAIM_BUSY_CLOSE_NEXT' || {
  printf '%s\n' "$out"
  echo 'T09|FAIL delivery guard evidence missing'
  exit 1
}
echo 'T09|PASS'
