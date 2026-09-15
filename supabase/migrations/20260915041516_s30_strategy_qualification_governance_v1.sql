-- S30 transversal correction: Strategy Qualification governance.
-- Finding: STRATEGY_QUALIFICATION_OPERATIONAL_STATE_COUPLING_DETECTED_20260914.
-- Related EKB: STRATEGY-QUALIFICATION-INDEPENDENT-REVIEW-BOOTSTRAP-DEADLOCK-001,
--              STRATEGY-QUALIFICATION-INDEPENDENT-REVIEW-FINALIZER-SUITE-STATE-GAP-001.
-- Scope only:
--   1) separate operational/handoff state from Strategy semantic revision;
--   2) require a real governed Strategy operation execution before qualification;
--   3) reuse canonical REVISION_INDEPENDIENTE_ESTRATEGIA_LF; create no reviewer/operation here.
-- No Strategy snapshot DML, no qualification rerun, no R15 continuation, no runtime/production activation.

DO $pre$
DECLARE
  x public.lf_operation_execution%rowtype;
  hash_def text;
  runner_def text;
BEGIN
  SELECT * INTO x
  FROM public.lf_operation_execution
  WHERE execution_id='EXEC-S30-STRATEGY-QUALIFICATION-GOVERNANCE-20260914-001';

  IF NOT FOUND
     OR x.operation_code<>'ACTUALIZACION_DB_LF'
     OR x.status<>'IN_PROGRESS'
     OR x.target_type<>'MIGRATION'
     OR x.target_code<>'S30_STRATEGY_QUALIFICATION_GOVERNANCE_V1'
     OR x.target_repo IS DISTINCT FROM 'cristhianlujan/claude-persona-lf-patch'
     OR x.target_path IS DISTINCT FROM 'supabase/migrations/20260915041000_s30_strategy_qualification_governance_v1.sql' THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_GOVERNANCE_EXECUTION_BINDING_INVALID';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_router_action_registry
    WHERE asset_type='MIGRATION'
      AND action_code='UPDATE'
      AND operation_code='ACTUALIZACION_DB_LF'
      AND status='ACTIVE'
      AND write_allowed
  ) THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_DB_ROUTE_NOT_ACTIVE';
  END IF;

  IF coalesce(x.manifest->>'operation_policy_source','')<>'SUPABASE'
     OR jsonb_typeof(x.manifest->'operation_policy_snapshots') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_DB_POLICY_SNAPSHOT_MISSING';
  END IF;

  SELECT pg_get_functiondef('public.lf_strategy_revision_sha256_from_json_v1(jsonb)'::regprocedure)
    INTO hash_def;
  IF strpos(hash_def,'strategy_close')=0 OR strpos(hash_def,'metadata')=0 THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_HASH_SOURCE_DRIFT';
  END IF;

  SELECT pg_get_functiondef('public.lf_run_strategy_qualification_v1(bigint,text)'::regprocedure)
    INTO runner_def;
  IF strpos(runner_def,'insert into public.lf_qualification_receipts')=0 THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_RUNNER_SOURCE_DRIFT';
  END IF;

  IF to_regprocedure('public.lf_independent_strategy_review_begin_v1(text,uuid,uuid,bigint,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('public.lf_independent_strategy_review_finalize_v1(text)') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.lf_router_action_registry
       WHERE asset_type='STRATEGY'
         AND action_code='STRATEGY_INDEPENDENT_REVIEW'
         AND operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
         AND status='ACTIVE'
     ) THEN
    RAISE EXCEPTION 'S30_CANONICAL_INDEPENDENT_STRATEGY_REVIEW_SURFACE_MISSING';
  END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.lf_strategy_revision_sha256_from_json_v1(p_row jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  payload jsonb;
  semantic_metadata jsonb;
BEGIN
  semantic_metadata:=jsonb_strip_nulls(jsonb_build_object(
    'semantic', p_row #> '{metadata,semantic}',
    'policy_set_fingerprint', p_row #> '{metadata,policy_set_fingerprint}',
    'test_assurance', p_row #> '{metadata,test_assurance}'
  ));

  payload:=jsonb_build_object(
    'snapshot_code',p_row->'snapshot_code',
    'snapshot_family',p_row->'snapshot_family',
    'snapshot_type',p_row->'snapshot_type',
    'canonical_name',p_row->'canonical_name',
    'version',p_row->'version',
    'project_code',p_row->'project_code',
    'front_code',p_row->'front_code',
    'owner_name',p_row->'owner_name',
    'source_kind',p_row->'source_kind',
    'source_asset_code',p_row->'source_asset_code',
    'related_asset_codes',p_row->'related_asset_codes',
    'related_operation_codes',p_row->'related_operation_codes',
    'related_profile_codes',p_row->'related_profile_codes',
    'content_payload',p_row->'content_payload',
    'sections',p_row->'sections',
    'decisions',p_row->'decisions',
    'backlog',p_row->'backlog',
    'risks',p_row->'risks',
    'tags',p_row->'tags',
    'semantic_metadata',semantic_metadata
  );

  RETURN encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex');
END
$function$;

CREATE OR REPLACE FUNCTION public.lf_run_strategy_qualification_v1(
  p_snapshot_id bigint,
  p_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  s public.lf_strategy_snapshots%rowtype;
  x public.lf_operation_execution%rowtype;
  rev text;
  cf text;
  qid uuid;
  qstate text;
  b public.lf_test_requirement_bindings%rowtype;
  rr jsonb;
  ids uuid[] := '{}'::uuid[];
  any_fail boolean := false;
  any_review boolean := false;
  fp text;
BEGIN
  IF btrim(coalesce(p_execution_id,''))='' THEN
    RAISE EXCEPTION 'LF_STRATEGY_QUALIFICATION_EXECUTION_REQUIRED';
  END IF;

  SELECT * INTO s
  FROM public.lf_strategy_snapshots
  WHERE id=p_snapshot_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LF_STRATEGY_QUALIFICATION_TARGET_MISSING:%',p_snapshot_id;
  END IF;

  SELECT * INTO x
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LF_STRATEGY_QUALIFICATION_EXECUTION_MISSING:%',p_execution_id;
  END IF;
  IF x.status<>'IN_PROGRESS' THEN
    RAISE EXCEPTION 'LF_STRATEGY_QUALIFICATION_EXECUTION_NOT_ACTIVE:%:%',p_execution_id,x.status;
  END IF;
  IF x.target_type<>'STRATEGY' THEN
    RAISE EXCEPTION 'LF_STRATEGY_QUALIFICATION_EXECUTION_NOT_STRATEGY:%:%',p_execution_id,x.target_type;
  END IF;
  IF x.target_code IS DISTINCT FROM s.snapshot_code
     OR x.target_path IS DISTINCT FROM format('supabase://public/lf_strategy_snapshots/%s',s.id) THEN
    RAISE EXCEPTION 'LF_STRATEGY_QUALIFICATION_EXECUTION_TARGET_MISMATCH:%:%:%',p_execution_id,x.target_code,s.snapshot_code;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_registry r
    WHERE r.operation_code=x.operation_code
      AND r.applies_to_asset_type='STRATEGY'
  ) THEN
    RAISE EXCEPTION 'LF_STRATEGY_QUALIFICATION_EXECUTION_OPERATION_SCOPE_INVALID:%:%',p_execution_id,x.operation_code;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_router_action_registry a
    WHERE a.asset_type='STRATEGY'
      AND a.operation_code=x.operation_code
      AND a.status='ACTIVE'
  ) THEN
    RAISE EXCEPTION 'LF_STRATEGY_QUALIFICATION_EXECUTION_ROUTE_NOT_ACTIVE:%:%',p_execution_id,x.operation_code;
  END IF;

  IF coalesce(x.manifest->>'operation_policy_source','')<>'SUPABASE'
     OR jsonb_typeof(x.manifest->'operation_policy_snapshots') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'LF_STRATEGY_QUALIFICATION_EXECUTION_POLICY_SNAPSHOT_MISSING:%',p_execution_id;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_each(x.manifest->'operation_policy_snapshots')
  ) THEN
    RAISE EXCEPTION 'LF_STRATEGY_QUALIFICATION_EXECUTION_POLICY_SNAPSHOT_MISSING:%',p_execution_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.v_lf_operation_policy_snapshot p
    WHERE p.operation_code=x.operation_code
      AND p.required
      AND (
        NOT (x.manifest->'operation_policy_snapshots' ? p.policy_role)
        OR (x.manifest->'operation_policy_snapshots'->p.policy_role->>'policy_code') IS DISTINCT FROM p.policy_code
        OR (x.manifest->'operation_policy_snapshots'->p.policy_role->>'policy_version') IS DISTINCT FROM p.policy_version
        OR (x.manifest->'operation_policy_snapshots'->p.policy_role->>'policy_sha') IS DISTINCT FROM p.policy_sha
      )
  ) THEN
    RAISE EXCEPTION 'LF_STRATEGY_QUALIFICATION_EXECUTION_POLICY_SNAPSHOT_STALE:%:%',p_execution_id,x.operation_code;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution_steps es
    WHERE es.execution_id=p_execution_id
      AND es.step_id='init_execution'
      AND es.status='PASS_CLEAN'
  ) THEN
    RAISE EXCEPTION 'LF_STRATEGY_QUALIFICATION_INIT_STEP_NOT_CLEAN:%',p_execution_id;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution_steps es
    WHERE es.execution_id=p_execution_id
      AND es.step_id='router'
      AND es.status='PASS_CLEAN'
      AND es.evidence_payload#>>'{route_decision,operation_code}'=x.operation_code
  ) THEN
    RAISE EXCEPTION 'LF_STRATEGY_QUALIFICATION_ROUTER_STEP_NOT_CLEAN:%:%',p_execution_id,x.operation_code;
  END IF;

  rev:=public.lf_strategy_revision_sha256_v1(p_snapshot_id);
  cf:=public.lf_strategy_classification_fingerprint_v1(p_snapshot_id);
  fp:=public.lf_required_test_suite_fingerprint_v1('STRATEGY',s.snapshot_code);

  INSERT INTO public.lf_qualification_receipts(
    subject_type,subject_code,subject_ref,revision_sha256,classification_fingerprint,
    lifecycle_state_code,suite_set_fingerprint,created_by_execution_id
  ) VALUES(
    'STRATEGY',s.snapshot_code,format('supabase://public/lf_strategy_snapshots/%s',s.id),
    rev,cf,null,fp,p_execution_id
  ) RETURNING qualification_id INTO qid;

  qstate:=public.lf_lifecycle_resolve_transition_v1(
    'QUALIFICATION_LIFECYCLE',
    public.lf_lifecycle_initial_state_v1('QUALIFICATION_LIFECYCLE'),
    'START_QUALIFICATION'
  );
  UPDATE public.lf_qualification_receipts
     SET lifecycle_state_code=qstate,updated_by_execution_id=p_execution_id
   WHERE qualification_id=qid;

  FOR b IN
    SELECT trb.*
    FROM public.lf_test_requirement_bindings AS trb
    WHERE trb.subject_type='STRATEGY'
      AND (trb.subject_code='*' OR trb.subject_code=s.snapshot_code)
      AND trb.status='ACTIVE'
      AND trb.required
      AND trb.effective_from<=clock_timestamp()
      AND public.lf_test_requirement_applies_v1(trb.binding_code,'STRATEGY',s.snapshot_code)
    ORDER BY trb.binding_code
  LOOP
    rr:=public.lf_run_strategy_matrix_suite_v1(
      b.suite_code,'STRATEGY',s.snapshot_code,rev,p_execution_id
    );
    ids:=array_append(ids,(rr->>'suite_run_id')::uuid);
    IF rr->>'status'='FAILED' THEN
      any_fail:=true;
    ELSIF rr->>'status'='REVIEW_REQUIRED' THEN
      any_review:=true;
    END IF;
  END LOOP;

  UPDATE public.lf_qualification_receipts
     SET suite_run_ids=ids,updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id
   WHERE qualification_id=qid;

  IF any_fail THEN
    UPDATE public.lf_qualification_receipts
       SET lifecycle_state_code=public.lf_lifecycle_resolve_transition_v1(
             'QUALIFICATION_LIFECYCLE',lifecycle_state_code,'FAIL_QUALIFICATION'
           ),
           findings=findings||jsonb_build_array(jsonb_build_object('type','MATRIX_FAILED')),
           updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id
     WHERE qualification_id=qid;
  ELSIF NOT any_review THEN
    UPDATE public.lf_qualification_receipts
       SET lifecycle_state_code=public.lf_lifecycle_resolve_transition_v1(
             'QUALIFICATION_LIFECYCLE',lifecycle_state_code,'PASS_QUALIFICATION'
           ),
           qualified_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id
     WHERE qualification_id=qid;
  END IF;

  RETURN (
    SELECT jsonb_build_object(
      'qualification_id',qualification_id,
      'subject_code',subject_code,
      'revision_sha256',revision_sha256,
      'classification_fingerprint',classification_fingerprint,
      'lifecycle_state_code',lifecycle_state_code,
      'suite_run_ids',suite_run_ids,
      'suite_set_fingerprint',suite_set_fingerprint,
      'governed_execution_id',p_execution_id,
      'governed_operation_code',x.operation_code
    )
    FROM public.lf_qualification_receipts
    WHERE qualification_id=qid
  );
END
$function$;

DO $semantic_canary$
DECLARE
  base_row jsonb;
  operational_row jsonb;
  semantic_row jsonb;
  base_sha text;
  operational_sha text;
  semantic_sha text;
BEGIN
  SELECT to_jsonb(s) INTO base_row
  FROM public.lf_strategy_snapshots s
  WHERE s.id=35;
  IF base_row IS NULL THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_CANARY_FIXTURE_MISSING';
  END IF;

  base_sha:=public.lf_strategy_revision_sha256_from_json_v1(base_row);

  operational_row:=base_row
    || jsonb_build_object(
         'status','S30_OPERATIONAL_CANARY',
         'visibility','S30_OPERATIONAL_CANARY',
         'runtime_state','S30_OPERATIONAL_CANARY',
         'impact_policy','S30_OPERATIONAL_CANARY',
         'lifecycle_state_code','S30_OPERATIONAL_CANARY',
         'updated_by_execution_id','S30_OPERATIONAL_CANARY',
         'updated_at','2099-01-01T00:00:00Z'
       );
  operational_row:=jsonb_set(
    operational_row,
    '{metadata}',
    coalesce(operational_row->'metadata','{}'::jsonb)
      || jsonb_build_object(
           'progress',jsonb_build_object('canary','operational_only'),
           'strategy_close',jsonb_build_object('status','CANARY'),
           'next_handoff',jsonb_build_object('canary','handoff_only'),
           'execution_frontier',jsonb_build_array('CANARY')
         ),
    true
  );
  operational_row:=jsonb_set(operational_row,'{evidence_refs}',jsonb_build_array(jsonb_build_object('canary',true)),true);
  operational_row:=jsonb_set(operational_row,'{change_log}',jsonb_build_array(jsonb_build_object('canary',true)),true);

  operational_sha:=public.lf_strategy_revision_sha256_from_json_v1(operational_row);
  IF operational_sha IS DISTINCT FROM base_sha THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_OPERATIONAL_COUPLING_REMAINS:%:%',base_sha,operational_sha;
  END IF;

  semantic_row:=jsonb_set(
    base_row,
    '{content_payload,__s30_strategy_qualification_semantic_canary}',
    'true'::jsonb,
    true
  );
  semantic_sha:=public.lf_strategy_revision_sha256_from_json_v1(semantic_row);
  IF semantic_sha IS NOT DISTINCT FROM base_sha THEN
    RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_SEMANTIC_CHANGE_NOT_DETECTED:%',base_sha;
  END IF;
END
$semantic_canary$;

DO $execution_canary$
DECLARE
  before_count bigint;
  after_count bigint;
  blocked boolean;
BEGIN
  SELECT count(*) INTO before_count FROM public.lf_qualification_receipts;

  blocked:=false;
  BEGIN
    PERFORM public.lf_run_strategy_qualification_v1(35,'EXEC-S30-QUALIFICATION-NONEXISTENT-CANARY');
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'LF_STRATEGY_QUALIFICATION_EXECUTION_MISSING:%' THEN blocked:=true; ELSE RAISE; END IF;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_MISSING_EXECUTION_CANARY_NOT_BLOCKED'; END IF;

  blocked:=false;
  BEGIN
    PERFORM public.lf_run_strategy_qualification_v1(35,'EXEC-S30-STRATEGY-QUALIFICATION-GOVERNANCE-20260914-001');
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'LF_STRATEGY_QUALIFICATION_EXECUTION_NOT_STRATEGY:%' THEN blocked:=true; ELSE RAISE; END IF;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_WRONG_OPERATION_CONTAINER_CANARY_NOT_BLOCKED'; END IF;

  SELECT count(*) INTO after_count FROM public.lf_qualification_receipts;
  IF after_count<>before_count THEN RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_NEGATIVE_CANARY_LEFT_RECEIPT:%:%',before_count,after_count; END IF;
END
$execution_canary$;

DO $post$
DECLARE
  hash_def text;
  runner_def text;
BEGIN
  SELECT pg_get_functiondef('public.lf_strategy_revision_sha256_from_json_v1(jsonb)'::regprocedure) INTO hash_def;
  IF strpos(hash_def,'''semantic_metadata''')=0 OR strpos(hash_def,'''content_payload''')=0 OR strpos(hash_def,'''backlog''')=0 OR strpos(hash_def,'''runtime_state''')>0 THEN RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_SEMANTIC_HASH_POSTCHECK_FAILED'; END IF;
  SELECT pg_get_functiondef('public.lf_run_strategy_qualification_v1(bigint,text)'::regprocedure) INTO runner_def;
  IF strpos(runner_def,'LF_STRATEGY_QUALIFICATION_EXECUTION_MISSING')=0 OR strpos(runner_def,'LF_STRATEGY_QUALIFICATION_EXECUTION_ROUTE_NOT_ACTIVE')=0 OR strpos(runner_def,'LF_STRATEGY_QUALIFICATION_INIT_STEP_NOT_CLEAN')=0 OR strpos(runner_def,'LF_STRATEGY_QUALIFICATION_ROUTER_STEP_NOT_CLEAN')=0 OR strpos(runner_def,'operation_policy_snapshots')=0 THEN RAISE EXCEPTION 'S30_STRATEGY_QUALIFICATION_EXECUTION_GUARD_POSTCHECK_FAILED'; END IF;
END
$post$;

UPDATE public.lf_operation_execution
SET manifest=manifest||jsonb_build_object(
      'result','S30_STRATEGY_QUALIFICATION_GOVERNANCE_SOURCE_APPLIED',
      'semantic_operational_separation_canary','PASS',
      'semantic_change_detection_canary','PASS',
      'synthetic_execution_negative_canary','PASS_ZERO_RECEIPT',
      'wrong_operation_container_negative_canary','PASS_ZERO_RECEIPT',
      'independent_review_reused','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
      's36_assurance_required_before_r15_requalification',true,
      'r15_requalification_performed',false,
      'runtime_activation',false,
      'production_activation',false
    ),
    status='COMPLETED',
    completed_at=clock_timestamp(),
    updated_by_execution_id='EXEC-S30-STRATEGY-QUALIFICATION-GOVERNANCE-20260914-001',
    updated_at=clock_timestamp()
WHERE execution_id='EXEC-S30-STRATEGY-QUALIFICATION-GOVERNANCE-20260914-001';