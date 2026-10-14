-- M10.5/CP2: append measured read evidence to canonical RUNTIME_PREFLIGHT.
-- Partial factual receipt only; cannot be used as R17 approval for deployment.
-- No modification of Edge, Operations router, release authority or CP2 jobs.
DO $r17_partial$
DECLARE
  c_event_type constant text := 'RUNTIME_PREFLIGHT';
  c_exec constant text := 'EXEC-IG-M105-R17-READ-EVIDENCE-20261014-001';
  c_target constant text := 'lf-profiles-governance-caller-v1';
  v_desc constant text := 'Read-only Supabase Management timing and source rollback baseline recorded; deployment effect rehearsal remains unexecuted.';
  v_payload jsonb;
  v_event_id bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.v_lf_event_type_contract_audit_v2
    WHERE event_type=c_event_type AND active=true
      AND contract_mode='OPERATIONAL'
      AND allowed_evidence_schemas=ARRAY['operational-event/v2']::text[]
      AND contract_version=2 AND governance_state='GOVERNED_V2'
  ) THEN RAISE EXCEPTION 'R17_PARTIAL_EVENT_CONTRACT_NOT_CURRENT'; END IF;

  IF EXISTS (SELECT 1 FROM public.lf_eventos
             WHERE evento_tipo=c_event_type AND created_by_execution_id=c_exec)
  THEN RAISE EXCEPTION 'R17_PARTIAL_EVENT_DUPLICATE'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry r
    JOIN public.lf_router_action_registry route USING(operation_code)
    WHERE r.operation_code='DEPLOY_SUPABASE_EDGE_FUNCTION_LF'
      AND r.status='CANDIDATO_READ_ONLY'
      AND r.lifecycle_state_code='OP_CANDIDATE'
      AND route.write_allowed=false
  ) THEN RAISE EXCEPTION 'R17_PARTIAL_NOT_READONLY'; END IF;

  v_payload:=jsonb_build_object(
    'evidence_schema_version','operational-event/v2',
    'execution_id',c_exec,
    'producer','LF_M105_CP2_READONLY_R17_COLLECTOR',
    'purpose','Durably bind real exact-target Edge Management read timings and rollback baseline without asserting a deployment effect',
    'occurred_at','2026-10-14T06:11:38.864058+00:00',
    'acceptance_declared',false,
    'operation_code','DEPLOY_SUPABASE_EDGE_FUNCTION_LF',
    'source_evidence',jsonb_build_object(
      'target',c_target,
      'live_edge_version',23,
      'live_edge_verify_jwt',false,
      'rollback_git_commit','cbaecd8d154b593f7d16126e9f3097797f31a7aa',
      'rollback_live_source_files_equal',true,
      'rollback_verified_paths',jsonb_build_array('index.ts','caller.ts'),
      'new_source_bridge_main_only',true,
      'source_comparison_scope','AS_OBSERVED_PREDEPLOY'
    ),
    'read_measurement',jsonb_build_object(
      'github_run_id',38520767968,
      'github_source_commit','dcb67b7188bc7a5c5b4a5ca52210fc7c1a21f533',
      'artifact_name','m105-r17-management-read-38520767968',
      'artifact_url','https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/38520767968',
      'sample_count',5,
      'p50_ms',107.307,'p90_ms',154.684,'max_ms',154.684,
      'get_timeout_ms',20000,
      'phase','MANAGEMENT_READ_ONLY',
      'runtime_deploy_timing_measured',false
    ),
    'db_migration_step_required_for_edge_deploy',false,
    'provider_deployment_executed',false,
    'runtime_rollback_drill_executed',false,
    'effect_idempotency_drill_executed',false,
    'runtime_authorization_present',false,
    'release_promoted',false,
    'cp2_jobs_started',0,
    'outstanding_evidence',jsonb_build_array(
      'runtime_phase_budget_and_timing','rollback_rehearsal',
      'idempotency_and_replay','independent_runtime_authorization'
    )
  );
  IF private.fn_lf_event_acceptance_signal_v2(c_event_type,c_target,v_desc,v_payload) IS NOT NULL
  THEN RAISE EXCEPTION 'R17_PARTIAL_EVENT_UNEXPECTED_ACCEPTANCE_SIGNAL'; END IF;

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,
    payload,origen,created_at,created_by_execution_id
  ) VALUES (
    c_event_type,'SUPABASE_EDGE_FUNCTION',c_target,v_desc,'INFO',
    v_payload,'DERIVE_FROM_EXECUTION_ID',clock_timestamp(),c_exec
  ) RETURNING id INTO v_event_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_eventos
    WHERE id=v_event_id AND evento_tipo=c_event_type
      AND created_by_execution_id=c_exec
      AND origen='EXECUTION:'||c_exec
      AND payload->>'evidence_schema_version'='operational-event/v2'
      AND payload->'read_measurement'->>'github_run_id'='38520767968'
      AND payload->>'acceptance_declared'='false'
      AND payload->>'provider_deployment_executed'='false'
      AND payload->>'runtime_rollback_drill_executed'='false'
  ) THEN RAISE EXCEPTION 'R17_PARTIAL_EVENT_READBACK_FAILED'; END IF;
END $r17_partial$;
