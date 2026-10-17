-- Governed transversal RUN_TEST executor routing: no implicit SentinelX.
-- One source-guarded migration, no checkpoint status/receipt mutation.
-- Exact live source fingerprints observed before authoring; Train applies migration.

CREATE OR REPLACE FUNCTION programacion.fn_engineering_test_executor_resolve_v1(p_action_spec jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE
SET search_path TO 'programacion','public','pg_catalog'
AS $resolver$
DECLARE
  v_route jsonb:=coalesce(p_action_spec#>'{test_execution_contract,execution_route}','{}'::jsonb);
  v_provider text:=upper(nullif(btrim(coalesce(v_route->>'provider','')),''));
  v_workflow text:=nullif(btrim(coalesce(v_route->>'workflow_path','')),'');
  v_job text:=nullif(btrim(coalesce(v_route->>'job_name','')),'');
  v_check text:=nullif(btrim(coalesce(v_route->>'check_name','')),'');
  v_host text:=nullif(btrim(coalesce(v_route->>'host_id','')),'');
BEGIN
  IF v_provider='GITHUB_ACTIONS' THEN
    IF v_workflow IS NULL OR v_workflow !~ '^\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$'
      OR v_job IS NULL OR v_job !~ '^[A-Za-z0-9_-]+$'
      OR v_check IS NULL OR length(v_check)>160 OR v_check !~ '^[A-Za-z0-9_. /:-]+$' THEN
      RETURN jsonb_build_object('status','BLOCK_RUN_TEST_CI_BINDING_INCOMPLETE',
        'required',jsonb_build_array('workflow_path','job_name','check_name'),'fail_closed',true);
    END IF;
    RETURN jsonb_build_object('status','READY','provider','GITHUB_ACTIONS',
      'runner_contract',jsonb_build_object(
        'execution_surface','GITHUB_ACTIONS',
        'repository','cristhianlujan/claude-persona-lf-patch',
        'workflow_path',v_workflow,'job_name',v_job,'check_name',v_check,
        'source_sha_binding','EXACT_MERGED_SHA','exact_head_check_required',true,
        'verified_run_id_required',true,'verified_check_conclusion','success',
        'skipped_is_pass',false,'actual_execution_required',true,
        'independent_provider_readback_required',true,'synthetic_pass','FORBIDDEN'));
  ELSIF v_provider='SENTINELX' THEN
    IF v_host IS NULL OR v_host !~ '^host_[A-Za-z0-9]+$' THEN
      RETURN jsonb_build_object('status','BLOCK_RUN_TEST_HOST_AUTHORITY_UNRESOLVED',
        'required',jsonb_build_array('host_id','operational_host_attestation'),'fail_closed',true);
    END IF;
    RETURN jsonb_build_object('status','READY','provider','SENTINELX',
      'runner_contract',jsonb_build_object(
        'host_id',v_host,'host_resolution','EXPLICIT_AUTHORIZED_HOST_ONLY',
        'operational_host_attestation_required',true,
        'source_sha_binding','EXACT_MERGED_SHA',
        'interpreter','python3','temporary_execution_allowed',true,
        'persistent_host_write_required',false,'actual_execution_required',true,
        'independent_provider_readback_required',true,
        'exit_code_required',0,'synthetic_pass','FORBIDDEN'));
  END IF;
  RETURN jsonb_build_object('status','BLOCK_RUN_TEST_EXECUTOR_UNRESOLVED',
    'reason','NO_EXPLICIT_EXECUTABLE_CI_OR_AUTHORIZED_RUNNER',
    'supported_providers',jsonb_build_array('GITHUB_ACTIONS','SENTINELX'),
    'fail_closed',true);
END;
$resolver$;

COMMENT ON FUNCTION programacion.fn_engineering_test_executor_resolve_v1(jsonb)
IS 'Select explicit executable CI or authorized operational runner; no automatic SentinelX, no synthetic PASS.';

DO $patch$
DECLARE
  v_name text;
  v_sig text;
  v_expected text;
  v_def text;
  v_old_runner text:=$old_runner$
        'runner_contract',jsonb_build_object(
          'host_resolution','ANY_CONNECTED_OPERATIONAL_HOST',
          'interpreter','python3',
          'temporary_execution_allowed',true,
          'persistent_host_write_required',false,
          'actual_execution_required',true,
          'synthetic_pass','FORBIDDEN',
          'exit_code_required',0
        ),
$old_runner$;
  v_new_runner text:=$new_runner$
        'runner_contract',v_execution_route->'runner_contract',
$new_runner$;
  v_plan_anchor text:='  v_plan:=programacion.fn_engineering_plan_add_transition_args_v1(';
  v_injection text:=$inject$
  v_execution_route:=programacion.fn_engineering_test_executor_resolve_v1(p_action_spec);
  IF v_execution_route->>'status'<>'READY' THEN
    RETURN p_packet || jsonb_build_object(
      'status',v_execution_route->>'status',
      'execution_allowed',false,
      'test_executor_resolution',v_execution_route
    );
  END IF;

  v_plan:=programacion.fn_engineering_plan_add_transition_args_v1(
$inject$;
BEGIN
  FOR v_name,v_sig,v_expected IN
    SELECT * FROM (VALUES
      ('fn_engineering_execution_packet_apply_bounded_checkpoint_test_v','jsonb,text,text,text,jsonb','65df1c942068c5d4d4877ec46e4d975c'),
      ('fn_engineering_packet_apply_failed_authored_test_repair_v1','jsonb,text,text,text,jsonb','0052e1b57fa711ddf24c7fa014cdf2b5')
    ) t(name,sig,md5)
  LOOP
    SELECT pg_get_functiondef(to_regprocedure('programacion.'||v_name||'('||v_sig||')')) INTO v_def;
    IF v_def IS NULL OR md5(v_def) <> v_expected THEN
      RAISE EXCEPTION 'RUN_TEST_SOURCE_DRIFT:%',v_name;
    END IF;
    IF position(v_old_runner IN v_def)=0
      OR position(v_plan_anchor IN v_def)=0
      OR position($old_provider$'provider','SENTINELX'$old_provider$ IN v_def)=0
      OR position('  v_plan jsonb;' IN v_def)=0
      OR position($connector_key$    'connector_plan',v_plan,$connector_key$ IN v_def)=0 THEN
      RAISE EXCEPTION 'RUN_TEST_PATCH_ANCHOR_MISSING:%',v_name;
    END IF;
    v_def:=replace(v_def,'  v_plan jsonb;',E'  v_plan jsonb;\n  v_execution_route jsonb;');
    v_def:=replace(v_def,v_plan_anchor,v_injection);
    v_def:=replace(v_def,$old_provider$'provider','SENTINELX'$old_provider$,
                         $new_provider$'provider',v_execution_route->>'provider'$new_provider$);
    v_def:=replace(v_def,v_old_runner,v_new_runner);
    v_def:=replace(v_def,$connector_key$    'connector_plan',v_plan,$connector_key$,
                         $connector_replacement$    'test_executor_resolution',v_execution_route,
    'connector_plan',v_plan,$connector_replacement$);
    IF position($old_provider$'provider','SENTINELX'$old_provider$ IN v_def)>0
      OR position(v_old_runner IN v_def)>0
      OR position('fn_engineering_test_executor_resolve_v1' IN v_def)=0 THEN
      RAISE EXCEPTION 'RUN_TEST_PATCH_INCOMPLETE:%',v_name;
    END IF;
    EXECUTE v_def;
  END LOOP;

  SELECT pg_get_functiondef(
    'programacion.fn_engineering_checkpoint_repair_dispatch_v2_core(text,text,text,text,boolean)'::regprocedure)
    INTO v_def;
  IF md5(v_def) <> 'ea26935fdbcbcbed07cf7c8acd5db6e5' THEN
    RAISE EXCEPTION 'RUN_TEST_REPAIR_DISPATCH_SOURCE_DRIFT';
  END IF;
  IF position($old_check$and x.item->>'provider'='SENTINELX'$old_check$ IN v_def)=0
    OR position('USE_CURRENT_SENTINELX_RUN_TEST_ROUTE' IN v_def)=0 THEN
    RAISE EXCEPTION 'RUN_TEST_DISPATCH_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,
    $old_check$and x.item->>'provider'='SENTINELX'$old_check$,
    $new_check$and x.item->>'provider' IN ('GITHUB_ACTIONS','SENTINELX')
        and v_packet->>'status'='READY'
        and v_packet#>>'{test_executor_resolution,status}'='READY'
        and x.item#>>'{source_contract,ref_mode}'='EXACT_MERGED_SHA'$new_check$);
  v_def:=replace(v_def,'USE_CURRENT_SENTINELX_RUN_TEST_ROUTE',
                       'USE_CURRENT_RESOLVED_RUN_TEST_ROUTE');
  EXECUTE v_def;
END;
$patch$;

UPDATE public.lf_error_knowledge
SET titulo='RUN_TEST requires an executable provider bound by the checkpoint contract',
    causa_raiz='Artifact transport and execution were conflated; a runner workaround became a blanket SentinelX rule for all authored checkpoints.',
    prevencion='Keep WRITE_GIT in GitHub; resolve RUN_TEST by an explicitly bound GitHub Actions workflow/job/check or authorized attested operational host. Missing binding blocks only the affected checkpoint, not the scheduler.',
    validacion='Negative: missing/malformed route blocks, no automatic SentinelX. Positive: explicit GitHub Actions and authorized host route preserve exact merged SHA, verified real run and non-skipped provider readback. Closure still needs actual output receipts.',
    ultima_vez=now(), updated_at=now()
WHERE codigo='ENGINEERING-RUN-TEST-RUNNER-ROUTE-001';

DO $test_runner_route$
DECLARE
  v_r jsonb;
  v_spec jsonb;
  v_packet jsonb;
BEGIN
  v_r:=programacion.fn_engineering_test_executor_resolve_v1('{}'::jsonb);
  IF v_r->>'status'<>'BLOCK_RUN_TEST_EXECUTOR_UNRESOLVED' THEN RAISE EXCEPTION 'MISSING_ROUTE_FAIL_OPEN'; END IF;
  v_r:=programacion.fn_engineering_test_executor_resolve_v1(
    '{"test_execution_contract":{"execution_route":{"provider":"GITHUB_ACTIONS","workflow_path":"../../fake.yml","job_name":"test","check_name":"check"}}}'::jsonb);
  IF v_r->>'status'<>'BLOCK_RUN_TEST_CI_BINDING_INCOMPLETE' THEN RAISE EXCEPTION 'BAD_CI_BINDING_FAIL_OPEN'; END IF;
  v_r:=programacion.fn_engineering_test_executor_resolve_v1(
    '{"test_execution_contract":{"execution_route":{"provider":"GITHUB_ACTIONS","workflow_path":".github/workflows/lf-engineering-checkpoint.yml","job_name":"test","check_name":"engineering-checkpoint / test"}}}'::jsonb);
  IF v_r->>'status'<>'READY' OR v_r->>'provider'<>'GITHUB_ACTIONS'
    OR v_r#>>'{runner_contract,skipped_is_pass}'<>'false'
    OR v_r#>>'{runner_contract,exact_head_check_required}'<>'true' THEN RAISE EXCEPTION 'VALID_CI_ROUTE_BROKEN'; END IF;
  v_r:=programacion.fn_engineering_test_executor_resolve_v1(
    '{"test_execution_contract":{"execution_route":{"provider":"SENTINELX"}}}'::jsonb);
  IF v_r->>'status'<>'BLOCK_RUN_TEST_HOST_AUTHORITY_UNRESOLVED' THEN RAISE EXCEPTION 'MISSING_HOST_FAIL_OPEN'; END IF;
  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1','A16Q','A16Q_C2');
  v_packet:=programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v(
    '{"status":"READY"}'::jsonb,'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1','A16Q','A16Q_C2',v_spec);
  IF v_packet->>'status'<>'BLOCK_RUN_TEST_EXECUTOR_UNRESOLVED'
    OR v_packet->>'execution_allowed'<>'false' THEN RAISE EXCEPTION 'A16Q_NOT_FAIL_CLOSED'; END IF;
  v_spec:=jsonb_set(v_spec,'{test_execution_contract,execution_route}',
    '{"provider":"GITHUB_ACTIONS","workflow_path":".github/workflows/lf-engineering-checkpoint.yml","job_name":"test","check_name":"engineering-checkpoint / test"}'::jsonb,true);
  v_packet:=programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v(
    '{"status":"READY"}'::jsonb,'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1','A16Q','A16Q_C2',v_spec);
  IF v_packet->>'status'<>'READY'
    OR v_packet#>>'{connector_plan,1,provider}'<>'GITHUB_ACTIONS'
    OR v_packet#>>'{connector_plan,1,runner_contract,skipped_is_pass}'<>'false'
  THEN RAISE EXCEPTION 'A16Q_CI_ROUTE_COMPILER_FAIL'; END IF;
  v_packet:=programacion.fn_engineering_packet_apply_failed_authored_test_repair_v1(
    '{"status":"READY"}'::jsonb,'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1','A16Q','A16Q_C2',
    jsonb_set(v_spec,'{repair_policy}',
      '{"mode":"REPAIR_DECLARED_TARGET_THEN_RETEST","mutation_targets":["public.lf_test_suite_runs"]}'::jsonb,true));
  IF v_packet->>'status'<>'READY'
    OR v_packet#>>'{connector_plan,2,provider}'<>'GITHUB_ACTIONS'
  THEN RAISE EXCEPTION 'REPAIR_RETEST_EXECUTOR_COMPILER_FAIL'; END IF;
END;
$test_runner_route$;
