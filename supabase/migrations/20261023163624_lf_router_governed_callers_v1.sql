-- ACT-0001: puerta de entrada registrada para llamadores automaticos gobernados.
-- Hoy el Router solo conoce una forma de atestiguar una mutacion: la que hace el modelo (etapa 1 + continuacion semantica).
-- Un workflow con identidad OIDC (p. ej. ACTUALIZACION_PERFIL_LF/init_execution) no tiene donde declararse y la funcion
-- que lo atiende tendria que fabricar su propio recibo. Aqui la autoridad queda en Supabase:
--   1) public.lf_router_governed_callers: registro de llamadores (metodo OIDC + repo + workflow_ref exactos -> tipo/accion/operacion permitidos);
--   2) public.lf_router_governed_caller_route_v1(caller, target_code, target_path): el Router valida al llamador contra el registro,
--      arma el recibo (hash de identidad del llamador + entradas) y re-deriva la ruta por lf_router_semantic_resume_route_v1,
--      es decir, por los mismos gates que cualquier otra mutacion. No autoriza efectos: downstream_execution_allowed=false.
-- Anadir otro llamador automatico = una fila nueva. Aplica solo por ACTUALIZACION_DB_LF / Merge Train.
BEGIN;

CREATE TABLE IF NOT EXISTS public.lf_router_governed_callers (
  caller_code     text PRIMARY KEY CHECK (caller_code ~ '^CALLER-[A-Z0-9-]{3,80}$'),
  caller_method   text NOT NULL UNIQUE CHECK (caller_method ~ '^[A-Z0-9_]{8,120}$'),
  repository      text NOT NULL CHECK (repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  workflow_ref    text NOT NULL CHECK (workflow_ref ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/\.github/workflows/[A-Za-z0-9_.-]+@refs/heads/[A-Za-z0-9_./-]+$'),
  asset_type      text NOT NULL CHECK (asset_type = upper(asset_type)),
  action_code     text NOT NULL CHECK (action_code = upper(action_code)),
  operation_code  text NOT NULL CHECK (operation_code = upper(operation_code)),
  literal_template text NOT NULL CHECK (position('{target}' in literal_template) > 0),
  status          text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','DISABLED')),
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.lf_router_governed_callers IS
  'ACT-0001: llamadores automaticos gobernados (identidad OIDC exacta) que pueden entrar al Router para una accion de mutacion concreta. Fuente de verdad en Supabase; el codigo de las funciones no decide quien es un llamador valido.';
ALTER TABLE public.lf_router_governed_callers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lf_router_governed_callers FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.lf_router_governed_callers TO service_role, supabase_read_only_user;

INSERT INTO public.lf_router_governed_callers
  (caller_code,caller_method,repository,workflow_ref,asset_type,action_code,operation_code,literal_template,notes)
VALUES
  ('CALLER-GHA-PROFILE-UPDATE-V1','GITHUB_ACTIONS_OIDC_EXACT_PROFILE_UPDATE_V1',
   'cristhianlujan/claude-persona-lf-patch',
   'cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-customer-profile-creator-governance-caller.yml@refs/heads/main',
   'PERFIL','PROFILE_UPDATE','ACTUALIZACION_PERFIL_LF','Actualizar perfil {target}',
   'Workflow_dispatch en main del repo del Router. El evento y la rama los exige la funcion de borde al validar el token OIDC; el registro fija repo, workflow_ref y que accion puede pedir.')
ON CONFLICT (caller_code) DO NOTHING;

CREATE OR REPLACE FUNCTION public.lf_router_governed_caller_route_v1(
  p_caller jsonb, p_target_code text, p_target_path text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  v_c public.lf_router_governed_callers%rowtype;
  v_reg_op text;
  v_reg_count integer;
  v_asset public.lf_activos%rowtype;
  v_lit text;
  v_sha text;
  v_cur text;
  v_receipt_src text;
  v_receipt text;
  v_req jsonb;
  v_res jsonb;
  v_rt jsonb;
  v_target text := upper(btrim(coalesce(p_target_code,'')));
  v_path text := btrim(coalesce(p_target_path,''));
BEGIN
  IF jsonb_typeof(coalesce(p_caller,'null'::jsonb)) <> 'object'
     OR coalesce(p_caller->>'method','') = '' OR coalesce(p_caller->>'repository','') = ''
     OR coalesce(p_caller->>'workflow_ref','') = '' OR coalesce(p_caller->>'run_id','') = ''
     OR coalesce(p_caller->>'workflow_sha','') !~ '^[0-9a-f]{40}$' THEN
    RETURN jsonb_build_object('schema_version','LF_ROUTER_GOVERNED_CALLER_ROUTE_V1','router','ACT-0001','status','BLOCKED',
      'blocking_code','BLOCK_GOVERNED_CALLER_IDENTITY_INCOMPLETE','downstream_execution_allowed',false);
  END IF;

  SELECT * INTO v_c FROM public.lf_router_governed_callers g
   WHERE g.status = 'ACTIVE' AND g.caller_method = p_caller->>'method'
     AND g.repository = p_caller->>'repository' AND g.workflow_ref = p_caller->>'workflow_ref';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('schema_version','LF_ROUTER_GOVERNED_CALLER_ROUTE_V1','router','ACT-0001','status','BLOCKED',
      'blocking_code','BLOCK_GOVERNED_CALLER_NOT_REGISTERED','downstream_execution_allowed',false);
  END IF;

  -- El registro no puede desviarse de la accion registrada en el Router.
  SELECT count(*), min(operation_code) INTO v_reg_count, v_reg_op
    FROM public.lf_router_action_registry
   WHERE asset_type = v_c.asset_type AND action_code = v_c.action_code AND status = 'ACTIVE';
  IF v_reg_count <> 1 OR v_reg_op IS DISTINCT FROM v_c.operation_code THEN
    RETURN jsonb_build_object('schema_version','LF_ROUTER_GOVERNED_CALLER_ROUTE_V1','router','ACT-0001','status','BLOCKED',
      'blocking_code','BLOCK_GOVERNED_CALLER_ACTION_REGISTRY_DRIFT','caller_code',v_c.caller_code,'downstream_execution_allowed',false);
  END IF;

  SELECT * INTO v_asset FROM public.lf_activos a WHERE a.codigo_activo = v_target AND a.archived_at IS NULL LIMIT 1;
  IF NOT FOUND OR v_asset.tipo_activo IS DISTINCT FROM v_c.asset_type OR v_path = '' THEN
    RETURN jsonb_build_object('schema_version','LF_ROUTER_GOVERNED_CALLER_ROUTE_V1','router','ACT-0001','status','BLOCKED',
      'blocking_code','BLOCK_GOVERNED_CALLER_TARGET_NOT_ALLOWED','caller_code',v_c.caller_code,'downstream_execution_allowed',false);
  END IF;

  v_lit := replace(v_c.literal_template,'{target}',v_asset.codigo_activo);
  v_sha := encode(extensions.digest(convert_to(v_lit,'UTF8'),'sha256'),'hex');
  v_cur := md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure));
  v_receipt_src := jsonb_build_object(
    'attestation','CALLER_REGISTRY_DISPATCH_V1','caller_code',v_c.caller_code,'caller_method',v_c.caller_method,
    'caller_workflow_ref',v_c.workflow_ref,'caller_workflow_sha',p_caller->>'workflow_sha','caller_run_id',p_caller->>'run_id',
    'literal_request',v_lit,'request_sha256',v_sha,'target_code',v_asset.codigo_activo,'target_path',v_path)::text;
  v_receipt := encode(extensions.digest(convert_to(v_receipt_src,'UTF8'),'sha256'),'hex');

  v_req := jsonb_build_object('schema_version','LF_ROUTER_SEMANTIC_REQUEST_V1','router','ACT-0001',
    'literal_request',v_lit,'request_sha256',v_sha,'reference_kind','EXPLICIT_CODE',
    'candidate_subjects',jsonb_build_array(jsonb_build_object('asset_code',v_asset.codigo_activo,'asset_type',v_asset.tipo_activo)),
    'excluded_target_refs','[]'::jsonb,'positive_target_refs',jsonb_build_array(v_asset.codigo_activo),
    'allowed_scope',jsonb_build_array(v_c.action_code),'forbidden_scope','[]'::jsonb,'conditions','[]'::jsonb,
    'source_currentness',jsonb_build_object('status','CURRENT','router_source_md5',v_cur));
  v_res := jsonb_build_object('schema_version','LF_ROUTER_SEMANTIC_RESULT_V1','request_sha256',v_sha,'decision','RESOLVED',
    'positive_target_refs',jsonb_build_array(v_asset.codigo_activo),'excluded_target_refs','[]'::jsonb,
    'allowed_scope',jsonb_build_array(v_c.action_code),'forbidden_scope','[]'::jsonb,'conditions','[]'::jsonb,
    'material_ambiguities','[]'::jsonb,'clarification_question',null,'semantic_receipt_sha256',v_receipt);

  v_rt := public.lf_router_semantic_resume_route_v1(v_req, v_res);

  RETURN jsonb_build_object(
    'schema_version','LF_ROUTER_GOVERNED_CALLER_ROUTE_V1','router','ACT-0001',
    'status', v_rt->>'status',
    'blocking_code', v_rt->>'blocking_code',
    'caller_code', v_c.caller_code,
    'semantic_receipt_sha256', v_receipt,
    'semantic_request', v_req,
    'router_result', v_rt->'router_result',
    'resume_route', v_rt,
    'semantic_result_route_authority', false,
    'semantic_result_effect_authority', false,
    'downstream_execution_allowed', false);
END
$fn$;
COMMENT ON FUNCTION public.lf_router_governed_caller_route_v1(jsonb,text,text) IS
  'ACT-0001: entrada de llamadores automaticos registrados en lf_router_governed_callers. Valida identidad contra el registro, arma el recibo y re-deriva por lf_router_semantic_resume_route_v1. No autoriza efectos.';
REVOKE ALL ON FUNCTION public.lf_router_governed_caller_route_v1(jsonb,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_governed_caller_route_v1(jsonb,text,text) TO service_role, supabase_read_only_user;

-- Ensayo: si algo no se cumple, aborta toda la migracion.
DO $rw$
DECLARE
  v_caller jsonb := jsonb_build_object('method','GITHUB_ACTIONS_OIDC_EXACT_PROFILE_UPDATE_V1',
    'repository','cristhianlujan/claude-persona-lf-patch',
    'workflow_ref','cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-customer-profile-creator-governance-caller.yml@refs/heads/main',
    'run_id','1','workflow_sha',repeat('a',40));
  v_r jsonb;
BEGIN
  v_r := public.lf_router_governed_caller_route_v1(v_caller,'PERFIL-UI-ARCHITECT','profiles/ui_architect/SKILL.md');
  IF v_r->>'status' IS DISTINCT FROM 'ROUTER_REDERIVED'
     OR v_r#>>'{router_result,status}' IS DISTINCT FROM 'READY_TO_EXECUTE'
     OR v_r#>>'{router_result,operation_code}' IS DISTINCT FROM 'ACTUALIZACION_PERFIL_LF'
     OR v_r#>>'{router_result,action_code}' IS DISTINCT FROM 'PROFILE_UPDATE'
     OR v_r#>>'{router_result,next_step,step_id}' IS DISTINCT FROM 'init_execution'
     OR (v_r#>>'{router_result,required_policy_count}') IS DISTINCT FROM (v_r#>>'{router_result,resolved_policy_count}')
     OR (v_r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false
     OR coalesce(v_r->>'semantic_receipt_sha256','') !~ '^[0-9a-f]{64}$'
  THEN RAISE EXCEPTION 'ROUTER_GOVERNED_CALLER_REHEARSAL_REGISTERED_%', v_r; END IF;

  v_r := public.lf_router_governed_caller_route_v1(jsonb_set(v_caller,'{workflow_ref}',to_jsonb('cristhianlujan/claude-persona-lf-patch/.github/workflows/otro.yml@refs/heads/main'::text)),'PERFIL-UI-ARCHITECT','profiles/ui_architect/SKILL.md');
  IF v_r->>'blocking_code' IS DISTINCT FROM 'BLOCK_GOVERNED_CALLER_NOT_REGISTERED' THEN
    RAISE EXCEPTION 'ROUTER_GOVERNED_CALLER_REHEARSAL_UNREGISTERED_%', v_r; END IF;

  v_r := public.lf_router_governed_caller_route_v1(v_caller,'B2B-AUTH-001','x/y.md');
  IF v_r->>'blocking_code' IS DISTINCT FROM 'BLOCK_GOVERNED_CALLER_TARGET_NOT_ALLOWED' THEN
    RAISE EXCEPTION 'ROUTER_GOVERNED_CALLER_REHEARSAL_NOT_A_PROFILE_%', v_r; END IF;

  v_r := public.lf_router_governed_caller_route_v1(v_caller - 'run_id','PERFIL-UI-ARCHITECT','profiles/ui_architect/SKILL.md');
  IF v_r->>'blocking_code' IS DISTINCT FROM 'BLOCK_GOVERNED_CALLER_IDENTITY_INCOMPLETE' THEN
    RAISE EXCEPTION 'ROUTER_GOVERNED_CALLER_REHEARSAL_INCOMPLETE_%', v_r; END IF;

  -- Sin atestacion sigue bloqueado: el registro no abre texto ni pistas sueltas.
  v_r := public.lf_router_resolve_v1('Actualizar perfil PERFIL-UI-ARCHITECT','PERFIL-UI-ARCHITECT','PROFILE_UPDATE','PERFIL','ROUTER');
  IF v_r->>'blocking_code' IS DISTINCT FROM 'BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED' THEN
    RAISE EXCEPTION 'ROUTER_GOVERNED_CALLER_REHEARSAL_HINTS_%', v_r; END IF;
END
$rw$;

COMMIT;
