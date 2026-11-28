#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T07|FAIL unsafe target'; exit 2; }
[[ -f "${F1_CANDIDATE:-}" && -n "${F1_CANDIDATE_SHA256:-}" ]] || { echo 'T07|FAIL candidate missing'; exit 2; }
printf '%s  %s\n' "$F1_CANDIDATE_SHA256" "$F1_CANDIDATE" | sha256sum -c - >/dev/null
BODY="$(mktemp)"; SQL="$(mktemp)"; trap 'rm -f "$BODY" "$SQL"' EXIT
python3 - "$F1_CANDIDATE" "$BODY" <<'PY'
import pathlib,sys
src=pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines(True)
non=[i for i,l in enumerate(src) if l.strip() and not l.lstrip().startswith("--")]
if len(non)<2 or src[non[0]].strip()!="BEGIN;" or src[non[-1]].strip()!="COMMIT;":
    raise SystemExit("F1_CANDIDATE_TRANSACTION_BOUNDARY_INVALID")
drop={non[0],non[-1]}
pathlib.Path(sys.argv[2]).write_text("".join(l for i,l in enumerate(src) if i not in drop),encoding="utf-8")
PY
cat >"$SQL" <<SQL
\set ON_ERROR_STOP on
BEGIN;
DO \$pre\$
BEGIN
 IF to_regclass('saly.creative_orders') IS NULL
 OR to_regclass('saly.creative_order_items') IS NULL
 OR to_regclass('saly.creative_item_sources') IS NULL
 OR to_regprocedure('saly.creative_item_context_l2a(bigint)') IS NULL
 OR to_regprocedure('saly.creative_item_work_packet_l2c(bigint)') IS NULL
 OR to_regprocedure('saly.creative_item_visual_contract_l3b(bigint)') IS NULL
 THEN RAISE EXCEPTION 'T07_INTEGRATED_BASELINE_MISSING'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
   JOIN saly.proyecto p ON p.id=o.project_id
   WHERE i.id=5 AND i.order_id=4 AND p.codigo='SALY-001'
     AND i.context_json#>'{screen_spec,visual_blueprint}' IS NOT NULL
 ) OR NOT EXISTS (
   SELECT 1 FROM saly.creative_order_items i
   WHERE i.id=7 AND i.order_id=4
     AND i.context_json#>'{screen_spec,visual_blueprint}' IS NULL
 ) THEN RAISE EXCEPTION 'T07_HISTORICAL_BLUEPRINT_AND_LEGACY_CASES_MISSING'; END IF;
END
\$pre\$;

INSERT INTO saly.creative_orders OVERRIDING SYSTEM VALUE
SELECT (jsonb_populate_record(NULL::saly.creative_orders,
  to_jsonb(o)||jsonb_build_object(
    'id',900004,'code','T07_SALY_PARITY_20261128','request_key','T07_SALY_PARITY_20261128',
    'title','T07 SALY parity synthetic','status','EN_PROCESO','completed_at',NULL,
    'created_at',clock_timestamp(),'updated_at',clock_timestamp()
  ))).*
FROM saly.creative_orders o WHERE o.id=4;

INSERT INTO saly.creative_order_items OVERRIDING SYSTEM VALUE
SELECT (jsonb_populate_record(NULL::saly.creative_order_items,
  to_jsonb(i)||jsonb_build_object(
    'id',CASE i.id WHEN 5 THEN 900005 ELSE 900007 END,
    'order_id',900004,'status','LISTO','approved_at',NULL,'approved_by',NULL,
    'qa_receipt','{}'::jsonb,'updated_at',clock_timestamp(),
    'acceptance_json',
      CASE WHEN i.acceptance_json ? 'visual_rules'
        THEN jsonb_set(i.acceptance_json,'{visual_rules,scope}',to_jsonb('T07_SALY_PARITY_20261128'::text),false)
        ELSE i.acceptance_json END
  ))).*
FROM saly.creative_order_items i WHERE i.id IN (5,7);

INSERT INTO saly.creative_item_sources(order_id,item_id,source_asset_id,purpose,source_sha256,created_at)
SELECT 900004,CASE item_id WHEN 5 THEN 900005 ELSE 900007 END,
       source_asset_id,purpose,source_sha256,created_at
FROM saly.creative_item_sources WHERE order_id=4 AND item_id IN (5,7);

CREATE TEMP TABLE t07_before AS
SELECT x.item_id,
 encode(extensions.digest(convert_to(saly.creative_item_context_l2a(x.item_id)::text,'UTF8'),'sha256'),'hex') AS l2a,
 encode(extensions.digest(convert_to(saly.creative_item_work_packet_l2c(x.item_id)::text,'UTF8'),'sha256'),'hex') AS l2c,
 CASE WHEN x.item_id=900005 THEN
   encode(extensions.digest(convert_to(saly.creative_item_visual_contract_l3b(x.item_id)::text,'UTF8'),'sha256'),'hex')
 END AS l3b
FROM (VALUES (900005::bigint),(900007::bigint)) x(item_id);

\i $BODY

CREATE TEMP TABLE t07_after AS
SELECT x.item_id,
 encode(extensions.digest(convert_to(saly.creative_item_context_l2a(x.item_id)::text,'UTF8'),'sha256'),'hex') AS l2a,
 encode(extensions.digest(convert_to(saly.creative_item_work_packet_l2c(x.item_id)::text,'UTF8'),'sha256'),'hex') AS l2c,
 CASE WHEN x.item_id=900005 THEN
   encode(extensions.digest(convert_to(saly.creative_item_visual_contract_l3b(x.item_id)::text,'UTF8'),'sha256'),'hex')
 END AS l3b
FROM (VALUES (900005::bigint),(900007::bigint)) x(item_id);

DO \$qa\$
BEGIN
 IF (SELECT count(*) FROM t07_before)<>2 OR (SELECT count(*) FROM t07_after)<>2
 OR EXISTS (
   SELECT 1 FROM t07_before b FULL JOIN t07_after a USING(item_id)
   WHERE a.item_id IS NULL OR b.item_id IS NULL
      OR a.l2a IS DISTINCT FROM b.l2a
      OR a.l2c IS DISTINCT FROM b.l2c
      OR a.l3b IS DISTINCT FROM b.l3b
 ) THEN RAISE EXCEPTION 'T07_SALY_BASE_CANDIDATE_PARITY_FAILED'; END IF;
END
\$qa\$;
ROLLBACK;
SQL
psql -X -v ON_ERROR_STOP=1 -f "$SQL" >/dev/null
echo 'T07|PASS'
