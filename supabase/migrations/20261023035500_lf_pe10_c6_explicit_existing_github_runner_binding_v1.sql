-- LF / PE10_C6: bind a REAL, already-run allowed GitHub Actions test executor.
-- This is execution ROUTING ONLY; a source-suite PASS is NOT C6 transaction PASS.
-- Existing CI: .github/workflows/profile-gpt-native-capture-regression.yml
-- Provider proof: run #39896340892, job capture-regression, exact PR head
-- 51e88ab3cbe845d001510e2d7ebfada39c6a9e70 (the job prints a
-- 57-case typed receipt; it explicitly says database_transaction_pass=false).
-- Applied ONLY by authorized PASE -> LF Migration Merge Train.
BEGIN;
DO $pe10_c6_executor$
DECLARE
 v_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
 v_unit constant text := 'PE10';
 v_cp constant text := 'PE10_C6';
 v_code constant text := 'PE10_C6.EXPLICIT_GITHUB_TEST_EXECUTOR_BOUND.V1';
 v_actor constant text := 'EXEC-PE10-C6-GITHUB-RUNNER-CONTRACT-20261023-V1';
 v_meta jsonb;
 v_old jsonb;
 v_spec jsonb;
 v_route jsonb;
 v_packet jsonb;
 v_readiness jsonb;
 v_event bigint;
 v_payload jsonb;
BEGIN
 SELECT unit_metadata INTO STRICT v_meta
 FROM programacion.engineering_plan_units
 WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=1103
 FOR UPDATE;
 v_old:=v_meta#>'{action_specs_v1,PE10_C6,test_execution_contract}';
 IF jsonb_typeof(v_old) IS DISTINCT FROM 'object'
   OR v_old->>'test_code' IS DISTINCT FROM 'PE10_C6_TRANSACTIONAL_DRY_RUN_V1'
   OR v_old->>'test_path' IS DISTINCT FROM
     'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/pe10_c6_transactional_dry_run_v1.py'
   OR v_old ? 'execution_route'
   OR (v_old ? 'authoring_required')
   OR (SELECT version FROM public.lf_operation_registry WHERE operation_code='ACTUALIZACION_PERFIL_LF') IS DISTINCT FROM 'v0.1'
   OR (SELECT count(*) FROM public.lf_operation_steps WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND active)<>15
   OR (SELECT count(*) FROM public.lf_operation_steps WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision') AND active)<>0
   OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=1103 AND checkpoint_code IN ('PE10_C6','PE10_C7') AND status='PENDING')<>2
   OR EXISTS (SELECT 1 FROM public.lf_eventos WHERE entidad_codigo=v_code)
 THEN RAISE EXCEPTION 'PE10_C6_EXECUTOR_BINDING_PRESTATE_CHANGED'; END IF;
 v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
 v_route:=programacion.fn_engineering_test_executor_resolve_v1(v_spec);
 IF v_route->>'status' IS DISTINCT FROM 'BLOCK_RUN_TEST_EXECUTOR_UNRESOLVED'
 THEN RAISE EXCEPTION 'PE10_C6_TEST_EXECUTOR_UNEXPECTEDLY_ALREADY_RESOLVED:%',v_route; END IF;

 -- Do NOT add a shadow runner or custom workflow. This job now executes the
 -- exact declared checkpoint script: 57 real source cases, typed fail-closed.
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(
   jsonb_set(unit_metadata,
     '{action_specs_v1,PE10_C6,test_execution_contract,execution_route}',
     jsonb_build_object(
       'provider','GITHUB_ACTIONS',
       'workflow_path','.github/workflows/profile-gpt-native-capture-regression.yml',
       'job_name','capture-regression',
       'check_name','capture-regression'),true),
   '{action_specs_v1,PE10_C6,test_execution_contract,authoring_required}',
   'false'::jsonb,true)
 WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=1103;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C6_EXECUTOR_BINDING_ROW_NOT_UPDATED'; END IF;

 v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
 v_route:=programacion.fn_engineering_test_executor_resolve_v1(v_spec);
 v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
   v_plan,v_unit,v_cp,v_spec,'{}'::jsonb);
 v_readiness:=programacion.fn_engineering_checkpoint_execution_readiness_v1(
   v_plan,v_unit,v_cp);
 IF v_spec->>'status' IS DISTINCT FROM 'READY'
  OR v_route->>'status' IS DISTINCT FROM 'READY'
  OR v_route->>'provider' IS DISTINCT FROM 'GITHUB_ACTIONS'
  OR v_route#>>'{runner_contract,workflow_path}' IS DISTINCT FROM
       '.github/workflows/profile-gpt-native-capture-regression.yml'
  OR v_route#>>'{runner_contract,job_name}' IS DISTINCT FROM 'capture-regression'
  OR v_route#>>'{runner_contract,check_name}' IS DISTINCT FROM 'capture-regression'
  OR v_route#>>'{runner_contract,source_sha_binding}' IS DISTINCT FROM 'EXACT_MERGED_SHA'
  OR v_packet->>'status' IS DISTINCT FROM 'READY'
  OR v_packet->>'execution_capability' IS DISTINCT FROM 'RUN_TEST'
  OR v_packet->>'execution_allowed' IS DISTINCT FROM 'true'
  OR v_packet->>'capability_mode' IS DISTINCT FROM 'RUN_EXISTING_DECLARED_CHECKPOINT_TEST'
  OR v_packet#>>'{test_contract_guard,status}' IS DISTINCT FROM 'PASS'
  OR NOT EXISTS(
    SELECT 1 FROM jsonb_array_elements(coalesce(v_packet->'connector_plan','[]'::jsonb)) op
    WHERE op->>'operation'='RUN_TEST'
      AND op#>>'{runner_contract,source_sha_binding}'='EXACT_MERGED_SHA'
      AND op#>>'{test_execution_contract,test_code}'='PE10_C6_TRANSACTIONAL_DRY_RUN_V1'
  )
  OR EXISTS(
    SELECT 1 FROM jsonb_array_elements(coalesce(v_packet->'connector_plan','[]'::jsonb)) op
    WHERE op->>'operation'='WRITE_GIT'
  )
  OR v_readiness->>'status' IS DISTINCT FROM 'READY'
  OR v_readiness->>'execution_ready' IS DISTINCT FROM 'true'
  OR v_readiness#>>'{gates,COMPILE_READY}' IS DISTINCT FROM 'true'
  OR v_readiness#>>'{gates,ACTION_EXACT}' IS DISTINCT FROM 'true'
  OR v_readiness#>>'{action_exactness,run_test_contract_present}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'PE10_C6_GITHUB_EXECUTOR_PACKET_NOT_READABLE:route=% packet=% readiness=%',
   v_route, v_packet, v_readiness; END IF;

 -- No assertion receipt or checkpoint transition: this only resolves an
 -- EXECUTOR, not C6's material PostgreSQL positive/negative rollback gate.
 IF EXISTS(
   SELECT 1 FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=1103 AND checkpoint_code IN ('PE10_C6','PE10_C7')
     AND (status<>'PENDING' OR assertion_receipt IS NOT NULL)
 ) THEN RAISE EXCEPTION 'PE10_C6_EXECUTOR_CAUSED_PREMATURE_CLOSURE'; END IF;

 v_payload:=jsonb_build_object(
   'evidence_schema_version','operational-event/v2',
   'execution_id',v_actor,
   'producer','LF_MIGRATION_TRAIN_PE10_C6_GITHUB_RUNNER_BINDING',
   'occurred_at',clock_timestamp(),
   'purpose','Compile existing GitHub Actions job as execution route for declared canonical C6 source test',
   'checkpoint_code',v_cp,
   'provider','GITHUB_ACTIONS',
   'runner_workflow','.github/workflows/profile-gpt-native-capture-regression.yml',
   'runner_job','capture-regression',
   'real_prior_run_id',39896340892,
   'real_prior_pr_head','51e88ab3cbe845d001510e2d7ebfada39c6a9e70',
   'declared_source_test_cases',57,
   'declared_source_test_receipt_sha256','ab65deba0ca86a2b58faf4ca41edcec437e998511c782bee9607a65e8b07b252',
   'test_runner_packet_compiles',true,
   'execution_readiness_status',v_readiness->>'status',
   'run_reuse_requires_exact_merged_sha',true,
   'postgres_transaction_tested',false,
   'provider_bound_evolved_output_verified',false,
   'assertion_receipt_issued',false,
   'checkpoint_pass',false,
   'cutover_authorized',false,
   'production_activation',false,
   'acceptance_declared',false
 );
 IF private.fn_lf_event_acceptance_signal_v2(
   'ARTIFACT_RECONCILED',v_code,
   'C6 declared GitHub source test executor bound; PostgreSQL cutover gate still pending',v_payload)
   IS NOT NULL
 THEN RAISE EXCEPTION 'PE10_C6_EXECUTOR_CONTRACT_FALSE_CLOSURE_SIGNAL'; END IF;
 INSERT INTO public.lf_eventos(
   evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,
   origen,created_by_execution_id,payload
 ) VALUES(
   'ARTIFACT_RECONCILED','PROGRAM_PLAN',v_code,
   'C6 declared test routed to existing GitHub job; DB rollback proof pending',
   'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_payload
 ) RETURNING id INTO v_event;
 IF NOT EXISTS(
  SELECT 1 FROM public.lf_eventos WHERE id=v_event
    AND payload->>'checkpoint_pass'='false'
    AND payload->>'test_runner_packet_compiles'='true'
    AND payload->>'postgres_transaction_tested'='false'
 ) THEN RAISE EXCEPTION 'PE10_C6_EXECUTOR_READBACK_NOT_DURABLE'; END IF;
END $pe10_c6_executor$;
COMMIT;
