-- M1.A8 / checkpoint RECEIPT_PER_RUN (5.13, 60 clauses).
-- Dedicated adapter over existing ASSURANCE_EVALUATOR catalogs + EVIDENCE_LEDGER.
-- No additional evidence store, parallel evaluator, or production cutover.
-- A traversal receipt records 60 classifications, NOT 60 successful claims.
DO $pre$
BEGIN
  IF to_regprocedure('programacion.fn_ig_spec_traversal_preview_v1(bigint)') IS NOT NULL
     OR to_regprocedure('programacion.fn_ig_spec_traversal_emit_per_run_v1(bigint,text,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'IG_M1A8_RECEIPT_ALREADY_MATERIALIZED';
  END IF;
  IF (SELECT count(*) FROM public.lf_assurance_obligation_catalog
      WHERE claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
        AND version=3
        AND evidence_contract#>>'{spec_traversal,classification}'='BLOCKED')<>60 THEN
    RAISE EXCEPTION 'IG_M1A8_RECEIPT_60_SOURCE_CLAUSES_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_registry
    WHERE capability_code='EVIDENCE_LEDGER' AND status='ACTIVE'
  ) THEN RAISE EXCEPTION 'IG_M1A8_EVIDENCE_LEDGER_UNAVAILABLE'; END IF;
END
$pre$;

CREATE FUNCTION programacion.fn_ig_spec_traversal_preview_v1(p_run_id bigint)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog'
AS $preview$
DECLARE
  v_run record;
  v_items jsonb;
  v_n integer;
  v_distinct integer;
  v_bad integer;
  v_link integer;
BEGIN
  IF p_run_id IS NULL OR p_run_id<=0 THEN
    RAISE EXCEPTION 'IG_SPEC_TRAVERSAL_RUN_ID_INVALID';
  END IF;
  SELECT id,pantalla_id,version_id,status,source_snapshot_sha256,
         contract_snapshot_sha256,source_manifest
    INTO v_run
  FROM programacion.input_readiness_runs
  WHERE id=p_run_id;

  IF v_run.id IS NULL OR v_run.status<>'COMPLETED'
      OR v_run.pantalla_id IS NULL OR v_run.version_id IS NULL
      OR coalesce(v_run.source_snapshot_sha256,'') !~ '^[0-9a-f]{64}$'
      OR coalesce(v_run.contract_snapshot_sha256,'') !~ '^[0-9a-f]{64}$'
      OR jsonb_typeof(v_run.source_manifest)<>'array' THEN
    RAISE EXCEPTION 'IG_SPEC_TRAVERSAL_RUN_NOT_ELIGIBLE:%',p_run_id;
  END IF;

  SELECT count(*) INTO v_link
  FROM public.lf_assurance_subject_bindings b
  WHERE b.subject_type='OPERATION'
    AND b.subject_code='EJECUCION_INPUT_GOVERNANCE_LF'
    AND b.standard_claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
    AND b.standard_claim_version=2 AND b.status='ACTIVE';
  IF v_link<>1 THEN
    RAISE EXCEPTION 'IG_SPEC_TRAVERSAL_ACTIVE_BINDING_AMBIGUOUS:%',v_link;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM programacion.contract_traceability_matrices m
    WHERE m.matrix_code='INPUT_READINESS_CONTRACT_5_13_TRACEABILITY'
      AND m.matrix_revision=1 AND m.contract_revision='5.13'
      AND m.clause_count=60
  ) THEN RAISE EXCEPTION 'IG_SPEC_TRAVERSAL_MATRIX_MISSING'; END IF;

  SELECT count(*),count(DISTINCT o.obligation_code),
         count(*) FILTER (
           WHERE o.claim_version<>2 OR o.status<>'CANDIDATO'
             OR o.evidence_contract->>'contract_revision'<>'5.13'
             OR nullif(o.evidence_contract->>'clause_key','') IS NULL
             OR o.evidence_contract#>>'{spec_traversal,classification}'<>'BLOCKED'
             OR coalesce(o.evidence_contract#>>'{spec_traversal,reason}','')=''
             OR o.evidence_contract#>>'{spec_traversal,independent_semantic_receipt_verified}'<>'false'
             OR o.evidence_contract#>>'{spec_traversal,not_applicable_positive_authority_verified}'<>'false'
             OR NOT EXISTS (
                SELECT 1 FROM public.lf_assurance_obligation_catalog previous
                WHERE previous.obligation_code=o.obligation_code
                  AND previous.version=2
                  AND previous.evidence_contract->>'clause_key'
                       =o.evidence_contract->>'clause_key'
             )
         ),
         jsonb_agg(jsonb_build_object(
           'obligation_code',o.obligation_code,
           'clause_key',o.evidence_contract->>'clause_key',
           'classification',o.evidence_contract#>>'{spec_traversal,classification}',
           'reason',o.evidence_contract#>>'{spec_traversal,reason}',
           'source_ref',o.source_ref,
           'semantic_receipt_verified',false
         ) ORDER BY o.obligation_code)
    INTO v_n,v_distinct,v_bad,v_items
  FROM public.lf_assurance_obligation_catalog o
  WHERE o.claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
    AND o.version=3;

  IF v_n<>60 OR v_distinct<>60 OR v_bad<>0
     OR jsonb_array_length(coalesce(v_items,'[]'::jsonb))<>60 THEN
    RAISE EXCEPTION 'IG_SPEC_TRAVERSAL_INCOMPLETE_OR_UNPROVEN:%:%:%',
      v_n,v_distinct,v_bad;
  END IF;

  RETURN jsonb_build_object(
    'schema_version','IG_SPEC_TRAVERSAL_PER_RUN_PREVIEW_V1',
    'run_id',v_run.id,'pantalla_id',v_run.pantalla_id,
    'version_id',v_run.version_id,'run_status',v_run.status,
    'source_snapshot_sha256',v_run.source_snapshot_sha256,
    'contract_snapshot_sha256',v_run.contract_snapshot_sha256,
    'contract_revision','5.13','obligation_version',3,
    'clause_count',v_n,'blocked_count',v_n,
    'applied_count',0,'not_applicable_count',0,
    'all_clauses_marked',true,'semantic_pass_authorized',false,
    'outcome','TRAVERSAL_COMPLETE_SEMANTICS_UNPROVEN',
    'clauses',v_items
  );
END;
$preview$;

CREATE FUNCTION programacion.fn_ig_spec_traversal_emit_per_run_v1(
  p_run_id bigint,
  p_producer_execution_id text,
  p_ledger_execution_id text,
  p_source_head_sha text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $issuer$
DECLARE
  v_preview_a jsonb;
  v_preview_b jsonb;
  v_sha text;
  v_actor record;
  v_producer record;
  v_result jsonb;
  v_count integer;
BEGIN
  IF p_run_id IS NULL OR p_run_id<=0
     OR coalesce(p_source_head_sha,'') !~ '^[0-9a-f]{40}$'
     OR nullif(btrim(p_producer_execution_id),'') IS NULL
     OR nullif(btrim(p_ledger_execution_id),'') IS NULL
     OR p_producer_execution_id=p_ledger_execution_id THEN
     RAISE EXCEPTION 'IG_SPEC_TRAVERSAL_ISSUER_IDENTITY_INVALID';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('IG_SPEC_TRAVERSAL_RUN:'||p_run_id::text,0));
  v_preview_a:=programacion.fn_ig_spec_traversal_preview_v1(p_run_id);
  v_preview_b:=programacion.fn_ig_spec_traversal_preview_v1(p_run_id);
  IF v_preview_a IS DISTINCT FROM v_preview_b THEN
    RAISE EXCEPTION 'IG_SPEC_TRAVERSAL_SOURCE_NOT_STABLE';
  END IF;
  v_sha:=programacion.fn_v09_sha256_jsonb(v_preview_a);
  IF coalesce(v_sha,'') !~ '^[0-9a-f]{64}$'
     OR v_sha IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_preview_b) THEN
    RAISE EXCEPTION 'IG_SPEC_TRAVERSAL_SHA_UNVERIFIED';
  END IF;

  SELECT execution_id,status,manifest INTO v_actor
  FROM public.lf_operation_execution
  WHERE execution_id=p_ledger_execution_id;
  IF v_actor.execution_id IS NULL OR v_actor.status<>'IN_PROGRESS'
     OR v_actor.manifest->>'capability_code'<>'EVIDENCE_LEDGER'
     OR v_actor.manifest->>'schema_version'<>'IG_SPEC_TRAVERSAL_PER_RUN_ISSUER_V1'
     OR v_actor.manifest->>'run_id' IS DISTINCT FROM p_run_id::text
     OR v_actor.manifest->>'pantalla_id' IS DISTINCT FROM v_preview_a->>'pantalla_id'
     OR v_actor.manifest->>'version_id' IS DISTINCT FROM v_preview_a->>'version_id'
     OR v_actor.manifest->>'source_snapshot_sha256'
        IS DISTINCT FROM v_preview_a->>'source_snapshot_sha256'
     OR v_actor.manifest->>'contract_snapshot_sha256'
        IS DISTINCT FROM v_preview_a->>'contract_snapshot_sha256'
     OR v_actor.manifest->>'subject_sha256' IS DISTINCT FROM v_sha
     OR v_actor.manifest->>'producer_execution_id'
        IS DISTINCT FROM p_producer_execution_id
     OR v_actor.manifest->>'source_head_sha' IS DISTINCT FROM p_source_head_sha
     OR coalesce(v_actor.manifest->>'plan_digest','') !~ '^[0-9a-f]{64}$'
     OR nullif(v_actor.manifest->>'orchestrator_execution_id','') IS NULL THEN
    RAISE EXCEPTION 'IG_SPEC_TRAVERSAL_LEDGER_ACTOR_SCOPE_MISMATCH';
  END IF;

  SELECT execution_id,status,manifest INTO v_producer
  FROM public.lf_operation_execution
  WHERE execution_id=p_producer_execution_id;
  IF v_producer.execution_id IS NULL
     OR v_producer.status NOT IN ('IN_PROGRESS','COMPLETED')
     OR v_producer.manifest->>'capability_code'<>'EVIDENCE_LEDGER'
     OR v_producer.manifest->>'run_id' IS DISTINCT FROM p_run_id::text
     OR v_producer.manifest->>'source_head_sha' IS DISTINCT FROM p_source_head_sha
     OR v_producer.manifest->>'source_snapshot_sha256'
        IS DISTINCT FROM v_preview_a->>'source_snapshot_sha256' THEN
    RAISE EXCEPTION 'IG_SPEC_TRAVERSAL_PRODUCER_RUN_BINDING_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_binding b
    JOIN public.lf_capability_current c
      ON c.capability_code=b.capability_code
    WHERE b.execution_id=p_ledger_execution_id
      AND b.capability_code='EVIDENCE_LEDGER'
      AND b.binding_state='BOUND'
      AND b.bound_version=c.version
      AND b.bound_manifest_sha256=c.manifest_sha256
  ) THEN RAISE EXCEPTION 'IG_SPEC_TRAVERSAL_LEDGER_NOT_GOVERNED_BOUND'; END IF;

  -- Anchoring, digest, immutability and exact execution identity are provided
  -- by the existing transversal EVIDENCE_LEDGER (no parallel writer).
  v_result:=public.fn_lf_evidence_ledger_anchor_v1(
    p_producer_execution_id,'EVIDENCE_LEDGER','IG_SPEC_TRAVERSAL_5_13',
    'SPEC_TRAVERSAL_RECEIPT','IG_SPEC_TRAVERSAL_PER_RUN',
    'supabase://programacion.input_readiness_runs/'||p_run_id::text||'#spec_traversal_5_13',
    v_sha,p_source_head_sha,
    'supabase://public.lf_assurance_obligation_catalog/INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1#version=3',
    'LF_SUPABASE_READBACK_V1','SUPABASE',
    'supabase://programacion.fn_ig_spec_traversal_preview_v1(bigint)',
    'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST','VERIFIED',
    jsonb_build_object(
      'provider_readback_verified',true,'digest_recomputed',true,
      'source_snapshot_sha256',v_preview_a->>'source_snapshot_sha256',
      'stable_double_readback',true,'semantic_independence_proven',false,
      'run_id',p_run_id,'clause_count',60),
    jsonb_build_object(
      'schema_version','IG_SPEC_TRAVERSAL_RECEIPT_PER_RUN_V1',
      'run_id',p_run_id,'pantalla_id',v_preview_a->>'pantalla_id',
      'version_id',v_preview_a->>'version_id',
      'source_snapshot_sha256',v_preview_a->>'source_snapshot_sha256',
      'contract_snapshot_sha256',v_preview_a->>'contract_snapshot_sha256',
      'clause_count',60,'blocked_count',60,'applied_count',0,
      'not_applicable_count',0,'semantic_pass_authorized',false,
      'clauses',v_preview_a->'clauses'
    ),
    p_ledger_execution_id
  );

  SELECT count(*) INTO v_count FROM private.lf_evidence_ledger_v1 l
  WHERE l.receipt_id=(v_result->>'receipt_id')::uuid
    AND l.execution_id=p_producer_execution_id
    AND l.capability_code='EVIDENCE_LEDGER'
    AND l.receipt_kind='SPEC_TRAVERSAL_RECEIPT'
    AND l.subject_sha256=v_sha
    AND l.verification_state='VERIFIED'
    AND l.created_by_execution_id=p_ledger_execution_id
    AND l.receipt_payload->>'run_id'=p_run_id::text
    AND l.receipt_payload->>'blocked_count'='60'
    AND l.receipt_payload->>'semantic_pass_authorized'='false';
  IF v_count<>1 THEN
    RAISE EXCEPTION 'IG_SPEC_TRAVERSAL_PROVIDER_LEDGER_READBACK_MISMATCH';
  END IF;

  RETURN jsonb_build_object(
    'schema_version','IG_SPEC_TRAVERSAL_RECEIPT_PER_RUN_V1',
    'status','RECORDED_BLOCKED_NOT_SEMANTIC_PASS',
    'run_id',p_run_id,'clause_count',60,
    'blocked_count',60,'semantic_pass_authorized',false,
    'receipt_id',v_result->>'receipt_id',
    'receipt_sha256',v_result->>'receipt_sha256',
    'ledger_readback_count',v_count
  );
END;
$issuer$;

REVOKE ALL ON FUNCTION programacion.fn_ig_spec_traversal_preview_v1(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION programacion.fn_ig_spec_traversal_emit_per_run_v1(bigint,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_spec_traversal_preview_v1(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_spec_traversal_emit_per_run_v1(bigint,text,text,text) TO service_role;

COMMENT ON FUNCTION programacion.fn_ig_spec_traversal_emit_per_run_v1(bigint,text,text,text)
 IS 'M1.A8 dedicated run-bound receipt adapter. Reuses current EVIDENCE_LEDGER identity/dispatch binding, verifies 60 contract 5.13 clauses, never credits semantic APPLIED/N/A, requires externally governed run-scoped execution actors. No automatic production activation.';
