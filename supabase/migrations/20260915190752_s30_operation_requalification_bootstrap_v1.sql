-- S30-R22: harden canonical Operation qualification runner.
-- Scope: qualification governance only. No business/runtime/production effects.

CREATE OR REPLACE FUNCTION public.lf_run_operation_qualification_v1(
  p_operation_code text,
  p_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  r public.lf_operation_registry%rowtype;
  x public.lf_operation_execution%rowtype;
  rev text;
  fp text;
  qid uuid;
  qstate text;
  b public.lf_test_requirement_bindings%rowtype;
  rr jsonb;
  ids uuid[] := '{}'::uuid[];
  any_fail boolean := false;
  any_review boolean := false;
BEGIN
  IF btrim(coalesce(p_operation_code,''))='' THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_TARGET_REQUIRED';
  END IF;
  IF btrim(coalesce(p_execution_id,''))='' THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_EXECUTION_REQUIRED';
  END IF;

  SELECT * INTO r
  FROM public.lf_operation_registry
  WHERE operation_code=p_operation_code;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_TARGET_MISSING:%',p_operation_code;
  END IF;

  rev:=public.lf_operation_revision_sha256_v1(p_operation_code);
  fp:=public.lf_required_test_suite_fingerprint_v1('OPERATION',p_operation_code);

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_test_requirement_bindings trb
    WHERE trb.subject_type='OPERATION'
      AND (trb.subject_code='*' OR trb.subject_code=p_operation_code)
      AND trb.status='ACTIVE'
      AND trb.required
      AND trb.effective_from<=clock_timestamp()
      AND public.lf_test_requirement_applies_v1(trb.binding_code,'OPERATION',p_operation_code)
  ) THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_REQUIRED_SUITE_MISSING:%',p_operation_code;
  END IF;

  SELECT * INTO x
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_EXECUTION_MISSING:%',p_execution_id;
  END IF;
  IF x.status<>'IN_PROGRESS' THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_EXECUTION_NOT_ACTIVE:%:%',p_execution_id,x.status;
  END IF;
  IF x.operation_code IS DISTINCT FROM p_operation_code THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_EXECUTION_OPERATION_MISMATCH:%:%:%',p_execution_id,x.operation_code,p_operation_code;
  END IF;
  IF x.target_type IS DISTINCT FROM 'OPERATION'
     OR x.target_code IS DISTINCT FROM p_operation_code
     OR x.target_path IS DISTINCT FROM 'supabase://public/lf_operation_registry/'||p_operation_code THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_EXECUTION_TARGET_MISMATCH:%:%:%',p_execution_id,x.target_type,x.target_code;
  END IF;
  IF coalesce((x.manifest->>'operation_requalification_bootstrap_only')::boolean,false) IS NOT TRUE
     OR coalesce(x.manifest->>'mode','')<>'OPERATION_REQUALIFICATION_BOOTSTRAP_ONLY' THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_EXECUTION_MODE_INVALID:%',p_execution_id;
  END IF;
  IF x.manifest->>'qualification_target_operation' IS DISTINCT FROM p_operation_code
     OR x.manifest->>'qualification_target_revision_sha256' IS DISTINCT FROM rev
     OR x.manifest->>'qualification_target_suite_fingerprint' IS DISTINCT FROM fp THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_EXECUTION_CURRENTNESS_MISMATCH:%',p_execution_id;
  END IF;

  IF jsonb_typeof(x.manifest->'route_binding') IS DISTINCT FROM 'object'
     OR btrim(coalesce(x.manifest#>>'{route_binding,asset_type}',''))=''
     OR btrim(coalesce(x.manifest#>>'{route_binding,action_code}',''))='' THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_ROUTE_BINDING_MISSING:%',p_execution_id;
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_router_action_registry a
    WHERE a.asset_type=x.manifest#>>'{route_binding,asset_type}'
      AND a.action_code=x.manifest#>>'{route_binding,action_code}'
      AND a.operation_code=p_operation_code
      AND a.status='ACTIVE'
  ) THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_ROUTE_NOT_ACTIVE:%:%',p_execution_id,p_operation_code;
  END IF;
  IF r.applies_to_asset_type IS NOT NULL
     AND r.applies_to_asset_type IS DISTINCT FROM x.manifest#>>'{route_binding,asset_type}' THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_ROUTE_SCOPE_MISMATCH:%:%:%',p_operation_code,r.applies_to_asset_type,x.manifest#>>'{route_binding,asset_type}';
  END IF;

  IF coalesce(x.manifest->>'operation_policy_source','')<>'SUPABASE'
     OR jsonb_typeof(x.manifest->'operation_policy_snapshots') IS DISTINCT FROM 'object'
     OR NOT EXISTS (SELECT 1 FROM jsonb_each(x.manifest->'operation_policy_snapshots')) THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_POLICY_SNAPSHOT_MISSING:%',p_execution_id;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.v_lf_operation_policy_snapshot p
    WHERE p.operation_code=p_operation_code
      AND p.required
      AND (
        NOT (x.manifest->'operation_policy_snapshots' ? p.policy_role)
        OR (x.manifest->'operation_policy_snapshots'->p.policy_role->>'policy_code') IS DISTINCT FROM p.policy_code
        OR (x.manifest->'operation_policy_snapshots'->p.policy_role->>'policy_version') IS DISTINCT FROM p.policy_version
        OR (x.manifest->'operation_policy_snapshots'->p.policy_role->>'policy_sha') IS DISTINCT FROM p.policy_sha
      )
  ) THEN
    RAISE EXCEPTION 'LF_OPERATION_QUALIFICATION_POLICY_SNAPSHOT_STALE:%:%',p_execution_id,p_operation_code;
  END IF;

  INSERT INTO public.lf_qualification_receipts(
    subject_type,subject_code,subject_ref,revision_sha256,lifecycle_state_code,
    suite_set_fingerprint,created_by_execution_id
  ) VALUES(
    'OPERATION',p_operation_code,'supabase://public/lf_operation_registry/'||p_operation_code,
    rev,NULL,fp,p_execution_id
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
    FROM public.lf_test_requirement_bindings trb
    WHERE trb.subject_type='OPERATION'
      AND (trb.subject_code='*' OR trb.subject_code=p_operation_code)
      AND trb.status='ACTIVE'
      AND trb.required
      AND trb.effective_from<=clock_timestamp()
      AND public.lf_test_requirement_applies_v1(trb.binding_code,'OPERATION',p_operation_code)
    ORDER BY trb.binding_code
  LOOP
    rr:=public.lf_run_strategy_matrix_suite_v1(
      b.suite_code,'OPERATION',p_operation_code,rev,p_execution_id
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
      'lifecycle_state_code',lifecycle_state_code,
      'suite_run_ids',suite_run_ids,
      'suite_set_fingerprint',suite_set_fingerprint,
      'governed_execution_id',p_execution_id,
      'governed_operation_code',x.operation_code,
      'qualification_bootstrap_only',true
    )
    FROM public.lf_qualification_receipts
    WHERE qualification_id=qid
  );
END
$function$;
