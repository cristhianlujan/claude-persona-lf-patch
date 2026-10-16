-- Candidate: preserve exact original request across an existing governed profile execution.
-- Router ACT-0001 -> ACTUALIZACION_DB_LF -> Migration Merge Train only.
-- Reuses input_literal, queue_request_id and the scope-authority packet; no new
-- queue, runtime, profile selector, ACL, operation, UI change or model activation.
-- Existing Router fail-closed on unattested executors remains unchanged.
-- EKB reviewed: LF-ROUTER-ACT0001-CROSSROLE-LEXICAL-20261016-005,
-- LF-ROUTER-ACT0001-SCREEN-SHORTCIRCUIT-20261016-003.
BEGIN;

DO $request_binding_patch$
DECLARE
  v_current text;
  v_anchor text := $anchor$
  execution_ref:='supabase://public.lf_operation_execution/'||p_execution_id||'#manifest';$anchor$;
  v_patch text := $patch$
  -- Bind the literal handed to the profile to its already-persisted request.
  -- The source digest is declared by the existing governed execution manifest.
  -- Never infer a literal from its digest and never silently accept a mismatch.
  IF e.manifest ? 'input_sha256' THEN
    IF e.manifest->>'input_sha256' IS DISTINCT FROM
       'sha256:'||encode(
         extensions.digest(convert_to(p_input_literal,'UTF8'),'sha256'),'hex')
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'code','SCOPE_AUTHORITY_INPUT_DIGEST_MISMATCH'
      );
    END IF;
  END IF;

  -- Queue-backed requests must retain the exact original source reference.
  -- This is a read-only binding check; it does not read, enqueue or run a worker.
  IF e.manifest ? 'queue_request_id' THEN
    IF nullif(e.manifest->>'queue_request_id','') IS NULL
       OR nullif(e.manifest->>'input_sha256','') IS NULL
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'code','SCOPE_AUTHORITY_QUEUE_BINDING_INCOMPLETE'
      );
    END IF;

    IF p_input_source_ref IS DISTINCT FROM
       'queue://private.lf_profile_runtime_queue_v1/'||
       (e.manifest->>'queue_request_id')||'@'||(e.manifest->>'input_sha256')
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'code','SCOPE_AUTHORITY_QUEUE_SOURCE_MISMATCH'
      );
    END IF;
  END IF;

  execution_ref:='supabase://public.lf_operation_execution/'||p_execution_id||'#manifest';$patch$;
BEGIN
  SELECT pg_get_functiondef(
    'public.lf_profile_execution_scope_authority_packet_v1(text,text,text)'::regprocedure
  ) INTO v_current;
  IF md5(v_current) <> '0b187c8cbf5cfbf2f9996022f98a1914' THEN
    RAISE EXCEPTION 'LF_PROFILE_REQUEST_BINDING_SOURCE_DRIFT:%',md5(v_current);
  END IF;
  IF (length(v_current)-length(replace(v_current,v_anchor,'')))<>length(v_anchor) THEN
    RAISE EXCEPTION 'LF_PROFILE_REQUEST_BINDING_ANCHOR_NOT_UNIQUE';
  END IF;
  EXECUTE replace(v_current,v_anchor,v_patch);
END;
$request_binding_patch$;

-- Positive and negative controls use a previously admitted immutable request;
-- tests are read-only, inside the same migration transaction.
DO $request_binding_tests$
DECLARE
  v_exec text;
  v_literal text;
  v_source text;
  v_result jsonb;
BEGIN
  SELECT e.execution_id,
         s.evidence_payload#>>'{scope_authority_packet,authorized_requirements,0,statement}',
         s.evidence_payload#>>'{scope_authority_packet,authorized_requirements,0,source_ref}'
  INTO v_exec,v_literal,v_source
  FROM public.lf_operation_execution e
  JOIN public.lf_operation_execution_steps s USING(execution_id)
  WHERE e.operation_code='EJECUCION_PERFIL_LF'
    AND s.step_id='input_validate'
    AND s.evidence_payload ? 'scope_authority_packet'
    AND e.manifest ? 'input_sha256'
    AND e.manifest ? 'queue_request_id'
    AND s.evidence_payload#>>'{scope_authority_packet,authorized_requirements,0,statement}' IS NOT NULL
    AND s.evidence_payload#>>'{scope_authority_packet,authorized_requirements,0,source_ref}' IS NOT NULL
  ORDER BY e.started_at DESC LIMIT 1;

  IF v_exec IS NULL THEN
    RAISE EXCEPTION 'LF_PROFILE_REQUEST_BINDING_REAL_FIXTURE_MISSING';
  END IF;

  v_result:=public.lf_profile_execution_scope_authority_packet_v1(
    v_exec,v_literal,v_source
  );
  IF v_result->>'status'<>'READY'
     OR v_result#>>'{scope_authority_packet,authorized_requirements,0,statement}'
        IS DISTINCT FROM v_literal
  THEN
    RAISE EXCEPTION 'LF_PROFILE_REQUEST_BINDING_POSITIVE_FAILED:%',v_result;
  END IF;

  v_result:=public.lf_profile_execution_scope_authority_packet_v1(
    v_exec,v_literal||' texto alterado',v_source
  );
  IF v_result->>'status'<>'BLOCKED'
     OR v_result->>'code'<>'SCOPE_AUTHORITY_INPUT_DIGEST_MISMATCH'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_REQUEST_BINDING_LITERAL_NEGATIVE_FAILED:%',v_result;
  END IF;

  v_result:=public.lf_profile_execution_scope_authority_packet_v1(
    v_exec,v_literal,v_source||'#wrong'
  );
  IF v_result->>'status'<>'BLOCKED'
     OR v_result->>'code'<>'SCOPE_AUTHORITY_QUEUE_SOURCE_MISMATCH'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_REQUEST_BINDING_SOURCE_NEGATIVE_FAILED:%',v_result;
  END IF;
END;
$request_binding_tests$;

DO $request_binding_readback$
DECLARE v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.lf_profile_execution_scope_authority_packet_v1(text,text,text)'::regprocedure
  ) INTO v_definition;
  IF md5(v_definition)='0b187c8cbf5cfbf2f9996022f98a1914'
     OR position('SCOPE_AUTHORITY_INPUT_DIGEST_MISMATCH' in v_definition)=0
     OR position('SCOPE_AUTHORITY_QUEUE_SOURCE_MISMATCH' in v_definition)=0
  THEN
    RAISE EXCEPTION 'LF_PROFILE_REQUEST_BINDING_READBACK_FAILED';
  END IF;
END;
$request_binding_readback$;
COMMIT;
