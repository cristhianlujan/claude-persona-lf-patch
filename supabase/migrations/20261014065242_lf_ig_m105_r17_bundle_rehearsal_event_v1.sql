-- M10.5 CP2 / R17: factual evidence of offline file-bundle reversal.
-- This does not attest to provider-level rollback or runtime idempotency,
-- authorize a deploy, mutate operation governance, or execute CP2.
DO $r17_file_rehearsal$
DECLARE
  c_exec constant text := 'EXEC-IG-M105-R17-OFFLINE-ROLLBACK-20261014-001';
  c_type constant text := 'RUNTIME_PREFLIGHT';
  c_target constant text := 'lf-profiles-governance-caller-v1';
  c_desc constant text :=
    'Exact Git bundle replay and isolated file restoration measured; runtime provider effect and authorization remain unexecuted.';
  v_payload jsonb;
  v_id bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.v_lf_event_type_contract_audit_v2
    WHERE event_type=c_type AND contract_mode='OPERATIONAL'
      AND allowed_evidence_schemas=ARRAY['operational-event/v2']::text[]
      AND active AND governance_state='GOVERNED_V2' AND contract_version=2
  ) THEN RAISE EXCEPTION 'R17_FILE_EVENT_TYPE_NOT_CURRENT'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_eventos
    WHERE id=20883 AND evento_tipo=c_type
      AND entidad_codigo=c_target
      AND payload->>'acceptance_declared'='false'
      AND payload->'read_measurement'->>'github_run_id'='38520767968'
  ) THEN RAISE EXCEPTION 'R17_FILE_PRIOR_READ_EVENT_MISSING'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_eventos
    WHERE evento_tipo=c_type AND created_by_execution_id=c_exec
  ) THEN RAISE EXCEPTION 'R17_FILE_RECEIPT_REPLAY'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry r
    JOIN public.lf_router_action_registry a USING(operation_code)
    JOIN public.lf_operation_contracts c USING(operation_code)
    WHERE r.operation_code='DEPLOY_SUPABASE_EDGE_FUNCTION_LF'
      AND r.status='CANDIDATO_READ_ONLY'
      AND r.lifecycle_state_code='OP_CANDIDATE'
      AND a.write_allowed=false
      AND c.allowed->>'runtime_effect_enabled'='false'
  ) THEN RAISE EXCEPTION 'R17_FILE_ROUTE_ACTIVATED_UNEXPECTEDLY'; END IF;

  v_payload:=jsonb_build_object(
    'evidence_schema_version','operational-event/v2',
    'execution_id',c_exec,
    'producer','LF_EDGE_OPERATIONS_R17_ISOLATED_REHEARSAL',
    'purpose','Persist actual non-effect file-bundle rehearsal and distinguish it from forbidden provider runtime claims',
    'occurred_at','2026-10-14T06:48:27.978237+00:00',
    'acceptance_declared',false,
    'operation_code','DEPLOY_SUPABASE_EDGE_FUNCTION_LF',
    'prior_r17_event_id',20883,
    'source_commit','37a72b57966858d7dad7bd43fc84e7744d6c3f65',
    'rollback_commit','cbaecd8d154b593f7d16126e9f3097797f31a7aa',
    'workflow_run_id',38524367551,
    'workflow_url','https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/38524367551',
    'workflow_artifact','m105-r17-offline-rollback-38524367551',
    'rehearsal_scope','EPHEMERAL_FILE_BUNDLE_ONLY',
    'file_bundle',jsonb_build_object(
      'old_files',jsonb_build_array('index.ts','caller.ts'),
      'new_files',jsonb_build_array('index.ts','caller.ts','cp2_edge_bridge.ts'),
      'initial_local_changes',2,
      'forward_local_changes',2,
      'repeated_forward_changes',0,
      'rollback_local_changes',2,
      'repeated_rollback_changes',0,
      'temporary_artifacts_retained',false,
      'main_caller_sha256','ef3f28a8ffb2b722801ae526b74b4dfcd8e6db5c1c95a2d263d2cb5c46d5a433',
      'main_bridge_sha256','b6083f3cc1defe170107aed8d858c6cbc9991efc280b85f5044a8e99ef073e83',
      'rollback_caller_sha256','ab9af18833ec77574025eaae219805b7f81d7025e4aa7928fb8530d51943ba24',
      'shared_index_sha256','9e9c9628838a9f840af4300e51efddd02735a58246852ab8351cacca04cb1fae'
    ),
    'management_read',jsonb_build_object(
      'sample_count',5,'p50_ms',94.044,'p90_ms',160.356,'max_ms',160.356,
      'budget_ms',20000,'live_version_before',23,'live_version_after',23,
      'http_method','GET'
    ),
    'db_migration_step_required_for_edge_provider_deploy',false,
    'live_edge_changed',false,
    'provider_deployment_executed',false,
    'provider_rollback_drill_executed',false,
    'provider_idempotency_drill_executed',false,
    'runtime_authorization_present',false,
    'release_promoted',false,
    'cp2_jobs_started',0,
    'pending_checks',jsonb_build_array(
      'LIVE_PROVIDER_ROLLBACK_REHEARSAL',
      'LIVE_PROVIDER_IDEMPOTENCY',
      'FULL_RUNTIME_PHASE_BUDGET',
      'INDEPENDENT_DEPLOY_AUTHORITY'
    )
  );

  IF private.fn_lf_event_acceptance_signal_v2(c_type,c_target,c_desc,v_payload) IS NOT NULL
  THEN RAISE EXCEPTION 'R17_FILE_PRETENDS_ACCEPTANCE'; END IF;

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,
    payload,origen,created_at,created_by_execution_id
  ) VALUES (
    c_type,'SUPABASE_EDGE_FUNCTION',c_target,c_desc,'INFO',
    v_payload,'DERIVE_FROM_EXECUTION_ID',clock_timestamp(),c_exec
  ) RETURNING id INTO v_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_eventos
    WHERE id=v_id AND evento_tipo=c_type AND entidad_codigo=c_target
      AND created_by_execution_id=c_exec
      AND origen='EXECUTION:'||c_exec
      AND payload->>'acceptance_declared'='false'
      AND payload->>'rehearsal_scope'='EPHEMERAL_FILE_BUNDLE_ONLY'
      AND payload->>'provider_deployment_executed'='false'
      AND payload->>'provider_rollback_drill_executed'='false'
      AND payload->>'provider_idempotency_drill_executed'='false'
      AND payload->'file_bundle'->>'repeated_forward_changes'='0'
      AND payload->'file_bundle'->>'repeated_rollback_changes'='0'
      AND payload->>'cp2_jobs_started'='0'
      AND payload->>'workflow_run_id'='38524367551'
  ) THEN RAISE EXCEPTION 'R17_FILE_RECEIPT_READBACK_FAILED'; END IF;
END $r17_file_rehearsal$;
