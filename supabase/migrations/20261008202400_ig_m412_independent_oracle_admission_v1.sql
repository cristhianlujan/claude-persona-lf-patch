-- IG M4.12: non-decisional admission check over existing independent review measure.
-- No new judge, no new review engine, no new tables, no Curator/Validator rewiring.
-- BLOCKED is an oracle-admission result only (not run / family lifecycle status).
CREATE FUNCTION programacion.fn_input_validator_oracle_admission_v1(
 p_run_id bigint,
 p_family_code text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog'
AS $ig_oracle_admission$
DECLARE
 v_run record;
 v_strategy jsonb;
 v_registry record;
 v_root text;
 v_declared text;
 v_live text;
 v_measure jsonb;
 v_oracle jsonb;
 v_family_count integer;
 v_payload jsonb;
BEGIN
 SELECT r.id,r.pantalla_id,r.version_id,r.status,r.source_snapshot_sha256,
        r.contract_snapshot_sha256
 INTO v_run
 FROM programacion.input_readiness_runs r WHERE r.id=p_run_id;
 IF NOT FOUND OR p_run_id IS NULL OR p_run_id<=0
    OR nullif(btrim(p_family_code),'') IS NULL THEN
   RAISE EXCEPTION 'IG_INDEPENDENT_ORACLE_RUN_OR_FAMILY_UNRESOLVED';
 END IF;
 SELECT count(*) INTO v_family_count
 FROM programacion.input_family_assessments a
 WHERE a.run_id=p_run_id AND a.family_code=p_family_code;
 IF v_family_count<>1 THEN
   RAISE EXCEPTION 'IG_INDEPENDENT_ORACLE_FAMILY_NOT_IN_RUN:%:%',p_run_id,p_family_code;
 END IF;
 SELECT c.especificacion->'families'->p_family_code->'validator_oracle_strategy' policy,
        c.id contract_id
 INTO v_registry
 FROM programacion.contratos c
 WHERE c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
   AND c.version_id=v_run.version_id AND c.estado='defined'
 ORDER BY c.id DESC LIMIT 1;
 v_strategy:=v_registry.policy;
 IF v_strategy IS NULL OR jsonb_typeof(v_strategy)<>'object'
   OR v_strategy->>'strategy' IS DISTINCT FROM 'SHADOW_FAMILY_POLICY_ORACLE_V2'
   OR v_strategy->>'activation_state'
      IS DISTINCT FROM 'DECLARED_FOR_M4_INDEPENDENT_ORACLE'
   OR v_strategy->>'current_validator_independence_claim' IS DISTINCT FROM 'false' THEN
   RAISE EXCEPTION 'IG_INDEPENDENT_ORACLE_FAMILY_POLICY_NOT_ADMISSIBLE:%',p_family_code;
 END IF;
 v_root:=nullif(v_strategy->>'priority_oracle_function','');
 v_declared:=nullif(v_strategy->>'priority_oracle_version_md5','');
 IF v_root IS NULL OR v_declared IS NULL OR v_declared !~ '^[0-9a-f]{32}$'
    OR v_root !~ '^programacion\.[a-z0-9_]+\(integer,text,bigint\)$' THEN
   RAISE EXCEPTION 'IG_INDEPENDENT_ORACLE_POLICY_IDENTITY_INVALID:%',p_family_code;
 END IF;
 SELECT md5(pg_get_functiondef(p.oid)) INTO v_live
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='programacion'
   AND p.oid=to_regprocedure(v_root);
 IF v_live IS NULL THEN
   RAISE EXCEPTION 'IG_INDEPENDENT_ORACLE_REGISTERED_FUNCTION_MISSING:%',v_root;
 END IF;

 -- Existing transversal measure, never a second judge. Notably it checks
 -- function dependency, source-data and reviewer-author dimensions.
 v_measure:=public.lf_independent_assurance_measure_v1(
   'programacion',
   'fn_input_governance_bootstrap_classify_v2',
   split_part(split_part(v_root,'(',1),'.',2),
   6,'{}'::jsonb
 );
 IF v_measure->>'schema_version' IS DISTINCT FROM
      'LF_INDEPENDENT_ASSURANCE_MEASURE_V1' THEN
   RAISE EXCEPTION 'IG_INDEPENDENT_ORACLE_MEASURE_CONTRACT_UNVERIFIED';
 END IF;
 -- Comparison-only oracle is never a decision or an independent receipt.
 -- Call only if the registered source is current and the function matches
 -- the known non-mutating shadow contract. Version drift must fail closed.
 IF v_live=v_declared
    AND v_root='programacion.fn_input_governance_shadow_priority_oracle_v2(integer,text,bigint)' THEN
   v_oracle:=programacion.fn_input_governance_shadow_priority_oracle_v2(
      v_run.pantalla_id,p_family_code,v_run.version_id);
 ELSE
   v_oracle:=jsonb_build_object('implemented',false,
     'comparison_only',true,'decisional',false,
     'reason','UNADMITTED_ORACLE_VERSION_OR_ROOT');
 END IF;

 v_payload:=jsonb_build_object(
   'schema_version','IG_INDEPENDENT_ORACLE_ADMISSION_V1',
   'run_id',p_run_id,'pantalla_id',v_run.pantalla_id,
   'family_code',p_family_code,'contract_id',v_registry.contract_id,
   'policy_strategy',v_strategy->>'strategy',
   'oracle_root',v_root,'declared_function_md5',v_declared,
   'live_function_md5',v_live,'version_parity',v_live=v_declared,
   'independence_measure',v_measure,
   'independence_state',v_measure->>'state',
   'shadow_implemented',coalesce((v_oracle->>'implemented')::boolean,false),
   'shadow_classification',v_oracle->>'classification',
   'comparison_only',true,'semantic_pass_authorized',false,
   'promotion_authorized',false,'production_authorized',false,
   'admission_status',case
     when v_live<>v_declared then 'BLOCKED_VERSION_DRIFT'
     when v_measure->>'state'<>'INDEPENDENT' then 'BLOCKED_NOT_INDEPENDENT'
     when not coalesce((v_oracle->>'implemented')::boolean,false)
       then 'BLOCKED_ORACLE_NOT_IMPLEMENTED'
     else 'BLOCKED_INDEPENDENT_RECEIPT_UNPROVEN' end
 );
 RETURN v_payload || jsonb_build_object(
   'admission_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
END;
$ig_oracle_admission$;

REVOKE ALL ON FUNCTION programacion.fn_input_validator_oracle_admission_v1(bigint,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION programacion.fn_input_validator_oracle_admission_v1(bigint,text) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION programacion.fn_input_validator_oracle_admission_v1(bigint,text) TO service_role;

COMMENT ON FUNCTION programacion.fn_input_validator_oracle_admission_v1(bigint,text)
IS 'M4.12 fail-closed read-only oracle admission; delegates to LF_INDEPENDENT_ASSURANCE_MEASURE_V1, checks exact policy/function version, never asserts semantic PASS. Needs real verified independent reviewer evidence before Validator activation.';
