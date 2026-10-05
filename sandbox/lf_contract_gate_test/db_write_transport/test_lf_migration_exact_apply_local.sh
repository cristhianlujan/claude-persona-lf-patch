#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$ROOT/.tmp_m3_3_supabase_local"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

supabase init >/dev/null
supabase start >/dev/null

cleanup() {
  cd "$WORK"
  supabase stop --no-backup >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p supabase/migrations
MIG="20261005235959_local_probe_v1"
cat > "supabase/migrations/${MIG}.sql" <<'SQL'
create table public.lf_m3_3_probe(
  id bigint primary key,
  created_at timestamptz not null default now()
);
SQL

DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"

python "$ROOT/sandbox/lf_contract_gate_test/db_write_transport/lf_migration_exact_apply.py"   --project-root "$WORK"   --migration-path "$WORK/supabase/migrations/${MIG}.sql"   --db-url "$DB_URL"   --source-blob aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

test "$(psql "$DB_URL" -X -Atc "select to_regclass('public.lf_m3_3_probe')::text")" = "lf_m3_3_probe"
test "$(psql "$DB_URL" -X -Atc "select count(*) from supabase_migrations.schema_migrations where version='20261005235959' and name='local_probe_v1'")" = "1"

# Idempotent retry: no second DDL/apply.
python "$ROOT/sandbox/lf_contract_gate_test/db_write_transport/lf_migration_exact_apply.py"   --project-root "$WORK"   --migration-path "$WORK/supabase/migrations/${MIG}.sql"   --db-url "$DB_URL"   --source-blob aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

test "$(psql "$DB_URL" -X -Atc "select count(*) from supabase_migrations.schema_migrations where version='20261005235959'")" = "1"
echo "PASS_MIGRATION_EXACT_APPLY_LOCAL_SUPABASE"
