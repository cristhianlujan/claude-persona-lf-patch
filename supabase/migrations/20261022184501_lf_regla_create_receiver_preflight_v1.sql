-- Receiver preflight for CREACION_REGLA_LF: before anything is written, the receiver states what
-- it can and will not do, the inputs it requires, the modes available, and similar existing rules.
-- Read-only (STABLE). Included in the Router route_proposal for REGLA_CREATE. The Router resolver
-- itself is NOT modified. Applied only through ACTUALIZACION_DB_LF / LF Migration Merge Train.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_regla_create_preflight_v1(p_request_text text)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'pg_catalog','public','lf_ops'
AS $f$
  WITH toks AS (
    SELECT DISTINCT CASE WHEN length(w)>4 AND w LIKE '%s' THEN left(w,length(w)-1) ELSE w END AS tk
    FROM regexp_split_to_table(regexp_replace(translate(lower(coalesce(p_request_text,'')),
           'áéíóúüñ','aeiouun'),'[^a-z0-9]+',' ','g'),' ') AS w
    WHERE length(w)>=5
      AND w NOT IN ('quiero','crear','regla','reglas','nueva','nuevo','para','crea','creame')
  ), r AS (
    SELECT g.codigo, g.titulo, g.estado,
           ' '||regexp_replace(translate(lower(g.codigo||' '||g.titulo||' '||coalesce(g.descripcion,'')),
             'áéíóúüñ','aeiouun'),'[^a-z0-9]+',' ','g')||' ' AS norm
    FROM lf_ops.reglas g
  ), sc AS (
    SELECT r.codigo, r.titulo, r.estado, count(*) AS score
    FROM toks t JOIN r ON position(' '||t.tk IN r.norm)>0
    GROUP BY 1,2,3
  ), top5 AS (SELECT * FROM sc ORDER BY score DESC, codigo LIMIT 5)
  SELECT jsonb_build_object(
    'receiver_operation','CREACION_REGLA_LF',
    'caller_authority','NOT_VERIFIED_BY_THIS_RECEIVER_NO_CALLER_IDENTITY_IN_DB_CALL',
    'can_do',jsonb_build_array(
      'Crear una regla en estado CANDIDATO (nunca VIGENTE).',
      'Modo EXPLORATION: guardar en almacén de exploración aceptando información parcial.',
      'Modo GOVERNED: guardar como candidato canónico, exige información completa.'),
    'will_not_do',jsonb_build_array(
      'Promover o publicar una regla como VIGENTE (esta operación no promueve).',
      'Modificar directamente una regla VIGENTE existente.',
      'Escribir sin una ejecución abierta y un modo de ejecución habilitado.'),
    'denial_format',jsonb_build_object(
      'plain_language_reason','obligatorio','reason_code','obligatorio','next_step','obligatorio'),
    'modes',(
      SELECT coalesce(jsonb_agg(jsonb_build_object('execution_mode',b.execution_mode,
             'writes_to',b.destination_kind,'input',b.input_completeness,'allowed',b.allowed,
             'write_allowed',b.write_allowed) ORDER BY b.execution_mode),'[]'::jsonb)
      FROM public.lf_operation_mode_bindings b
      WHERE b.operation_code='CREACION_REGLA_LF' AND b.task_mode='CREATE_NEW' AND b.status='ACTIVE'),
    'required_inputs_governed',jsonb_build_array('codigo','categoria','titulo','descripcion'),
    'optional_inputs',jsonb_build_array('razon','valor_config','es_transversal','origen'),
    'related_existing_rules',(
      SELECT coalesce(jsonb_agg(jsonb_build_object('codigo',codigo,'titulo',titulo,'estado',estado)
                                ORDER BY score DESC, codigo),'[]'::jsonb) FROM top5),
    'max_material_questions_per_round',1
  )
$f$;

CREATE OR REPLACE FUNCTION public.lf_router_route_proposal_v1(p_request_text text, p_asset_type text, p_action_code text)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'pg_catalog','public'
AS $f$
  SELECT jsonb_build_object(
    'basis','REGISTRY_CANDIDATE_NOT_AUTHORITY',
    'candidate_asset_type',p_asset_type,
    'candidate_action_code',p_action_code,
    'receiver_operation',(
      SELECT jsonb_build_object('operation_code',o.operation_code,'operation_status',o.status,
             'lifecycle_state',o.lifecycle_state_code,'operation_type',o.operation_type,
             'what_it_does',o.notes)
      FROM public.lf_router_action_registry ar
      JOIN public.lf_operation_registry o ON o.operation_code=ar.operation_code
      WHERE ar.asset_type=p_asset_type AND ar.action_code=p_action_code AND ar.status='ACTIVE'
      LIMIT 1),
    'steps',(
      SELECT coalesce(jsonb_agg(s.step_id ORDER BY coalesce(s.execution_order,s.step_order),s.step_id),'[]'::jsonb)
      FROM public.lf_router_action_registry ar
      JOIN public.lf_operation_step_contracts s
        ON s.operation_code=ar.operation_code AND s.status IN ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')
      WHERE ar.asset_type=p_asset_type AND ar.action_code=p_action_code AND ar.status='ACTIVE'),
    'advisory_profiles_available',(
      SELECT coalesce(jsonb_agg(jsonb_build_object('asset_code',b.codigo_activo,
             'estado_operativo',b.estado_operativo,'runtime_estado',b.runtime_estado)
             ORDER BY b.codigo_activo),'[]'::jsonb)
      FROM public.v_lf_fuente_operativa_busqueda b
      WHERE b.tipo_activo='PERFIL' AND upper(b.estado_operativo)='READ_ONLY'),
    'permission_contract',jsonb_build_object(
      'router_grants_nothing',true,
      'router_knows_caller_authority',false,
      'receiver_must_answer','ALLOWED_OR_DENIED',
      'denial_must_include',jsonb_build_array('plain_language_reason','reason_code','next_step'),
      'advisory_profiles_are_read_only',true)
  ) || CASE WHEN p_action_code='REGLA_CREATE'
            THEN jsonb_build_object('receiver_preflight',public.lf_regla_create_preflight_v1(p_request_text))
            ELSE '{}'::jsonb END
$f$;

REVOKE ALL ON FUNCTION public.lf_regla_create_preflight_v1(text) FROM PUBLIC;
DO $g$
DECLARE v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('REVOKE ALL ON FUNCTION public.lf_regla_create_preflight_v1(text) FROM %I',v_role); END IF;
  END LOOP;
  FOREACH v_role IN ARRAY ARRAY['service_role','supabase_read_only_user'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION public.lf_regla_create_preflight_v1(text) TO %I',v_role); END IF;
  END LOOP;
END
$g$;

DO $rw$
DECLARE v_r jsonb; v_d jsonb;
BEGIN
  v_r := public.lf_router_resolve_v1('Quiero crear una regla nueva para validar montos',null,null,null,null);
  v_d := v_r#>'{route_proposal,receiver_preflight}';
  IF v_d IS NULL
     OR v_d->>'receiver_operation' IS DISTINCT FROM 'CREACION_REGLA_LF'
     OR jsonb_array_length(v_d->'modes') <> 2
     OR jsonb_array_length(v_d->'will_not_do') < 3
     OR v_d->'required_inputs_governed' IS DISTINCT FROM '["codigo","categoria","titulo","descripcion"]'::jsonb
     OR jsonb_array_length(v_d->'related_existing_rules') < 1
     OR (v_r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false
     OR v_r#>>'{route_proposal,steps,0}' IS DISTINCT FROM 'ekb_preflight'
  THEN RAISE EXCEPTION 'RULE_PREFLIGHT_REHEARSAL_RULE_%', v_r; END IF;

  -- Other intents must not get a preflight, and must stay non-executable.
  v_r := public.lf_router_resolve_v1('Quiero crear algo nuevo',null,null,null,null);
  IF v_r#>'{route_proposal,receiver_preflight}' IS NOT NULL
     OR (v_r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'RULE_PREFLIGHT_REHEARSAL_OTHER_%', v_r; END IF;

  -- No write happened: rules count is unchanged by this migration (read-only function).
  IF (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE') <> 35 THEN
    RAISE EXCEPTION 'RULE_PREFLIGHT_ACTION_REGISTRY_DRIFT'; END IF;
END
$rw$;
COMMIT;
