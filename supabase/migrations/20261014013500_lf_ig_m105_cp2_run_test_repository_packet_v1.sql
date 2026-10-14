-- M10.5 CP2 only. Reuse the existing RUN_TEST repository capability route.
-- Deliberately no release registration/promotion, no production activation and no checkpoint DONE.
CREATE OR REPLACE FUNCTION programacion.fn_ig_m105_cp2_route_repository_dispatch_v1(
 p_packet jsonb,p_action_spec jsonb
) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO pg_catalog,programacion,public
AS $cp2$
DECLARE
 v_ref text:=p_action_spec#>>'{test_execution_contract,producer_path}';
 v_sha text:=p_action_spec#>>'{test_execution_contract,producer_sha256}';
 v_mode text:=p_action_spec#>>'{test_execution_contract,router_mode}';
 v_steps jsonb;
 v_verifications jsonb:=coalesce(p_action_spec->'verification_queries','[]'::jsonb);
BEGIN
 IF p_packet->>'status' IS DISTINCT FROM 'READY'
   OR p_action_spec->>'status' IS DISTINCT FROM 'READY'
   OR p_action_spec->>'action_kind' IS DISTINCT FROM 'DECLARED_TEST_EXECUTION'
   OR v_mode IS DISTINCT FROM 'REPOSITORY_EDGE_DISPATCH_THEN_CANONICAL_READBACK_V1'
   OR v_ref IS DISTINCT FROM 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m10_5/dispatch_vnext_cohort.py'
   OR v_sha IS NULL OR v_sha !~ '^[0-9a-f]{64}$'
   OR coalesce(p_action_spec#>>'{test_execution_contract,attestation_rpc}','')<> 'public.fn_ig_m105_cp2_attest_run_v1'
   OR coalesce(p_action_spec#>>'{test_execution_contract,synthetic_pass}','')<>'FORBIDDEN'
   OR jsonb_typeof(v_verifications)<>'array' OR jsonb_array_length(v_verifications)<>1
   OR coalesce((p_action_spec->>'requires_material_execution')::boolean,false) IS DISTINCT FROM true
 THEN RETURN (p_packet || jsonb_build_object(
   'status','BLOCK_IG_M105_CP2_RUNTIME_ROUTING_CONTRACT_DRIFT',
   'execution_allowed',false,
   'block_reasons',jsonb_build_array('IG_M105_CP2_ROUTING_CONTRACT_DRIFT'),
   'connector_plan','[]'::jsonb
 )); END IF;
 -- Repo executor is a pre-existing RUN_TEST transport. Its target is the
 -- already published dispatcher, not a newly authored test or synthetic case.
 v_steps:=jsonb_build_array(
   jsonb_build_object(
     'seq',1,'provider','GITHUB','operation','RUN_TEST','capability','RUN_TEST',
     'mode','REPOSITORY_CAPABILITY',
     'targets',jsonb_build_array(jsonb_build_object('path',v_ref,
       'version','M105_CP2_EXISTING_DISPATCH_V1','manifest_sha256',v_sha)),
     'executor_contract',jsonb_build_object(
       'executor','ENGINEERING_REPOSITORY_CAPABILITY_EXECUTOR_V1',
       'source_policy','EXACT_MAIN_SOURCE_SHA256',
       'implementation_ref',v_ref,
       'current_version','M105_CP2_EXISTING_DISPATCH_V1',
       'manifest_sha256',v_sha,
       'execution_input',jsonb_build_object(
          'entrypoint','main','argv',jsonb_build_array('--execute'),
          'execution_scope','M10.5_NEW_RUNS_VNEXT_ONLY',
          'authority_preflight_rpc','public.fn_ig_m105_cp2_dispatch_context_v1',
          'attestation_rpc','public.fn_ig_m105_cp2_attest_run_v1',
          'post_readback_rpc','public.fn_ig_m105_cp2_screen_readback_v1'),
       'fetch_exact_repository_source',true,
       'execute_capability_entrypoint',true,
       'capture_result_evidence',true,
       'environment_names',jsonb_build_array('IG_CANONICAL_ENDPOINT','IG_CANONICAL_AUTH'),
       'credential_literal','FORBIDDEN',
       'synthetic_pass','FORBIDDEN',
       'test_case_discovery','FORBIDDEN',
       'run_test_when_case_set_empty',true,
       'domain_mutation','AUTHENTIC_EDGE_COHORT_ONLY',
       'no_cutover_promotion',true,
       'require_fresh_13_edge_runs',true,
       'return_evidence_for_transition',true
     )
   ),
   jsonb_build_object(
     'seq',2,'provider','SUPABASE','operation','READ','capability','READ',
     'mode','POST_EDGE_CANONICAL_VERDICT',
     'queries',v_verifications,
     'targets',p_action_spec#>'{target,declared_objects}',
     'executor_contract',jsonb_build_object(
       'query_mode','ONE_STATEMENT_PER_CALL',
       'domain_mutation','FORBIDDEN',
       'readback_provider','SUPABASE_CANONICAL_READONLY',
       'per_screen_count',13,
       'pass_only_if','13_GENUINE_VNEXT_RUNS_WITH_SIGNED_RECEIPTS',
       'validator_outcome_is_not_technical_error',true
     )
   ),
   jsonb_build_object('seq',3,'provider','SUPABASE',
      'operation','CHECKPOINT_TRANSITION')
 );
 v_steps:=programacion.fn_engineering_plan_add_transition_args_v1(
   v_steps,'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.5','NEW_RUNS_VNEXT');
 RETURN jsonb_set(
   p_packet || jsonb_build_object(
     'status','READY','execution_capability','RUN_TEST',
     'capability_mode','REPOSITORY_CAPABILITY',
     'effective_action_kind','DECLARED_TEST_EXECUTION',
     'execution_allowed',true,
     'checkpoint_execution_route','EXECUTE_REPO_DISPATCH_THEN_CANONICAL_READBACK_V1',
     'zero_test_cases_policy','DISPATCH_REAL_EDGE_INSTEAD_OF_NOOP',
     'no_new_router_capability',true,
     'block_reasons','[]'::jsonb),
   '{connector_plan}',v_steps,true);
END $cp2$;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_execution_packet_apply_transversal_adapter_v1(p_packet jsonb, p_plan_code text, p_unit_code text, p_checkpoint_code text, p_action_spec jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_exec jsonb;
  v_impl text;
  v_plan jsonb;
begin
  if p_plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
     and p_unit_code='M10.5'
     and p_checkpoint_code='NEW_RUNS_VNEXT'
     and p_action_spec#>>'{test_execution_contract,router_mode}'='REPOSITORY_EDGE_DISPATCH_THEN_CANONICAL_READBACK_V1' then
    return programacion.fn_ig_m105_cp2_route_repository_dispatch_v1(p_packet,p_action_spec);
  end if;

  if coalesce(p_action_spec->>'status','')<>'READY'
     or coalesce(p_action_spec->>'action_kind','')<>'TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION' then
    return p_packet;
  end if;

  v_exec:=coalesce(p_action_spec->'capability_execution','{}'::jsonb);
  v_impl:=nullif(btrim(coalesce(v_exec->>'implementation_ref','')),'');

  if v_impl is null
     or coalesce(v_exec->>'manifest_sha256','') !~ '^[0-9a-f]{64}$'
     or nullif(btrim(coalesce(v_exec->>'current_version','')),'') is null then
    return p_packet || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_REPOSITORY_EXECUTOR_CONTRACT_INCOMPLETE'
    );
  end if;

  v_plan:=programacion.fn_engineering_plan_add_transition_args_v1(
    jsonb_build_array(
      jsonb_build_object(
        'seq',1,
        'provider','GITHUB',
        'operation','RUN_TEST',
        'capability','RUN_TEST',
        'mode','REPOSITORY_CAPABILITY',
        'targets',jsonb_build_array(
          jsonb_build_object(
            'path',v_impl,
            'version',v_exec->>'current_version',
            'manifest_sha256',v_exec->>'manifest_sha256'
          )
        ),
        'capability_execution',v_exec,
        'executor_contract',jsonb_build_object(
          'executor','ENGINEERING_REPOSITORY_CAPABILITY_EXECUTOR_V1',
          'source_policy','CURRENT_EXACT_MANIFEST',
          'implementation_ref',v_impl,
          'current_version',v_exec->>'current_version',
          'manifest_sha256',v_exec->>'manifest_sha256',
          'execution_input',coalesce(v_exec->'execution_input','{}'::jsonb),
          'input_resolver_entrypoint',coalesce(v_exec->>'input_resolver_entrypoint','programacion.fn_engineering_repository_capability_input_resolve_v1'),
          'input_resolution',coalesce(v_exec->'input_resolution','{}'::jsonb),
          'fetch_exact_repository_source',true,
          'execute_capability_entrypoint',true,
          'capture_result_evidence',true,
          'synthetic_pass','FORBIDDEN',
          'domain_mutation',coalesce(v_exec->>'domain_mutation','FORBIDDEN')
        )
      ),
      jsonb_build_object(
        'seq',2,
        'provider','SUPABASE',
        'operation','CHECKPOINT_TRANSITION'
      )
    ),
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  return p_packet || jsonb_build_object(
    'status','READY',
    'execution_capability','RUN_TEST',
    'capability_mode','REPOSITORY_CAPABILITY',
    'requires_material_execution',true,
    'effective_action_kind','TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION',
    'verification_mode','CAPABILITY_OWNED',
    'block_reasons','[]'::jsonb,
    'connector_plan',v_plan,
    'mutation_policy','CAPABILITY_CONTRACT_ONLY'
  );
end;
$function$

DO $cp2$
DECLARE
 v_unit jsonb;v_old jsonb;v_work bigint;
BEGIN
 SELECT work_item_id,unit_metadata INTO STRICT v_work,v_unit
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5'
 FOR UPDATE;
 v_old:=v_unit#>'{action_specs_v1,NEW_RUNS_VNEXT}';
 IF (SELECT status FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=v_work AND checkpoint_code='NEW_RUNS_VNEXT') IS DISTINCT FROM 'PENDING'
 OR v_old->>'action_kind' IS DISTINCT FROM 'DECLARED_TEST_EXECUTION'
 OR v_old#>>'{test_execution_contract,producer_path}' IS DISTINCT FROM
  'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m10_5/dispatch_vnext_cohort.py'
 OR v_old#>>'{test_execution_contract,attestation_rpc}' IS DISTINCT FROM
  'public.fn_ig_m105_cp2_attest_run_v1'
 THEN RAISE EXCEPTION 'IG_M105_CP2_PRESTATE_DRIFT'; END IF;
 v_unit:=jsonb_set(v_unit,
  '{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,router_mode}',
  to_jsonb('REPOSITORY_EDGE_DISPATCH_THEN_CANONICAL_READBACK_V1'::text),true);
 v_unit:=jsonb_set(v_unit,
  '{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,producer_sha256}',
  to_jsonb('e7212a93e39d515b14bbe0789c20ab7ab0c8dae412bc89bfc02c71989d32a354'::text),true);
 v_unit:=jsonb_set(v_unit,
  '{m105_cp2_producer_v1,execution_route}',
  to_jsonb('RUN_TEST/REPOSITORY_CAPABILITY -> EXISTING_DISPATCHER -> CANONICAL_READBACK'::text),true);
 v_unit:=jsonb_set(v_unit,
  '{m105_cp2_producer_v1,execution_status}',
  to_jsonb('DISPATCH_ROUTE_COMPILED_PENDING_AUTHENTIC_RELEASE'::text),true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_unit
 WHERE work_item_id=v_work AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5';
END $cp2$;

INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia,source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
SELECT 'IG-M105-CP2-RUN-TEST-EMPTY-CASE-ROUTE-009','INPUT_GOVERNANCE',
'M10.5 CP2 RUN_TEST selected authored cases instead of existing Edge dispatcher',
'13 past SQL evaluations were technically complete, but new Edge runs stayed 0; the execution packet used ENGINEERING_AGENT_RUN_TEST_V1 with 0 authored test cases and never invoked the cohort producer.',
'The material checkpoint action had been mapped to case-set RUN_TEST rather than the existing repository-capability RUN_TEST transport; there was no producer invocation in connector_plan.',
'For CP2 only, retarget the RUN_TEST connector plan to existing GitHub repository capability executor with exact source digest, --execute, canonical authority RPC and signed attest per run, then separate read-only 13-screen readback. Keep no fifth capability, no production activation, no automatic DONE.',
'Positive: bootstrap connector_plan 3 operations RUN_TEST REPOSITORY_CAPABILITY -> READ -> CHECKPOINT_TRANSITION, with Python path/manifest and no case filter. Negative: missing SHA/attestation/ref returns BLOCK. Current vNext not authorized must remain unexecuted, not PASS.',
'github://cristhianlujan/claude-persona-lf-patch/ig/m105-cp2-packet-route-20261013',
'programacion.engineering_plan_units/M10.5/NEW_RUNS_VNEXT',
'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5','ACTIVO','CONTRACT_PREFLIGHT',
ARRAY['Architect','Builder','Judge','Auditor']::text[]
WHERE NOT EXISTS(SELECT 1 FROM transversal.error_knowledge WHERE codigo='IG-M105-CP2-RUN-TEST-EMPTY-CASE-ROUTE-009');
