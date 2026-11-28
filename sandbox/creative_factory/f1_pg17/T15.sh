#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
[[ "$PGHOST" == 127.0.0.1 && "$PGDATABASE" == lf_creative_f1_ci && "$PGUSER" == postgres ]] || { echo 'T15|FAIL unsafe target'; exit 2; }

root="$(cd .. && pwd)"
runner="$root/queue_v02/test_pg17.sh"
[[ -x "$runner" || -f "$runner" ]] || { echo 'T15|FAIL queue concurrency runner missing'; exit 2; }

db="saly_queue_test"
cleanup(){
  PGDATABASE=postgres dropdb --if-exists "$db" >/dev/null 2>&1 || true
}
trap cleanup EXIT
PGDATABASE=postgres dropdb --if-exists "$db" >/dev/null 2>&1 || true
PGDATABASE=postgres createdb "$db"
export PGDATABASE="$db"

out="$(bash "$runner" 2>&1)"
printf '%s\n' "$out" | grep -Fq 'PASS two physical PG17 connections serialized' || {
  printf '%s\n' "$out"
  echo 'T15|FAIL two-session serialization evidence missing'
  exit 1
}
printf '%s\n' "$out" | grep -Fq 'PASS only one active claim' || {
  printf '%s\n' "$out"
  echo 'T15|FAIL single-active evidence missing'
  exit 1
}
echo 'T15|PASS'
