#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PGHOST="${PGHOST:-127.0.0.1}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
[[ "$PGHOST" == 127.0.0.1 && "$PGUSER" == postgres ]] || { echo F3A_UNSAFE_TARGET; exit 2; }

shopt -s nullglob
F1S=("$ROOT"/supabase/migrations/*_lf_saly_creative_f1_enablement_v1.sql)
F3S=("$ROOT"/supabase/migrations/*_lf_saly_creative_lf_f3a_prompt_compile_v1.sql)
[[ "${#F1S[@]}" -eq 1 && "${#F3S[@]}" -eq 1 ]] || { echo F3A_CANDIDATE_FILES_INVALID; exit 3; }
F1="${F1S[0]}"
F3="${F3S[0]}"
FIXTURE="$ROOT/sandbox/creative_factory/f1_pg17/fixtures/f3a_item27_real_fixture_v1.sql"
VERIFY="$ROOT/supabase/tests/saly_creative_lf_f3a_prompt_compile_v1_independent.py"
[[ -f "$FIXTURE" && -f "$VERIFY" ]] || { echo F3A_REAL_FIXTURE_OR_VERIFIER_MISSING; exit 4; }
F1_SHA="$(sha256sum "$F1" | awk '{print $1}')"

export PGDATABASE=lf_creative_f1_ci
F1_CANDIDATE="$F1" F1_CANDIDATE_SHA256="$F1_SHA" bash "$ROOT/sandbox/creative_factory/f1_pg17/setup.sh" >/tmp/f3a_f1_setup.log 2>&1
grep -q 'F1_SETUP_PASS' /tmp/f3a_f1_setup.log

export PGDATABASE=postgres
dropdb --if-exists --maintenance-db=postgres lf_creative_f3a_test
createdb --maintenance-db=postgres -T lf_creative_f1_candidate lf_creative_f3a_test
export PGDATABASE=lf_creative_f3a_test

psql -X -v ON_ERROR_STOP=1 -f "$F3" >/tmp/f3a_migration.log 2>&1
grep -q 'LF_F3A_COMPILER_MIGRATION|PASS' /tmp/f3a_migration.log
psql -X -v ON_ERROR_STOP=1 -f "$FIXTURE" >/tmp/f3a_fixture.log 2>&1
grep -q 'F3A_REAL_FIXTURE|PASS|order=9323|item=9327|tokens=109' /tmp/f3a_fixture.log

# Independent before/after snapshots: compiler must not create seals, runs or mutate fixture rows.
psql -XAt -v ON_ERROR_STOP=1 -c "
SELECT jsonb_build_object(
 'seal_count',(SELECT count(*) FROM saly.creative_lf_prompt_seal_v1 WHERE item_id=9327),
 'run_count',(SELECT count(*) FROM saly.creative_runs WHERE order_id=9323 OR item_id=9327),
 'order_count',(SELECT count(*) FROM saly.creative_orders WHERE id=9323),
 'item_count',(SELECT count(*) FROM saly.creative_order_items WHERE id=9327),
 'order_status',(SELECT status FROM saly.creative_orders WHERE id=9323),
 'item_status',(SELECT status FROM saly.creative_order_items WHERE id=9327)
)::text;" > /tmp/f3a_before.json

# Two independent compiler executions over the same real-data fixture.
for n in 1 2; do
  psql -XAt -v ON_ERROR_STOP=1 -c "
  WITH r AS (SELECT saly.creative_lf_prompt_compile_v1(9327) AS c)
  SELECT jsonb_build_object(
    'schema_version',c->>'schema_version',
    'prompt_b64',encode(convert_to(c->>'prompt_text','UTF8'),'base64'),
    'prompt_sha256',c->>'prompt_sha256',
    'inputs_sha256',c->>'inputs_sha256',
    'prompt_sealed',(c->>'prompt_sealed')::boolean,
    'native_transmitted',(c->>'native_transmitted')::boolean,
    'ready_for_independent_review',(c->>'ready_for_independent_review')::boolean
  )::text FROM r;" > "/tmp/f3a_run${n}.json"
done

psql -XAt -v ON_ERROR_STOP=1 -c "
SELECT jsonb_build_object(
 'seal_count',(SELECT count(*) FROM saly.creative_lf_prompt_seal_v1 WHERE item_id=9327),
 'run_count',(SELECT count(*) FROM saly.creative_runs WHERE order_id=9323 OR item_id=9327),
 'order_count',(SELECT count(*) FROM saly.creative_orders WHERE id=9323),
 'item_count',(SELECT count(*) FROM saly.creative_order_items WHERE id=9327),
 'order_status',(SELECT status FROM saly.creative_orders WHERE id=9323),
 'item_status',(SELECT status FROM saly.creative_order_items WHERE id=9327)
)::text;" > /tmp/f3a_after.json

# Build expected governed bytes independently from the fixture tables and context function,
# never from the compiler's self-declared qa_checks.
psql -XAt -v ON_ERROR_STOP=1 -c "
WITH b AS (
  SELECT o.id AS order_id,o.scope_json,i.id AS item_id,i.code AS item_code,
         i.acceptance_json,i.context_json,saly.creative_lf_item_context_v1(i.id) AS ctx
  FROM saly.creative_orders o JOIN saly.creative_order_items i ON i.order_id=o.id
  WHERE o.id=9323 AND i.id=9327
), x AS (
  SELECT *,
    coalesce(scope_json->'owner_amendment','null'::jsonb) AS amendment,
    context_json->'screen_spec' AS screen,
    coalesce(context_json->'authorized_sample_amounts','{}'::jsonb) AS amounts,
    acceptance_json->'semantic_qa' AS sem,
    ctx->'tokens' AS toks,
    ctx->'source_refs' AS assets
  FROM b
), inp AS (
  SELECT *, jsonb_build_object(
    'schema_version','LF_PROMPT_INPUT_F3A_V1',
    'order_id',order_id,
    'item_id',item_id,
    'item_code',item_code,
    'literal_request',scope_json->>'literal_request',
    'owner_amendment',amendment,
    'screen_spec',screen,
    'authorized_sample_amounts',amounts,
    'semantic_qa',sem,
    'identity_tokens',toks,
    'frozen_assets',assets
  ) AS inputs
  FROM x
), snap AS (
  SELECT jsonb_agg(jsonb_build_object(
      'version_id',identity_version_id,'sha256',value_sha256,'role',role)
      ORDER BY identity_version_id) AS s
  FROM saly.creative_context_tokens WHERE context_set_id=9006
)
SELECT jsonb_build_object(
 'literal_b64',encode(convert_to(scope_json->>'literal_request','UTF8'),'base64'),
 'original_literal_b64',encode(convert_to(scope_json->>'original_literal_request','UTF8'),'base64'),
 'owner_amendment_b64',encode(convert_to(amendment::text,'UTF8'),'base64'),
 'screen_spec_b64',encode(convert_to(screen::text,'UTF8'),'base64'),
 'amounts_b64',encode(convert_to(amounts::text,'UTF8'),'base64'),
 'semantic_b64',encode(convert_to(sem::text,'UTF8'),'base64'),
 'original_messages_b64',encode(convert_to((sem->'original_messages')::text,'UTF8'),'base64'),
 'tokens_b64',encode(convert_to(toks::text,'UTF8'),'base64'),
 'assets_b64',encode(convert_to(assets::text,'UTF8'),'base64'),
 'inputs_b64',encode(convert_to(inputs::text,'UTF8'),'base64'),
 'snapshot_sha256',encode(extensions.digest(convert_to((SELECT s FROM snap)::text,'UTF8'),'sha256'),'hex')
)::text
FROM inp;" > /tmp/f3a_expected.json

python3 "$VERIFY"   --run1 /tmp/f3a_run1.json   --run2 /tmp/f3a_run2.json   --expected /tmp/f3a_expected.json   --before /tmp/f3a_before.json   --after /tmp/f3a_after.json

# Explicit ACL and protected-production-ID checks remain outside the byte verifier.
psql -XAt -v ON_ERROR_STOP=1 <<'SQL'
DO $$
BEGIN
  IF has_function_privilege('anon','saly.creative_lf_prompt_compile_v1(bigint)','EXECUTE')
     OR has_function_privilege('authenticated','saly.creative_lf_prompt_compile_v1(bigint)','EXECUTE')
     OR has_function_privilege('service_role','saly.creative_lf_prompt_compile_v1(bigint)','EXECUTE')
  THEN RAISE EXCEPTION 'F3A_ACL_TOO_BROAD'; END IF;
  IF EXISTS (SELECT 1 FROM saly.creative_orders WHERE id=23)
     OR EXISTS (SELECT 1 FROM saly.creative_order_items WHERE id=27)
  THEN RAISE EXCEPTION 'F3A_PROTECTED_PRODUCTION_ID_PRESENT_IN_CI'; END IF;
  RAISE NOTICE 'F3A_ACL_AND_PROTECTED_ID|PASS';
END $$;
SQL

echo F3A_REAL_ITEM27_PG17_PASS
