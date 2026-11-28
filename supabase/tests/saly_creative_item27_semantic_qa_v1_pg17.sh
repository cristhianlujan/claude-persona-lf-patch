#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
: "${PGHOST:?}" "${PGDATABASE:?}" "${PGUSER:?}"
[[ "$PGHOST" == 127.0.0.1 && "$PGDATABASE" == lf_item27_semqa_test && "$PGUSER" == postgres ]] || { echo PR3_BLOCK_NON_DISPOSABLE_DB; exit 2; }
psql -XAt -v ON_ERROR_STOP=1 -c 'show server_version_num' | grep -qE '^17[0-9]{4}$' || { echo PR3_BLOCK_NON_PG17; exit 2; }

shopt -s nullglob
MIGS=("$ROOT"/supabase/migrations/*_lf_saly_creative_lf_item27_semantic_qa_v1.sql)
FIX="$ROOT/supabase/tests/saly_creative_item27_semantic_qa_v1_fixture_pg17.sql"
[[ "${#MIGS[@]}" -eq 1 && -f "$FIX" ]] || { echo PR3_BLOCK_FILES_MISSING; exit 2; }
MIG="${MIGS[0]}"
BODY="$(mktemp)"
POS="$(mktemp)"
NEG="$(mktemp)"
trap 'rm -f "$BODY" "$POS" "$NEG"' EXIT
sed -e '/^[[:space:]]*BEGIN;[[:space:]]*$/d' -e '/^[[:space:]]*COMMIT;[[:space:]]*$/d' "$MIG" > "$BODY"

psql -X -v ON_ERROR_STOP=1 -f "$FIX" >/dev/null
cat >"$POS" <<SQL
\set ON_ERROR_STOP on
BEGIN;
\i $BODY
DO \$qa\$
DECLARE s jsonb;
BEGIN
 SELECT acceptance_json->'semantic_qa' INTO STRICT s FROM saly.creative_order_items WHERE id=27;
 IF s->>'original_request_sha256' IS DISTINCT FROM '78160d6438c2908d469e9ece838b0a14b57eb317b1215cfb702e507e7bbb1f40'
 OR jsonb_array_length(s->'checks')<>5
 OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(s->'checks') x WHERE x->>'code'='LF_SEM_SCOPE_AND_ACTION')
 THEN RAISE EXCEPTION 'PR3_POSITIVE_ASSERTION_FAILED'; END IF;
END
\$qa\$;
ROLLBACK;
SQL
psql -X -v ON_ERROR_STOP=1 -f "$POS" >/dev/null
post="$(psql -XAt -v ON_ERROR_STOP=1 -c "select coalesce((acceptance_json ? 'semantic_qa')::text,'false') from saly.creative_order_items where id=27")"
[[ "$post" == false ]] || { echo PR3_POSITIVE_ROLLBACK_FAILED; exit 1; }
echo 'PR3_ITEM27_POSITIVE|PASS'

psql -X -v ON_ERROR_STOP=1 -f "$FIX" >/dev/null
cat >"$NEG" <<SQL
\set ON_ERROR_STOP on
BEGIN;
UPDATE saly.creative_orders
SET scope_json=jsonb_set(scope_json,'{owner_amendment,text}','"DRIFT"'::jsonb)
WHERE id=23;
\i $BODY
ROLLBACK;
SQL
set +e
out="$(psql -X -v ON_ERROR_STOP=1 -f "$NEG" 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || { echo PR3_NEGATIVE_UNEXPECTED_PASS; exit 1; }
grep -q 'LF_SEM_ORIGINAL_MESSAGES_HASH_DRIFT' <<<"$out" || { printf '%s\n' "$out"; echo PR3_NEGATIVE_WRONG_ERROR; exit 1; }
post="$(psql -XAt -v ON_ERROR_STOP=1 -c "select scope_json#>>'{owner_amendment,text}' from saly.creative_orders where id=23")"
[[ "$post" == 'Los montos deben ser reales no texto' ]] || { echo PR3_NEGATIVE_ROLLBACK_FAILED; exit 1; }
echo 'PR3_ITEM27_NEGATIVE|PASS'
