-- S30/S36 transversal repair: governed independent Strategy qualification review.
-- EKB: STRATEGY-QUALIFICATION-INDEPENDENT-REVIEW-BOOTSTRAP-DEADLOCK-001
-- Scope: qualification evidence only. No Strategy snapshot mutation, runtime, production business effect, Golden or scheduler activation.
-- Bootstrap is bounded by fn_lf_operation_provenance_guard_v1: VULNERABILITY_COVERAGE_REPAIR_LF may create only this SANDBOX_ACTIVE operation.

DO $pre$
DECLARE
  c integer;
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_operation_registry WHERE operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF') THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_OPERATION_ALREADY_EXISTS';
  END IF;
  IF EXISTS (SELECT 1 FROM public.lf_router_action_registry WHERE asset_type='STRATEGY' AND action_code='STRATEGY_INDEPENDENT_REVIEW') THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_ROUTE_ALREADY_EXISTS';
  END IF;
  IF EXISTS (SELECT 1 FROM public.lf_test_suites WHERE suite_code='TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1') THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_SUITE_ALREADY_EXISTS';
  END IF;
  IF EXISTS (SELECT 1 FROM public.lf_test_requirement_bindings WHERE binding_code='BIND-OP-STRATEGY-INDEPENDENT-REVIEW-V1') THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_BINDING_ALREADY_EXISTS';
  END IF;
  SELECT count(*) INTO c FROM public.lf_activos
   WHERE codigo_activo IN ('POL-LF-OPERATION-LIFECYCLE','POL-LF-POLICY-CONSUMPTION','POL-LF-SOURCE-RESOLUTION','POL-LF-STATE-MODEL');
  IF c<>4 THEN RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_POLICY_GAP:%',c; END IF;
  IF to_regprocedure('public.lf_record_test_judge_result_v1(uuid,text,text,text,text,jsonb,text,jsonb)') IS NULL
     OR to_regprocedure('public.lf_finalize_qualification_independent_review_v1(uuid,text,jsonb)') IS NULL
     OR to_regprocedure('public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)') IS NULL THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_REQUIRED_RUNTIME_MISSING';
  END IF;
END $pre$;

INSERT INTO public.lf_operation_execution(
  execution_id,operation_code,target_type,target_code,status,manifest,created_by_execution_id,updated_by_execution_id
) VALUES (
  'EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001',
  'VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_PROTOCOL_REPAIR','REVISION_INDEPENDIENTE_ESTRATEGIA_LF','IN_PROGRESS',
  '{"mode":"INDEPENDENT_STRATEGY_REVIEW_OPERATION_BOOTSTRAP","governance_bootstrap":true,"bootstrap_operation_code":"REVISION_INDEPENDIENTE_ESTRATEGIA_LF","bootstrap_status_ceiling":"SANDBOX_ACTIVE","production_allowed":false,"runtime_activation":false,"strategy_snapshot_mutation":false,"qualification_evidence_only":true,"operation_policy_snapshots":{}}'::jsonb,
  'EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'
);

INSERT INTO public.lf_operation_registry(
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,
  created_by_execution_id,updated_by_execution_id,lifecycle_state_code
) VALUES (
  'REVISION_INDEPENDIENTE_ESTRATEGIA_LF','v1.0','SANDBOX_ACTIVE','SUPABASE_STRUCTURED_OPERATION',
  'cristhianlujan/claude-persona-lf-patch',
  '["supabase/migrations/20260915031921_s30_independent_strategy_review_operation_v1.sql","public.lf_independent_strategy_review_begin_v1","public.lf_record_independent_strategy_review_step_v1","public.lf_independent_strategy_review_record_judge_v1","public.lf_independent_strategy_review_finalize_v1"]'::jsonb,
  'Transversal independent review for Strategy qualification REVIEW_REQUIRED cases. Reviewer identity is its own governed operation execution; it does not require another Strategy to be qualification_current.',
  'GOVERNANCE','STRATEGY_ASSURANCE','INDEPENDENT_REVIEW','STRATEGY',
  'EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001',
  'EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','OP_CANDIDATE'
);

INSERT INTO public.lf_operation_contracts(
  operation_code,contract_code,contract_path,required_before_write,allowed,blocked,required_after_write,status,
  created_by_execution_id,updated_by_execution_id
) VALUES (
  'REVISION_INDEPENDIENTE_ESTRATEGIA_LF','CONTRACT-REVISION-INDEPENDIENTE-ESTRATEGIA-LF-v1',
  'supabase/migrations/20260915031921_s30_independent_strategy_review_operation_v1.sql',
  '["router_receipt","operation_qualification_current","qualification_bound","exact_strategy_revision","exact_suite_fingerprint","review_required_test","independent_reviewer_execution","evidence_refs"]'::jsonb,
  '{"qualification_evidence_write_allowed":true,"independent_review_required":true,"reviewer_must_be_operation_execution":true,"reviewer_must_complete_before_finalizer":true,"direct_business_write_allowed":false,"strategy_snapshot_mutation_allowed":false,"runtime_activation":false,"production_activation":false,"scheduler_activation":false,"orchestrator_activation":false}'::jsonb,
  '["direct_strategy_snapshot_write","runtime_enable","production_enable","scheduler_enable","orchestrator_enable","stale_revision","stale_suite_fingerprint","reviewer_equals_producer","judge_without_evidence","finalize_before_reviewer_completed","unrouted_execution"]'::jsonb,
  '["judge_receipt","reviewer_execution_completed","qualification_finalizer_receipt","qualification_readback"]'::jsonb,
  'ACTIVE_ENFORCEMENT','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'
);

WITH s(o,id,purpose,keys,next_step,judge) AS (VALUES
  (10,'route_bind','Bind ACT-0001 route and exact independent-review operation.',
    '["router_receipt","operation_code"]'::jsonb,'target_currentness','JUDGE-INDEPENDENT-STRATEGY-REVIEW-ROUTE-v1'),
  (20,'target_currentness','Bind current Strategy qualification, revision, fingerprint, suite and REVIEW_REQUIRED test.',
    '["qualification_id","snapshot_id","revision_sha256","suite_set_fingerprint","suite_run_id","test_run_id"]'::jsonb,'semantic_review','JUDGE-INDEPENDENT-STRATEGY-REVIEW-CURRENTNESS-v1'),
  (30,'semantic_review','Persist independent semantic verdict rationale and evidence references before judge recording.',
    '["verdict","review_type","review_context","rationale_summary","evidence_refs"]'::jsonb,'judge_record','JUDGE-INDEPENDENT-STRATEGY-REVIEW-SEMANTIC-v1'),
  (40,'judge_record','Prove canonical judge result was recorded by this reviewer execution.',
    '["judge_result_id","verdict","test_run_id"]'::jsonb,'reviewer_readback','JUDGE-INDEPENDENT-STRATEGY-REVIEW-JUDGE-v1'),
  (50,'reviewer_readback','Re-read judge and target currentness before reviewer completion.',
    '["judge_result_id","qualification_id","revision_sha256","suite_set_fingerprint"]'::jsonb,'report_output','JUDGE-INDEPENDENT-STRATEGY-REVIEW-READBACK-v1'),
  (60,'report_output','Close reviewer execution only after all required review steps are clean.',
    '["review_receipt","evidence_refs","next_gate"]'::jsonb,NULL,'JUDGE-INDEPENDENT-STRATEGY-REVIEW-REPORT-v1')
), ins AS (
  INSERT INTO public.lf_operation_steps(
    operation_code,step_order,step_id,required,evidence_required,source_path,active,execution_order,created_by_execution_id,updated_by_execution_id
  )
  SELECT 'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',o,id,true,
         array_to_string(ARRAY(SELECT jsonb_array_elements_text(keys)),','),
         'supabase://public/lf_operation_step_contracts/REVISION_INDEPENDIENTE_ESTRATEGIA_LF/'||id,
         true,o,'EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'
  FROM s RETURNING 1
)
INSERT INTO public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,output_payload,
  pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,
  status,notes,fail_condition,created_by_execution_id,updated_by_execution_id
)
SELECT 'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',id,o,o,'CONTRACT-REVISION-INDEPENDIENTE-ESTRATEGIA-LF-v1',purpose,
       '[]'::jsonb,
       CASE id
         WHEN 'route_bind' THEN 'public.lf_router_resolve_v1'
         WHEN 'target_currentness' THEN 'public.lf_qualification_current_v1'
         WHEN 'semantic_review' THEN 'GPT_RUNTIME_WITH_SUPABASE_CONTEXT'
         WHEN 'judge_record' THEN 'public.lf_record_test_judge_result_v1'
         WHEN 'reviewer_readback' THEN 'public.lf_test_judge_results'
         ELSE 'public.lf_record_operation_step_core_v1'
       END,
       keys,'{"server_assertions_complete":true,"required_evidence_present":true,"fail_closed":true}'::jsonb,
       '{"server_validation_failed":true}'::jsonb,
       'BLOCKED_REVISION_INDEPENDIENTE_ESTRATEGIA_'||upper(id),judge,keys,next_step,'RETURN_TO_ROUTER',
       'ACTIVE_ENFORCEMENT','Independent review is evidence-only until canonical finalizer runs.','{}'::jsonb,
       'EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'
FROM s;

INSERT INTO public.lf_operation_judges(
  operation_code,judge_code,judge_path,pass_if,fail_if,result_values,status,created_by_execution_id,updated_by_execution_id
) VALUES
('REVISION_INDEPENDIENTE_ESTRATEGIA_LF','JUDGE-INDEPENDENT-STRATEGY-REVIEW-ROUTE-v1','supabase://REVISION_INDEPENDIENTE_ESTRATEGIA_LF/route',
 '["router_ready","operation_exact"]'::jsonb,'["route_invalid"]'::jsonb,'["STEP_PASS_WITH_EVIDENCE","RETURN_TO_ROUTER","BLOCKED_STEP_NOT_CLEAN"]'::jsonb,'ACTIVE_ENFORCEMENT','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('REVISION_INDEPENDIENTE_ESTRATEGIA_LF','JUDGE-INDEPENDENT-STRATEGY-REVIEW-CURRENTNESS-v1','supabase://REVISION_INDEPENDIENTE_ESTRATEGIA_LF/currentness',
 '["qualification_bound","revision_current","suite_fingerprint_current","test_review_required"]'::jsonb,'["target_stale"]'::jsonb,'["STEP_PASS_WITH_EVIDENCE","RETURN_TO_ROUTER","BLOCKED_STEP_NOT_CLEAN"]'::jsonb,'ACTIVE_ENFORCEMENT','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('REVISION_INDEPENDIENTE_ESTRATEGIA_LF','JUDGE-INDEPENDENT-STRATEGY-REVIEW-SEMANTIC-v1','supabase://REVISION_INDEPENDIENTE_ESTRATEGIA_LF/semantic',
 '["review_receipt_shape_valid","review_context_independent","evidence_refs_present","verdict_allowed"]'::jsonb,'["review_receipt_invalid"]'::jsonb,'["STEP_PASS_WITH_EVIDENCE","RETURN_TO_ROUTER","BLOCKED_STEP_NOT_CLEAN"]'::jsonb,'ACTIVE_ENFORCEMENT','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('REVISION_INDEPENDIENTE_ESTRATEGIA_LF','JUDGE-INDEPENDENT-STRATEGY-REVIEW-JUDGE-v1','supabase://REVISION_INDEPENDIENTE_ESTRATEGIA_LF/judge',
 '["judge_persisted","judge_bound","judge_verdict_matches"]'::jsonb,'["judge_invalid"]'::jsonb,'["STEP_PASS_WITH_EVIDENCE","RETURN_TO_ROUTER","BLOCKED_STEP_NOT_CLEAN"]'::jsonb,'ACTIVE_ENFORCEMENT','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('REVISION_INDEPENDIENTE_ESTRATEGIA_LF','JUDGE-INDEPENDENT-STRATEGY-REVIEW-READBACK-v1','supabase://REVISION_INDEPENDIENTE_ESTRATEGIA_LF/readback',
 '["judge_readback","target_still_current","test_still_review_required"]'::jsonb,'["readback_invalid"]'::jsonb,'["STEP_PASS_WITH_EVIDENCE","RETURN_TO_ROUTER","BLOCKED_STEP_NOT_CLEAN"]'::jsonb,'ACTIVE_ENFORCEMENT','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('REVISION_INDEPENDIENTE_ESTRATEGIA_LF','JUDGE-INDEPENDENT-STRATEGY-REVIEW-REPORT-v1','supabase://REVISION_INDEPENDIENTE_ESTRATEGIA_LF/report',
 '["all_prior_clean","reviewer_ready_to_complete","target_still_current"]'::jsonb,'["completion_invalid"]'::jsonb,'["STEP_PASS_WITH_EVIDENCE","RETURN_TO_ROUTER","BLOCKED_STEP_NOT_CLEAN"]'::jsonb,'ACTIVE_ENFORCEMENT','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001');

WITH b(o,id,judge,keys) AS (VALUES
  (10,'route_bind','JUDGE-INDEPENDENT-STRATEGY-REVIEW-ROUTE-v1','["router_receipt","operation_code"]'::jsonb),
  (20,'target_currentness','JUDGE-INDEPENDENT-STRATEGY-REVIEW-CURRENTNESS-v1','["qualification_id","snapshot_id","revision_sha256","suite_set_fingerprint","suite_run_id","test_run_id"]'::jsonb),
  (30,'semantic_review','JUDGE-INDEPENDENT-STRATEGY-REVIEW-SEMANTIC-v1','["verdict","review_type","review_context","rationale_summary","evidence_refs"]'::jsonb),
  (40,'judge_record','JUDGE-INDEPENDENT-STRATEGY-REVIEW-JUDGE-v1','["judge_result_id","verdict","test_run_id"]'::jsonb),
  (50,'reviewer_readback','JUDGE-INDEPENDENT-STRATEGY-REVIEW-READBACK-v1','["judge_result_id","qualification_id","revision_sha256","suite_set_fingerprint"]'::jsonb),
  (60,'report_output','JUDGE-INDEPENDENT-STRATEGY-REVIEW-REPORT-v1','["review_receipt","evidence_refs","next_gate"]'::jsonb)
)
INSERT INTO public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
)
SELECT 'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',o,id,judge,
       'STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER',keys,'ACTIVE_ENFORCEMENT',
       'EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'
FROM b;

INSERT INTO public.lf_operation_policy_bindings(
  operation_code,policy_code,policy_role,required,distribution_modes,binding_status,created_by_execution_id,updated_by_execution_id
) VALUES
('REVISION_INDEPENDIENTE_ESTRATEGIA_LF','POL-LF-OPERATION-LIFECYCLE','GOVERNANCE_LIFECYCLE',true,ARRAY['ROUTER','DIRECT'],'ACTIVE','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('REVISION_INDEPENDIENTE_ESTRATEGIA_LF','POL-LF-POLICY-CONSUMPTION','POLICY_CONSUMPTION',true,ARRAY['ROUTER','DIRECT'],'ACTIVE','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('REVISION_INDEPENDIENTE_ESTRATEGIA_LF','POL-LF-SOURCE-RESOLUTION','SOURCE_RESOLUTION',true,ARRAY['ROUTER','DIRECT'],'ACTIVE','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('REVISION_INDEPENDIENTE_ESTRATEGIA_LF','POL-LF-STATE-MODEL','STATE_MODEL',true,ARRAY['ROUTER','DIRECT'],'ACTIVE','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001');

INSERT INTO public.lf_router_action_registry(
  asset_type,action_code,operation_code,operation_resolution,requires_existing_target,requires_missing_target,write_allowed,status,notes,
  created_by_execution_id,updated_by_execution_id
) VALUES (
  'STRATEGY','STRATEGY_INDEPENDENT_REVIEW','REVISION_INDEPENDIENTE_ESTRATEGIA_LF','STATIC',false,false,true,'ACTIVE',
  'Independent qualification review resolves exact Strategy snapshot/qualification inside the operation; no dependency on another Strategy execution.',
  'EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'
);

CREATE OR REPLACE FUNCTION public.lf_independent_strategy_review_begin_v1(
  p_execution_id text,
  p_qualification_id uuid,
  p_test_run_id uuid,
  p_snapshot_id bigint,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_manifest jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  s public.lf_strategy_snapshots%rowtype;
  q public.lf_qualification_receipts%rowtype;
  tr public.lf_test_runs%rowtype;
  sr public.lf_test_suite_runs%rowtype;
  route jsonb;
  r jsonb;
  rev text;
  fp text;
  policy_capsule jsonb := '{}'::jsonb;
  manifest jsonb;
BEGIN
  IF btrim(coalesce(p_execution_id,''))='' OR p_qualification_id IS NULL OR p_test_run_id IS NULL OR p_snapshot_id IS NULL
     OR coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$' OR btrim(coalesce(p_idempotency_key,''))=''
     OR btrim(coalesce(p_actor_execution_id,''))='' OR p_manifest IS NULL OR jsonb_typeof(p_manifest)<>'object' THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_BEGIN_INPUT_INVALID';
  END IF;

  SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=p_snapshot_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_SNAPSHOT_NOT_FOUND'; END IF;
  rev:=public.lf_strategy_revision_sha256_v1(s.id);
  fp:=public.lf_required_test_suite_fingerprint_v1('STRATEGY',s.snapshot_code);

  SELECT * INTO q FROM public.lf_qualification_receipts WHERE qualification_id=p_qualification_id;
  IF NOT FOUND OR q.subject_type<>'STRATEGY' OR q.subject_code<>s.snapshot_code
     OR q.revision_sha256<>rev OR q.suite_set_fingerprint<>fp OR q.lifecycle_state_code<>'QUAL_QUALIFYING' THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_QUALIFICATION_BINDING_INVALID';
  END IF;

  SELECT * INTO tr FROM public.lf_test_runs WHERE test_run_id=p_test_run_id;
  IF NOT FOUND OR tr.status<>'REVIEW_REQUIRED' OR tr.test_code<>'A03'
     OR tr.input_payload->>'probe_code'<>'INDEPENDENT_REVIEW' OR NOT (tr.suite_run_id=ANY(q.suite_run_ids)) THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_TEST_BINDING_INVALID';
  END IF;
  SELECT * INTO sr FROM public.lf_test_suite_runs WHERE suite_run_id=tr.suite_run_id;
  IF NOT FOUND OR sr.status<>'REVIEW_REQUIRED' THEN RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_SUITE_NOT_REVIEW_REQUIRED'; END IF;

  route:=public.lf_router_resolve_v1('revision independiente de qualification de estrategia',NULL,'STRATEGY_INDEPENDENT_REVIEW','STRATEGY','ROUTER');
  IF route->>'status'<>'READY_TO_EXECUTE' OR route->>'operation_code'<>'REVISION_INDEPENDIENTE_ESTRATEGIA_LF' THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_ROUTER_NOT_READY:%',route;
  END IF;
  PERFORM public.lf_operation_execution_qualification_guard_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF',clock_timestamp());

  SELECT coalesce(jsonb_object_agg(p.policy_role,jsonb_build_object(
      'policy_code',p.policy_code,'policy_version',p.policy_version,'policy_sha',p.policy_sha,'source_ref',p.source_ref
    )),'{}'::jsonb)
    INTO policy_capsule
  FROM public.v_lf_operation_policy_snapshot p
  WHERE p.operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF' AND p.required;

  manifest:=p_manifest || jsonb_build_object(
    'contract_code','CONTRACT-REVISION-INDEPENDIENTE-ESTRATEGIA-LF-v1',
    'qualification_id',p_qualification_id::text,
    'test_run_id',p_test_run_id::text,
    'suite_run_id',tr.suite_run_id::text,
    'snapshot_id',s.id,
    'snapshot_code',s.snapshot_code,
    'revision_sha256',rev,
    'suite_set_fingerprint',fp,
    'producer_execution_id',q.created_by_execution_id,
    'operation_policy_snapshots',policy_capsule,
    'runtime_activation',false,
    'production_activation',false,
    'business_effect_allowed',false
  );

  r:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,'REVISION_INDEPENDIENTE_ESTRATEGIA_LF','STRATEGY',s.snapshot_code,
    p_idempotency_key,p_request_sha256,p_actor_execution_id,NULL,
    'supabase://public/lf_qualification_receipts/'||p_qualification_id::text,manifest
  );
  IF r->>'status'<>'IN_PROGRESS' THEN RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_RESERVATION_NOT_IN_PROGRESS:%',r; END IF;
  RETURN r || jsonb_build_object('router_receipt',route,'target_revision_sha256',rev,'suite_set_fingerprint',fp,'next_step','route_bind');
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_record_independent_strategy_review_step_v1(
  p_execution_id text,p_step_id text,p_evidence_ref text,p_evidence_payload jsonb,p_actor_execution_id text
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  x public.lf_operation_execution%rowtype;
  q public.lf_qualification_receipts%rowtype;
  tr public.lf_test_runs%rowtype;
  jr public.lf_test_judge_results%rowtype;
  route jsonb;
  rev text;
  fp text;
  qid uuid;
  trid uuid;
  jrid uuid;
  sid bigint;
  assertions jsonb:='[]'::jsonb;
  hard_fails jsonb:='[]'::jsonb;
  valid boolean:=true;
  code text:='OK';
  trust jsonb;
  verdict text;
BEGIN
  IF p_evidence_payload IS NULL OR jsonb_typeof(p_evidence_payload)<>'object' THEN
    RETURN jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID','durable',false);
  END IF;
  SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
  IF NOT FOUND OR x.operation_code<>'REVISION_INDEPENDIENTE_ESTRATEGIA_LF' OR x.target_type<>'STRATEGY' OR x.status<>'IN_PROGRESS' THEN
    RETURN jsonb_build_object('outcome','BLOCKED','code','EXECUTION_IDENTITY_INVALID','durable',false);
  END IF;
  BEGIN
    qid:=(x.manifest->>'qualification_id')::uuid;
    trid:=(x.manifest->>'test_run_id')::uuid;
    sid:=(x.manifest->>'snapshot_id')::bigint;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('outcome','BLOCKED','code','EXECUTION_MANIFEST_BINDING_INVALID','durable',false);
  END;
  rev:=public.lf_strategy_revision_sha256_v1(sid);
  fp:=public.lf_required_test_suite_fingerprint_v1('STRATEGY',x.target_code);
  SELECT * INTO q FROM public.lf_qualification_receipts WHERE qualification_id=qid;
  SELECT * INTO tr FROM public.lf_test_runs WHERE test_run_id=trid;

  IF p_step_id='route_bind' THEN
    route:=public.lf_router_resolve_v1('revision independiente de qualification de estrategia',NULL,'STRATEGY_INDEPENDENT_REVIEW','STRATEGY','ROUTER');
    IF route->>'status'='READY_TO_EXECUTE' THEN assertions:=assertions||'"router_ready"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"route_invalid"'::jsonb; code:='ROUTE_INVALID'; END IF;
    IF route->>'operation_code'='REVISION_INDEPENDIENTE_ESTRATEGIA_LF' THEN assertions:=assertions||'"operation_exact"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"route_invalid"'::jsonb; code:='OPERATION_MISMATCH'; END IF;
  ELSIF p_step_id='target_currentness' THEN
    IF q.qualification_id=qid AND q.subject_code=x.target_code AND q.lifecycle_state_code='QUAL_QUALIFYING' THEN assertions:=assertions||'"qualification_bound"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"target_stale"'::jsonb; code:='QUALIFICATION_NOT_BOUND'; END IF;
    IF rev=x.manifest->>'revision_sha256' AND q.revision_sha256=rev THEN assertions:=assertions||'"revision_current"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"target_stale"'::jsonb; code:='REVISION_STALE'; END IF;
    IF fp=x.manifest->>'suite_set_fingerprint' AND q.suite_set_fingerprint=fp THEN assertions:=assertions||'"suite_fingerprint_current"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"target_stale"'::jsonb; code:='SUITE_FINGERPRINT_STALE'; END IF;
    IF tr.test_run_id=trid AND tr.status='REVIEW_REQUIRED' AND tr.test_code='A03' AND tr.input_payload->>'probe_code'='INDEPENDENT_REVIEW' AND tr.suite_run_id=ANY(q.suite_run_ids) THEN assertions:=assertions||'"test_review_required"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"target_stale"'::jsonb; code:='TEST_NOT_REVIEW_REQUIRED'; END IF;
  ELSIF p_step_id='semantic_review' THEN
    verdict:=upper(coalesce(p_evidence_payload->>'verdict',''));
    IF verdict IN ('PASS','FAIL') AND nullif(btrim(coalesce(p_evidence_payload->>'rationale_summary','')),'') IS NOT NULL
       AND p_evidence_payload->>'review_type' IN ('S36_ASSURANCE','INDEPENDENT_HOLDOUT') THEN assertions:=assertions||'"review_receipt_shape_valid"'::jsonb||'"verdict_allowed"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb; code:='REVIEW_RECEIPT_INVALID'; END IF;
    IF p_evidence_payload->>'review_context'='INDEPENDENT_OPERATION_CONTEXT' THEN assertions:=assertions||'"review_context_independent"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb; code:='REVIEW_CONTEXT_INVALID'; END IF;
    IF jsonb_typeof(p_evidence_payload->'evidence_refs')='array' AND jsonb_array_length(p_evidence_payload->'evidence_refs')>0 THEN assertions:=assertions||'"evidence_refs_present"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb; code:='REVIEW_EVIDENCE_MISSING'; END IF;
  ELSIF p_step_id IN ('judge_record','reviewer_readback','report_output') THEN
    BEGIN jrid:=coalesce(nullif(p_evidence_payload->>'judge_result_id',''),x.checkpoint_payload->>'judge_result_id')::uuid; EXCEPTION WHEN others THEN jrid:=NULL; END;
    IF jrid IS NOT NULL THEN SELECT * INTO jr FROM public.lf_test_judge_results WHERE judge_result_id=jrid; END IF;
    IF p_step_id='judge_record' THEN
      IF jr.judge_result_id=jrid THEN assertions:=assertions||'"judge_persisted"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"judge_invalid"'::jsonb; code:='JUDGE_NOT_FOUND'; END IF;
      IF jr.test_run_id=trid AND jr.created_by_execution_id=p_execution_id AND jr.metadata->>'reviewer_execution_id'=p_execution_id THEN assertions:=assertions||'"judge_bound"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"judge_invalid"'::jsonb; code:='JUDGE_BINDING_INVALID'; END IF;
      IF jr.verdict=upper(coalesce(x.checkpoint_payload->>'verdict','')) THEN assertions:=assertions||'"judge_verdict_matches"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"judge_invalid"'::jsonb; code:='JUDGE_VERDICT_MISMATCH'; END IF;
    ELSIF p_step_id='reviewer_readback' THEN
      IF jr.judge_result_id=jrid AND jr.test_run_id=trid AND jr.created_by_execution_id=p_execution_id THEN assertions:=assertions||'"judge_readback"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='JUDGE_READBACK_INVALID'; END IF;
      IF rev=x.manifest->>'revision_sha256' AND fp=x.manifest->>'suite_set_fingerprint' AND q.lifecycle_state_code='QUAL_QUALIFYING' THEN assertions:=assertions||'"target_still_current"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='TARGET_STALE_AT_READBACK'; END IF;
      IF tr.status='REVIEW_REQUIRED' THEN assertions:=assertions||'"test_still_review_required"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='TEST_STATE_CHANGED_BEFORE_FINALIZE'; END IF;
    ELSE
      IF NOT EXISTS (
        SELECT 1 FROM public.lf_operation_steps s
        LEFT JOIN public.lf_operation_execution_steps es ON es.execution_id=p_execution_id AND es.step_order=s.step_order AND es.step_id=s.step_id
        LEFT JOIN public.lf_operation_step_judge_bindings b ON b.operation_code=s.operation_code AND b.step_order=s.step_order AND b.step_id=s.step_id AND b.status='ACTIVE_ENFORCEMENT'
        WHERE s.operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF' AND s.required AND s.active AND s.step_id<>'report_output'
          AND (es.step_id IS NULL OR b.clean_result_value IS NULL OR es.status<>b.clean_result_value)
      ) THEN assertions:=assertions||'"all_prior_clean"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='PRIOR_STEPS_NOT_CLEAN'; END IF;
      IF jr.judge_result_id=jrid AND jr.created_by_execution_id=p_execution_id THEN assertions:=assertions||'"reviewer_ready_to_complete"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='JUDGE_NOT_BOUND_AT_COMPLETION'; END IF;
      IF rev=x.manifest->>'revision_sha256' AND fp=x.manifest->>'suite_set_fingerprint' AND q.lifecycle_state_code='QUAL_QUALIFYING' AND tr.status='REVIEW_REQUIRED' THEN assertions:=assertions||'"target_still_current"'::jsonb; ELSE valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='TARGET_STALE_AT_COMPLETION'; END IF;
    END IF;
  ELSE
    RETURN jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_SUPPORTED','durable',false);
  END IF;

  trust:=jsonb_build_object('valid',valid,'code',code,'server_assertions',assertions,'server_hard_fails',hard_fails,
    'details',jsonb_build_object('qualification_id',qid,'test_run_id',trid,'snapshot_id',sid,'current_revision',rev,'current_fingerprint',fp));
  RETURN public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'REVISION_INDEPENDIENTE_ESTRATEGIA_LF','STRATEGY',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',trust,true,'lf_record_independent_strategy_review_step_v1'
  );
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_independent_strategy_review_record_judge_v1(
  p_execution_id text,p_verdict text,p_evidence_payload jsonb,p_rationale_summary text,p_findings jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  x public.lf_operation_execution%rowtype;
  semantic_step public.lf_operation_execution_steps%rowtype;
  test_id uuid;
  r jsonb;
  step_r jsonb;
  jrid uuid;
  evidence jsonb;
BEGIN
  SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=p_execution_id FOR UPDATE;
  IF NOT FOUND OR x.operation_code<>'REVISION_INDEPENDIENTE_ESTRATEGIA_LF' OR x.status<>'IN_PROGRESS' THEN
    RETURN jsonb_build_object('result','BLOCKED','code','REVIEWER_EXECUTION_NOT_IN_PROGRESS');
  END IF;
  SELECT * INTO semantic_step FROM public.lf_operation_execution_steps
   WHERE execution_id=p_execution_id AND step_id='semantic_review' AND status='STEP_PASS_WITH_EVIDENCE';
  IF NOT FOUND THEN RETURN jsonb_build_object('result','BLOCKED','code','SEMANTIC_REVIEW_STEP_NOT_CLEAN'); END IF;
  IF upper(coalesce(p_verdict,'')) IS DISTINCT FROM upper(coalesce(semantic_step.evidence_payload->>'verdict','')) THEN
    RETURN jsonb_build_object('result','BLOCKED','code','JUDGE_VERDICT_DIFFERS_FROM_SEMANTIC_REVIEW');
  END IF;
  test_id:=(x.manifest->>'test_run_id')::uuid;
  evidence:=coalesce(p_evidence_payload,'{}'::jsonb)||jsonb_build_object(
    'qualification_id',x.manifest->>'qualification_id','snapshot_id',x.manifest->>'snapshot_id',
    'revision_sha256',x.manifest->>'revision_sha256','suite_set_fingerprint',x.manifest->>'suite_set_fingerprint',
    'reviewer_operation_code','REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
  );
  r:=public.lf_record_test_judge_result_v1(
    test_id,p_execution_id,'STRATEGY-QUAL-A03-INDEPENDENT-REVIEW-V1','S36_ASSURANCE',upper(p_verdict),
    evidence,p_rationale_summary,p_findings
  );
  IF r->>'result' NOT IN ('JUDGE_RECORDED','JUDGE_ALREADY_RECORDED_IDENTICAL') THEN RETURN r; END IF;
  jrid:=(r->>'judge_result_id')::uuid;
  UPDATE public.lf_operation_execution
     SET checkpoint_payload=coalesce(checkpoint_payload,'{}'::jsonb)||jsonb_build_object(
       'judge_result_id',jrid::text,'verdict',upper(p_verdict),'rationale_summary',p_rationale_summary,
       'evidence_refs',semantic_step.evidence_payload->'evidence_refs'
     ),updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id
   WHERE execution_id=p_execution_id;
  step_r:=public.lf_record_independent_strategy_review_step_v1(
    p_execution_id,'judge_record','supabase://public/lf_test_judge_results/'||jrid::text,
    jsonb_build_object('judge_result_id',jrid::text,'verdict',upper(p_verdict),'test_run_id',test_id::text),p_execution_id
  );
  RETURN r||jsonb_build_object('operation_step',step_r);
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_independent_strategy_review_finalize_v1(p_execution_id text) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  x public.lf_operation_execution%rowtype;
  qid uuid;
  test_id uuid;
  jrid uuid;
  jr public.lf_test_judge_results%rowtype;
  review_ref jsonb;
  r jsonb;
  rev text;
  current_ok boolean;
BEGIN
  SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=p_execution_id FOR UPDATE;
  IF NOT FOUND OR x.operation_code<>'REVISION_INDEPENDIENTE_ESTRATEGIA_LF' OR x.status<>'COMPLETED' OR x.completed_at IS NULL THEN
    RETURN jsonb_build_object('result','BLOCKED','code','REVIEWER_EXECUTION_NOT_COMPLETED');
  END IF;
  qid:=(x.manifest->>'qualification_id')::uuid;
  test_id:=(x.manifest->>'test_run_id')::uuid;
  jrid:=(x.checkpoint_payload->>'judge_result_id')::uuid;
  SELECT * INTO jr FROM public.lf_test_judge_results WHERE judge_result_id=jrid;
  IF NOT FOUND OR jr.test_run_id<>test_id OR jr.created_by_execution_id<>p_execution_id THEN
    RETURN jsonb_build_object('result','BLOCKED','code','FINALIZER_JUDGE_BINDING_INVALID');
  END IF;
  review_ref:=jsonb_build_object(
    'review_type','S36_ASSURANCE',
    'review_context','INDEPENDENT_OPERATION_CONTEXT',
    'assessor_execution_id',p_execution_id,
    'reviewer_operation_code','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
    'judge_result_id',jrid::text,
    'verdict',jr.verdict,
    'evidence_refs',coalesce(x.checkpoint_payload->'evidence_refs','[]'::jsonb),
    'qualification_id',qid::text,
    'test_run_id',test_id::text,
    'snapshot_id',x.manifest->>'snapshot_id',
    'revision_sha256',x.manifest->>'revision_sha256',
    'suite_set_fingerprint',x.manifest->>'suite_set_fingerprint'
  );
  r:=public.lf_finalize_qualification_independent_review_v1(qid,p_execution_id,review_ref);
  rev:=x.manifest->>'revision_sha256';
  current_ok:=public.lf_qualification_current_v1('STRATEGY',x.target_code,rev);
  UPDATE public.lf_operation_execution
     SET checkpoint_payload=coalesce(checkpoint_payload,'{}'::jsonb)||jsonb_build_object(
       'finalizer_receipt',r,'qualification_current_after',current_ok,'finalized_at',clock_timestamp()
     ),updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id
   WHERE execution_id=p_execution_id;
  IF r->>'result'='QUALIFIED' AND NOT current_ok THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_FINALIZER_CURRENTNESS_FAILED:%',r;
  END IF;
  RETURN r||jsonb_build_object('qualification_current',current_ok,'reviewer_execution_id',p_execution_id);
END $fn$;

REVOKE ALL ON FUNCTION public.lf_independent_strategy_review_begin_v1(text,uuid,uuid,bigint,text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_record_independent_strategy_review_step_v1(text,text,text,jsonb,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_independent_strategy_review_record_judge_v1(text,text,jsonb,text,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_independent_strategy_review_finalize_v1(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_independent_strategy_review_begin_v1(text,uuid,uuid,bigint,text,text,text,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_record_independent_strategy_review_step_v1(text,text,text,jsonb,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_independent_strategy_review_record_judge_v1(text,text,jsonb,text,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_independent_strategy_review_finalize_v1(text) TO service_role;

INSERT INTO public.lf_test_suites(
  suite_code,module_code,name,version,status,rule_set_code,execution_policy,metadata,created_by_execution_id,updated_by_execution_id
) VALUES (
  'TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','STRATEGY_GOVERNANCE','Independent Strategy Review Operation Qualification Matrix','v1','CANDIDATO',NULL,
  '{"exact_revision":true,"deterministic_first":true,"false_pass_tolerance":0}'::jsonb,
  '{"matrix_family":"OPERATION_QUALIFICATION","operation_code":"REVISION_INDEPENDIENTE_ESTRATEGIA_LF","bootstrap_deadlock_breaker":true}'::jsonb,
  'EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'
);

INSERT INTO public.lf_test_suite_cases(
  suite_code,test_code,test_order,title,test_type,execution_mode,severity,preconditions,input_payload,expected_output,prohibited_output,status,metadata,created_by_execution_id,updated_by_execution_id
) VALUES
('TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','Q01',10,'Operation state is catalog-bound','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"OP_REGISTRY_STATE_VALID"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','Q02',20,'Router action is active','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"ROUTER_ACTIVE"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','Q03',30,'Active contract exists','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"ACTIVE_CONTRACT_PRESENT"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','Q04',40,'Active steps exist','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"ACTIVE_STEPS_PRESENT"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','Q05',50,'All active steps have active judges','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"ALL_ACTIVE_STEPS_JUDGED"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','Q06',60,'Qualification binding is registered','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"QUALIFICATION_BINDING_PRESENT"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','Q07',70,'Qualification evidence write is allowed','CONTRACT','AUTOMATED','CRITICAL','{}','{"probe_code":"OP_CONTRACT_BOOL","key":"qualification_evidence_write_allowed","expected":true}','{"passed":true}','{}','CANDIDATO','{}','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','Q08',80,'Independent review is required','CONTRACT','AUTOMATED','CRITICAL','{}','{"probe_code":"OP_CONTRACT_BOOL","key":"independent_review_required","expected":true}','{"passed":true}','{}','CANDIDATO','{}','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','Q09',90,'Direct business writes are forbidden','CONTRACT','AUTOMATED','CRITICAL','{}','{"probe_code":"OP_CONTRACT_BOOL","key":"direct_business_write_allowed","expected":false}','{"passed":true}','{}','CANDIDATO','{}','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','Q10',100,'Strategy snapshot mutation is forbidden','CONTRACT','AUTOMATED','CRITICAL','{}','{"probe_code":"OP_CONTRACT_BOOL","key":"strategy_snapshot_mutation_allowed","expected":false}','{"passed":true}','{}','CANDIDATO','{}','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','Q11',110,'Runtime activation is forbidden','CONTRACT','AUTOMATED','HIGH','{}','{"probe_code":"OP_CONTRACT_BOOL","key":"runtime_activation","expected":false}','{"passed":true}','{}','CANDIDATO','{}','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','Q12',120,'Production activation is forbidden','CONTRACT','AUTOMATED','HIGH','{}','{"probe_code":"OP_CONTRACT_BOOL","key":"production_activation","expected":false}','{"passed":true}','{}','CANDIDATO','{}','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','Q13',130,'Scheduler activation is forbidden','CONTRACT','AUTOMATED','HIGH','{}','{"probe_code":"OP_CONTRACT_BOOL","key":"scheduler_activation","expected":false}','{"passed":true}','{}','CANDIDATO','{}','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'),
('TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1','Q14',140,'Orchestrator activation is forbidden','CONTRACT','AUTOMATED','HIGH','{}','{"probe_code":"OP_CONTRACT_BOOL","key":"orchestrator_activation","expected":false}','{"passed":true}','{}','CANDIDATO','{}','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001');

INSERT INTO public.lf_test_requirement_bindings(
  binding_code,subject_type,subject_code,characteristic_code,suite_code,required,min_pass_rate,false_pass_tolerance,
  independent_review_required,rollback_required,currentness_mode,activation_condition,effective_from,status,
  created_by_execution_id,updated_by_execution_id
) VALUES (
  'BIND-OP-STRATEGY-INDEPENDENT-REVIEW-V1','OPERATION','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',NULL,
  'TS-STRATEGY-OP-INDEPENDENT-REVIEW-V1',true,1.0,0,false,true,'EXACT_REVISION','{"type":"ALWAYS"}'::jsonb,
  clock_timestamp(),'ACTIVE','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001'
);

DO $qualify_and_promote$
DECLARE
  qr jsonb;
  op_rev text;
  promote_exec text:='EXEC-INDEPENDENT-STRATEGY-REVIEW-PROMOTE-20260915-001';
  policy_capsule jsonb:='{}'::jsonb;
  reserve_r jsonb;
  promote_r jsonb;
BEGIN
  qr:=public.lf_run_operation_qualification_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF','EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001');
  op_rev:=public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF');
  IF qr->>'lifecycle_state_code' IS DISTINCT FROM public.lf_lifecycle_action_target_state_v1('QUALIFICATION_LIFECYCLE','PASS_QUALIFICATION') THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_OPERATION_QUALIFICATION_FAILED:%',qr;
  END IF;
  IF NOT public.lf_qualification_current_v1('OPERATION','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',op_rev) THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_OPERATION_QUALIFICATION_NOT_CURRENT:%',op_rev;
  END IF;
  PERFORM public.lf_operation_execution_qualification_guard_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF',clock_timestamp());

  SELECT coalesce(jsonb_object_agg(p.policy_role,jsonb_build_object(
      'policy_code',p.policy_code,'policy_version',p.policy_version,'policy_sha',p.policy_sha,'source_ref',p.source_ref
    )),'{}'::jsonb)
    INTO policy_capsule
  FROM public.v_lf_operation_policy_snapshot p
  WHERE p.operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF' AND p.required;

  reserve_r:=public.fn_lf_operation_reserve_execution_v1(
    promote_exec,'REVISION_INDEPENDIENTE_ESTRATEGIA_LF','OPERATION','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
    'PROMOTE-INDEPENDENT-STRATEGY-REVIEW-V1',repeat('a',64),promote_exec,NULL,
    'supabase://public/lf_operation_registry/REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
    jsonb_build_object('scope','QUALIFIED_OPERATION_PROMOTION','qualification_required',true,
      'qualified_revision_sha256',op_rev,'operation_policy_source','SUPABASE','operation_policy_snapshots',policy_capsule)
  );
  IF reserve_r->>'status'<>'IN_PROGRESS' THEN RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_PROMOTION_EXEC_NOT_IN_PROGRESS:%',reserve_r; END IF;
  promote_r:=public.lf_promote_operation_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF',promote_exec);
  IF promote_r->>'to_state' IS DISTINCT FROM public.lf_lifecycle_action_target_state_v1('OPERATION_LIFECYCLE','PROMOTE_OPERATION') THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_PROMOTION_FAILED:%',promote_r;
  END IF;
  UPDATE public.lf_operation_execution
     SET status='COMPLETED',completed_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=promote_exec,
         manifest=manifest||jsonb_build_object('result','QUALIFIED_OPERATION_PROMOTED')
   WHERE execution_id=promote_exec AND status='IN_PROGRESS';
END $qualify_and_promote$;

UPDATE public.lf_operation_execution
SET status='COMPLETED',completed_at=clock_timestamp(),updated_at=clock_timestamp(),
    updated_by_execution_id=execution_id,manifest=manifest||jsonb_build_object('result','INDEPENDENT_STRATEGY_REVIEW_OPERATION_BOOTSTRAPPED_QUALIFIED_PROMOTED')
WHERE execution_id='EXEC-BOOTSTRAP-INDEPENDENT-STRATEGY-REVIEW-20260915-001' AND status='IN_PROGRESS';

DO $post$
DECLARE
  op_rev text;
  route jsonb;
  qstate text;
  c integer;
BEGIN
  op_rev:=public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF');
  qstate:=public.lf_lifecycle_action_target_state_v1('QUALIFICATION_LIFECYCLE','PASS_QUALIFICATION');
  IF NOT public.lf_qualification_current_v1('OPERATION','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',op_rev) THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_POST_QUALIFICATION_NOT_CURRENT';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      AND lifecycle_state_code=public.lf_lifecycle_action_target_state_v1('OPERATION_LIFECYCLE','PROMOTE_OPERATION')
  ) THEN RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_POST_NOT_OPERATIONAL'; END IF;
  SELECT count(*) INTO c FROM public.lf_test_requirement_bindings
    WHERE binding_code='BIND-OP-STRATEGY-INDEPENDENT-REVIEW-V1' AND status='ACTIVE' AND required;
  IF c<>1 THEN RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_POST_BINDING_COUNT:%',c; END IF;
  route:=public.lf_router_resolve_v1('revision independiente de qualification de estrategia',NULL,'STRATEGY_INDEPENDENT_REVIEW','STRATEGY','ROUTER');
  IF route->>'status'<>'READY_TO_EXECUTE' OR route->>'operation_code'<>'REVISION_INDEPENDIENTE_ESTRATEGIA_LF' THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_POST_ROUTER_NOT_READY:%',route;
  END IF;
  IF to_regprocedure('public.lf_independent_strategy_review_begin_v1(text,uuid,uuid,bigint,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('public.lf_record_independent_strategy_review_step_v1(text,text,text,jsonb,text)') IS NULL
     OR to_regprocedure('public.lf_independent_strategy_review_record_judge_v1(text,text,jsonb,text,jsonb)') IS NULL
     OR to_regprocedure('public.lf_independent_strategy_review_finalize_v1(text)') IS NULL THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_POST_RUNTIME_FUNCTION_MISSING';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.routine_privileges
    WHERE routine_schema='public' AND routine_name IN (
      'lf_independent_strategy_review_begin_v1','lf_record_independent_strategy_review_step_v1',
      'lf_independent_strategy_review_record_judge_v1','lf_independent_strategy_review_finalize_v1'
    ) AND grantee IN ('PUBLIC','anon','authenticated') AND privilege_type='EXECUTE'
  ) THEN RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_POST_PUBLIC_EXECUTE_EXPOSED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lf_qualification_receipts q WHERE q.subject_type='OPERATION' AND q.subject_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF' AND q.revision_sha256=op_rev AND q.lifecycle_state_code=qstate AND q.invalidated_at IS NULL) THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_POST_QUALIFICATION_RECEIPT_MISSING';
  END IF;
END $post$;
