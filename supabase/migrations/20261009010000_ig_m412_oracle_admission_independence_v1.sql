-- IG M4.12 package 1: oracle admission measures independence of derived conclusions, not of shared canonical sources.
-- Scope: replaces only programacion.fn_input_validator_oracle_admission_v1(bigint,text). No table/data change,
-- no Curator or Validator rewiring, no new judge. The oracle stays comparison-only
-- (semantic_pass_authorized=false, promotion_authorized=false, production_authorized=false).
--
-- Why: the admission called the independence measure with an empty context, so the 7 canonical readers/hash
-- utilities shared by the Curator classifier and the oracle always ended in BLOCKED_NOT_INDEPENDENT, and the
-- function had no "admitted" outcome at all.
--
-- What changes:
--  1. A shared function is an earned exception only if it is a pure canonical reader/utility: unique name,
--     IMMUTABLE/STABLE, no programacion.input_* table, no DML, not a classifier/probe/semantic function.
--  2. Data dimension compares Curator-derived tables (programacion.input_*) read by each side's function closure,
--     computed by static scan; shared canonical lf_ops/lf_design sources are allowed.
--  3. Author dimension: producer = run.curator_identity, reviewer = ORACLE:<root>@<live md5>.
--  4. New outcome ADMITTED_COMPARISON_ONLY when version parity, INDEPENDENT measure and an implemented shadow
--     oracle hold. It replaces BLOCKED_INDEPENDENT_RECEIPT_UNPROVEN; payload carries independent_receipt_persisted=false.
--
-- Tested with ROLLBACK (see PR): 100/100 BLOCKED_NOT_INDEPENDENT before -> 4 ADMITTED_COMPARISON_ONLY +
-- 96 BLOCKED_ORACLE_NOT_IMPLEMENTED after; negatives N1/N2/N4/N5 all NOT_INDEPENDENT.
CREATE OR REPLACE FUNCTION programacion.fn_input_validator_oracle_admission_v1(p_run_id bigint, p_family_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
 v_run record;
 v_strategy jsonb;
 v_registry record;
 v_root text;
 v_declared text;
 v_live text;
 v_measure jsonb;
 v_probe jsonb;
 v_oracle jsonb;
 v_family_count integer;
 v_payload jsonb;
 v_producer_root constant text := 'fn_input_governance_bootstrap_classify_v2';
 v_oracle_name text;
 v_shared text[];
 v_earned text[];
 v_pclosure text[];
 v_rclosure text[];
 v_pdata text[];
 v_rdata text[];
 v_ctx jsonb;
 v_curator text;
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

 v_oracle_name:=split_part(split_part(v_root,'(',1),'.',2);

 -- Pass 1: shared function closure between the Curator classifier and the oracle, no exceptions.
 v_probe:=public.lf_independent_assurance_measure_v1(
   'programacion',v_producer_root,v_oracle_name,6,'{}'::jsonb);
 IF v_probe->>'schema_version' IS DISTINCT FROM
      'LF_INDEPENDENT_ASSURANCE_MEASURE_V1' THEN
   RAISE EXCEPTION 'IG_INDEPENDENT_ORACLE_MEASURE_CONTRACT_UNVERIFIED';
 END IF;
 v_shared:=coalesce(ARRAY(
   SELECT jsonb_array_elements_text(v_probe->'dependency_dimension'->'shared_dependencies')),
   '{}'::text[]);

 -- A shared dependency is an earned exception only if it is a pure canonical reader/utility:
 -- unique name, immutable/stable, no Curator-conclusion table, no DML, not a classifier/probe.
 v_earned:=coalesce(ARRAY(
   SELECT f.name FROM unnest(v_shared) f(name)
   WHERE (SELECT count(*) FROM pg_proc p
          WHERE p.pronamespace='programacion'::regnamespace AND p.proname=f.name)=1
     AND EXISTS (SELECT 1 FROM pg_proc p
          WHERE p.pronamespace='programacion'::regnamespace AND p.proname=f.name
            AND p.provolatile IN ('i','s')
            AND p.prosrc !~* 'programacion\.input_[a-z_0-9]+'
            AND p.prosrc !~* '\m(insert\s+into|update\s+[a-z_.]+\s+set|delete\s+from|truncate)\M')
     AND f.name !~* '(probe|classify|semantic|validate|assess)'
   ORDER BY f.name),'{}'::text[]);

 -- Data dimension: only Curator-derived (conclusion) tables count; canonical sources may be shared.
 v_pclosure:=array_append(coalesce(public.lf_function_dependency_closure_qualified_v1(
   'programacion',v_producer_root,6),'{}'::text[]),v_producer_root);
 v_rclosure:=array_append(coalesce(public.lf_function_dependency_closure_qualified_v1(
   'programacion',v_oracle_name,6),'{}'::text[]),v_oracle_name);
 v_pdata:=coalesce(ARRAY(
   SELECT DISTINCT m[1] FROM pg_proc p,
     regexp_matches(p.prosrc,'programacion\.(input_[a-z_0-9]+)','g') m
   WHERE p.pronamespace='programacion'::regnamespace
     AND p.proname IN (SELECT regexp_replace(x,'^programacion\.','') FROM unnest(v_pclosure) x)
   ORDER BY 1),'{}'::text[]);
 v_rdata:=coalesce(ARRAY(
   SELECT DISTINCT m[1] FROM pg_proc p,
     regexp_matches(p.prosrc,'programacion\.(input_[a-z_0-9]+)','g') m
   WHERE p.pronamespace='programacion'::regnamespace
     AND p.proname IN (SELECT regexp_replace(x,'^programacion\.','') FROM unnest(v_rclosure) x)
   ORDER BY 1),'{}'::text[]);

 SELECT r.curator_identity INTO v_curator
 FROM programacion.input_readiness_runs r WHERE r.id=p_run_id;
 v_ctx:=jsonb_build_object(
   'adjudicated_dependency_exceptions',to_jsonb(v_earned),
   'producer_data_refs',to_jsonb(v_pdata),
   'reviewer_data_refs',to_jsonb(v_rdata),
   'reviewer_author_ref','ORACLE:'||v_root||'@'||v_live);
 IF nullif(btrim(v_curator),'') IS NOT NULL THEN
   v_ctx:=v_ctx||jsonb_build_object('producer_author_ref',v_curator);
 END IF;

 v_measure:=public.lf_independent_assurance_measure_v1(
   'programacion',v_producer_root,v_oracle_name,6,v_ctx);
 IF v_measure->>'schema_version' IS DISTINCT FROM
      'LF_INDEPENDENT_ASSURANCE_MEASURE_V1' THEN
   RAISE EXCEPTION 'IG_INDEPENDENT_ORACLE_MEASURE_CONTRACT_UNVERIFIED';
 END IF;
 -- Comparison-only oracle is never a decision or an independent receipt.
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
   'earned_dependency_exceptions',to_jsonb(v_earned),
   'unearned_shared_dependencies',to_jsonb(coalesce(ARRAY(
      SELECT unnest(v_shared) EXCEPT SELECT unnest(v_earned)),'{}'::text[])),
   'derived_data_refs',jsonb_build_object('producer',to_jsonb(v_pdata),'reviewer',to_jsonb(v_rdata)),
   'shadow_implemented',coalesce((v_oracle->>'implemented')::boolean,false),
   'shadow_classification',v_oracle->>'classification',
   'comparison_only',true,'semantic_pass_authorized',false,
   'promotion_authorized',false,'production_authorized',false,
   'independent_receipt_persisted',false,
   'admission_status',case
     when v_live<>v_declared then 'BLOCKED_VERSION_DRIFT'
     when v_measure->>'state'<>'INDEPENDENT' then 'BLOCKED_NOT_INDEPENDENT'
     when not coalesce((v_oracle->>'implemented')::boolean,false)
       then 'BLOCKED_ORACLE_NOT_IMPLEMENTED'
     else 'ADMITTED_COMPARISON_ONLY' end
 );
 RETURN v_payload || jsonb_build_object(
   'admission_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
END;
$function$
;

DO $ig_admission_readback$
BEGIN
  IF pg_get_functiondef('programacion.fn_input_validator_oracle_admission_v1(bigint,text)'::regprocedure)
       NOT LIKE '%ADMITTED_COMPARISON_ONLY%'
     OR pg_get_functiondef('programacion.fn_input_validator_oracle_admission_v1(bigint,text)'::regprocedure)
       NOT LIKE '%earned_dependency_exceptions%' THEN
    RAISE EXCEPTION 'IG_ORACLE_ADMISSION_READBACK_MISMATCH';
  END IF;
END
$ig_admission_readback$;
