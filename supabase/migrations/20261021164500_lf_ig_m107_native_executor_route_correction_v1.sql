-- IG M10.7 native executor correction.
-- Adds GPT_NATIVE / CLAUDE_NATIVE to the canonical engineering RUN_TEST resolver
-- and rebinds M10.7 NO_FALSE_PASS from SentinelX to GPT Native current context.
-- No checkpoint closure and no production activation.

BEGIN;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_test_executor_resolve_v1(
  p_action_spec jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'programacion','public','pg_catalog'
AS $function$
DECLARE
  v_route jsonb:=coalesce(p_action_spec#>'{test_execution_contract,execution_route}','{}'::jsonb);
  v_provider text:=upper(nullif(btrim(coalesce(v_route->>'provider','')),''));
  v_workflow text:=nullif(btrim(coalesce(v_route->>'workflow_path','')),'');
  v_job text:=nullif(btrim(coalesce(v_route->>'job_name','')),'');
  v_check text:=nullif(btrim(coalesce(v_route->>'check_name','')),'');
  v_host text:=nullif(btrim(coalesce(v_route->>'host_id','')),'');
  v_adapter text:=nullif(btrim(coalesce(v_route->>'adapter_id','')),'');
  v_scope text:=upper(nullif(btrim(coalesce(v_route->>'conversation_scope','')),''));
BEGIN
  IF v_provider='GITHUB_ACTIONS' THEN
    IF v_workflow IS NULL OR v_workflow !~ '^\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$'
      OR v_job IS NULL OR v_job !~ '^[A-Za-z0-9_-]+$'
      OR v_check IS NULL OR length(v_check)>160 OR v_check !~ '^[A-Za-z0-9_. /:-]+$' THEN
      RETURN jsonb_build_object(
        'status','BLOCK_RUN_TEST_CI_BINDING_INCOMPLETE',
        'required',jsonb_build_array('workflow_path','job_name','check_name'),
        'fail_closed',true
      );
    END IF;
    RETURN jsonb_build_object(
      'status','READY',
      'provider','GITHUB_ACTIONS',
      'runner_contract',jsonb_build_object(
        'execution_surface','GITHUB_ACTIONS',
        'repository','cristhianlujan/claude-persona-lf-patch',
        'workflow_path',v_workflow,
        'job_name',v_job,
        'check_name',v_check,
        'source_sha_binding','EXACT_MERGED_SHA',
        'exact_head_check_required',true,
        'verified_run_id_required',true,
        'verified_check_conclusion','success',
        'skipped_is_pass',false,
        'actual_execution_required',true,
        'independent_provider_readback_required',true,
        'synthetic_pass','FORBIDDEN'
      )
    );

  ELSIF v_provider='SENTINELX' THEN
    IF v_host IS NULL OR v_host !~ '^host_[A-Za-z0-9]+$' THEN
      RETURN jsonb_build_object(
        'status','BLOCK_RUN_TEST_HOST_AUTHORITY_UNRESOLVED',
        'required',jsonb_build_array('host_id','operational_host_attestation'),
        'fail_closed',true
      );
    END IF;
    RETURN jsonb_build_object(
      'status','READY',
      'provider','SENTINELX',
      'runner_contract',jsonb_build_object(
        'host_id',v_host,
        'host_resolution','EXPLICIT_AUTHORIZED_HOST_ONLY',
        'operational_host_attestation_required',true,
        'source_sha_binding','EXACT_MERGED_SHA',
        'interpreter','python3',
        'temporary_execution_allowed',true,
        'persistent_host_write_required',false,
        'actual_execution_required',true,
        'independent_provider_readback_required',true,
        'exit_code_required',0,
        'synthetic_pass','FORBIDDEN'
      )
    );

  ELSIF v_provider='GPT_NATIVE' THEN
    IF v_adapter IS DISTINCT FROM 'chatgpt-native-current-context-v1'
       OR v_scope IS DISTINCT FROM 'EXISTING_CONVERSATION_ONLY'
       OR v_route ? 'host_id'
       OR v_route ? 'workflow_path'
    THEN
      RETURN jsonb_build_object(
        'status','BLOCK_RUN_TEST_NATIVE_BINDING_INVALID',
        'provider','GPT_NATIVE',
        'required',jsonb_build_array(
          'adapter_id=chatgpt-native-current-context-v1',
          'conversation_scope=EXISTING_CONVERSATION_ONLY',
          'no_host_id',
          'no_workflow_path'
        ),
        'fail_closed',true
      );
    END IF;
    RETURN jsonb_build_object(
      'status','READY',
      'provider','GPT_NATIVE',
      'runner_contract',jsonb_build_object(
        'execution_surface','CHATGPT_NATIVE_CURRENT_CONTEXT',
        'executor_mode','GPT_NATIVE',
        'adapter_id','chatgpt-native-current-context-v1',
        'provider_identity','OPENAI_CHATGPT_NATIVE',
        'native_conversation_scope','EXISTING_CONVERSATION_ONLY',
        'native_api_invocation',false,
        'native_session_creation',false,
        'remote_api_fallback','FORBIDDEN',
        'host_execution','FORBIDDEN',
        'source_sha_binding','EXACT_MERGED_SHA',
        'actual_execution_required',true,
        'native_capture_required',true,
        'provider_attestation_claim','FORBIDDEN_UNLESS_EXTERNALLY_VERIFIED',
        'synthetic_pass','FORBIDDEN'
      )
    );

  ELSIF v_provider='CLAUDE_NATIVE' THEN
    IF v_adapter IS DISTINCT FROM 'claude-native-current-context-v1'
       OR v_scope IS DISTINCT FROM 'EXISTING_CONVERSATION_ONLY'
       OR v_route ? 'host_id'
       OR v_route ? 'workflow_path'
    THEN
      RETURN jsonb_build_object(
        'status','BLOCK_RUN_TEST_NATIVE_BINDING_INVALID',
        'provider','CLAUDE_NATIVE',
        'required',jsonb_build_array(
          'adapter_id=claude-native-current-context-v1',
          'conversation_scope=EXISTING_CONVERSATION_ONLY',
          'no_host_id',
          'no_workflow_path'
        ),
        'fail_closed',true
      );
    END IF;
    RETURN jsonb_build_object(
      'status','READY',
      'provider','CLAUDE_NATIVE',
      'runner_contract',jsonb_build_object(
        'execution_surface','CLAUDE_NATIVE_CURRENT_CONTEXT',
        'executor_mode','CLAUDE_NATIVE',
        'adapter_id','claude-native-current-context-v1',
        'provider_identity','ANTHROPIC_CLAUDE_NATIVE',
        'native_conversation_scope','EXISTING_CONVERSATION_ONLY',
        'native_api_invocation',false,
        'native_session_creation',false,
        'remote_api_fallback','FORBIDDEN',
        'host_execution','FORBIDDEN',
        'source_sha_binding','EXACT_MERGED_SHA',
        'actual_execution_required',true,
        'native_capture_required',true,
        'provider_attestation_claim','FORBIDDEN_UNLESS_EXTERNALLY_VERIFIED',
        'synthetic_pass','FORBIDDEN'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'status','BLOCK_RUN_TEST_EXECUTOR_UNRESOLVED',
    'reason','NO_EXPLICIT_EXECUTABLE_RUNNER',
    'supported_providers',jsonb_build_array(
      'GPT_NATIVE','CLAUDE_NATIVE','GITHUB_ACTIONS','SENTINELX'
    ),
    'fail_closed',true
  );
END;
$function$;

COMMENT ON FUNCTION programacion.fn_engineering_test_executor_resolve_v1(jsonb)
IS 'Resolve exact governed RUN_TEST executor. Supports GPT Native / Claude Native current-context execution plus legacy explicit CI/host routes. Native modes forbid remote/API or host substitution and synthetic PASS.';

DO $preflight$
DECLARE
  v_route jsonb;
  v_status text;
BEGIN
  SELECT unit_metadata#>'{action_specs_v1,NO_FALSE_PASS,test_execution_contract,execution_route}'
    INTO v_route
  FROM programacion.engineering_plan_units
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND unit_code='M10.7'
    AND disposition='ASSIGNED';

  IF v_route#>>'{provider}' IS DISTINCT FROM 'SENTINELX'
     OR v_route#>>'{host_id}' IS DISTINCT FROM 'host_3d5ff6fb467d4e9e'
  THEN
    RAISE EXCEPTION 'M107_NATIVE_REBIND_PREIMAGE_DRIFT:%',v_route;
  END IF;

  SELECT status INTO v_status
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=478 AND checkpoint_code='NO_FALSE_PASS';

  IF v_status IS DISTINCT FROM 'PENDING' THEN
    RAISE EXCEPTION 'M107_NO_FALSE_PASS_NOT_PENDING:%',v_status;
  END IF;
END
$preflight$;

UPDATE programacion.engineering_plan_units
SET unit_metadata = jsonb_set(
  unit_metadata,
  '{action_specs_v1,NO_FALSE_PASS,test_execution_contract,execution_route}',
  jsonb_build_object(
    'provider','GPT_NATIVE',
    'adapter_id','chatgpt-native-current-context-v1',
    'conversation_scope','EXISTING_CONVERSATION_ONLY'
  ),
  true
)
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  AND unit_code='M10.7'
  AND disposition='ASSIGNED';

UPDATE public.lf_error_knowledge
SET estado='SUPERSEDED',
    evidencia=coalesce(evidencia,'') ||
      ' | Superseded 2026-10-21: owner clarified Input Governance does not use Scalora/SentinelX; native execution is GPT_NATIVE/CLAUDE_NATIVE.',
    ultima_vez=now(),
    updated_at=now()
WHERE codigo='IG-M107-NO-FALSE-PASS-RUNNER-BINDING-043';

INSERT INTO public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
)
VALUES(
  'IG-M107-NATIVE-EXECUTOR-ROUTE-CORRECTION-044',
  'GOVERNANCE',
  'M10.7: RUN_TEST fue ligado erróneamente a SentinelX en un flujo Native',
  'NO_FALSE_PASS fue enlazado a SentinelX aunque Input Governance usa ejecución GPT Native / Claude Native y el runtime de perfiles ya define adapters nativos separados de REMOTE_API.',
  'El resolver genérico de engineering RUN_TEST sólo contemplaba GITHUB_ACTIONS y SENTINELX y no había sido alineado con los modos GPT_NATIVE y CLAUDE_NATIVE del runtime canónico.',
  'GENERIC_TEST_EXECUTOR_RESOLVER_LAGGED_NATIVE_RUNTIME_MODES',
  'Para checkpoints ejecutados dentro de una conversación nativa, usar provider GPT_NATIVE o CLAUDE_NATIVE con su adapter exacto y EXISTING_CONVERSATION_ONLY. Prohibir fallback a host/API remoto y no declarar atestación externa inexistente.',
  'PASS cuando el resolver admite positivos separados GPT_NATIVE/CLAUDE_NATIVE, rechaza adapters cruzados/host/workflow en Native y M10.7 compila RUN_TEST GPT_NATIVE con checkpoint aún PENDING.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'Owner clarification 2026-10-21. Canonical adapters: chatgpt-native-current-context-v1 and claude-native-current-context-v1. Sentinel binding 043 superseded.',
  'EXECUTION',
  array['ENGINEERING_EXECUTOR','INPUT_GOVERNANCE']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'M10.7 native executor binding correction',
  'supabase://programacion.fn_engineering_test_executor_resolve_v1'
)
ON CONFLICT (codigo) DO UPDATE SET
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();

DO $postcheck$
DECLARE
  v_gpt jsonb;
  v_claude jsonb;
  v_bad jsonb;
  v_spec jsonb;
  v_packet jsonb;
  v_status text;
BEGIN
  v_gpt := programacion.fn_engineering_test_executor_resolve_v1(
    jsonb_build_object(
      'test_execution_contract',jsonb_build_object(
        'execution_route',jsonb_build_object(
          'provider','GPT_NATIVE',
          'adapter_id','chatgpt-native-current-context-v1',
          'conversation_scope','EXISTING_CONVERSATION_ONLY'
        )
      )
    )
  );
  IF v_gpt->>'status' IS DISTINCT FROM 'READY'
     OR v_gpt->>'provider' IS DISTINCT FROM 'GPT_NATIVE'
     OR v_gpt#>>'{runner_contract,adapter_id}' IS DISTINCT FROM 'chatgpt-native-current-context-v1'
     OR v_gpt#>>'{runner_contract,remote_api_fallback}' IS DISTINCT FROM 'FORBIDDEN'
  THEN
    RAISE EXCEPTION 'GPT_NATIVE_RESOLVER_POSITIVE_FAIL:%',v_gpt;
  END IF;

  v_claude := programacion.fn_engineering_test_executor_resolve_v1(
    jsonb_build_object(
      'test_execution_contract',jsonb_build_object(
        'execution_route',jsonb_build_object(
          'provider','CLAUDE_NATIVE',
          'adapter_id','claude-native-current-context-v1',
          'conversation_scope','EXISTING_CONVERSATION_ONLY'
        )
      )
    )
  );
  IF v_claude->>'status' IS DISTINCT FROM 'READY'
     OR v_claude->>'provider' IS DISTINCT FROM 'CLAUDE_NATIVE'
     OR v_claude#>>'{runner_contract,adapter_id}' IS DISTINCT FROM 'claude-native-current-context-v1'
  THEN
    RAISE EXCEPTION 'CLAUDE_NATIVE_RESOLVER_POSITIVE_FAIL:%',v_claude;
  END IF;

  v_bad := programacion.fn_engineering_test_executor_resolve_v1(
    jsonb_build_object(
      'test_execution_contract',jsonb_build_object(
        'execution_route',jsonb_build_object(
          'provider','GPT_NATIVE',
          'adapter_id','claude-native-current-context-v1',
          'conversation_scope','EXISTING_CONVERSATION_ONLY'
        )
      )
    )
  );
  IF v_bad->>'status' IS NOT DISTINCT FROM 'READY' THEN
    RAISE EXCEPTION 'NATIVE_CROSS_ADAPTER_FALSE_PASS:%',v_bad;
  END IF;

  v_bad := programacion.fn_engineering_test_executor_resolve_v1(
    jsonb_build_object(
      'test_execution_contract',jsonb_build_object(
        'execution_route',jsonb_build_object(
          'provider','GPT_NATIVE',
          'adapter_id','chatgpt-native-current-context-v1',
          'conversation_scope','EXISTING_CONVERSATION_ONLY',
          'host_id','host_forbidden'
        )
      )
    )
  );
  IF v_bad->>'status' IS NOT DISTINCT FROM 'READY' THEN
    RAISE EXCEPTION 'NATIVE_HOST_FALSE_PASS:%',v_bad;
  END IF;

  v_spec := programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.7','NO_FALSE_PASS'
  );
  v_packet := programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.7','NO_FALSE_PASS',v_spec,'{}'::jsonb
  );

  IF v_packet->>'status' IS DISTINCT FROM 'READY'
     OR v_packet->>'execution_capability' IS DISTINCT FROM 'RUN_TEST'
     OR v_packet#>>'{connector_plan,0,provider}' IS DISTINCT FROM 'GPT_NATIVE'
     OR v_packet#>>'{connector_plan,0,runner_contract,adapter_id}' IS DISTINCT FROM 'chatgpt-native-current-context-v1'
     OR v_packet#>>'{connector_plan,0,runner_contract,host_execution}' IS DISTINCT FROM 'FORBIDDEN'
     OR v_packet#>>'{connector_plan,0,runner_contract,remote_api_fallback}' IS DISTINCT FROM 'FORBIDDEN'
  THEN
    RAISE EXCEPTION 'M107_GPT_NATIVE_PACKET_FAIL:%',v_packet;
  END IF;

  SELECT status INTO v_status
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=478 AND checkpoint_code='NO_FALSE_PASS';

  IF v_status IS DISTINCT FROM 'PENDING' THEN
    RAISE EXCEPTION 'M107_FALSE_CLOSURE:%',v_status;
  END IF;
END
$postcheck$;

COMMIT;
