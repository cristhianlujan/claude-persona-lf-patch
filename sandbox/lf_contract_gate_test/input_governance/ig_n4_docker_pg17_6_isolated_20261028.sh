#!/usr/bin/env bash
# LF IG G3 — isolated PostgreSQL 17.6 certification candidate via Docker.
# NO Supabase credentials, NO Router, NO network, NO source DB connection.
# Developer-run only on a machine with Docker and the postgres:17.6 image.
# The Docker daemon pulls the image before executing the --network none job.
set -euo pipefail
umask 077
command -v docker >/dev/null || { echo "NO_VERIFICADO: docker not present"; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"

docker run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
  --read-only --tmpfs /tmp:rw,nosuid,nodev,size=256m \
  --user postgres --mount "type=bind,src=$here,dst=/ig,readonly" \
  --entrypoint /bin/bash postgres:17.6 -ceu '
set -euo pipefail
umask 077
[[ "$(id -u)" -ne 0 ]] || { echo "BLOCK: root forbidden"; exit 2; }
[[ "$(postgres --version)" == *"17.6"* ]] || { echo "BLOCK: PG17.6 required"; exit 2; }

data="$(mktemp -d /tmp/lf_ig_n4_data_XXXXXXXX)"
sock="$(mktemp -d /tmp/lf_ig_n4_socket_XXXXXXXX)"
log="$data/server.log"
out="$data/results.txt"
started=0
cleanup() {
  if [[ "$started" == 1 ]]; then
    pg_ctl -D "$data" -m immediate -w stop >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
initdb -A trust -U ig_n4_local --no-sync -D "$data" >/dev/null
pg_ctl -D "$data" -l "$log" \
  -o "-c listen_addresses= -c unix_socket_directories=$sock -c unix_socket_permissions=0700" \
  -w start >/dev/null
started=1
export PGHOST="$sock" PGUSER=ig_n4_local PGDATABASE=lf_ig_n4_isolated_ci
unset PGSERVICE PGSERVICEFILE DATABASE_URL PGHOSTADDR PGOPTIONS PGPASSWORD || true
createdb "$PGDATABASE"
psql -X -w -v ON_ERROR_STOP=1 -q \
  -f /ig/ig_n4_pg17_6_sanitized_fixture_20261028.sql >/dev/null

# Candidate DDL must have exactly one outer BEGIN and one final ROLLBACK.
[[ "$(grep -cx "BEGIN;" /ig/ig_n4_clause_matcher_hardened_candidate_20261028.sql)" == 1 ]]
[[ "$(grep -cx "ROLLBACK;" /ig/ig_n4_clause_matcher_hardened_candidate_20261028.sql)" == 1 ]]
{
cat <<'"'"'SQL'"'"'
BEGIN;
CREATE TEMP TABLE ig_n4_preimage ON COMMIT DROP AS
SELECT r.rule_id,p.screen_id,
  programacion.fn_input_rule_selector_matches_v1(r.selector,p.context) old_match
FROM public.ig_n4_rule_fixtures r CROSS JOIN public.ig_n4_screen_fixtures p;
SQL
awk '"'"'
  $0=="BEGIN;" { in_body=1; start++; next }
  $0=="ROLLBACK;" { in_body=0; finish++; next }
  in_body { print }
  END { if(start!=1 || finish!=1) exit 5 }
'"'"' /ig/ig_n4_clause_matcher_hardened_candidate_20261028.sql
cat /ig/ig_n4_preclass_synthetic_matcher_v2_20261028.sql
cat <<'"'"'SQL'"'"'
SELECT '"'"'PARITY'"'"',
 count(*),
 count(*) FILTER(WHERE old_match),
 count(*) FILTER(WHERE new_match),
 count(*) FILTER(WHERE old_match IS DISTINCT FROM new_match),
 count(DISTINCT rule_id),
 count(DISTINCT screen_id)
FROM (
 SELECT a.*,programacion.fn_input_rule_selector_matches_v1(r.selector,p.context) new_match
 FROM ig_n4_preimage a
 JOIN public.ig_n4_rule_fixtures r ON r.rule_id=a.rule_id
 JOIN public.ig_n4_screen_fixtures p ON p.screen_id=a.screen_id
) results;
ROLLBACK;
SQL
} | psql -X -w -A -t -F "|" -v ON_ERROR_STOP=1 > "$out"

[[ "$(grep -Ec "^T[0-9]{2}\|" "$out")" -eq 28 ]] ||
  { echo "FAIL: missing 28 matcher cases"; exit 1; }
if grep -E "^T[0-9]{2}\|" "$out" | grep -Evq "\|PASS$"; then
  echo "FAIL: matcher vector mismatch"; exit 1
fi
grep -Fxq "PARITY|812|52|52|0|14|58" "$out" ||
  { echo "FAIL: active-selector parity mismatch"; exit 1; }
readback="$(psql -X -w -A -t -F "|" -v ON_ERROR_STOP=1 -c "
SELECT md5(pg_get_functiondef(
  '"'"'programacion.fn_input_rule_selector_matches_v1(jsonb,jsonb)'"'"'::regprocedure)),
 md5(pg_get_functiondef(
  '"'"'programacion.fn_input_rule_selector_clause_matches_v1(jsonb,jsonb)'"'"'::regprocedure)),
 to_regprocedure(
  '"'"'programacion.fn_input_rule_selector_clause_schema_valid_v1(jsonb)'"'"') IS NULL;
")"
[[ "$readback" == "3b912c7872aceff83de24e9e8d1ad934|1123257c0c6c7eb1e2aa26783f3ccc0a|t" ]] ||
  { echo "FAIL: post-ROLLBACK source changed"; exit 1; }

echo "PASS_G3_PG17_6_ISOLATED_28_VECTORS_812_PARITY_ROLLBACK"
echo "PARITY|812|52|52|0|14|58"
'
