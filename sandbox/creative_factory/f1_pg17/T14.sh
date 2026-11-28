#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
[[ "$PGHOST" == 127.0.0.1 && "$PGDATABASE" == lf_creative_f1_ci && "$PGUSER" == postgres ]] || { echo 'T14|FAIL unsafe target'; exit 2; }

root="$(cd ../../.. && pwd)"
source_migration="$root/supabase/migrations/20261126153000_lf_saly_creative_replace_attempt3_order22_v1.sql"
[[ -f "$source_migration" ]] || { echo 'T14|FAIL exact historical source missing'; exit 2; }

tmp="$(mktemp -d)"
body="$tmp/order22_functions.sql"
sql="$tmp/t14.sql"
db="lf_f1_t14_$$"
cleanup(){
  PGDATABASE=postgres dropdb --if-exists "$db" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

python3 - "$source_migration" "$body" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
start = src.index("CREATE OR REPLACE FUNCTION saly.creative_execution_policy_for_item_v1")
end = src.index("CREATE OR REPLACE FUNCTION saly.creative_queue_claim_by_id_v1", start)
fragment = src[start:end]
required = [
    "OLD.order_id=22",
    "OLD.item_id=26",
    "OLD.attempt_number IN (3,4)",
    "interval '24 hours'",
]
missing = [x for x in required if x not in fragment]
if missing:
    raise SystemExit("T14_EXACT_SOURCE_ANCHOR_MISSING:" + ",".join(missing))
pathlib.Path(sys.argv[2]).write_text(fragment, encoding="utf-8")
PY

PGDATABASE=postgres createdb "$db"
export PGDATABASE="$db"

cat > "$sql" <<'SQL'
\set ON_ERROR_STOP on
CREATE SCHEMA saly;
CREATE TABLE saly.creative_orders(
  id bigint PRIMARY KEY,
  status text NOT NULL,
  scope_json jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE TABLE saly.creative_order_items(
  id bigint PRIMARY KEY,
  order_id bigint NOT NULL,
  status text NOT NULL,
  acceptance_json jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE TABLE saly.creative_runs(
  id bigint PRIMARY KEY,
  order_id bigint NOT NULL,
  item_id bigint NOT NULL,
  attempt_number integer NOT NULL,
  idempotency_key text NOT NULL,
  state text NOT NULL,
  input_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  execution_policy jsonb NOT NULL DEFAULT '{}'::jsonb,
  deadline_at timestamptz,
  worker_ref text,
  started_at timestamptz,
  finished_at timestamptz,
  output_evidence jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE OR REPLACE FUNCTION saly.creative_execution_policy_v1(p_asof timestamptz)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
SELECT '{"QUEUE_MAX":5,"MAX_ATTEMPTS":10,"QUEUE_TIMEOUT_SECONDS":900,"LEASE_SECONDS":600}'::jsonb
$fn$;

INSERT INTO saly.creative_orders VALUES
  (22,'EN_PROCESO','{"rendering_authority":true}'::jsonb);
INSERT INTO saly.creative_order_items VALUES
  (26,22,'PRODUCIENDO','{}'::jsonb);
INSERT INTO saly.creative_runs
(id,order_id,item_id,attempt_number,idempotency_key,state,execution_policy,deadline_at,finished_at)
VALUES
  (1,22,26,1,'old-1','CANCELADO','{"LEASE_SECONDS":600}'::jsonb,clock_timestamp(),clock_timestamp()),
  (2,22,26,2,'old-2','CANCELADO','{"LEASE_SECONDS":600}'::jsonb,clock_timestamp(),clock_timestamp());
SQL
printf '\\i %s\n' "$body" >> "$sql"
cat >> "$sql" <<'SQL'
CREATE TRIGGER trg_creative_run_guard_l1
BEFORE INSERT OR UPDATE ON saly.creative_runs
FOR EACH ROW EXECUTE FUNCTION saly.creative_run_guard_l1();

INSERT INTO saly.creative_runs
(id,order_id,item_id,attempt_number,idempotency_key,state,input_snapshot)
VALUES (3,22,26,3,'hist-3','EN_COLA','{}');
UPDATE saly.creative_runs SET state='EJECUTANDO',worker_ref='T14-W3' WHERE id=3;
DO $qa3$
DECLARE secs numeric;
BEGIN
 SELECT extract(epoch FROM deadline_at-started_at) INTO secs FROM saly.creative_runs WHERE id=3;
 IF secs IS DISTINCT FROM 86400::numeric THEN
   RAISE EXCEPTION 'T14_ATTEMPT3_NOT_24H:%',secs;
 END IF;
END
$qa3$;
UPDATE saly.creative_runs SET state='CANCELADO' WHERE id=3;

INSERT INTO saly.creative_runs
(id,order_id,item_id,attempt_number,idempotency_key,state,input_snapshot)
VALUES (4,22,26,4,'hist-4','EN_COLA','{}');
UPDATE saly.creative_runs SET state='EJECUTANDO',worker_ref='T14-W4' WHERE id=4;
DO $qa4$
DECLARE secs numeric;
BEGIN
 SELECT extract(epoch FROM deadline_at-started_at) INTO secs FROM saly.creative_runs WHERE id=4;
 IF secs IS DISTINCT FROM 86400::numeric THEN
   RAISE EXCEPTION 'T14_ATTEMPT4_NOT_24H:%',secs;
 END IF;
END
$qa4$;
UPDATE saly.creative_runs SET state='CANCELADO' WHERE id=4;

INSERT INTO saly.creative_runs
(id,order_id,item_id,attempt_number,idempotency_key,state,input_snapshot)
VALUES (5,22,26,5,'control-5','EN_COLA','{}');
UPDATE saly.creative_runs SET state='EJECUTANDO',worker_ref='T14-W5' WHERE id=5;
DO $qa5$
DECLARE secs numeric;
BEGIN
 SELECT extract(epoch FROM deadline_at-started_at) INTO secs FROM saly.creative_runs WHERE id=5;
 IF secs IS DISTINCT FROM 600::numeric THEN
   RAISE EXCEPTION 'T14_CONTROL_ATTEMPT5_NOT_POLICY_LEASE:%',secs;
 END IF;
END
$qa5$;
SQL

psql -X -v ON_ERROR_STOP=1 -f "$sql" >/dev/null
echo 'T14|PASS'
