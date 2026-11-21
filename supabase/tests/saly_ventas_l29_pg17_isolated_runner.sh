#!/usr/bin/env bash
# L29: only an empty, loopback PostgreSQL 17 fixture. No prod or user data.
set -euo pipefail
export PGCONNECT_TIMEOUT=5
if [[ "$PGHOST" != 127.0.0.1 || "$PGPORT" != 5432 ||
      "$PGDATABASE" != saly_sales_ci_l29 || "$PGUSER" != postgres ]]; then
  echo "BLOCKED_NON_ISOLATED_DB_TARGET" >&2; exit 32
fi
for cmd in psql sed mktemp; do command -v "$cmd" >/dev/null || exit 33; done
root="$(cd "$(dirname "$0")/../.." && pwd)"
l27="$root/supabase/migrations/20261120235000_lf_saly_ventas_discovery_staging_v1.sql"
l28="$root/supabase/migrations/20261120235100_lf_saly_ventas_discovery_coverage_fk_v1.sql"
t27="$root/supabase/tests/saly_ventas_discovery_staging_v1_pg17_rollback.sql"
t28="$root/supabase/tests/saly_ventas_discovery_coverage_fk_v1_pg17_rollback.sql"
r27="$root/supabase/tests/saly_ventas_discovery_staging_v1_readback.sql"
r28="$root/supabase/tests/saly_ventas_discovery_coverage_fk_v1_readback.sql"
for f in "$l27" "$l28" "$t27" "$t28" "$r27" "$r28"; do
  [[ -f "$f" ]] || { echo "BLOCKED_MISSING_TEST_FILE" >&2; exit 34; }
done
major="$(psql -X -v ON_ERROR_STOP=1 -Atqc "SELECT current_setting('server_version_num')::integer/10000;")"
[[ "$major" == 17 ]] || { echo "BLOCKED_NOT_PG17" >&2; exit 35; }
clean="$(psql -X -v ON_ERROR_STOP=1 -Atqc "
SELECT CASE WHEN to_regclass('saly.proyecto') IS NULL
  AND NOT EXISTS(SELECT 1 FROM pg_tables WHERE schemaname='saly')
THEN 'YES' ELSE 'NO' END;")"
[[ "$clean" == YES ]] || { echo "BLOCKED_NOT_FRESH_DB" >&2; exit 36; }
psql -X -v ON_ERROR_STOP=1 <<'SQL'
DO $fixture$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END $fixture$;
CREATE SCHEMA saly;
CREATE TABLE saly.proyecto(codigo text NOT NULL,estado text NOT NULL);
INSERT INTO saly.proyecto VALUES('SALY-001','ACTIVO');
SQL
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sed -e '/^BEGIN;$/d' -e '/^COMMIT;$/d' "$l27" > "$tmp/l27.sql"
sed -e '/^BEGIN;$/d' -e '/^COMMIT;$/d' "$l28" > "$tmp/l28.sql"
{
 echo 'BEGIN;'
 printf '\\i %s\n' "$tmp/l27.sql" "$tmp/l28.sql"
 cat <<'SQL'
DO $c$
BEGIN
 IF (SELECT count(*) FROM pg_tables WHERE schemaname='saly' AND tablename LIKE 'ventas_%')<>9
 THEN RAISE EXCEPTION 'NINE_TABLES_MISSING_INSIDE_TX'; END IF;
END $c$;
ROLLBACK;
DO $c$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_tables WHERE schemaname='saly' AND tablename LIKE 'ventas_%')
 THEN RAISE EXCEPTION 'L29_DDL_ROLLBACK_FAILED'; END IF;
END $c$;
SQL
} > "$tmp/rollback.sql"
psql -X -v ON_ERROR_STOP=1 -f "$tmp/rollback.sql"
echo PASS_L29_DDL_ROLLBACK
psql -X -v ON_ERROR_STOP=1 -f "$l27"
psql -X -v ON_ERROR_STOP=1 -f "$t27"
echo PASS_L29_L27_FUNCTIONAL
psql -X -v ON_ERROR_STOP=1 -f "$l28"
psql -X -v ON_ERROR_STOP=1 -f "$t28"
echo PASS_L29_L28_FUNCTIONAL
psql -X -v ON_ERROR_STOP=1 -f "$r27"
psql -X -v ON_ERROR_STOP=1 -f "$r28"
psql -X -v ON_ERROR_STOP=1 <<'SQL'
DO $c$
DECLARE n int; protected int;
BEGIN
 SELECT count(*),count(*) FILTER (WHERE c.relrowsecurity)
 INTO n,protected
 FROM pg_class c JOIN pg_namespace p ON p.oid=c.relnamespace
 WHERE p.nspname='saly' AND c.relkind='r' AND c.relname LIKE 'ventas_%';
 IF n<>9 OR protected<>9 THEN RAISE EXCEPTION 'RLS_OR_TABLE_MISSING'; END IF;
 IF EXISTS(SELECT 1 FROM saly.ventas_discovery_runs)
 OR EXISTS(SELECT 1 FROM saly.ventas_discovery_ingestas)
 OR EXISTS(SELECT 1 FROM saly.ventas_hallazgos)
 THEN RAISE EXCEPTION 'L29_FIXTURE_DATA_PERSISTED'; END IF;
 RAISE NOTICE 'PASS_L29_PG17_ALL_GATES';
END $c$;
SQL
echo PASS_L29_PG17_ALL_CHECKS
