BEGIN;
DO $pre$
BEGIN
 IF to_regprocedure('private.fn_lf_programming_context_handoff_receipt_resolve_v1(jsonb)') IS NULL
    OR to_regclass('public.lf_router_action_registry') IS NULL THEN
   RAISE EXCEPTION 'PG01_DEVELOPMENT_ADMISSION_PREREQUISITE_MISSING';
 END IF;
 IF to_regprocedure('public.lf_programming_admission_gate_v1(jsonb)') IS NOT NULL
    OR to_regprocedure('public.lf_programming_development_admission_v1(jsonb,jsonb)') IS NOT NULL THEN
   RAISE EXCEPTION 'PG01_DEVELOPMENT_ADMISSION_ALREADY_INSTALLED';
 END IF;
END $pre$;

CREATE FUNCTION public.lf_programming_admission_gate_v1(p_binding jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER STABLE
SET search_path TO 'pg_catalog', 'public', 'private'
AS $gate$
DECLARE
 v_result jsonb;
 v_digest CONSTANT text := 'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8';
BEGIN
 IF p_binding IS NULL
    OR jsonb_typeof(p_binding) IS DISTINCT FROM 'object'
    OR NOT (p_binding ?& ARRAY['context_id','context_sha256','target_ref','requested_scope_ids','producer_execution_ref','entry_contract_digest_sha256'])
    OR jsonb_typeof(p_binding->'context_id') IS DISTINCT FROM 'string'
    OR (p_binding->>'context_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR jsonb_typeof(p_binding->'context_sha256') IS DISTINCT FROM 'string'
    OR (p_binding->>'context_sha256') !~ '^[0-9a-f]{64}$'
    OR jsonb_typeof(p_binding->'target_ref') IS DISTINCT FROM 'string'
    OR btrim(p_binding->>'target_ref') = ''
    OR jsonb_typeof(p_binding->'producer_execution_ref') IS DISTINCT FROM 'string'
    OR btrim(p_binding->>'producer_execution_ref') = ''
    OR jsonb_typeof(p_binding->'requested_scope_ids') IS DISTINCT FROM 'array'
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(
           CASE WHEN jsonb_typeof(p_binding->'requested_scope_ids')='array'
           THEN p_binding->'requested_scope_ids' ELSE '[]'::jsonb END) AS v(x)
         WHERE jsonb_typeof(v.x) IS DISTINCT FROM 'string' OR btrim(v.x#>>'{}')='')
    OR jsonb_typeof(p_binding->'entry_contract_digest_sha256') IS DISTINCT FROM 'string'
    OR p_binding->>'entry_contract_digest_sha256' IS DISTINCT FROM v_digest
 THEN
   RETURN jsonb_build_object('schema_version','LF_PROGRAMMING_ADMISSION_GATE_V1',
                             'found',false,'admissible',false,'reason','PG01_GATE_BINDING_INVALID');
 END IF;
 v_result := private.fn_lf_programming_context_handoff_receipt_resolve_v1(p_binding);
 RETURN jsonb_build_object('schema_version','LF_PROGRAMMING_ADMISSION_GATE_V1',
   'found',COALESCE((v_result->>'found')::boolean,false),
   'admissible',COALESCE((v_result->>'admissible')::boolean,false),
   'reason',COALESCE(v_result->>'reason','PG01_GATE_ADMISSION_UNDETERMINED'));
EXCEPTION
 WHEN invalid_text_representation OR invalid_parameter_value OR data_exception THEN
   RETURN jsonb_build_object('schema_version','LF_PROGRAMMING_ADMISSION_GATE_V1',
      'found',false,'admissible',false,'reason','PG01_GATE_BINDING_INVALID');
 WHEN insufficient_privilege THEN
   RETURN jsonb_build_object('schema_version','LF_PROGRAMMING_ADMISSION_GATE_V1',
      'found',false,'admissible',false,'reason','PG01_GATE_READER_NOT_GRANTED');
 WHEN OTHERS THEN
   RETURN jsonb_build_object('schema_version','LF_PROGRAMMING_ADMISSION_GATE_V1',
      'found',false,'admissible',false,'reason','PG01_GATE_ADMISSION_UNDETERMINED');
END $gate$;

CREATE FUNCTION public.lf_programming_development_admission_v1(
 p_router_action_binding jsonb, p_programming_handoff jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER STABLE
SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $admission$
DECLARE
 v_base jsonb := jsonb_build_object('schema_version','LF_PROGRAMMING_DEVELOPMENT_ADMISSION_V1',
                 'operation_code','DESARROLLO_CODIGO_AGENTE_LF','downstream_execution_allowed',false);
 v_hash text;
 v_gate jsonb;
 v_status text;
 v_pre jsonb;
BEGIN
 IF p_router_action_binding IS NULL OR jsonb_typeof(p_router_action_binding) IS DISTINCT FROM 'object' THEN
  RETURN v_base || jsonb_build_object('paso','PROGRAMACION_BINDING_INVALIDO','codigo','PG01_ROUTER_BINDING_NOT_OBJECT',
   'motivo_es','El binding del perfil no es un objeto.','siguiente_paso_es','Reobtener el binding del perfil seleccionado.');
 END IF;
 IF jsonb_typeof(p_router_action_binding->'binding_sha256') IS DISTINCT FROM 'string' THEN
  RETURN v_base || jsonb_build_object('paso','PROGRAMACION_BINDING_INVALIDO','codigo','PG01_ROUTER_BINDING_SHA_MISMATCH',
   'motivo_es','Falta la huella del binding.','siguiente_paso_es','Obtener el binding completo.');
 END IF;
 v_hash := 'sha256:' || encode(extensions.digest(convert_to((p_router_action_binding - 'binding_sha256')::text,'UTF8'),'sha256'),'hex');
 IF p_router_action_binding->>'binding_sha256' IS DISTINCT FROM v_hash THEN
  RETURN v_base || jsonb_build_object('paso','PROGRAMACION_BINDING_INVALIDO','codigo','PG01_ROUTER_BINDING_SHA_MISMATCH',
   'motivo_es','La huella no coincide con el binding recibido.','siguiente_paso_es','Solicitar nuevamente el binding íntegro.');
 END IF;
 IF p_router_action_binding->>'channel' IS DISTINCT FROM 'PROGRAMACION' THEN
  RETURN v_base || jsonb_build_object('paso','PROGRAMACION_BINDING_INVALIDO','codigo','PG01_ROUTER_BINDING_CHANNEL_MISMATCH',
   'motivo_es','El binding no pertenece a Programación.','siguiente_paso_es','Seleccionar el canal correcto.');
 END IF;
 IF p_router_action_binding->'channel_effect_authority' IS DISTINCT FROM 'false'::jsonb THEN
  RETURN v_base || jsonb_build_object('paso','PROGRAMACION_BINDING_INVALIDO','codigo','PG01_ROUTER_BINDING_EFFECT_AUTHORITY_UNEXPECTED',
   'motivo_es','El Router no puede otorgar autoridad de efectos.','siguiente_paso_es','Corregir el binding del perfil.');
 END IF;
 v_pre := p_router_action_binding->'channel_precondition';
 IF jsonb_typeof(v_pre) IS DISTINCT FROM 'object'
    OR v_pre->>'code' IS DISTINCT FROM 'PROGRAMACION_PRECHECK_DEFINICION'
    OR v_pre->'required_before_channel_effect' IS DISTINCT FROM 'true'::jsonb
    OR v_pre->>'programming_entry_contract' IS DISTINCT FROM 'PROGRAMMING_ENTRY_CONTRACT_V1' THEN
  RETURN v_base || jsonb_build_object('paso','PROGRAMACION_BINDING_INVALIDO','codigo','PG01_ROUTER_BINDING_PRECONDITION_MISMATCH',
   'motivo_es','La precondición del canal no coincide con el contrato vigente.','siguiente_paso_es','Resolver precondición de definición y perfil.');
 END IF;
 v_gate := public.lf_programming_admission_gate_v1(p_programming_handoff);
 IF v_gate->>'reason' = 'PG01_GATE_BINDING_INVALID' THEN
  RETURN v_base || jsonb_build_object('paso','PROGRAMACION_HANDOFF_INVALIDO','codigo','PG01_GATE_BINDING_INVALID',
   'motivo_es','El handoff PG-01 no cumple la identidad requerida.','siguiente_paso_es','Reconstruir el handoff desde el análisis.');
 END IF;
 IF v_gate->'admissible' IS DISTINCT FROM 'true'::jsonb THEN
  RETURN v_base || jsonb_build_object('paso','PROGRAMACION_ADMISION_BLOQUEADA',
   'codigo',COALESCE(v_gate->>'reason','PG01_GATE_ADMISSION_UNDETERMINED'),
   'context_id',p_programming_handoff->>'context_id',
   'context_sha256',p_programming_handoff->>'context_sha256',
   'retorno',CASE WHEN v_gate->>'reason'='PG01_RECEIPT_NOT_FOUND' THEN 'RETURN_TO_ANALYSIS_NO_CODE' ELSE 'BLOCK_NO_CODE' END,
   'motivo_es','PG-01 no acredita una admisión vigente.','siguiente_paso_es','Resolver la admisión sin ejecutar código.');
 END IF;
 SELECT status INTO v_status FROM public.lf_router_action_registry
 WHERE asset_type='REPOSITORY_ARTIFACT' AND action_code='CODE_DEVELOPMENT'
 AND operation_code='DESARROLLO_CODIGO_AGENTE_LF';
 IF v_status IS DISTINCT FROM 'ACTIVE' THEN
  RETURN v_base || jsonb_build_object('paso','PROGRAMACION_OPERACION_NO_ACTIVA',
   'operation_status',COALESCE(v_status,'NOT_REGISTERED'),
   'motivo_es','La operación de desarrollo aún no está activa.','siguiente_paso_es','Esperar la activación gobernada I1.');
 END IF;
 RETURN v_base || jsonb_build_object('paso','PROGRAMACION_DESARROLLO_ADMITIDO',
  'admision',jsonb_build_object('context_id',p_programming_handoff->>'context_id',
   'context_sha256',p_programming_handoff->>'context_sha256',
   'requested_scope_ids',p_programming_handoff->'requested_scope_ids',
   'entry_contract','PROGRAMMING_ENTRY_CONTRACT_V1',
   'router_binding_sha256',p_router_action_binding->>'binding_sha256'),
  'motivo_es','Admisión verificada sin autorizar ejecución.','siguiente_paso_es','Solicitar por separado autorización de ejecución gobernada.');
END $admission$;

ALTER FUNCTION public.lf_programming_admission_gate_v1(jsonb) OWNER TO postgres;
ALTER FUNCTION public.lf_programming_development_admission_v1(jsonb,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.lf_programming_admission_gate_v1(jsonb) FROM PUBLIC, anon, authenticated, service_role, supabase_read_only_user;
REVOKE ALL ON FUNCTION public.lf_programming_development_admission_v1(jsonb,jsonb) FROM PUBLIC, anon, authenticated, service_role, supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_programming_admission_gate_v1(jsonb) TO service_role, supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_programming_development_admission_v1(jsonb,jsonb) TO service_role, supabase_read_only_user;
COMMENT ON FUNCTION public.lf_programming_admission_gate_v1(jsonb) IS
 'Read-only PG-01 exact receipt admission gate; SECURITY INVOKER, no grants on D7 reader or ledger; returns only schema_version, found, admissible, reason.';
COMMENT ON FUNCTION public.lf_programming_development_admission_v1(jsonb,jsonb) IS
 'Admission check at development-operation entry; no Router mutation, no execution authority; SECURITY INVOKER.';
DO $after$
DECLARE v_count integer;
BEGIN
 SELECT count(*) INTO v_count FROM pg_proc p
 WHERE p.oid IN ('public.lf_programming_admission_gate_v1(jsonb)'::regprocedure,
                 'public.lf_programming_development_admission_v1(jsonb,jsonb)'::regprocedure)
 AND p.prosecdef = false;
 IF v_count <> 2 THEN RAISE EXCEPTION 'PG01_ADMISSION_FUNCTION_SECURITY_MISMATCH'; END IF;
 IF has_function_privilege('anon','public.lf_programming_admission_gate_v1(jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','public.lf_programming_admission_gate_v1(jsonb)','EXECUTE')
 OR has_function_privilege('anon','public.lf_programming_development_admission_v1(jsonb,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','public.lf_programming_development_admission_v1(jsonb,jsonb)','EXECUTE') THEN
 RAISE EXCEPTION 'PG01_ADMISSION_FUNCTION_ACL_MISMATCH'; END IF;
END $after$;
COMMIT;
