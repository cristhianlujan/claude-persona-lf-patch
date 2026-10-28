#!/usr/bin/env bash
# LF Input Governance P10 — isolated PG17.6 process-boundary test.
# Requires Docker and an available postgres:17.6 image; no Supabase access.
set -euo pipefail
umask 077
command -v docker >/dev/null || { echo 'NO_VERIFICADO: docker not present'; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
docker run -i --rm --network none --cap-drop ALL --security-opt no-new-privileges \
  --read-only --tmpfs /tmp:rw,nosuid,nodev,size=256m \
  --user postgres --mount "type=bind,src=$here,dst=/ig,readonly" \
  --entrypoint /bin/bash postgres:17.6 -seu <<'ISOLATED_SCRIPT'
set -euo pipefail
umask 077
[[ "$(id -u)" -ne 0 ]] || { echo "BLOCK: root"; exit 2; }
[[ "$(postgres --version)" == *"17.6"* ]] || { echo "BLOCK: wrong PG version"; exit 2; }
data="$(mktemp -d /tmp/ig_p10_data_XXXXXXXX)"
sock="$(mktemp -d /tmp/ig_p10_sock_XXXXXXXX)"
started=0
cleanup() {
 if [[ "$started" == 1 ]]; then
   pg_ctl -D "$data" -m immediate -w stop >/dev/null 2>&1 || true
 fi
}
trap cleanup EXIT
initdb -A trust -U ig_n4_local --no-sync -D "$data" >/dev/null
pg_ctl -D "$data" -l "$data/pg.log" \
 -o "-c listen_addresses= -c unix_socket_directories=$sock -c unix_socket_permissions=0700" \
 -w start >/dev/null
started=1
export PGHOST="$sock" PGDATABASE=lf_ig_n4_isolated_ci PGUSER=ig_n4_local
unset PGHOSTADDR PGSERVICE PGSERVICEFILE DATABASE_URL PGPASSWORD PGOPTIONS || true
createdb "$PGDATABASE"
psql -X -w -v ON_ERROR_STOP=1 -q -f /ig/ig_p10_pg17_6_process_fixture_20261028.sql >/dev/null
source=/ig/ig_p10_forward_only_scope_boundary_candidate_20261028.sql
[[ "$(grep -Fxc "BEGIN;" "$source")" -eq 1 &&
   "$(grep -Fxc "ROLLBACK;" "$source")" -eq 1 ]] ||
 { echo "FAIL: unsafe candidate transaction boundary"; exit 1; }
{
 echo "BEGIN;"
 awk '
  $0=="BEGIN;" {started++;inside=1;next}
  $0=="ROLLBACK;" {finished++;inside=0;next}
  inside {print}
  END {if(started!=1||finished!=1)exit 4}
 ' "$source"
 cat <<'SQL'
DO $cases$
DECLARE v_error text;
BEGIN
 IF (SELECT count(*) FROM programacion.ig_n4_legacy_scope_frozen_v1 WHERE source_code='IG_DERIVED')<>1
 OR (SELECT count(*) FROM programacion.ig_n4_legacy_scope_frozen_v1 WHERE source_code='TREMED_GLOBAL')<>1
 OR (SELECT count(*) FROM programacion.ig_n4_legacy_scope_frozen_v1 WHERE source_code='IG_LEGACY')<>4
 OR (SELECT count(*) FROM programacion.ig_n4_legacy_scope_frozen_v1 WHERE source_code='TREMED_OWN')<>4
 THEN RAISE EXCEPTION 'P10_BASELINE_COUNT_FAILED'; END IF;
 RAISE NOTICE 'P10_CASE|HISTORICAL_PARITY|PASS';

 -- A candidate with physical links must not be promoted without scope approval.
 BEGIN
  UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE id=200;
  RAISE EXCEPTION 'P10_PROBE_PROMOTION_UNBLOCKED' USING ERRCODE='P9000';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
  GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  IF v_error IS DISTINCT FROM 'IG_P10_SCOPE_AUTHORITY_REQUIRED_ON_CANDIDATE_PROMOTION'
  THEN RAISE EXCEPTION 'P10_UNEXPECTED_PROMOTION_ERROR:%',v_error; END IF;
 END;
 RAISE NOTICE 'P10_CASE|PROMOTION_DENIED|PASS';

 BEGIN
  INSERT INTO lf_ops.reglas_pantallas(pantalla_id,regla_id) VALUES(3,100);
  RAISE EXCEPTION 'P10_PROBE_LINK_UNBLOCKED' USING ERRCODE='P9000';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
  GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  IF v_error IS DISTINCT FROM 'IG_P10_SCOPE_AUTHORITY_REQUIRED_ON_NEW_PHYSICAL_LINK'
  THEN RAISE EXCEPTION 'P10_UNEXPECTED_LINK_ERROR:%',v_error; END IF;
 END;
 RAISE NOTICE 'P10_CASE|NEW_VIGENTE_LINK_DENIED|PASS';

 BEGIN
  INSERT INTO lf_ops.reglas(id,codigo,categoria,estado,es_transversal,valor_config)
  VALUES(400,'NEW_ACTIVE','FIXTURE','VIGENTE',false,
  '{"applicability_v1":{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","id"],"op":"EQ","value":4}],"any":[]}}'::jsonb);
  RAISE EXCEPTION 'P10_PROBE_ACTIVE_UNBLOCKED' USING ERRCODE='P9000';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
  GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  IF v_error IS DISTINCT FROM 'IG_P10_SCOPE_AUTHORITY_REQUIRED_ON_NEW_ACTIVE_SELECTOR'
  THEN RAISE EXCEPTION 'P10_UNEXPECTED_ACTIVE_ERROR:%',v_error; END IF;
 END;
 RAISE NOTICE 'P10_CASE|NEW_ACTIVE_DENIED|PASS';

 BEGIN
  UPDATE lf_ops.reglas SET valor_config=
  '{"applicability_v1":{"status":"UNRESOLVED"}}'::jsonb WHERE id=100;
  RAISE EXCEPTION 'P10_PROBE_SELECTOR_CHANGE_UNBLOCKED' USING ERRCODE='P9000';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
  GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  IF v_error IS DISTINCT FROM 'IG_P10_SCOPE_AUTHORITY_REQUIRED_ON_SELECTOR_CHANGE'
  THEN RAISE EXCEPTION 'P10_UNEXPECTED_SCOPE_CHANGE_ERROR:%',v_error; END IF;
 END;
 RAISE NOTICE 'P10_CASE|SELECTOR_CHANGE_DENIED|PASS';

 -- Candidate drafting is allowed; it is NOT operational publication.
 INSERT INTO lf_ops.reglas(id,codigo,categoria,estado,es_transversal,valor_config)
 VALUES(401,'DRAFT_SELECTOR','FIXTURE','CANDIDATO',false,
  '{"applicability_v1":{"status":"ACTIVE"}}'::jsonb);
 RAISE NOTICE 'P10_CASE|CANDIDATE_AUTHORING_ALLOWED|PASS';

 -- New candidate links remain available to Curator via source data,
 -- but MUST NOT appear in either effective operational reader.
 INSERT INTO lf_ops.reglas_pantallas(pantalla_id,regla_id) VALUES (3,200);
 IF EXISTS(SELECT 1 FROM programacion.fn_input_effective_rule_links_v1(3,'INPUT_GOVERNANCE')
   WHERE regla_id=200 AND binding_source='LEGACY_EXPLICIT')
 OR EXISTS(SELECT 1 FROM programacion.fn_t_remed_effective_rules_v1(3,0.25)
   WHERE regla_id=200 AND origin='OWN')
 THEN RAISE EXCEPTION 'P10_NEW_CANDIDATE_PHYSICAL_LINK_ESCAPED'; END IF;
 RAISE NOTICE 'P10_CASE|CANDIDATE_LINK_REVIEW_ONLY|PASS';

 -- No physical links: technical status change cannot create global scope
 -- because the executable resolver now reads ONLY the frozen baseline.
 UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE id=300;
 IF EXISTS(SELECT 1 FROM programacion.fn_input_effective_rule_links_v1(3,'INPUT_GOVERNANCE')
   WHERE regla_id=300 AND binding_source='DERIVED_GLOBAL')
 THEN RAISE EXCEPTION 'P10_UNLINKED_PROMOTION_ESCAPED'; END IF;
 RAISE NOTICE 'P10_CASE|UNLINKED_NO_GLOBAL|PASS';

 INSERT INTO lf_ops.pantallas(id,module_id) VALUES(4,11);
 IF EXISTS(SELECT 1 FROM programacion.fn_input_effective_rule_links_v1(4,'INPUT_GOVERNANCE')
   WHERE binding_source='DERIVED_GLOBAL')
 OR EXISTS(SELECT 1 FROM programacion.fn_t_remed_effective_rules_v1(4,0.25)
   WHERE origin='GLOBAL')
 THEN RAISE EXCEPTION 'P10_NEW_SCREEN_IMPLICIT_GLOBAL'; END IF;
 RAISE NOTICE 'P10_CASE|NEW_SCREEN_NO_IMPLICIT_GLOBAL|PASS';

 -- Lifecycle deactivation remains available (no blanket lock on history).
 UPDATE lf_ops.reglas SET estado='CANDIDATO' WHERE id=100;
 IF EXISTS(SELECT 1 FROM programacion.fn_input_effective_rule_links_v1(3,'INPUT_GOVERNANCE')
    WHERE regla_id=100 AND binding_source='DERIVED_GLOBAL')
 THEN RAISE EXCEPTION 'P10_REVOKED_STILL_EFFECTIVE'; END IF;
 RAISE NOTICE 'P10_CASE|REVOCATION_ALLOWED|PASS';
END
$cases$;
ROLLBACK;
SQL
} | psql -X -w -A -t -F "|" -v ON_ERROR_STOP=1 > "$data/log.txt" 2>&1 ||
 { cat "$data/log.txt"; echo "FAIL: isolated P10 execution"; exit 1; }

for marker in HISTORICAL_PARITY PROMOTION_DENIED NEW_VIGENTE_LINK_DENIED \
 NEW_ACTIVE_DENIED SELECTOR_CHANGE_DENIED CANDIDATE_AUTHORING_ALLOWED \
 CANDIDATE_LINK_REVIEW_ONLY UNLINKED_NO_GLOBAL NEW_SCREEN_NO_IMPLICIT_GLOBAL REVOCATION_ALLOWED; do
 [[ "$(grep -Fc "P10_CASE|$marker|PASS" "$data/log.txt")" -eq 1 ]] ||
  { echo "FAIL: missing/duplicated case $marker"; cat "$data/log.txt"; exit 1; }
done
readback="$(psql -X -w -A -t -F "|" -v ON_ERROR_STOP=1 -c "
SELECT
 to_regclass('programacion.ig_n4_legacy_scope_frozen_v1') IS NULL,
 to_regprocedure('programacion.fn_ig_p10_forward_selector_admission_v1()') IS NULL,
 to_regprocedure('programacion.fn_ig_p10_forward_binding_admission_v1()') IS NULL,
 md5(pg_get_functiondef('programacion.fn_input_effective_rule_links_v1(integer,text)'::regprocedure))=
  '156247a925d74c6f4accd7a6d2508489',
 md5(pg_get_functiondef('programacion.fn_t_remed_effective_rules_v1(integer,numeric)'::regprocedure))=
  'ad5aecf15e12be5b55fdd1e8dac00295',
 (SELECT count(*)=3 FROM lf_ops.pantallas),
 (SELECT estado='CANDIDATO' FROM lf_ops.reglas WHERE id=200);
")"
[[ "$readback" == "t|t|t|t|t|t|t" ]] ||
 { echo "FAIL: rollback did not restore preimage: $readback"; exit 1; }
grep -F "P10_CASE|" "$data/log.txt"
echo "PASS_P10_FORWARD_BOUNDARY_PG17_6_10_CASES_ROLLBACK"
ISOLATED_SCRIPT
