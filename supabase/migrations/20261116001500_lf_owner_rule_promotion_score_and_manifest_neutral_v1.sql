-- Owner 19:05 + 19:08 single atomic migration > 20261115222000 (Merge Train: one migration per PR).
-- Source preimages from SELECT, fail closed; no DML to product tables in this migration.
BEGIN;
DO $pre$ BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_execution_canonical_read_judge_v1(text)'::regprocedure))<>'0d88cd4d746f9a3e330a9b3ca1ca1b06' THEN RAISE EXCEPTION 'LF_OWNER_PREIMAGE_DRIFT_lf_profile_execution_canonical_read_judge_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_profile_execution_scope_authority_packet_v1(text,text,text)'::regprocedure))<>'0f240686dcdd75a3f9b95c07e4e25968' THEN RAISE EXCEPTION 'LF_OWNER_PREIMAGE_DRIFT_lf_profile_execution_scope_authority_packet_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_profile_execution_trust_validation_v2(text,text,jsonb)'::regprocedure))<>'b77ce57d25bceda1ca6681c1d3b59788' THEN RAISE EXCEPTION 'LF_OWNER_PREIMAGE_DRIFT_lf_profile_execution_trust_validation_v2'; END IF;
 IF md5(pg_get_functiondef('public.lf_profile_native_bridge_record_report_v1(text,text,text)'::regprocedure))<>'79d47899b6d46620f2b558da18cb4ba2' THEN RAISE EXCEPTION 'LF_OWNER_PREIMAGE_DRIFT_lf_profile_native_bridge_record_report_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure))<>'8c0ebc4a17c7efde16981f6105adeed4' THEN RAISE EXCEPTION 'LF_OWNER_PREIMAGE_DRIFT_lf_profile_native_bridge_record_semantic_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_profile_srcr_same_context_candidate_scope_v1(text)'::regprocedure))<>'261db8a52a89810fdfea41f4f78a4553' THEN RAISE EXCEPTION 'LF_OWNER_PREIMAGE_DRIFT_lf_profile_srcr_same_context_candidate_scope_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_profile_step70_clean_eval_context_verify_v1(text,jsonb)'::regprocedure))<>'54c8309c45292283b1b544c5f202895c' THEN RAISE EXCEPTION 'LF_OWNER_PREIMAGE_DRIFT_lf_profile_step70_clean_eval_context_verify_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_rule_promotion_request_v1(text,text,text)'::regprocedure))<>'f782b9c0f95ae507c8681aea31cdd2c9' THEN RAISE EXCEPTION 'LF_OWNER_PREIMAGE_DRIFT_lf_rule_promotion_request_v1'; END IF;
 IF to_regprocedure('public.lf_rule_promotion_score_v1(text,text)') IS NOT NULL THEN RAISE EXCEPTION 'LF_OWNER_SCORE_ALREADY_INSTALLED'; END IF;
END $pre$;


-- LF_OWNER_SCORE_SCORER_BEGIN
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_score_v1(p_execution_id text,p_rule_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $score$
DECLARE
  r record; p40 record; p50 record; p60 record; p70 record;
  refs jsonb; tests jsonb; t jsonb; is_bound boolean:=false; has_ref boolean:=false;
  a integer:=0; b integer:=0; c integer:=0; d integer:=0; total integer;
  hard_block boolean; decision text;
  blocked_categories CONSTANT text[]:=ARRAY['LEGAL','APPROVAL','OFERTAS_CUOTAS','AUTH','PRIVACY','PAGOS'];
  wizard_test CONSTANT text:='github://cristhianlujan/claude-persona-lf-patch@4c300100fa6df3f15c3d9a2433b5dbda2695239f/sandbox/lf_contract_gate_test/edge_function_operation/test_b2b_wizard_three_step_pgdual_v1.py';
  wizard_run CONSTANT text:='actions://cristhianlujan/claude-persona-lf-patch/runs/43771883221';
BEGIN
  SELECT codigo,estado,categoria,pendiente_decision,updated_at INTO r FROM lf_ops.reglas WHERE codigo=p_rule_code;
  IF NOT FOUND THEN RETURN jsonb_build_object('score',0,'A',0,'B',0,'C',0,'D',0,'hard_block',true,
    'decision','BLOCKED','next_gate','RETURN_TO_ROUTER','reason','RULE_NOT_FOUND'); END IF;
  SELECT * INTO p40 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=40 AND step_id='input_validate';
  SELECT * INTO p50 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=50 AND step_id='execute_profile';
  SELECT * INTO p60 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=60 AND step_id='output_validate';
  SELECT * INTO p70 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=70 AND step_id='semantic_judge';
  is_bound:=p40.status='STEP_PASS_WITH_EVIDENCE'
    AND p50.status='STEP_PASS_WITH_EVIDENCE'
    AND p60.status='STEP_PASS_WITH_EVIDENCE'
    AND p70.status='STEP_PASS_WITH_EVIDENCE'
    AND p70.evidence_payload#>>'{semantic_judge_result,verdict}'
      IN ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT')
    AND p50.evidence_payload->>'raw_output_sha256' ~ '^[0-9a-f]{64}$'
    AND p50.evidence_payload->>'raw_output_sha256'=p60.evidence_payload->>'raw_output_sha256'
    AND p50.evidence_payload->>'raw_output_sha256'=p70.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'
    AND p40.evidence_payload->>'scope_authority_packet_sha256'
      ='sha256:'||(p70.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}')
    AND jsonb_typeof(p70.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')='array'
    AND jsonb_array_length(p70.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')=0;
  refs:=p50.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}';
  IF jsonb_typeof(refs)='array' THEN
    SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(refs) x
      WHERE x->>'source_ref'='supabase://lf_ops.reglas/'||p_rule_code) INTO has_ref;
  END IF;
  IF is_bound AND has_ref THEN b:=30; END IF;
  IF r.pendiente_decision IS FALSE THEN c:=20; END IF;
  IF b>0 AND r.updated_at<p70.observed_at THEN d:=10; END IF;
  tests:=p50.evidence_payload#>'{profile_output,deliverable_created,behavior_tests}';
  IF jsonb_typeof(tests)<>'array' THEN tests:=p50.evidence_payload#>'{profile_output,behavior_tests}'; END IF;
  IF is_bound AND jsonb_typeof(tests)='array' THEN
    FOR t IN SELECT x FROM jsonb_array_elements(tests) x LOOP
      -- Only a known PG behavior test with actually checked GitHub R17 is eligible.
      -- Merely reading fixture JSON does not qualify; additional tests require a governed allowlist change.
      IF t->>'rule_code'=p_rule_code AND t->>'pg17'='PASS' AND t->>'pg18'='PASS'
        AND p_rule_code='B2B-RULE-LOAD-WIZARD-001'
        AND t->>'test_ref'=wizard_test AND t->>'ci_run'=wizard_run
      THEN a:=40; EXIT; END IF;
    END LOOP;
  END IF;
  hard_block:=coalesce(r.pendiente_decision,true) OR r.categoria=ANY(blocked_categories)
    OR p_rule_code LIKE '%INSTALLMENT%';
  total:=a+b+c+d;
  -- Below 60 always returns Router; hard_block forces MANUAL at/above 60.
  IF r.estado<>'CANDIDATO' OR total<60 THEN decision:='BLOCKED';
  ELSIF hard_block THEN decision:='MANUAL';
  ELSIF total>=85 THEN decision:='AUTO';
  ELSE decision:='MANUAL'; END IF;
  RETURN jsonb_build_object('score',total,'A',a,'B',b,'C',c,'D',d,
    'hard_block',hard_block,'decision',decision,
    'next_gate',CASE WHEN decision='BLOCKED' THEN 'RETURN_TO_ROUTER' ELSE 'PROMOTION_REQUEST' END,
    'judge_independence',CASE
      WHEN p70.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_REVIEWED_CURRENT_CONTEXT'
       THEN 'NOT_PROVEN_OWNER_ACCEPTED'
      WHEN p70.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_INDEPENDENT_SEMANTIC'
       THEN 'INDEPENDENCE_ASSERTED_NOT_REVERIFIED'
      ELSE 'NO_VALID_JUDGE' END,
    'reason','OWNER_SCORE_V1; no_promotion ignored; A allowlisted real PG17/PG18 CI only');
END $score$;
-- LF_OWNER_SCORE_SCORER_END

-- LF_OWNER_SCORE_REQUEST_BEGIN
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_request_v1(p_execution_id text, p_rule_code text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare par record; r record; v_sha text; v_id text; v_score jsonb; v_auto jsonb; v_reason text;
begin
 select * into par from public.lf_operation_execution e where e.execution_id=p_execution_id and e.operation_code='EJECUCION_PERFIL_LF' and e.status='IN_PROGRESS';
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PARENT_EXECUTION_NOT_ACTIVE'); end if;
 if not exists(select 1 from public.lf_profile_write_authority_v1 a where a.profile_code=par.target_code and a.operation_code='PROMOCION_REGLA_LF' and a.status='ACTIVE') then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROFILE_NOT_AUTHORIZED_FOR_PROMOTION','profile',par.target_code); end if;

 -- No independent-judge attestation is claimed for current-context review.
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s
 WHERE s.execution_id=p_execution_id AND s.step_order=70
 AND s.step_id='semantic_judge' AND s.status='STEP_PASS_WITH_EVIDENCE'
 AND s.evidence_payload#>>'{semantic_judge_result,verdict}'
   IN ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT')
 AND s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}' ~ '^[0-9a-f]{64}$'
 AND s.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}' ~ '^[0-9a-f]{64}$'
 AND jsonb_typeof(s.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')='array'
 AND jsonb_array_length(s.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')=0
 AND EXISTS(SELECT 1 FROM public.lf_operation_execution_steps f
  WHERE f.execution_id=p_execution_id AND f.step_order=50
  AND f.step_id='execute_profile' AND f.status='STEP_PASS_WITH_EVIDENCE'
  AND f.evidence_payload->>'raw_output_sha256'=s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'
  AND jsonb_typeof(f.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}')='array'
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(
    f.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}') z
    WHERE z->>'source_ref'='supabase://lf_ops.reglas/'||p_rule_code))
 AND EXISTS(SELECT 1 FROM public.lf_operation_execution_steps v
  WHERE v.execution_id=p_execution_id AND v.step_order=60
  AND v.step_id='output_validate' AND v.status='STEP_PASS_WITH_EVIDENCE'
  AND v.evidence_payload->>'raw_output_sha256'=s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}')
 AND EXISTS(SELECT 1 FROM public.lf_operation_execution_steps c
  WHERE c.execution_id=p_execution_id AND c.step_order=40
  AND c.step_id='input_validate' AND c.status='STEP_PASS_WITH_EVIDENCE'
  AND c.evidence_payload->>'scope_authority_packet_sha256'
    ='sha256:'||(s.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}'))
 ) THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STEP70_HASH_CHAIN_NOT_ATTESTED',
   'next_gate','RETURN_TO_ROUTER'); END IF;
 select * into r from lf_ops.reglas where codigo=p_rule_code;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','RULE_NOT_FOUND'); end if;
 if r.estado<>'CANDIDATO' then return jsonb_build_object('status','BLOCKED','blocking_code','RULE_NOT_CANDIDATE','estado',r.estado); end if;
 if exists(select 1 from public.lf_rule_promotion_v1 p where p.rule_code=p_rule_code and p.status in ('PENDING','APPROVED')) then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_ALREADY_OPEN'); end if;
 if nullif(btrim(p_reason),'') is null then return jsonb_build_object('status','BLOCKED','blocking_code','REASON_REQUIRED'); end if;

 v_score:=public.lf_rule_promotion_score_v1(p_execution_id,p_rule_code);
 IF v_score->>'decision'='BLOCKED' THEN RETURN jsonb_build_object(
 'status','BLOCKED','blocking_code','PROMOTION_SCORE_BELOW_60','next_gate','RETURN_TO_ROUTER',
 'score_note',v_score,'judge_independence',v_score->>'judge_independence'); END IF;
 v_reason:=p_reason||' | OWNER_SCORE_V1='||(v_score->>'score')
   ||'; decision='||(v_score->>'decision')
   ||'; hard_block='||(v_score->>'hard_block')
   ||'; judge_independence='||(v_score->>'judge_independence');
 v_sha := public.lf_asset_snapshot_sha_v1('REGLA',p_rule_code);
 insert into public.lf_rule_promotion_v1(rule_code,request_execution_id,requested_by_profile,request_snapshot_sha256,reason) values(p_rule_code,p_execution_id,par.target_code,v_sha,v_reason) returning promotion_id into v_id;

 -- No human identity spoofing; decide_v1's HUMAN gate remains unchanged.
 IF v_score->>'decision'='AUTO' THEN
  v_auto:=public.lf_rule_promotion_decide_v1(v_id,'APPROVE','AUTO_SCORE_V1',
    'OWNER_SCORE_V1 request; only human may finalize existing decide_v1');
 ELSE v_auto:=NULL; END IF;
 RETURN jsonb_build_object('status','PENDING_HUMAN_APPROVAL','promotion_id',v_id,
  'snapshot_sha256',v_sha,'score_note',v_score,'score_decision',v_score->>'decision',
  'judge_independence',v_score->>'judge_independence','auto_decision_attempt',v_auto,
  'next_action','Human decision required by unchanged decide_v1');

end $function$;
-- LF_OWNER_SCORE_REQUEST_END

-- Owner neutralization: lf_profile_execution_canonical_read_judge_v1
CREATE OR REPLACE FUNCTION public.lf_profile_execution_canonical_read_judge_v1(p_execution_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_input public.lf_operation_execution_steps%rowtype;
  v_context public.lf_operation_execution_steps%rowtype;
  v_execute public.lf_operation_execution_steps%rowtype;
  v_validate public.lf_operation_execution_steps%rowtype;
  v_handoff jsonb;
  v_handoff_validation jsonb;
  v_profile_slug text;
  v_pc jsonb;
  v_out jsonb;
  v_direct_rules jsonb;
  v_blockers jsonb;
  v_assumptions jsonb;
  v_direct_ref text;
  v_effective_ref text;
  v_subject text;
  v_direct_count integer;
  v_effective_count integer;
  v_candidate_digest text;
  v_scope_digest text;
  v_out_text text;
  v_hard jsonb:='[]'::jsonb;
  v_body jsonb;
  v_family_gate jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'verdict','BLOCKED_DETERMINISTIC_CANONICAL_READ',
      'blocking_codes',jsonb_build_array('CANONICAL_READ_EXECUTION_ID_REQUIRED'),
      'judge_mode','DETERMINISTIC_CANONICAL_READ_V1',
      'producer_independence_proven',true,
      'model_call_count',0
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_EXECUTION_AUTHORITY_INVALID');
  ELSE
    v_handoff:=e.manifest->'router_profile_handoff';

    IF e.operation_code<>'EJECUCION_PERFIL_LF'
       OR e.target_type<>'PERFIL'
       OR e.status NOT IN ('IN_PROGRESS','COMPLETED')
       OR e.manifest->>'executor_mode'<>'GPT_NATIVE'
       OR e.manifest->>'executor_provider'<>'OPENAI_CHATGPT_NATIVE'
       OR coalesce((e.manifest->>'read_only')::boolean,false) IS NOT TRUE
       OR coalesce((e.manifest->>'no_write')::boolean,false) IS NOT TRUE
       OR e.manifest#>>'{router_profile_handoff,channel}'<>'PRODUCTO'
       OR e.manifest#>>'{router_profile_handoff,business}'<>'LF'
       OR e.manifest#>>'{router_profile_handoff,semantic_request,router_action_binding,profile_task_intent}'
            <>'READ_PRODUCT_DEFINITION'
       OR e.manifest#>>'{router_profile_handoff,semantic_request,router_action_binding,input_governance_requirement}'
            <>'NOT_REQUIRED_CANONICAL_READ'
    THEN
      v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_EXECUTION_AUTHORITY_INVALID');
    END IF;

    v_handoff_validation:=public.lf_router_profile_execution_handoff_validate_v1(
      v_handoff,
      v_handoff->>'literal_request',
      e.target_code
    );

    IF coalesce((v_handoff_validation->>'valid')::boolean,false) IS NOT TRUE
       OR v_handoff->>'profile_code' IS DISTINCT FROM e.target_code THEN
      v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_PROFILE_HANDOFF_INVALID');
    END IF;

    SELECT a.metadata->>'profile_slug'
      INTO v_profile_slug
    FROM public.lf_activos a
    WHERE a.codigo_activo=e.target_code
      AND a.tipo_activo='PERFIL'
      AND a.archived_at IS NULL
    LIMIT 1;

    IF nullif(v_profile_slug,'') IS NULL THEN
      v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_PROFILE_REGISTRY_UNRESOLVED');
    END IF;
  END IF;

  SELECT * INTO v_input
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='input_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_input.step_id IS NULL
     OR v_input.evidence_payload#>>'{input_governance,status}'<>'NOT_REQUIRED'
     OR v_input.evidence_payload#>>'{input_governance,decision}'<>'SKIP'
     OR v_input.evidence_payload#>>'{input_governance,profile_task_intent}'<>'READ_PRODUCT_DEFINITION'
     OR v_input.evidence_payload#>>'{input_governance,input_governance_requirement}'<>'NOT_REQUIRED_CANONICAL_READ'
     OR coalesce((v_input.evidence_payload#>>'{input_governance,continuation_allowed}')::boolean,false) IS NOT TRUE
     OR coalesce((v_input.evidence_payload#>>'{input_governance,router_reentry_required}')::boolean,true) IS TRUE
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_INPUT_GOVERNANCE_INVALID');
  END IF;

  v_scope_digest:=v_input.evidence_payload->>'scope_authority_packet_sha256';
  IF coalesce(v_scope_digest,'') !~ '^sha256:[0-9a-f]{64}$' THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_SCOPE_DIGEST_INVALID');
  END IF;

  SELECT * INTO v_context
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='context_admission'
    AND status='STEP_PASS_WITH_EVIDENCE';

  v_pc:=v_context.evidence_payload#>'{context_capsule,channel_context,product_context}';
  IF v_context.step_id IS NULL
     OR jsonb_typeof(v_pc)<>'object'
     OR v_pc->>'schema_version'<>'LF_PRODUCT_CANONICAL_RULE_READ_V1'
     OR nullif(v_pc->>'subject_ref','') IS NULL
     OR nullif(v_pc->>'direct_rules_ref','') IS NULL
     OR nullif(v_pc->>'effective_rules_ref','') IS NULL
     OR coalesce(v_pc->>'direct_rule_count','') !~ '^[0-9]+$'
     OR coalesce(v_pc->>'effective_rule_count','') !~ '^[0-9]+$'
     OR jsonb_typeof(v_pc->'direct_rules')<>'array'
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_CONTEXT_INVALID');
  ELSE
    v_subject:=v_pc->>'subject_ref';
    v_direct_ref:=v_pc->>'direct_rules_ref';
    v_effective_ref:=v_pc->>'effective_rules_ref';
    v_direct_count:=(v_pc->>'direct_rule_count')::integer;
    v_effective_count:=(v_pc->>'effective_rule_count')::integer;
    v_direct_rules:=v_pc->'direct_rules';

    IF v_direct_count<=0
       OR v_effective_count<v_direct_count
       OR jsonb_array_length(v_direct_rules)<>v_direct_count
       OR EXISTS(
         SELECT 1
         FROM jsonb_array_elements(v_direct_rules) r(value)
         WHERE jsonb_typeof(r.value)<>'array'
           OR jsonb_array_length(r.value)<>3
           OR EXISTS(
             SELECT 1
             FROM jsonb_array_elements(r.value) f(value)
             WHERE jsonb_typeof(f.value)<>'string'
               OR nullif(btrim(f.value#>>'{}'),'') IS NULL
           )
       )
    THEN
      v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_RULE_PROJECTION_INVALID');
    END IF;
  END IF;

  SELECT * INTO v_execute
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='execute_profile'
    AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO v_validate
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='output_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';

  v_out:=v_execute.evidence_payload->'profile_output';
  v_candidate_digest:=v_execute.evidence_payload->>'candidate_digest';
  -- LF family reuse V1-V5: content finding, not a transport hard-block.
  v_family_gate:=public.lf_input_family_claims_gate_for_run_v1(p_execution_id,v_out);
  IF v_family_gate->>'status'='RETURN_TO_WORKER' THEN
    RETURN jsonb_build_object('status','RETURN_TO_WORKER',
      'verdict','FAMILY_REUSE_CONTENT_REPAIR_REQUIRED',
      'continuation_allowed',true,'automatic_rule_creation',false,
      'next_action','REPAIR_NATIVE_PROFILE_OUTPUT_SAME_RUN',
      'family_reuse_gate',v_family_gate);
  END IF;

  IF v_execute.step_id IS NULL
     OR jsonb_typeof(v_out)<>'object'
     OR coalesce(v_candidate_digest,'') !~ '^sha256:[0-9a-f]{64}$'
     OR v_candidate_digest IS DISTINCT FROM
        'sha256:'||encode(
          extensions.digest(convert_to(v_out::text,'UTF8'),'sha256'),'hex'
        )
     OR (
       nullif(v_out->>'worker','') IS NOT NULL
       AND nullif(v_profile_slug,'') IS NOT NULL
       AND v_out->>'worker' IS DISTINCT FROM v_profile_slug
     )
     OR (
       nullif(v_out->>'self_verdict','') IS NOT NULL
       AND v_out->>'self_verdict'<>'PASS'
     )
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_PRODUCER_OUTPUT_INVALID');
  END IF;

  IF v_validate.step_id IS NULL
     OR v_validate.evidence_payload->>'output_contract_result'<>'PASS'
     OR coalesce((v_validate.evidence_payload#>>'{deterministic_validation,valid}')::boolean,false) IS NOT TRUE
     OR v_validate.evidence_payload#>>'{deterministic_validation,status}'<>'PASS'
     OR v_validate.evidence_payload->>'raw_output_sha256'
          IS DISTINCT FROM substr(v_candidate_digest,8)
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_OUTPUT_VALIDATOR_NOT_PASS');
  END IF;

  v_out_text:=coalesce(v_out::text,'');

  -- Capability-level semantic binding: the producer schema may vary by profile,
  -- but the canonical subject, both authoritative refs and both server-derived
  -- counts must be represented in the validated candidate.
  IF nullif(v_subject,'') IS NULL
     OR nullif(v_direct_ref,'') IS NULL
     OR nullif(v_effective_ref,'') IS NULL
     OR position(v_subject in v_out_text)=0
     OR position(v_direct_ref in v_out_text)=0
     OR position(v_effective_ref in v_out_text)=0
     OR position(v_direct_count::text in v_out_text)=0
     OR position(v_effective_count::text in v_out_text)=0
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_MATERIAL_CLAIMS_NOT_DERIVED');
  END IF;

  v_blockers:=v_out#>'{deliverable_created,blockers}';
  v_assumptions:=v_out#>'{deliverable_created,open_assumptions}';

  IF (v_blockers IS NOT NULL AND (
        jsonb_typeof(v_blockers)<>'array'
        OR jsonb_array_length(v_blockers)<>0
      ))
     OR (v_assumptions IS NOT NULL AND (
        jsonb_typeof(v_assumptions)<>'array'
        OR jsonb_array_length(v_assumptions)<>0
      ))
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_UNRESOLVED_BLOCKER_OR_ASSUMPTION');
  END IF;

  IF jsonb_array_length(v_hard)>0 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'verdict','BLOCKED_DETERMINISTIC_CANONICAL_READ',
      'validator_status',case
        when v_validate.evidence_payload#>>'{deterministic_validation,status}'='PASS'
          then 'PASS' else 'BLOCKED' end,
      'producer_independence_proven',true,
      'model_call_count',0,
      'judge_mode','DETERMINISTIC_CANONICAL_READ_V1',
      'candidate_sha256',case
        when coalesce(v_candidate_digest,'') ~ '^sha256:[0-9a-f]{64}$'
          then substr(v_candidate_digest,8) else null end,
      'scope_packet_sha256',case
        when coalesce(v_scope_digest,'') ~ '^sha256:[0-9a-f]{64}$'
          then substr(v_scope_digest,8) else null end,
      'blocking_codes',v_hard,
      'unsupported_claims','[]'::jsonb,
      'result',jsonb_build_object(
        'verdict','BLOCKED_DETERMINISTIC_CANONICAL_READ',
        'candidate_sha256',case
          when coalesce(v_candidate_digest,'') ~ '^sha256:[0-9a-f]{64}$'
            then substr(v_candidate_digest,8) else null end,
        'scope_packet_sha256',case
          when coalesce(v_scope_digest,'') ~ '^sha256:[0-9a-f]{64}$'
            then substr(v_scope_digest,8) else null end,
        'unsupported_claims','[]'::jsonb,
        'blocking_codes',v_hard
      )
    );
  END IF;

  v_body:=jsonb_build_object(
    'status','PASS',
    'verdict','PASS_INDEPENDENT_SEMANTIC',
    'validator_status','PASS',
    'producer_independence_proven',true,
    'model_call_count',0,
    'judge_mode','DETERMINISTIC_CANONICAL_READ_V1',
    'candidate_sha256',substr(v_candidate_digest,8),
    'scope_packet_sha256',substr(v_scope_digest,8),
    'unsupported_claims','[]'::jsonb,
    'deterministic_readback',jsonb_build_object(
      'profile_task_intent','READ_PRODUCT_DEFINITION',
      'input_governance_requirement','NOT_REQUIRED_CANONICAL_READ',
      'product_context_schema','LF_PRODUCT_CANONICAL_RULE_READ_V1',
      'subject_ref',v_subject,
      'direct_rule_count',v_direct_count,
      'effective_rule_count',v_effective_count,
      'direct_rules_ref',v_direct_ref,
      'effective_rules_ref',v_effective_ref,
      'output_validator','PASS',
      'no_write',true
    ),
    'result',jsonb_build_object(
      'verdict','PASS_INDEPENDENT_SEMANTIC',
      'judge_mode','DETERMINISTIC_CANONICAL_READ_V1',
      'candidate_sha256',substr(v_candidate_digest,8),
      'scope_packet_sha256',substr(v_scope_digest,8),
      'unsupported_claims','[]'::jsonb,
      'blocking_codes','[]'::jsonb
    )
  );
  RETURN v_body;
END
$function$;

-- Owner neutralization: lf_profile_execution_scope_authority_packet_v1
CREATE OR REPLACE FUNCTION public.lf_profile_execution_scope_authority_packet_v1(p_execution_id text, p_input_literal text, p_input_source_ref text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  reqs jsonb := '[]'::jsonb;
  constraints_json jsonb := '[]'::jsonb;
  forbidden_json jsonb := '[]'::jsonb;
  packet_body jsonb;
  packet jsonb;
  digest_value text;
  execution_ref text;
  v_repair_write boolean:=false;
  v_repair_auth jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_input_literal,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_input_source_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','code','SCOPE_AUTHORITY_PACKET_INPUT_INVALID');
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND OR e.operation_code<>'EJECUCION_PERFIL_LF' OR e.target_type<>'PERFIL' THEN
    RETURN jsonb_build_object('status','BLOCKED','code','SCOPE_AUTHORITY_EXECUTION_INVALID');
  END IF;

  IF e.manifest ? 'input_sha256' THEN
    IF e.manifest->>'input_sha256' IS DISTINCT FROM
       'sha256:'||encode(
         extensions.digest(convert_to(p_input_literal,'UTF8'),'sha256'),'hex')
    THEN
      RETURN jsonb_build_object('status','BLOCKED','code','SCOPE_AUTHORITY_INPUT_DIGEST_MISMATCH');
    END IF;
  END IF;

  IF e.manifest ? 'queue_request_id' THEN
    IF nullif(e.manifest->>'queue_request_id','') IS NULL
       OR nullif(e.manifest->>'input_sha256','') IS NULL
    THEN
      RETURN jsonb_build_object('status','BLOCKED','code','SCOPE_AUTHORITY_QUEUE_BINDING_INCOMPLETE');
    END IF;

    IF p_input_source_ref IS DISTINCT FROM
       'queue://private.lf_profile_runtime_queue_v1/'||
       (e.manifest->>'queue_request_id')||'@'||(e.manifest->>'input_sha256')
    THEN
      RETURN jsonb_build_object('status','BLOCKED','code','SCOPE_AUTHORITY_QUEUE_SOURCE_MISMATCH');
    END IF;
  END IF;

  v_repair_write:=coalesce((e.manifest->>'governed_repair_write')::boolean,false);
  v_repair_auth:=e.manifest->'repair_execution_authority';

  IF v_repair_write THEN
    IF e.target_code<>public.lf_router_repair_profile_code_v1()
       OR jsonb_typeof(v_repair_auth)<>'object'
       OR v_repair_auth->>'schema_version'<>'LF_SRCR_REPAIR_EXECUTION_AUTHORITY_V1'
       OR v_repair_auth->>'mode'<>'GOVERNED_REPAIR_WRITE'
       OR v_repair_auth->>'profile_task_intent'<>'REPAIR_MISSING_PRODUCT_STRUCTURE'
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED','code','SCOPE_AUTHORITY_GOVERNED_REPAIR_INVALID'
      );
    END IF;
  END IF;

  execution_ref:='supabase://public.lf_operation_execution/'||p_execution_id||'#manifest';
  reqs:=jsonb_build_array(jsonb_build_object(
    'id','REQ-INPUT-LITERAL',
    'statement',p_input_literal,
    'source_ref',p_input_source_ref,
    'materiality','MATERIAL'
  ));

  constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
    'id','CON-TARGET-EXACT',
    'statement','Execution target must remain exact: '||e.target_type||'/'||e.target_code||'.',
    'source_ref',execution_ref,
    'materiality','BLOCKING'
  ));

  IF coalesce((e.manifest->>'read_only')::boolean,false) THEN
    constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
      'id','CON-READ-ONLY','statement','Execution is read-only.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
  END IF;

  IF coalesce((e.manifest->>'no_write')::boolean,false) THEN
    constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
      'id','CON-NO-WRITE','statement','No operational write is authorized.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
    forbidden_json:=forbidden_json||jsonb_build_array(jsonb_build_object(
      'id','FORBID-WRITE','statement','Do not perform operational mutation.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
  END IF;

  IF v_repair_write THEN
    constraints_json:=constraints_json||jsonb_build_array(
      jsonb_build_object(
        'id','CON-GOVERNED-REPAIR-WRITE',
        'statement','Only the minimum sufficient in-scope repair is authorized; post-write readback and rollback evidence are mandatory.',
        'source_ref','router-repair-authority://'||(v_repair_auth->>'fingerprint_sha256'),
        'materiality','BLOCKING'
      ),
      jsonb_build_object(
        'id','CON-REPAIR-SCOPE-EXACT',
        'statement','Repair scope is exactly the Router-carried scope and may not be widened.',
        'source_ref',execution_ref,
        'materiality','BLOCKING'
      )
    );
    forbidden_json:=forbidden_json||jsonb_build_array(
      jsonb_build_object(
        'id','FORBID-OUT-OF-SCOPE-REPAIR',
        'statement','Do not mutate unrelated assets or semantics outside the carried repair scope.',
        'source_ref',execution_ref,
        'materiality','BLOCKING'
      ),
      jsonb_build_object(
        'id','FORBID-DIRECT-PROFILE-INVOKE',
        'statement','After repair, return to Router; do not invoke another profile directly.',
        'source_ref',execution_ref,
        'materiality','BLOCKING'
      )
    );
  END IF;
  -- Owner: promotion gated by score/request, not manifest.no_promotion.

  IF coalesce((e.manifest->>'automatic_impact')::boolean,false)=false THEN
    forbidden_json:=forbidden_json||jsonb_build_array(jsonb_build_object(
      'id','FORBID-AUTOMATIC-IMPACT',
      'statement','Do not introduce unrequested automatic impact outside the explicit repair.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
  END IF;

  IF coalesce((e.manifest->>'prior_output_reuse_forbidden')::boolean,false) THEN
    constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
      'id','CON-NO-PRIOR-OUTPUT-REUSE','statement','Prior candidate/output reuse is forbidden.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
  END IF;

  IF coalesce((e.manifest->>'blind_holdout_required')::boolean,false) THEN
    constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
      'id','CON-BLIND-HOLDOUT','statement','Blind holdout separation must be preserved.',
      'source_ref',execution_ref,'materiality','MATERIAL'
    ));
  END IF;

  packet_body:=jsonb_build_object(
    'packet_version','LF_SCOPE_AUTHORITY_PACKET_V1',
    'execution_id',p_execution_id,
    'subject_ref',execution_ref,
    'authorized_requirements',reqs,
    'constraints',constraints_json,
    'forbidden_changes',forbidden_json,
    'repair_execution_authority',
      case when v_repair_write then v_repair_auth else null end,
    'authority_precedence',jsonb_build_array(
      jsonb_build_object(
        'rank',1,'source_ref',execution_ref,
        'reason','Exact execution manifest and literal request define authorized scope.'
      ),
      jsonb_build_object(
        'rank',2,
        'source_ref','supabase://public.v_lf_operation_policy_snapshot/EJECUCION_PERFIL_LF',
        'reason','Canonical operation policies constrain execution behavior.'
      )
    ),
    'related_context_refs','[]'::jsonb,
    'source_refs',jsonb_build_array(
      execution_ref,
      p_input_source_ref,
      'supabase://public.v_lf_operation_policy_snapshot/EJECUCION_PERFIL_LF'
    ),
    'compiled_at',to_jsonb(e.started_at),
    'canonicalization_rule','POSTGRES_JSONB_TEXT_UTF8_SHA256_V1'
  );

  digest_value:='sha256:'||
    encode(extensions.digest(convert_to(packet_body::text,'UTF8'),'sha256'),'hex');
  packet:=packet_body||jsonb_build_object('sha256',digest_value);

  RETURN jsonb_build_object(
    'status','READY',
    'scope_authority_packet',packet,
    'scope_packet_sha256',digest_value,
    'canonicalization_rule','POSTGRES_JSONB_TEXT_UTF8_SHA256_V1'
  );
END
$function$;

-- Owner neutralization: lf_profile_execution_trust_validation_v2
CREATE OR REPLACE FUNCTION public.lf_profile_execution_trust_validation_v2(p_execution_id text, p_step_id text, p_evidence_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
declare
  base jsonb;
  e public.lf_operation_execution%rowtype;
  input_step public.lf_operation_execution_steps%rowtype;
  execute_step public.lf_operation_execution_steps%rowtype;
  semantic_step public.lf_operation_execution_steps%rowtype;
  input_binding public.lf_operation_step_judge_bindings%rowtype;
  execute_binding public.lf_operation_step_judge_bindings%rowtype;
  semantic_binding public.lf_operation_step_judge_bindings%rowtype;
  packet jsonb;
  packet_body jsonb;
  expected_digest text;
  scope_digest text;
  candidate_digest text;
  semantic_result jsonb;
  canonical_read_judge jsonb;
  hard jsonb := '[]'::jsonb;
begin
  base:=public.lf_profile_execution_trust_validation_v1(
    p_execution_id,p_step_id,p_evidence_payload
  );
  if coalesce((base->>'valid')::boolean,false) is not true then
    return base;
  end if;

  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id;
  if not found then
    return jsonb_build_object(
      'valid',false,'code','PROFILE_EXECUTION_V2_BINDING_INVALID',
      'details',jsonb_build_object('execution_id',p_execution_id),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  if p_step_id='input_validate' then
    packet:=p_evidence_payload->'scope_authority_packet';
    scope_digest:=p_evidence_payload->>'scope_authority_packet_sha256';
    if jsonb_typeof(packet)<>'object'
       or coalesce(packet->>'packet_version','')<>'LF_SCOPE_AUTHORITY_PACKET_V1'
       or packet->>'execution_id' is distinct from p_execution_id
       or packet->>'subject_ref' is distinct from
          'supabase://public.lf_operation_execution/'||p_execution_id||'#manifest'
       or packet->>'canonicalization_rule' is distinct from
          'POSTGRES_JSONB_TEXT_UTF8_SHA256_V1'
       or jsonb_typeof(packet->'authorized_requirements')<>'array'
       or jsonb_array_length(packet->'authorized_requirements')=0
       or jsonb_typeof(packet->'constraints')<>'array'
       or jsonb_typeof(packet->'forbidden_changes')<>'array'
       or coalesce(scope_digest,'') !~ '^sha256:[0-9a-f]{64}$'
    then
      hard:=hard||jsonb_build_array('scope_authority_packet_shape_invalid');
    else
      packet_body:=packet-'sha256';
      expected_digest:='sha256:'||
        encode(extensions.digest(convert_to(packet_body::text,'UTF8'),'sha256'),'hex');
      if scope_digest is distinct from expected_digest
         or packet->>'sha256' is distinct from expected_digest then
        hard:=hard||jsonb_build_array('scope_authority_packet_digest_mismatch');
      end if;
    end if;

  elsif p_step_id='semantic_judge' then
    select * into input_binding
    from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='input_validate'
      and status='ACTIVE_ENFORCEMENT';
    select * into input_step
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='input_validate';

    select * into execute_binding
    from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='execute_profile'
      and status='ACTIVE_ENFORCEMENT';
    select * into execute_step
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='execute_profile';

    if input_step.step_id is null
       or input_step.status<>input_binding.clean_result_value then
      hard:=hard||jsonb_build_array('input_validate_predecessor_not_clean');
    end if;
    if execute_step.step_id is null
       or execute_step.status<>execute_binding.clean_result_value then
      hard:=hard||jsonb_build_array('execute_profile_predecessor_not_clean');
    end if;

    scope_digest:=input_step.evidence_payload->>'scope_authority_packet_sha256';
    candidate_digest:=execute_step.evidence_payload->>'candidate_digest';
    semantic_result:=p_evidence_payload->'semantic_judge_result';
    canonical_read_judge:=public.lf_profile_execution_canonical_read_judge_v1(p_execution_id);

    if jsonb_typeof(semantic_result)<>'object'
       or semantic_result->>'status' is distinct from 'PASS'
       or semantic_result->>'validator_status' is distinct from 'PASS'
       or not (
         (
           semantic_result->>'verdict'='PASS_INDEPENDENT_SEMANTIC'
           and coalesce((semantic_result->>'producer_independence_proven')::boolean,false) is true
           and (
             coalesce((semantic_result->>'model_call_count')::integer,-1)=1
             or (
               coalesce((semantic_result->>'model_call_count')::integer,-1)=0
               and semantic_result->>'judge_mode'='DETERMINISTIC_CANONICAL_READ_V1'
               and canonical_read_judge->>'status'='PASS'
               and semantic_result is not distinct from canonical_read_judge
             )
           )
         )
         or (
           semantic_result->>'verdict'='PASS_REVIEWED_CURRENT_CONTEXT'
           and semantic_result->>'review_mode'='CURRENT_CONTEXT_REVIEW'
           and semantic_result->>'reviewer_is_producer'='true'
           and coalesce((semantic_result->>'producer_independence_proven')::boolean,true) is false
           and coalesce((semantic_result->>'model_call_count')::integer,-1)=0
           and (
             (
               coalesce((e.manifest->>'read_only')::boolean,false) is true
               and coalesce((e.manifest->>'no_write')::boolean,false) is true
             )
             or (
               e.target_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
               and public.lf_profile_srcr_same_context_candidate_scope_v1(p_execution_id)
             )
           )
           and semantic_result#>>'{judge_v3_evidence,verdict}'='PASS_REVIEWED_CURRENT_CONTEXT'
           and semantic_result#>>'{judge_v3_evidence,review_mode}'='CURRENT_CONTEXT_REVIEW'
           and semantic_result#>>'{judge_v3_evidence,reviewer_is_producer}'='true'
           and semantic_result#>>'{judge_v3_evidence,producer_independence_proven}'='false'
           and semantic_result#>>'{judge_v3_evidence,model_call_count}'='0'
           and semantic_result#>>'{judge_v3_evidence,router_direct_consistency}'='NOT_TESTED'
           and semantic_result#>>'{judge_v3_evidence,decision_checks,router_direct_consistency,result}'='not_applicable'
           and semantic_result#>>'{judge_v3_evidence,decision_checks,router_direct_consistency,applicability}'='ROUTER_ONLY'
           and semantic_result#>>'{judge_v3_evidence,counterfactual_result}'='PASS'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,context_resolution_valid,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,evidence_supported,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,decision_resolves_objective,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,authority_resolution_valid,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,constraints_preserved,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,claims_authorized,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,materiality_handled_correctly,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,tradeoff_defensible,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,acceptance_detects_wrong_implementation,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,handoff_implementation_ready,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,counterfactual_trajectory,result}'='true'
         )
       )
       or coalesce(candidate_digest,'') !~ '^sha256:[0-9a-f]{64}$'
       or coalesce(scope_digest,'') !~ '^sha256:[0-9a-f]{64}$'
       or 'sha256:'||coalesce(semantic_result->>'candidate_sha256','')
          is distinct from candidate_digest
       or 'sha256:'||coalesce(semantic_result->>'scope_packet_sha256','')
          is distinct from scope_digest
       or jsonb_typeof(semantic_result->'result')<>'object'
       or semantic_result#>>'{result,verdict}'
          is distinct from semantic_result->>'verdict'
       or semantic_result#>>'{result,candidate_sha256}'
          is distinct from semantic_result->>'candidate_sha256'
       or semantic_result#>>'{result,scope_packet_sha256}'
          is distinct from semantic_result->>'scope_packet_sha256'
       or jsonb_typeof(p_evidence_payload->'unsupported_claims')<>'array'
       or jsonb_array_length(p_evidence_payload->'unsupported_claims')<>0
       or jsonb_typeof(semantic_result#>'{result,unsupported_claims}')<>'array'
       or jsonb_array_length(semantic_result#>'{result,unsupported_claims}')<>0
       or jsonb_typeof(semantic_result#>'{result,blocking_codes}')<>'array'
       or jsonb_array_length(semantic_result#>'{result,blocking_codes}')<>0
    then
      hard:=hard||jsonb_build_array('semantic_judge_v2_not_pass');
    end if;

  elsif p_step_id='report_output' then
    select * into semantic_binding
    from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='semantic_judge'
      and status='ACTIVE_ENFORCEMENT';
    select * into semantic_step
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='semantic_judge';

    if semantic_step.step_id is null
       or semantic_step.status<>semantic_binding.clean_result_value then
      hard:=hard||jsonb_build_array('semantic_judge_predecessor_not_clean');
    end if;

    if p_evidence_payload->>'result' is distinct from semantic_step.evidence_payload#>>'{semantic_judge_result,verdict}'
       or p_evidence_payload->>'profile_code' is distinct from e.target_code
       or p_evidence_payload->>'execution_id' is distinct from p_execution_id
       or coalesce((p_evidence_payload->>'no_write_performed')::boolean,false) is not true
       or p_evidence_payload->>'candidate_sha256'
          is distinct from semantic_step.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'
       or p_evidence_payload->>'scope_packet_sha256'
          is distinct from semantic_step.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}'
    then
      hard:=hard||jsonb_build_array('report_output_semantic_binding_invalid');
    end if;
  end if;

  if jsonb_array_length(hard)>0 then
    return jsonb_build_object(
      'valid',false,
      'code','PROFILE_EXECUTION_SERVER_VALIDATION_V2_FAILED',
      'details',jsonb_build_object('step_id',p_step_id,'hard_fails',hard),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','PROFILE_EXECUTION_SERVER_VALIDATED_V2',
    'details',jsonb_build_object('step_id',p_step_id,'execution_id',p_execution_id),
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb
  );
end
$function$;

-- Owner neutralization: lf_profile_native_bridge_record_report_v1
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_report_v1(p_execution_id text, p_evidence_ref text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_semantic public.lf_operation_execution_steps%rowtype;
  v_input jsonb;
  v_profile_output jsonb;
  v_report_findings jsonb;
  v_existing text;
  v_actor text;
  v_candidate text;
  v_scope text;
  v_semantic_receipt text;
  v_step jsonb;
  v_clean integer;
  v_terminal jsonb;
  v_attached jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_evidence_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_INPUT_INVALID');
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status NOT IN ('IN_PROGRESS','COMPLETED')
     OR NOT COALESCE(
       (e.manifest->>'executor_mode'='GPT_NATIVE'
        AND e.manifest->>'executor_provider'='OPENAI_CHATGPT_NATIVE')
       OR
       (e.manifest->>'executor_mode'='CLAUDE_NATIVE'
        AND e.manifest->>'executor_provider'='ANTHROPIC_CLAUDE_NATIVE'),
       false
     )
     OR e.manifest ? 'queue_request_id'
     OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXECUTION_INVALID');
  END IF;

  SELECT * INTO v_semantic
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='semantic_judge'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_semantic.step_id IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_SEMANTIC_NOT_CLEAN');
  END IF;

  -- Read canonical evidence only. A security BLOCKED is never relabeled READY.
  SELECT evidence_payload INTO v_input
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='input_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';
  IF v_input#>>'{input_governance,status}'='BLOCKED'
     AND v_input->>'analysis_scope' IS DISTINCT FROM 'READ_ONLY_WITH_IG_FINDINGS' THEN
    RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','BLOCK_REPORT_IG_FINDINGS_WRITE_SCOPE');
  END IF;
  IF v_input->>'analysis_scope'='READ_ONLY_WITH_IG_FINDINGS' THEN
    IF NOT (
       (e.manifest->>'read_only'='true'
        AND e.manifest->>'no_write'='true'
        AND e.manifest->>'automatic_impact'='false'
        AND e.manifest->>'governed_repair_write'='false'
        AND v_input#>>'{input_governance,status}'='BLOCKED'
        AND v_input->>'ig_security_clearance'='false'
        AND jsonb_typeof(v_input#>'{input_governance,governance_result}')='object')
       OR public.lf_profile_srcr_same_context_candidate_scope_v1(p_execution_id)
    )
    THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','BLOCK_REPORT_IG_FINDINGS_SCOPE_OR_SOURCE_INVALID');
    END IF;
    SELECT evidence_payload->'profile_output' INTO v_profile_output
    FROM public.lf_operation_execution_steps
    WHERE execution_id=p_execution_id AND step_id='execute_profile'
      AND status='STEP_PASS_WITH_EVIDENCE';
    IF jsonb_typeof(v_profile_output)<>'object' THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','BLOCK_REPORT_PROFILE_DECISION_SOURCE_MISSING');
    END IF;
    v_report_findings:=jsonb_build_object(
      'analysis_scope','READ_ONLY_WITH_IG_FINDINGS',
      'security_state',CASE WHEN v_input#>>'{input_governance,status}'='BLOCKED' THEN 'BLOCKED' ELSE 'FINDINGS_NOT_CLEARED' END,
      'security_clearance',false,
      'input_step_ref','supabase://public.lf_operation_execution_steps/'||p_execution_id||'/input_validate',
      'input_governance',v_input->'input_governance',
      'profile_decision_observed',v_profile_output#>'{traceability,ig_open_work_resolution}',
      'report_status',CASE WHEN v_input#>>'{input_governance,status}'='BLOCKED' THEN 'FINDINGS_REPORTED_NOT_RESOLVED' ELSE 'CANDIDATE_REVIEWED_NO_EFFECT_APPROVAL' END,
      'mutation_authorized',false,
      'promotion_authorized',false);
  END IF;

  v_candidate:=v_semantic.evidence_payload#>>'{semantic_judge_result,candidate_sha256}';
  v_scope:=v_semantic.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}';
  v_semantic_receipt:=coalesce(v_semantic.evidence_payload->>'semantic_review_receipt_ref',v_semantic.evidence_payload->>'independent_semantic_receipt_ref');

  IF coalesce(v_candidate,'') !~ '^[0-9a-f]{64}$'
     OR coalesce(v_scope,'') !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_SEMANTIC_BINDING_INVALID');
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='report_output';

  IF v_existing IS NULL THEN
    IF e.status<>'IN_PROGRESS' THEN
      RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXECUTION_ALREADY_CLOSED_WITHOUT_REPORT');
    END IF;
    v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'report_output',
      p_evidence_ref,
      jsonb_build_object(
        'family_source_receipts',public.lf_input_family_catalog_receipts_for_run_v1(p_execution_id),
        'family_source_receipt_schema','LF_FAMILY_SOURCE_RECEIPTS_BY_REFERENCE_V1',
        'result',v_semantic.evidence_payload#>>'{semantic_judge_result,verdict}',
        'execution_id',p_execution_id,
        'profile_code',e.target_code,
        'no_write_performed',true,
        'candidate_sha256',v_candidate,
        'scope_packet_sha256',v_scope,
        'semantic_review_receipt_ref',v_semantic_receipt,
        'independent_semantic_receipt_ref',case
          when v_semantic.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW' then null
          else v_semantic.evidence_payload->>'independent_semantic_receipt_ref' end,
        'judge_independence_status',coalesce(
          v_semantic.evidence_payload->>'judge_independence_status',
          CASE WHEN v_semantic.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW'
          THEN 'NOT_PROVEN' ELSE 'REQUIRES_PROVIDER_VERIFICATION' END),
        'content_findings',coalesce(v_semantic.evidence_payload->'content_findings',
          CASE WHEN v_semantic.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW'
             THEN jsonb_build_array(jsonb_build_object('finding_code','JUDGE_INDEPENDENCE_NOT_PROVEN','continuation_allowed',true))
             ELSE '[]'::jsonb END),
        'next_gate','RETURN_TO_ROUTER'
      ) || CASE WHEN v_report_findings IS NOT NULL
           THEN jsonb_build_object('ig_findings',v_report_findings,
                                   'ig_findings_reported',true)
           ELSE '{}'::jsonb END,
      v_actor
    );
    IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_RECORD_REJECTED',
        'recorder_result',v_step
      );
    END IF;
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXISTING_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF v_clean<>11 OR e.status<>'COMPLETED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_COMPLETION_NOT_CLEAN',
      'clean_step_count',v_clean,
      'execution_status',e.status
    );
  END IF;

  v_terminal:=public.lf_profile_execution_terminal_authority_receipt_v1(p_execution_id);
  IF v_terminal->>'status' IS DISTINCT FROM 'READY' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_TERMINAL_RECEIPT_NOT_READY',
      'terminal_result',v_terminal
    );
  END IF;

  -- Attach the terminal route after the canonical 11/11 clean step and
  -- terminal receipt are proven. Reuse the existing idempotent CAS writer.
  v_attached:=public.lf_profile_execution_attach_terminal_authority_receipt_v1(
    p_execution_id,p_execution_id
  );
  IF v_attached->>'result' NOT IN (
    'TERMINAL_AUTHORITY_RECEIPT_ATTACHED',
    'TERMINAL_AUTHORITY_RECEIPT_ALREADY_ATTACHED'
  )
  OR v_attached->>'terminal_authority_receipt_sha256' IS DISTINCT FROM
     v_terminal->>'terminal_authority_receipt_sha256'
  OR jsonb_typeof(v_attached->'post_profile_route')<>'object'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','PD_EXECUTOR_TERMINAL_ROUTER_RETURN_NOT_ATTACHED',
      'attach_result',v_attached
    );
  END IF;
  RETURN jsonb_build_object(
    'status','PROFILE_EXECUTION_COMPLETED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'clean_step_count',v_clean,
    'last_completed_step','report_output',
    'execution_status',e.status,
    'terminal_authority_receipt_sha256',v_terminal->>'terminal_authority_receipt_sha256',
    'post_profile_route',v_attached->'post_profile_route',
    'next_action',v_attached->>'next_action',
    'next_gate',CASE WHEN v_attached->>'next_action'='REENTER_ROUTER_STAGE1'
                  THEN 'ACT-0001_STAGE1' ELSE 'RETURN_TO_ROUTER' END
  );
END
$function$;

-- Owner neutralization: lf_profile_native_bridge_record_semantic_v1
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_semantic_v1(p_execution_id text, p_semantic_judge_result jsonb, p_evidence_ref text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_actor text;
  v_existing text;
  v_family_judge jsonb;
  v_step jsonb;
  v_clean integer;
  v_verified_native jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR jsonb_typeof(p_semantic_judge_result)<>'object'
     OR nullif(btrim(coalesce(p_evidence_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_INPUT_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'IN_PROGRESS'
     OR NOT COALESCE(
       (e.manifest->>'executor_mode'='GPT_NATIVE'
        AND e.manifest->>'executor_provider'='OPENAI_CHATGPT_NATIVE')
       OR
       (e.manifest->>'executor_mode'='CLAUDE_NATIVE'
        AND e.manifest->>'executor_provider'='ANTHROPIC_CLAUDE_NATIVE'),
       false
     )
     OR e.manifest ? 'queue_request_id'
     OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_EXECUTION_INVALID'
    );
  END IF;

  -- Governed SRCR clean-eval mode: independent CONTEXT and EVAL, same LLM.
  -- Server recomputes immutable event SHA chain and Step40/50/60 bindings.
  -- Model-authored flags alone cannot satisfy this verifier.
  IF p_semantic_judge_result->>'review_mode'='INDEPENDENT_EVAL_CONTEXT' THEN
    v_verified_native:=public.lf_profile_step70_clean_eval_context_verify_v1(
       p_execution_id,p_semantic_judge_result);
    IF v_verified_native->>'status' IS DISTINCT FROM 'CLEAN_CONTEXT_EVAL_VERIFIED' THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code',coalesce(v_verified_native->>'blocking_code',
          'LF_STEP70_CLEAN_CONTEXT_RECEIPT_NOT_VERIFIED'));
    END IF;
  END IF;

  -- Effects-bearing LF Product Director Step70 requires a genuinely
  -- verified independent native provider receipt. Read-only profiles retain
  -- their pre-existing current-context path. No HMAC / asserted-JSON bypass.
  IF e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
    AND NOT (
      coalesce((e.manifest->>'read_only')::boolean,false) IS TRUE
      AND coalesce((e.manifest->>'no_write')::boolean,false) IS TRUE
    )
  THEN
    IF p_semantic_judge_result->>'review_mode'
       IN ('CURRENT_CONTEXT_REVIEW','HMAC_TEST','MOCK')
    THEN RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','LF_STEP70_NATIVE_SELF_REVIEW_FORBIDDEN'); END IF;
    IF to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL
    THEN RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','LF_STEP70_NATIVE_PROVIDER_VERIFIER_MISSING'); END IF;
    EXECUTE 'SELECT public.lf_ig_verified_native_provider_receipt_v1($1)'
      INTO v_verified_native USING p_execution_id;
    IF jsonb_typeof(v_verified_native)<>'object'
      OR v_verified_native->>'status' IS DISTINCT FROM 'CRYPTOGRAPHICALLY_VERIFIED'
      OR v_verified_native->>'execution_id' IS DISTINCT FROM p_execution_id
      OR v_verified_native->>'provider_receipt_ref'
           IS DISTINCT FROM p_semantic_judge_result->>'provider_receipt_ref'
      OR v_verified_native->>'candidate_sha256'
           IS DISTINCT FROM p_semantic_judge_result->>'candidate_sha256'
      OR v_verified_native->>'scope_packet_sha256'
           IS DISTINCT FROM p_semantic_judge_result->>'scope_packet_sha256'
      OR coalesce(p_semantic_judge_result->>'provider_receipt_ref','')=''
      OR p_semantic_judge_result->>'producer_independence_proven'
           IS DISTINCT FROM 'true'
      OR p_semantic_judge_result->>'model_call_count'
           IS DISTINCT FROM '1'
    THEN RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','LF_STEP70_NATIVE_RECEIPT_NOT_VERIFIED'); END IF;
  END IF;

  -- An asserted independent review is not proof of another model/reviewer.
  -- No cryptographically verified provider attestation => refuse the authority
  -- claim; callers can continue read-only through CURRENT_CONTEXT_REVIEW.
  IF p_semantic_judge_result->>'verdict'='PASS_INDEPENDENT_SEMANTIC'
    AND p_semantic_judge_result->>'review_mode' IS DISTINCT FROM 'INDEPENDENT_EVAL_CONTEXT' THEN
    IF to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','JUDGE_INDEPENDENCE_PROVIDER_VERIFIER_UNAVAILABLE');
    END IF;
    EXECUTE 'SELECT public.lf_ig_verified_native_provider_receipt_v1($1)'
      INTO v_verified_native USING p_execution_id;
    IF v_verified_native->>'status'<>'CRYPTOGRAPHICALLY_VERIFIED'
      OR v_verified_native->>'execution_id' IS DISTINCT FROM p_execution_id
      OR v_verified_native->>'candidate_sha256'
            IS DISTINCT FROM p_semantic_judge_result->>'candidate_sha256'
      OR v_verified_native->>'scope_packet_sha256'
            IS DISTINCT FROM p_semantic_judge_result->>'scope_packet_sha256'
      OR p_semantic_judge_result->>'provider_receipt_ref'
            IS DISTINCT FROM v_verified_native->>'provider_receipt_ref'
      OR v_verified_native->>'reviewer_model_independence_proven'<>'true'
    THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','JUDGE_INDEPENDENCE_UNVERIFIED_AUTHORITY_CLAIM');
    END IF;
  END IF;

  IF p_semantic_judge_result->>'status' IS DISTINCT FROM 'PASS'
     OR p_semantic_judge_result->>'validator_status' IS DISTINCT FROM 'PASS'
     OR NOT (
       (
         p_semantic_judge_result->>'verdict'='PASS_INDEPENDENT_SEMANTIC'
         AND coalesce((p_semantic_judge_result->>'producer_independence_proven')::boolean,false) IS TRUE
         AND coalesce((p_semantic_judge_result->>'model_call_count')::integer,-1)=1
       ) OR (
         p_semantic_judge_result->>'verdict'='PASS_INDEPENDENT_SEMANTIC'
         AND p_semantic_judge_result->>'review_mode'='INDEPENDENT_EVAL_CONTEXT'
         AND p_semantic_judge_result->>'reviewer_is_producer'='false'
         AND p_semantic_judge_result->>'producer_independence_proven'='true'
         AND p_semantic_judge_result->>'model_call_count' IS NULL
         AND v_verified_native->>'status'='CLEAN_CONTEXT_EVAL_VERIFIED'
       ) OR (
         p_semantic_judge_result->>'verdict'='PASS_REVIEWED_CURRENT_CONTEXT'
         AND p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW'
         AND p_semantic_judge_result->>'reviewer_is_producer'='true'
         AND coalesce((p_semantic_judge_result->>'producer_independence_proven')::boolean,true) IS FALSE
         AND coalesce((p_semantic_judge_result->>'model_call_count')::integer,-1)=0
         AND (
           (coalesce((e.manifest->>'read_only')::boolean,false) IS TRUE
            AND coalesce((e.manifest->>'no_write')::boolean,false) IS TRUE)
           OR public.lf_profile_srcr_same_context_candidate_scope_v1(p_execution_id)
         )
       )
     )
     OR jsonb_typeof(p_semantic_judge_result#>'{result,unsupported_claims}')<>'array'
     OR jsonb_array_length(p_semantic_judge_result#>'{result,unsupported_claims}')<>0
     OR jsonb_typeof(p_semantic_judge_result#>'{result,blocking_codes}')<>'array'
     OR jsonb_array_length(p_semantic_judge_result#>'{result,blocking_codes}')<>0 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_JUDGE_NOT_PASS'
    );
  END IF;


  -- Independent V3 remains the authority for provenance; this specialist
  -- validates each claimed family/source equivalence and transferability.
  v_family_judge:=public.lf_input_family_semantic_transfer_eval_for_run_v1(
    p_execution_id,p_semantic_judge_result#>'{result,family_reuse_evaluation}');
  IF v_family_judge->>'status'='RETURN_TO_WORKER' THEN
    RETURN jsonb_build_object('status','RETURN_TO_WORKER',
      'code','FAMILY_REUSE_SEMANTIC_REVIEW_REQUIRED',
      'continuation_allowed',true,'family_reuse_evaluation',v_family_judge,
      'next_action','REVIEW_TRANSFERABILITY_AND_RESUME_SAME_RUN');
  END IF;
  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='semantic_judge';

  IF v_existing IS NULL OR v_existing IN ('BLOCKED_STEP_NOT_CLEAN', 'RETURN_TO_ROUTER') THEN
    -- Reuse the canonical recorder retry path, retaining attempt_history on the same RUN.
    v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'semantic_judge',
      p_evidence_ref,
      jsonb_build_object(
        'semantic_judge_result',p_semantic_judge_result,
        'family_reuse_evaluation',v_family_judge,
        'unsupported_claims','[]'::jsonb,
        'semantic_review_receipt_ref',p_evidence_ref,
        'independent_semantic_receipt_ref',case
          when p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW' then null
          when p_semantic_judge_result->>'review_mode'='INDEPENDENT_EVAL_CONTEXT' then v_verified_native->>'context_receipt_ref'
          else v_verified_native->>'provider_receipt_ref' end,
        'judge_independence_status',case
          when p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW'
            then 'NOT_PROVEN'
          when p_semantic_judge_result->>'review_mode'='INDEPENDENT_EVAL_CONTEXT'
            then 'CONTEXT_EVAL_VERIFIED'
          else 'PROVIDER_VERIFIED' end,
        'content_findings',case
          when p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW'
            then jsonb_build_array(jsonb_build_object(
               'finding_code','JUDGE_INDEPENDENCE_NOT_PROVEN',
               'continuation_allowed',true,'effect_authority',false,
               'reviewer_is_producer',true,'producer_independence_proven',false,
               'model_call_count',0))
          else '[]'::jsonb end
      ),
      v_actor
    );

    IF coalesce(v_step->>'status',v_step->>'step_status')
       IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_RECORD_REJECTED',
        'recorder_result',v_step
      );
    END IF;

  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_EXISTING_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>10 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_POST_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',10
    );
  END IF;

  RETURN jsonb_build_object(
    'status','SEMANTIC_JUDGE_RECORDED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'clean_step_count',v_clean,
    'last_completed_step','semantic_judge',
    'next_step','report_output',
    'next_action','RECORD_EXISTING_REPORT_OUTPUT'
  );
END
$function$;

-- Owner neutralization: lf_profile_srcr_same_context_candidate_scope_v1
CREATE OR REPLACE FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1(p_execution_id text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
 e public.lf_operation_execution%rowtype;
 v40 jsonb; v50 jsonb; v60 jsonb; changes jsonb;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
 IF NOT FOUND OR e.status<>'IN_PROGRESS' OR e.operation_code<>'EJECUCION_PERFIL_LF'
    OR e.target_code<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    OR e.manifest->>'executor_mode'<>'GPT_NATIVE'
    OR e.manifest->>'governed_repair_write'<>'true'
    OR e.manifest->>'read_only'<>'false'
    OR e.manifest->>'no_write'<>'false'
    OR e.manifest->>'automatic_impact'<>'false'
    OR e.manifest#>>'{router_profile_handoff,router_authorization_receipt,effect_authority}' IS DISTINCT FROM 'false'
 THEN RETURN false; END IF;
 SELECT evidence_payload INTO v40 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='input_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO v50 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO v60 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 IF v40 IS NULL OR v50 IS NULL OR v60 IS NULL
    OR v40->>'analysis_scope'<>'READ_ONLY_WITH_IG_FINDINGS'
    OR v40->>'mutation_authorized' IS DISTINCT FROM 'false'
    OR v40->>'promotion_authorized' IS DISTINCT FROM 'false'
    OR v40#>>'{input_governance,analysis_scope}' IS DISTINCT FROM 'READ_ONLY_WITH_IG_FINDINGS'
    OR jsonb_typeof(v40->'allowed_actions')<>'array'
    OR NOT (v40->'allowed_actions' <@ '["ANALYZE","PROPOSE","VALIDATE","REPORT"]'::jsonb)
    OR v60#>>'{deterministic_validation,status}'<>'PASS'
 THEN RETURN false; END IF;
 changes:=v50#>'{profile_output,repair_execution,changes}';
 IF jsonb_typeof(changes)<>'array' OR jsonb_array_length(changes)=0 THEN RETURN false; END IF;
 IF EXISTS (
   SELECT 1 FROM jsonb_array_elements(changes) ch
   WHERE jsonb_typeof(ch)<>'object'
      OR coalesce(ch->>'target_ref','') !~ '^github://cristhianlujan/claude-persona-lf-patch@[0-9a-f]{40}/sandbox/lf_contract_gate_test/'
      OR coalesce(ch->>'after_ref','') IS DISTINCT FROM ch->>'target_ref'
      OR ch->>'before_ref' IS NOT NULL
      OR ch->>'change_type'<>'CREATE'
 ) THEN RETURN false; END IF;
 RETURN true;
END
$function$;

-- Owner neutralization: lf_profile_step70_clean_eval_context_verify_v1
CREATE OR REPLACE FUNCTION public.lf_profile_step70_clean_eval_context_verify_v1(p_execution_id text, p_semantic_judge_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
 e public.lf_operation_execution%ROWTYPE;
 r record;
 j jsonb;
 v50 public.lf_operation_execution_steps%ROWTYPE;
 v40 public.lf_operation_execution_steps%ROWTYPE;
 v60 public.lf_operation_execution_steps%ROWTYPE;
 n int:=0; tip text:=repeat('0',64); link_hash text;
 candidate text; scope_hash text; nonce_value text;
 expected_bundle text; bundle_hash text; producer_ctx text;
 producer_schema text; producer_eval text; producer_profile text;
 reviewer_ctx text; reviewer_schema text; reviewer_eval text;
 reviewer_profile text; receipt_ref text;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
 IF NOT FOUND OR e.status<>'IN_PROGRESS' OR e.operation_code<>'EJECUCION_PERFIL_LF'
    OR e.target_code<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    OR e.manifest->>'governed_repair_write'<>'true'
    OR p_semantic_judge_result->>'review_mode'<>'INDEPENDENT_EVAL_CONTEXT'
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_SCOPE_INVALID'); END IF;
 SELECT * INTO v40 FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='input_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT * INTO v50 FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT * INTO v60 FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 IF v40.step_id IS NULL OR v50.step_id IS NULL OR v60.step_id IS NULL
   OR v60.evidence_payload#>>'{deterministic_validation,status}'<>'PASS'
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_UPSTREAM_NOT_CLEAN'); END IF;
 candidate:=v50.evidence_payload->>'raw_output_sha256';
 scope_hash:=replace(v40.evidence_payload->>'scope_authority_packet_sha256','sha256:','');
 IF coalesce(candidate,'') !~ '^[0-9a-f]{64}$' OR coalesce(scope_hash,'') !~ '^[0-9a-f]{64}$'
  OR p_semantic_judge_result->>'candidate_sha256' IS DISTINCT FROM candidate
  OR p_semantic_judge_result->>'scope_packet_sha256' IS DISTINCT FROM scope_hash
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_SOURCE_SHA_DRIFT'); END IF;
 expected_bundle:=encode(extensions.digest(convert_to(
    'LF_STEP70_FROZEN_BUNDLE_V1|'||candidate||'|'||scope_hash||'|'||v50.evidence_ref,
    'UTF8'),'sha256'),'hex');
 FOR r IN SELECT * FROM public.lf_ig_native_chat_receipt_v1
    WHERE execution_id=p_execution_id ORDER BY seq LOOP
   n:=n+1;
   IF n>3 OR r.seq<>n OR r.kind<>(CASE n WHEN 1 THEN 'REQUEST' WHEN 2 THEN 'EXECUTOR' WHEN 3 THEN 'JUDGE' END)
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_SEQUENCE_DRIFT'); END IF;
   IF encode(extensions.digest(convert_to(r.raw_text,'UTF8'),'sha256'),'hex')<>r.raw_sha256
      OR r.prev_sha256<>tip
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_RAW_SHA_DRIFT'); END IF;
   link_hash:=encode(extensions.digest(convert_to(
     'LF_NATIVE_CHAT_EVENT_V1|'||r.execution_id||'|'||r.seq::text||'|'||
     r.kind||'|'||r.raw_sha256||'|'||r.prev_sha256||'|'||
     r.writer_receipt_sha256,'UTF8'),'sha256'),'hex');
   IF link_hash<>r.chain_sha256 OR r.recorded_at<e.created_at
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_CHAIN_DRIFT'); END IF;
   j:=r.raw_text::jsonb;
   IF jsonb_typeof(j)<>'object' OR j->>'stage' IS DISTINCT FROM r.kind
      OR j->>'execution_id' IS DISTINCT FROM p_execution_id
      OR j->>'candidate_sha256' IS DISTINCT FROM candidate
      OR j->>'scope_packet_sha256' IS DISTINCT FROM scope_hash
      OR j->>'frozen_bundle_sha256' IS DISTINCT FROM expected_bundle
      OR coalesce(j->>'nonce','')=''
      OR (nonce_value IS NOT NULL AND j->>'nonce' IS DISTINCT FROM nonce_value)
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_BINDING_DRIFT'); END IF;
   IF n=1 THEN
     nonce_value:=j->>'nonce';bundle_hash:=j->>'frozen_bundle_sha256';
   ELSIF n=2 THEN
     producer_ctx:=nullif(j->>'executor_context_ref','');
     producer_schema:=nullif(j->>'producer_schema_id','');
     producer_eval:=nullif(j->>'producer_eval_id','');
     producer_profile:=nullif(j->>'producer_profile_id','');
     IF producer_ctx IS NULL OR producer_schema IS NULL OR producer_eval IS NULL
        OR producer_profile IS NULL OR r.recorded_at<v50.created_at
     THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_PRODUCER_CONFIG_MISSING'); END IF;
   ELSIF n=3 THEN
     reviewer_ctx:=nullif(j->>'reviewer_context_ref','');
     reviewer_schema:=nullif(j->>'reviewer_schema_id','');
     reviewer_eval:=nullif(j->>'reviewer_eval_id','');
     reviewer_profile:=nullif(j->>'reviewer_profile_id','');
     receipt_ref:=r.writer_receipt_ref;
     IF reviewer_ctx IS NULL OR reviewer_ctx=producer_ctx OR reviewer_schema IS NULL
        OR reviewer_schema<>'LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1'
        OR reviewer_schema=producer_schema
        OR reviewer_eval<>'LF_STEP70_SAME_LLM_SEMANTIC_EVAL_V1'
        OR reviewer_eval=producer_eval
        OR reviewer_profile IS NULL OR reviewer_profile=producer_profile
        OR j->>'review_mode' IS DISTINCT FROM 'INDEPENDENT_EVAL_CONTEXT'
        OR j->>'eval_status' IS DISTINCT FROM 'PASS'
        OR j->>'reviewer_context_cleared' IS DISTINCT FROM 'true'
        OR j->'review_payload' IS DISTINCT FROM p_semantic_judge_result->'judge_v3_evidence'
        OR r.recorded_at<=v50.created_at
     THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_JUDGE_NOT_ISOLATED'); END IF;
   END IF;
   tip:=r.chain_sha256;
 END LOOP;
 IF n<>3 THEN RETURN jsonb_build_object('status','BLOCKED',
   'blocking_code','LF_STEP70_CLEAN_CONTEXT_RECEIPT_NOT_VERIFIED'); END IF;
 RETURN jsonb_build_object('status','CLEAN_CONTEXT_EVAL_VERIFIED',
   'execution_id',p_execution_id,'candidate_sha256',candidate,
   'scope_packet_sha256',scope_hash,'bundle_sha256',bundle_hash,
   'context_receipt_ref',receipt_ref,'reviewer_context_ref',reviewer_ctx,
   'producer_context_ref',producer_ctx,'judge_schema_id',reviewer_schema,
   'judge_eval_id',reviewer_eval,'chain_tip_sha256',tip,
   'provider_attestation_required',false,'effect_authority',false);
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object(
 'status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_RAW_JSON_INVALID');
END
$function$;


DO $ekb$
BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo='LF-QUALITY-CURRENT-CONTEXT-TECHNICAL-PASS-NOT-APPROVAL-20261115-001' AND estado='ACTIVO')<>1
 THEN RAISE EXCEPTION 'LF_OWNER_SCORE_OLD_EKB_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN (
  'LF-OWNER-SCORE-CURRENT-CONTEXT-PROMOTION-20261115-001',
  'LF-OWNER-OVERRIDE-NO_PROMOTION-MANIFEST-20261115-001'))
 THEN RAISE EXCEPTION 'LF_OWNER_SCORE_EKB_DUPLICATE'; END IF;
 UPDATE public.lf_error_knowledge SET estado='SUPERSEDED',updated_at=clock_timestamp()
 WHERE codigo='LF-QUALITY-CURRENT-CONTEXT-TECHNICAL-PASS-NOT-APPROVAL-20261115-001' AND estado='ACTIVO';
 INSERT INTO public.lf_error_knowledge(id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
 validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
 lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref,created_at,updated_at)
 VALUES
 (gen_random_uuid(),'LF-OWNER-SCORE-CURRENT-CONTEXT-PROMOTION-20261115-001','RULE_GOVERNANCE',
 'Owner: promoción por nota, sin simular juez independiente',
 'Owner 19:05 admite CURRENT_CONTEXT_REVIEW / PASS_REVIEWED_CURRENT_CONTEXT y hashes Step40/50/60/70 para solicitar promoción; no equivale a independencia. Nota A40 B30 C20 D10 y hard_block. AUTO intenta decide_v1 con identidad AUTO_SCORE_V1 y respeta su rechazo si exige humano.',
 'Gate de solicitud exigía independencia separada, imposibilitando evaluación y registro de candidatos.',
 'OWNER_SCORE_GOVERNED_CURRENT_CONTEXT',
 'Mantener hashes, sin unsupported_claims; no contar test de solo fixture como comportamiento. Si AUTO_SCORE_V1 no es humano, no falsificar HUMAN. <60 vuelve al Router; hard_block obliga MANUAL si >=60.',
 'PG17/18 BEGIN/ROLLBACK, CI real, pg_get_functiondef y SELECT del EKB por Merge Train.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),'LF_OWNER_SCORE_20261115','#4009','ACTIVO',
 'Owner 19:05, ruta de promoción y nota; independencia actual no acreditada.',
 'RULE_GOVERNANCE',ARRAY['PRODUCT_DIRECTOR','ROUTER','QUALITY']::text[],
 'R5_EROSION_PROCESO','LOUD_EARLY','Owner instruction 19:05 2026-11-15',
 'supabase/migrations/20261116001500_lf_owner_rule_promotion_score_and_manifest_neutral_v1.sql',
 clock_timestamp(),clock_timestamp()),
 (gen_random_uuid(),'LF-OWNER-OVERRIDE-NO_PROMOTION-MANIFEST-20261115-001','PROFILE_EXECUTION',
 'Owner: neutralizar no_promotion no aprobado como veto',
 'Owner 19:08 ordena retirar el bloqueo derivado exclusivamente de manifest.no_promotion=true en solicitud, cierre y caller; mantener verificaciones de fuente y permisos, y autorización humana expresa para borrados y actos irreversibles.',
 'Bandera de manifest fue confundida con autoridad final del dueño.',
 'GPT_UNAPPROVED_NO_PROMOTION_RESTRICTION',
 'No usar manifest.no_promotion como bloqueo; mantener hashes, Router, paso 70 y decisión de owner si se requiere. Eliminar frases fijas sandbox/NO-GO de plantillas actuales; no modificar hechos históricos.',
 'PG17/18, CI y definición SQL leída del sandbox tras Train.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),'LF_OWNER_SCORE_20261115','#4009','ACTIVO',
 'Owner 19:08, ninguna promoción ni producción ejecutada al instalar definiciones.',
 'PROFILE_EXECUTION',ARRAY['ROUTER','QUALITY','PRODUCT_DIRECTOR']::text[],
 'R5_EROSION_PROCESO','LOUD_EARLY','Owner instruction 19:08 2026-11-15',
 'supabase/migrations/20261116001500_lf_owner_rule_promotion_score_and_manifest_neutral_v1.sql',
 clock_timestamp(),clock_timestamp());
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE estado='ACTIVO' AND codigo IN (
 'LF-OWNER-SCORE-CURRENT-CONTEXT-PROMOTION-20261115-001',
 'LF-OWNER-OVERRIDE-NO_PROMOTION-MANIFEST-20261115-001'))<>2
 THEN RAISE EXCEPTION 'LF_OWNER_SCORE_EKB_INSERT_FAILED'; END IF;
END $ekb$;

COMMIT;
