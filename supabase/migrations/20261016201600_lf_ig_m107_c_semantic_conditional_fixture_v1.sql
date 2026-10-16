-- M10.7 C: one-screen/three-family reversible integration check.
-- Must fail in Train on any false PASS, stale source, missing trigger or residue.
DO $test$
DECLARE
 v_code constant text:='IG-M107-C-SEMANTIC-GRAPH-CONDITIONAL-035';
 v_run_id bigint; v_run programacion.input_readiness_runs%rowtype;
 v_family programacion.input_family_assessments%rowtype;
 v_prop programacion.input_gap_proposals%rowtype;
 v_curator jsonb; v_validator text; v_component bigint;
 v_code_family text; v_assertions jsonb; v_assertion jsonb; v_eval jsonb;
 v_sha text; v_evidence jsonb; v_physical jsonb; v_bad jsonb;
 v_parent_has_contract boolean;
 v_ref jsonb; v_obs jsonb; v_readbacks jsonb;
 v_plan jsonb; v_triggers jsonb; v_family_times jsonb:='[]'::jsonb;
 v_family_trigger_count int; v_proposal_trigger_count int;
 v_before_count int; v_family_success int:=0; v_negative text;
 v_proposal_success boolean:=false;
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN
   RAISE EXCEPTION 'IG_M107_C_EKB_ALREADY_EXISTS'; END IF;
 IF (SELECT max(id) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>933
 OR (SELECT status FROM programacion.input_readiness_runs WHERE id=933)<>'COMPLETED'
 THEN RAISE EXCEPTION 'IG_M107_C_SAMPLE_SCREEN_DRIFT'; END IF;
 IF position('if old.family_code in (''ACCESSIBILITY'',''MFA_OTP_SSO'') then'
   in pg_get_functiondef('programacion.fn_guard_input_validator_semantic_coherence_v512()'::regprocedure))=0
 THEN RAISE EXCEPTION 'IG_M107_C_CONDITIONAL_FUNCTION_MISSING'; END IF;
 SELECT count(*) INTO v_before_count FROM programacion.input_readiness_runs WHERE pantalla_id=43;
 BEGIN
   v_curator:=programacion.fn_input_governance_direct_step_v1(43,'MANUAL');
   IF v_curator->>'status' IS DISTINCT FROM 'VALIDATOR_RUNTIME_REQUIRED'
      OR v_curator->>'step' IS DISTINCT FROM 'CURATOR_MATERIALIZED'
   THEN RAISE EXCEPTION 'IG_M107_C_UNEXPECTED_CURATOR:%',left(v_curator::text,320); END IF;
   v_run_id:=(v_curator->>'run_id')::bigint;
   SELECT * INTO STRICT v_run FROM programacion.input_readiness_runs WHERE id=v_run_id;
   IF v_run.status<>'CURATING' OR v_run.pantalla_id<>43
      OR (SELECT count(*) FROM programacion.input_family_assessments WHERE run_id=v_run_id)<>47
   THEN RAISE EXCEPTION 'IG_M107_C_CURATOR_FIXTURE_INVALID'; END IF;
   SELECT id INTO STRICT v_component FROM programacion.componentes
    WHERE version_id=v_run.version_id AND componente_codigo='INPUT_VALIDATOR';
   v_validator:='INPUT_VALIDATOR:SQL:ig-governed-dispatch-v1:'||gen_random_uuid()::text;
   UPDATE programacion.input_readiness_runs SET status='VALIDATING',
     validator_identity=v_validator,validator_component_id=v_component WHERE id=v_run_id;
   SELECT * INTO STRICT v_run FROM programacion.input_readiness_runs WHERE id=v_run_id;
   IF v_run.status<>'VALIDATING'
    OR (programacion.fn_input_governance_continuation_currentness_v1(v_run_id)->>'continuation_current')<>'true'
   THEN RAISE EXCEPTION 'IG_M107_C_VALIDATING_NOT_CURRENT'; END IF;

   FOREACH v_code_family IN ARRAY ARRAY['SCREEN_IDENTITY','ACCESSIBILITY','MFA_OTP_SSO'] LOOP
     SELECT * INTO STRICT v_family FROM programacion.input_family_assessments
       WHERE run_id=v_run_id AND family_code=v_code_family AND validator_outcome='PENDING';
     SELECT EXISTS (
       SELECT 1 FROM programacion.input_family_assessments p
       CROSS JOIN LATERAL jsonb_array_elements(
        programacion.fn_input_validator_evidence_rehydrate_v1(p.validator_evidence)->'assertions') a(val)
       WHERE p.run_id=v_run.supersedes_run_id AND p.family_code=v_family.family_code
         AND a.val#>>'{source_ref,kind}'='CONTRACT') INTO v_parent_has_contract;
     IF v_run.supersedes_run_id IS NOT NULL AND NOT v_parent_has_contract THEN
       v_assertions:=programacion.fn_input_v58_build_assertions(v_run_id,v_run.supersedes_run_id,v_code_family);
     ELSE
       v_assertions:=programacion.fn_input_governance_bootstrap_assertions_v1(v_run_id,v_code_family);
     END IF;
     IF jsonb_typeof(v_assertions) IS DISTINCT FROM 'array'
         OR jsonb_array_length(v_assertions)<>1 THEN
       RAISE EXCEPTION 'IG_M107_C_UNEXPECTED_ASSERTION_SET:%',v_code_family; END IF;
     FOR v_assertion IN SELECT value FROM jsonb_array_elements(v_assertions) LOOP
       v_eval:=programacion.fn_input_evaluate_assertion(v_run_id,v_code_family,v_assertion);
       IF (v_eval->>'passed')::boolean IS NOT TRUE
         OR v_assertion->>'result' IS DISTINCT FROM 'PASS'
         OR v_assertion->>'source_observed_sha256' IS DISTINCT FROM v_eval->>'source_observed_sha256'
       THEN RAISE EXCEPTION 'IG_M107_C_POSITIVE_SOURCE_MISMATCH:%',v_code_family; END IF;
     END LOOP;
     v_sha:=programacion.fn_v09_sha256_jsonb(v_assertions);
     INSERT INTO programacion.input_validator_assertion_sets_v1(assertion_set_sha256,assertions)
     VALUES(v_sha,v_assertions) ON CONFLICT(assertion_set_sha256) DO NOTHING;
     IF (SELECT assertions FROM programacion.input_validator_assertion_sets_v1
          WHERE assertion_set_sha256=v_sha) IS DISTINCT FROM v_assertions
     THEN RAISE EXCEPTION 'IG_M107_C_ASSERTION_HASH_DRIFT:%',v_code_family; END IF;
     v_evidence:=jsonb_build_object(
       'component_id',v_component,'execution_id',gen_random_uuid()::text,
       'validated_curator_execution_id',v_family.curator_evidence->>'execution_id',
       'execution_mode','INDEPENDENT_VALIDATOR',
       'runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1',
       'direct_source_readback',true,'contract_revision',v_run.contract_revision,
       'source_snapshot_sha256',v_run.source_snapshot_sha256,
       'curator_sha256',v_family.curator_sha256,
       'semantic_depth_sha256',v_family.semantic_depth_sha256,
       'bootstrap_classifier_sha256',NULL,
       'semantic_conclusion_independence','UNPROVEN',
       'validation_phase','SOURCE_INTEGRITY',
       'semantic_comparison_requested',false,'semantic_independence_credited',false,
       'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
       'assertions',v_assertions);
     v_physical:=(v_evidence-'assertions')||
       jsonb_build_object('assertion_set_sha256',v_sha);
     IF programacion.fn_input_validator_evidence_rehydrate_v1(v_physical)
        IS DISTINCT FROM v_evidence THEN
       RAISE EXCEPTION 'IG_M107_C_EVIDENCE_ROUNDTRIP_DRIFT:%',v_code_family; END IF;
     IF v_code_family='SCREEN_IDENTITY' THEN
       v_bad:=jsonb_set(v_physical,'{source_snapshot_sha256}',
          to_jsonb(repeat('0',64)),true);
       v_negative:=NULL;
       BEGIN
         UPDATE programacion.input_family_assessments
         SET validator_outcome='PASS',validator_findings='[]'::jsonb,
             validator_evidence=v_bad,validator_identity=v_validator,
             validator_assessed_at=clock_timestamp() WHERE id=v_family.id;
       EXCEPTION WHEN OTHERS THEN v_negative:=SQLERRM; END;
       IF position('VALIDATOR_EVIDENCE_SOURCE_SNAPSHOT_MISMATCH' in coalesce(v_negative,''))=0
          OR (SELECT validator_outcome FROM programacion.input_family_assessments WHERE id=v_family.id)<>'PENDING'
       THEN RAISE EXCEPTION 'IG_M107_C_SOURCE_NEGATIVE_DID_NOT_REJECT:%',v_negative; END IF;
     END IF;
     EXECUTE 'EXPLAIN (ANALYZE,FORMAT JSON)
       UPDATE programacion.input_family_assessments
       SET validator_outcome=$1,validator_findings=$2,
           validator_evidence=$3,validator_identity=$4,
           validator_assessed_at=clock_timestamp()
       WHERE id=$5' INTO v_plan
       USING 'PASS'::text,'[]'::jsonb,v_physical,v_validator,v_family.id;
     v_triggers:=coalesce(v_plan->0->'Triggers','[]'::jsonb);
     SELECT count(*) INTO v_family_trigger_count
     FROM jsonb_array_elements(v_triggers) t(x)
     WHERE t.x->>'Trigger Name' IN (
      SELECT tgname FROM pg_trigger WHERE tgrelid='programacion.input_family_assessments'::regclass
       AND NOT tgisinternal AND tgenabled IN ('O','A') AND tgtype&16=16);
     IF v_family_trigger_count<>6
      OR (SELECT validator_outcome FROM programacion.input_family_assessments WHERE id=v_family.id)<>'PASS'
     THEN RAISE EXCEPTION 'IG_M107_C_FAMILY_GUARDS_NOT_POSITIVE:%',v_code_family; END IF;
     v_family_times:=v_family_times||jsonb_build_array(jsonb_build_object(
       'family',v_code_family,'duration_ms',(v_plan->0->>'Execution Time')::numeric,
       'active_update_triggers',v_family_trigger_count));
     v_family_success:=v_family_success+1;
   END LOOP;

   SELECT * INTO STRICT v_prop FROM programacion.input_gap_proposals
    WHERE run_id=v_run_id AND validator_outcome='PENDING' ORDER BY id LIMIT 1;
   v_readbacks:='[]'::jsonb;
   FOR v_ref IN SELECT value FROM jsonb_array_elements(v_prop.source_refs) LOOP
     v_obs:=programacion.fn_input_resolve_source_ref(v_ref,v_run.pantalla_id,v_run.version_id);
     v_readbacks:=v_readbacks||jsonb_build_array(jsonb_build_object(
        'source_ref',v_ref,'source_observed_sha256',programacion.fn_v09_sha256_jsonb(v_obs)));
   END LOOP;
   v_evidence:=jsonb_build_object('direct_source_readback',true,
    'source_snapshot_sha256',v_run.source_snapshot_sha256,
    'source_readbacks',v_readbacks,
    'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
    'proposal_is_canonical_source',false,'automatic_canonicalization','DENY');
   EXECUTE 'EXPLAIN (ANALYZE,FORMAT JSON)
      UPDATE programacion.input_gap_proposals
      SET validator_identity=$1,validator_outcome=$2,
          status=CASE WHEN proposal_kind=''HUMAN_DECISION_REQUIRED''
                THEN ''HUMAN_DECISION_REQUIRED'' ELSE ''VALIDATED'' END,
          validator_evidence=$3,validated_at=clock_timestamp()
      WHERE id=$4' INTO v_plan USING v_validator,'PASS'::text,v_evidence,v_prop.id;
   SELECT count(*) INTO v_proposal_trigger_count
     FROM jsonb_array_elements(coalesce(v_plan->0->'Triggers','[]'::jsonb)) t(x)
     WHERE t.x->>'Trigger Name' IN (
       SELECT tgname FROM pg_trigger WHERE tgrelid='programacion.input_gap_proposals'::regclass
         AND NOT tgisinternal AND tgenabled IN ('O','A') AND tgtype&16=16);
   IF v_proposal_trigger_count<>2
      OR (SELECT validator_outcome FROM programacion.input_gap_proposals WHERE id=v_prop.id)<>'PASS'
   THEN RAISE EXCEPTION 'IG_M107_C_PROPOSAL_GUARDS_NOT_POSITIVE'; END IF;
   v_proposal_success:=true;
   RAISE EXCEPTION 'IG_M107_C_EXPECTED_ROLLBACK' USING ERRCODE='PZ127';
 EXCEPTION WHEN SQLSTATE 'PZ127' THEN NULL;
 END;

 IF v_family_success<>3 OR NOT v_proposal_success OR v_negative IS NULL
 OR (SELECT count(*) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>v_before_count
 OR EXISTS(SELECT 1 FROM programacion.input_readiness_runs WHERE id=v_run_id)
 OR EXISTS(SELECT 1 FROM programacion.input_family_assessments WHERE run_id=v_run_id)
 OR EXISTS(SELECT 1 FROM programacion.input_gap_proposals WHERE run_id=v_run_id)
 THEN RAISE EXCEPTION 'IG_M107_C_ROLLBACK_OR_PROOF_INCOMPLETE'; END IF;
 INSERT INTO public.lf_error_knowledge(
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,
 created_at,updated_at,lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
 VALUES(gen_random_uuid(),v_code,'GOVERNANCE',
 'M10.7 C: grafo semántico solo para familias que utilizan reglas del grafo',
 'Optimización del guard semántico con tres familias positivas y una propuesta, todos los triggers activos, negativo de fuente y fixture revertido.',
 'Construcción incondicional del grafo en el guard semántico aunque solo ACCESSIBILITY y MFA_OTP_SSO lo necesitan para sus reglas especiales.',
 'CONDITIONAL_SEMANTIC_GRAPH_EVALUATION',
 'Conservar identidad, hash, currentness, guard final y reglas especiales. No compartir caché ni quitar rehidratación de evidencia.',
 'Migration Train: 3 PASS de familia (SCREEN_IDENTITY, ACCESSIBILITY, MFA_OTP_SSO) con 6 triggers por fila; una propuesta con 2 triggers; SHA de fuente alterado rechazado; rollback sin residuos.',
 'MEDIUM',1,clock_timestamp(),clock_timestamp(),
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7/LOT_C','ACTIVO',
 jsonb_build_object('schema_version','IG_M107_C_CONDITIONAL_SEMANTIC_GRAPH_V1',
  'screen_id',43,'run_id_rolled_back',v_run_id,'family_rows_tested',v_family_success,
  'families',v_family_times,'proposal_validated',v_proposal_success,
  'proposal_triggers',v_proposal_trigger_count,
  'source_sha_negative',v_negative,'rollback_clean',true,
  'trigger_disabled',false,'full_manifest_guard_retained',true,
  'no_false_pass_observed',true,'real_validator_p90_measured',false,
  'C_integrated',true,'CP3_closed',false)::text,
 clock_timestamp(),clock_timestamp(),'VALIDATION','R5_EROSION_PROCESO','LOUD_EARLY',
 'One-screen one-temporary-run SQL rollback proof',
 'docs/ig/IG_M107_C_SEMANTIC_GRAPH_CONDITIONAL_V1.md');
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1 THEN
   RAISE EXCEPTION 'IG_M107_C_EKB_NOT_PERSISTED'; END IF;
END $test$;
