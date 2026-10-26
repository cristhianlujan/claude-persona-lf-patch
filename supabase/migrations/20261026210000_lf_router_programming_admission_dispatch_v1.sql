BEGIN;

DO $pre$
BEGIN
  IF pg_catalog.md5(pg_catalog.pg_get_functiondef('public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure))
     <> '42828a549c0e4ce15e45c902816fa9ea' THEN
    RAISE EXCEPTION 'LF_ROUTER_PROGRAMMING_ADMISSION_SOURCE_DRIFT';
  END IF;
  IF to_regprocedure('private.fn_lf_programming_context_handoff_receipt_resolve_v1(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'LF_ROUTER_PROGRAMMING_ADMISSION_D7_READER_MISSING';
  END IF;
  IF to_regclass('public.lf_router_action_registry') IS NULL THEN
    RAISE EXCEPTION 'LF_ROUTER_PROGRAMMING_ADMISSION_REGISTRY_MISSING';
  END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.lf_router_programming_admission_gate_v1(p_binding jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path TO 'pg_catalog', 'public', 'private'
AS $gate$
DECLARE
  v_result jsonb;
  v_digest CONSTANT text := 'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8';
BEGIN
  IF p_binding IS NULL
     OR jsonb_typeof(p_binding) IS DISTINCT FROM 'object'
     OR NOT (p_binding ?& ARRAY['context_id','context_sha256','target_ref',
         'requested_scope_ids','producer_execution_ref','entry_contract_digest_sha256'])
     OR jsonb_typeof(p_binding->'context_id') IS DISTINCT FROM 'string'
     -- Lowercase only: the D7 reader raises on any other form, so mirror it exactly.
     OR (p_binding->>'context_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     OR jsonb_typeof(p_binding->'context_sha256') IS DISTINCT FROM 'string'
     OR (p_binding->>'context_sha256') !~ '^[0-9a-f]{64}$'
     OR jsonb_typeof(p_binding->'target_ref') IS DISTINCT FROM 'string'
     OR btrim(p_binding->>'target_ref') = ''
     OR jsonb_typeof(p_binding->'producer_execution_ref') IS DISTINCT FROM 'string'
     OR btrim(p_binding->>'producer_execution_ref') = ''
     OR jsonb_typeof(p_binding->'requested_scope_ids') IS DISTINCT FROM 'array'
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_binding->'requested_scope_ids') = 'array' THEN p_binding->'requested_scope_ids' ELSE '[]'::jsonb END) AS v(x)
          WHERE jsonb_typeof(v.x) IS DISTINCT FROM 'string' OR btrim(v.x#>>'{}')='')
     OR jsonb_typeof(p_binding->'entry_contract_digest_sha256') IS DISTINCT FROM 'string'
     OR p_binding->>'entry_contract_digest_sha256' IS DISTINCT FROM v_digest
  THEN
    RETURN jsonb_build_object('schema_version','LF_ROUTER_PROGRAMMING_ADMISSION_GATE_V1',
                              'found',false,'admissible',false,'reason','PG01_ROUTER_BINDING_INVALID');
  END IF;

  v_result := private.fn_lf_programming_context_handoff_receipt_resolve_v1(p_binding);
  RETURN jsonb_build_object('schema_version','LF_ROUTER_PROGRAMMING_ADMISSION_GATE_V1',
    'found',COALESCE((v_result->>'found')::boolean,false),
    'admissible',COALESCE((v_result->>'admissible')::boolean,false),
    'reason',COALESCE(v_result->>'reason','PG01_ROUTER_ADMISSION_UNDETERMINED'));
EXCEPTION
  WHEN invalid_text_representation OR invalid_parameter_value OR data_exception THEN
    RETURN jsonb_build_object('schema_version','LF_ROUTER_PROGRAMMING_ADMISSION_GATE_V1',
                 'found',false,'admissible',false,'reason','PG01_ROUTER_BINDING_INVALID');
  WHEN OTHERS THEN
    -- Fail closed: any reader error is non-admissible, never a Router crash.
    RETURN jsonb_build_object('schema_version','LF_ROUTER_PROGRAMMING_ADMISSION_GATE_V1',
                 'found',false,'admissible',false,'reason','PG01_ROUTER_ADMISSION_UNDETERMINED');
END
$gate$;

ALTER FUNCTION public.lf_router_programming_admission_gate_v1(jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.lf_router_programming_admission_gate_v1(jsonb)
  FROM PUBLIC, anon, authenticated, service_role, supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_programming_admission_gate_v1(jsonb)
  TO service_role, supabase_read_only_user;
COMMENT ON FUNCTION public.lf_router_programming_admission_gate_v1(jsonb) IS
 'Read-only security-definer minimization bridge to PG-01 exact receipt gate. Returns no stored content or receipt metadata.';

DO $route$
DECLARE
  d text; a text; b text; p1 integer; p2 integer;
  v_prefix text; v_suffix text;
BEGIN
  d := pg_get_functiondef('public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure);
  a := E'    IF v_channel=\'PROGRAMACION\' THEN\n';
  b := E'    IF v_channel=\'OPERACIONES\' THEN\n';
  p1 := strpos(d,a);
  p2 := strpos(d,b);
  IF p1 <= 0 OR p2 <= p1 OR strpos(substring(d from p1+length(a)),a)>0 THEN
    RAISE EXCEPTION 'LF_ROUTER_PROGRAMMING_ADMISSION_BLOCK_DRIFT';
  END IF;
  IF substring(d from p1 for p2-p1) <> $old$    IF v_channel='PROGRAMACION' THEN
      RETURN v_base || jsonb_build_object(
        'paso','PROGRAMACION_PRECHECK_DEFINICION',
        'precondicion_requerida','EXACT_CANONICAL_DEFINITION_REF_AND_CURRENTNESS',
        'si_definicion_falta_o_difiere','PRODUCTO_PRIMERO',
        'si_definicion_vigente','PROGRAMACION_ADMISION_REQUERIDA',
        'contrato_entrada_despues_precheck','PROGRAMMING_ENTRY_CONTRACT_V1',
        'upstream_requerido_despues_precheck','ANALYSIS_IMPLEMENTATION_PACKAGE_V1',
        'alcance_requiere_ready',v_scope IS NOT NULL,
        'motivo_es','Antes de Programacion se verifica la definicion funcional canonica. Si falta o difiere, Producto la corrige primero; si coincide, continua la admision tecnica.',
        'siguiente_paso_es','Verificar la fuente canonica y su currentness; solo con definicion vigente continuar a PG-01.'
      );
    END IF;

$old$ THEN
    RAISE EXCEPTION 'LF_ROUTER_PROGRAMMING_ADMISSION_BLOCK_DRIFT';
  END IF;

  v_prefix := substring(d from 1 for p1-1);
  v_suffix := substring(d from p2);
  CREATE TEMP TABLE pg_temp.router_programming_patch_baseline
     (prefix text NOT NULL, suffix text NOT NULL) ON COMMIT DROP;
  INSERT INTO pg_temp.router_programming_patch_baseline VALUES(v_prefix,v_suffix);

  d := v_prefix || $block$    IF v_channel='PROGRAMACION' THEN
      IF p_caller IS NULL OR NOT (p_caller ? 'programming_handoff') THEN
        RETURN v_base || jsonb_build_object(
          'paso','PROGRAMACION_PRECHECK_DEFINICION',
          'precondicion_requerida','EXACT_CANONICAL_DEFINITION_REF_AND_CURRENTNESS',
          'si_definicion_falta_o_difiere','PRODUCTO_PRIMERO',
          'si_definicion_vigente','PROGRAMACION_ADMISION_REQUERIDA',
          'contrato_entrada_despues_precheck','PROGRAMMING_ENTRY_CONTRACT_V1',
          'upstream_requerido_despues_precheck','ANALYSIS_IMPLEMENTATION_PACKAGE_V1',
          'alcance_requiere_ready',v_scope IS NOT NULL,
          'motivo_es','Antes de Programacion se verifica la definicion funcional canonica. Si falta o difiere, Producto la corrige primero; si coincide, continua la admision tecnica.',
          'siguiente_paso_es','Verificar la fuente canonica y su currentness; solo con definicion vigente continuar a PG-01.'
        );
      END IF;

      v := p_caller->'programming_handoff';
      -- Binding shape is validated only in the gate (single source of truth, aligned with D7).
      v_d := public.lf_router_programming_admission_gate_v1(v);
      IF v_d->>'reason' = 'PG01_ROUTER_BINDING_INVALID' THEN
        RETURN v_base || jsonb_build_object(
          'paso','PROGRAMACION_HANDOFF_INVALIDO',
          'codigo','PG01_ROUTER_BINDING_INVALID',
          'motivo_es','El handoff de Programacion no contiene una identidad exacta valida o no usa el contrato vigente.',
          'siguiente_paso_es','Corregir el handoff desde Analisis antes de consultar PG-01.');
      END IF;

      IF COALESCE((v_d->>'admissible')::boolean,false) IS NOT TRUE THEN
        RETURN v_base || jsonb_build_object(
          'paso','PROGRAMACION_ADMISION_BLOQUEADA',
          'reason',v_d->>'reason',
          'context_id',v->>'context_id',
          'context_sha256',v->>'context_sha256',
          'retorno',CASE WHEN v_d->>'reason'='PG01_RECEIPT_NOT_FOUND'
                   THEN 'RETURN_TO_ANALYSIS_NO_CODE' ELSE 'BLOCK_NO_CODE' END,
          'motivo_es','La compuerta PG-01 no autoriza el ingreso a Programacion.',
          'siguiente_paso_es','Resolver el recibo exacto y sus condiciones de admision; no ejecutar codigo.');
      END IF;

      SELECT jsonb_build_object('status', r.status) INTO v_d
      FROM public.lf_router_action_registry r
      WHERE r.asset_type='REPOSITORY_ARTIFACT'
        AND r.action_code='CODE_DEVELOPMENT'
        AND r.operation_code='DESARROLLO_CODIGO_AGENTE_LF'
      LIMIT 1;
      IF v_d IS NULL OR v_d->>'status' IS DISTINCT FROM 'ACTIVE' THEN
        RETURN v_base || jsonb_build_object(
          'paso','PROGRAMACION_OPERACION_NO_ACTIVA',
          'operation_code','DESARROLLO_CODIGO_AGENTE_LF',
          'operation_status',COALESCE(v_d->>'status','NOT_REGISTERED'),
          'motivo_es','La admision no basta: la operacion de desarrollo aun no esta activa.',
          'siguiente_paso_es','Esperar la activacion gobernada de la operacion; no ejecutar codigo.');
      END IF;

      RETURN v_base || jsonb_build_object(
        'paso','DISPATCHED',
        'despacho',jsonb_build_object(
          'operation_code','DESARROLLO_CODIGO_AGENTE_LF',
          'context_id',v->>'context_id',
          'context_sha256',v->>'context_sha256',
          'requested_scope_ids',v->'requested_scope_ids',
          'entry_contract','PROGRAMMING_ENTRY_CONTRACT_V1'),
        'motivo_es','Se identifica el despacho de Programacion, sin autorizar ejecucion downstream.',
        'siguiente_paso_es','Someter la ejecucion a su propia compuerta gobernada.');
    END IF;

$block$ || v_suffix;
  EXECUTE d;
END
$route$;

DO $after$
DECLARE
  d text; a text; b text; p1 integer; p2 integer;
  v_old record;
BEGIN
  IF to_regprocedure('public.lf_router_programming_admission_gate_v1(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'LF_ROUTER_PROGRAMMING_ADMISSION_POSTCHECK_GATE_MISSING';
  END IF;
  SELECT * INTO STRICT v_old FROM pg_temp.router_programming_patch_baseline;
  d := pg_get_functiondef('public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure);
  a := E'    IF v_channel=\'PROGRAMACION\' THEN\n';
  b := E'    IF v_channel=\'OPERACIONES\' THEN\n';
  p1 := strpos(d,a); p2 := strpos(d,b);
  IF p1 <= 0 OR p2 <= p1
     OR substring(d from 1 for p1-1) <> v_old.prefix
     OR substring(d from p2) <> v_old.suffix THEN
    RAISE EXCEPTION 'LF_ROUTER_PROGRAMMING_ADMISSION_POSTCHECK_OUTSIDE_BLOCK_DRIFT';
  END IF;
  IF has_function_privilege('anon', 'public.lf_router_programming_admission_gate_v1(jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.lf_router_programming_admission_gate_v1(jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'LF_ROUTER_PROGRAMMING_ADMISSION_POSTCHECK_ACL';
  END IF;
END
$after$;
COMMIT;
