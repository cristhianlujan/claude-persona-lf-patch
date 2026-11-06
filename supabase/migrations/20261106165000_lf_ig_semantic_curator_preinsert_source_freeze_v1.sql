-- IG L8: freeze exact governed source hashes inside the Curator's existing
-- BEFORE INSERT composition. No trigger/table added. This precedes Curator SHA and
-- the Evidence Verifier handoff. SOURCE_INTEGRITY_ONLY keeps its old behavior.
-- EKB: GOV-010, GOV-032, GOV-LF-RECEIPT-001, IG-EKB-READ-WITHOUT-SEMANTIC-PREFLIGHT-001.
-- Preflight on the exact LIVE function. Change fail-closed on version drift.
BEGIN;
DO $source_preflight$
DECLARE v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef(
    'programacion.fn_input_curator_compose_before_insert_v1()'::regprocedure))
    INTO v_md5;
  IF v_md5 IS DISTINCT FROM '54531263418fb9d9ba491fd1e4d702f7' THEN
    RAISE EXCEPTION 'IG_L8_CURATOR_PREINSERT_SOURCE_DRIFT:%',v_md5;
  END IF;
END $source_preflight$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_semantic_source_snapshot_v1(
  p_pantalla_id integer, p_family text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion','lf_ops'
AS $freeze$
DECLARE v_rows jsonb;
BEGIN
 IF p_family NOT IN ('RATE_LIMIT','SESSION') OR p_pantalla_id IS NULL THEN
   RAISE EXCEPTION 'IG_L8_SEMANTIC_SOURCE_FAMILY_UNSUPPORTED:%',p_family;
 END IF;
 WITH effective AS (
   SELECT r.*
   FROM programacion.fn_input_effective_rule_links_v1(
      p_pantalla_id,'INPUT_GOVERNANCE') links
   JOIN lf_ops.reglas r ON r.id=links.regla_id
   WHERE r.estado IN ('VIGENTE','CANDIDATO')
     AND NOT coalesce(r.pendiente_decision,false)
 ),
 source_rows AS (
   SELECT 'RATE_LIMIT'::text family,
     'lf_ops.politicas_rate_limit:'||p.rate_limit_policy_id::text ref,
     programacion.fn_v09_sha256_jsonb(jsonb_build_object(
       'policy',to_jsonb(p),'binding',to_jsonb(b),'rule',to_jsonb(r))) observed_sha256
   FROM lf_ops.pantallas_politicas b
   JOIN lf_ops.politicas_rate_limit p
     ON p.rate_limit_policy_id=b.rate_limit_policy_id
   JOIN effective r
     ON r.valor_config->>'rate_limit_policy_id'=p.rate_limit_policy_id::text
   WHERE p_family='RATE_LIMIT'
     AND b.pantalla_id=p_pantalla_id
     AND b.policy_kind='RATE_LIMIT' AND b.reference_role='rate_limit_policy_id'
   UNION ALL
   SELECT 'SESSION'::text,
     'lf_ops.reglas:'||r.id::text,
     programacion.fn_v09_sha256_jsonb(jsonb_build_object(
       'policy',to_jsonb(p),'binding',to_jsonb(b),'rule',to_jsonb(r)))
   FROM lf_ops.pantallas_politicas b
   JOIN lf_ops.politicas_sesion p
     ON p.session_policy_id=b.session_policy_id
   JOIN effective r
     ON r.valor_config->>'session_policy_id'=p.session_policy_id::text
   WHERE p_family='SESSION'
     AND b.pantalla_id=p_pantalla_id
     AND b.policy_kind='SESSION' AND b.reference_role='session_policy_id'
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'ref',ref,'observed_sha256',observed_sha256)
   ORDER BY family,ref),'[]'::jsonb)
 INTO v_rows FROM source_rows;
 IF jsonb_array_length(v_rows)=0 OR jsonb_array_length(v_rows)>47 THEN
   RAISE EXCEPTION 'IG_L8_CURATOR_SOURCE_INVENTORY_UNRESOLVED:%:%',
     p_pantalla_id,p_family;
 END IF;
 IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_rows) a(value)
    GROUP BY a.value->>'ref' HAVING count(*)>1
 ) THEN RAISE EXCEPTION 'IG_L8_CURATOR_DUPLICATE_SOURCE_REF:%',p_family; END IF;
 RETURN v_rows;
END;
$freeze$;

REVOKE ALL ON FUNCTION
 programacion.fn_input_governance_semantic_source_snapshot_v1(integer,text)
 FROM PUBLIC,anon,authenticated,service_role;

DO $compose$
DECLARE
 v_orig text;
 v_new text;
 v_anchor text:='  new.curator_sha256:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(';
 v_insert text;
BEGIN
 v_orig:=pg_get_functiondef('programacion.fn_input_curator_compose_before_insert_v1()'::regprocedure);
 IF (length(v_orig)-length(replace(v_orig,v_anchor,'')))/length(v_anchor)<>1 THEN
   RAISE EXCEPTION 'IG_L8_CURATOR_PREINSERT_ANCHOR_DRIFT';
 END IF;
 v_insert:=$addition$
  -- LF IG L8, pilot source freeze. BEFORE immutable insert; no extra trigger.
  -- Existing SOURCE_INTEGRITY_ONLY RUNs are unaffected.
  if new.family_code in ('RATE_LIMIT','SESSION') then
    declare
      v_semantic_run_scope jsonb;
      v_semantic_source_pins jsonb;
    begin
      select r.scope into v_semantic_run_scope
      from programacion.input_readiness_runs r where r.id=new.run_id;
      if v_semantic_run_scope->>'validator_semantic_mode'
            ='SELECTED_SEMANTIC_COMPARISON'
         and jsonb_typeof(v_semantic_run_scope->'validator_semantic_comparison_families')
            ='array'
         and v_semantic_run_scope->'validator_semantic_comparison_families'
             ? new.family_code then
        v_semantic_source_pins:=
          programacion.fn_input_governance_semantic_source_snapshot_v1(
            v_run.pantalla_id,new.family_code);
        new.curator_evidence:=new.curator_evidence||jsonb_build_object(
          'ig_semantic_source_snapshot_v1',v_semantic_source_pins);
      end if;
    end;
  end if;
  -- The preexisting curator fingerprint immediately below includes new pins.
$addition$;
 v_new:=replace(v_orig,v_anchor,v_insert||v_anchor);
 IF v_new=v_orig THEN RAISE EXCEPTION 'IG_L8_CURATOR_PATCH_NOOP'; END IF;
 EXECUTE rtrim(v_new,';'||E'\n')||';';
END $compose$;

DO $postcheck$
DECLARE v_fn text;
BEGIN
 v_fn:=pg_get_functiondef(
    'programacion.fn_input_curator_compose_before_insert_v1()'::regprocedure);
 IF position('fn_input_governance_semantic_source_snapshot_v1' IN v_fn)=0
   OR position('ig_semantic_source_snapshot_v1' IN v_fn)=0
   OR position('new.curator_sha256:=programacion.fn_v09_sha256_jsonb' IN v_fn)=0 THEN
   RAISE EXCEPTION 'IG_L8_CURATOR_PREINSERT_PIN_NOT_CONNECTED';
 END IF;
 IF has_function_privilege('anon',
    'programacion.fn_input_governance_semantic_source_snapshot_v1(integer,text)'::regprocedure,
    'EXECUTE') OR
    has_function_privilege('authenticated',
    'programacion.fn_input_governance_semantic_source_snapshot_v1(integer,text)'::regprocedure,
    'EXECUTE') THEN
    RAISE EXCEPTION 'IG_L8_UNAUTHORIZED_SOURCE_SCAN';
 END IF;
END $postcheck$;
-- Per-screen tests belong in sandbox and are never a deployment prerequisite.
COMMIT;
