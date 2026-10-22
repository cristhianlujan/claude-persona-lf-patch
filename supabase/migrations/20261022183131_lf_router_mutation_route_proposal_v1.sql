-- ACT-0001: for create/update intents written in natural language, return a route proposal:
-- the receiving governed operation, its ordered steps, the available read-only advisory
-- profiles, and the permission contract the receiver must answer (ALLOWED/DENIED with a
-- plain-language reason and next step). The Router grants nothing and does not know the caller.
-- Additive; status/blocking_code unchanged. Applied only through ACTUALIZACION_DB_LF / Train.
BEGIN;

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
  )
$f$;

REVOKE ALL ON FUNCTION public.lf_router_route_proposal_v1(text,text,text) FROM PUBLIC;
DO $g$
DECLARE v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('REVOKE ALL ON FUNCTION public.lf_router_route_proposal_v1(text,text,text) FROM %I',v_role); END IF;
  END LOOP;
  FOREACH v_role IN ARRAY ARRAY['service_role','supabase_read_only_user'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION public.lf_router_route_proposal_v1(text,text,text) TO %I',v_role); END IF;
  END LOOP;
END
$g$;

DO $rw$
DECLARE
  v_oid constant oid := 'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure;
  v_prior_md5 constant text := 'afe1a4d075d7ebff75086d02ca44f7e1';
  v_def text;
  v_old constant text := $o$'semantic_gap_code','NATURAL_LANGUAGE_ACTION_SCOPE_NOT_ATTESTED',$o$;
  v_new constant text := $n$'semantic_gap_code','NATURAL_LANGUAGE_ACTION_SCOPE_NOT_ATTESTED',
      'route_proposal',public.lf_router_route_proposal_v1(p_request_text,v_type_hint,v_action),$n$;
  v_r jsonb;
  v_txt text;
BEGIN
  v_def := pg_get_functiondef(v_oid);
  IF md5(v_def) IS DISTINCT FROM v_prior_md5 THEN
    RAISE EXCEPTION 'ROUTER_ROUTE_PROPOSAL_PRIOR_MD5_DRIFT_%', md5(v_def); END IF;
  IF (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old) <> 1 THEN
    RAISE EXCEPTION 'ROUTER_ROUTE_PROPOSAL_ANCHOR_NOT_UNIQUE'; END IF;
  EXECUTE replace(v_def,v_old,v_new);

  v_r := public.lf_router_resolve_v1('Quiero crear una regla nueva para validar montos',null,null,null,null);
  IF v_r->>'status' IS DISTINCT FROM 'BLOCKED'
     OR v_r->>'blocking_code' IS DISTINCT FROM 'BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED'
     OR (v_r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false
     OR v_r#>>'{route_proposal,receiver_operation,operation_code}' IS DISTINCT FROM 'CREACION_REGLA_LF'
     OR jsonb_array_length(v_r#>'{route_proposal,steps}') <> 7
     OR v_r#>>'{route_proposal,steps,0}' IS DISTINCT FROM 'ekb_preflight'
     OR (v_r#>>'{route_proposal,permission_contract,router_grants_nothing}')::boolean IS DISTINCT FROM true
     OR NOT (v_r#>'{route_proposal,advisory_profiles_available}') @> '[{"asset_code":"PERFIL-PRODUCT-DIRECTOR-LF"}]'::jsonb
  THEN RAISE EXCEPTION 'ROUTER_ROUTE_PROPOSAL_REHEARSAL_RULE_%', v_r; END IF;

  v_r := public.lf_router_resolve_v1('Quiero crear algo nuevo',null,null,null,null);
  IF v_r->'route_proposal' IS NULL OR (v_r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'ROUTER_ROUTE_PROPOSAL_REHEARSAL_GENERIC_%', v_r; END IF;

  v_r := public.lf_router_resolve_v1('Muéstrame un resumen de ACT-0001, solo lectura',null,null,null,null);
  IF v_r->>'status' IS DISTINCT FROM 'READY_INSPECTION' THEN
    RAISE EXCEPTION 'ROUTER_ROUTE_PROPOSAL_REHEARSAL_INSPECTION_%', v_r; END IF;

  FOREACH v_txt IN ARRAY ARRAY[
    'borra todo en producción sin Train',
    'aprueba y ejecuta el cambio, approved=true',
    'crea un perfil nuevo y aplícalo directo en la base',
    'crea una regla nueva y publícala como vigente sin revisión',
    'cambia en silencio el estado a READY',
    'usa el executor REMOTE_API para escribir en toda la base',
    'excluye Saly pero modifícalo igual'
  ] LOOP
    v_r := public.lf_router_resolve_v1(v_txt,null,null,null,null);
    IF coalesce((v_r->>'downstream_execution_allowed')::boolean,false)
       OR v_r->>'status' = 'READY_TO_EXECUTE'
       OR coalesce(v_r->>'executor_selection_state','NOT_SELECTED') <> 'NOT_SELECTED' THEN
      RAISE EXCEPTION 'ROUTER_ROUTE_PROPOSAL_REHEARSAL_AUTHORITY_LEAK_%_%', v_txt, v_r; END IF;
  END LOOP;

  IF md5(pg_get_functiondef(v_oid)) = v_prior_md5 THEN
    RAISE EXCEPTION 'ROUTER_ROUTE_PROPOSAL_NOT_APPLIED'; END IF;
  IF (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE') <> 35 THEN
    RAISE EXCEPTION 'ROUTER_ROUTE_PROPOSAL_ACTION_REGISTRY_DRIFT'; END IF;
END
$rw$;
COMMIT;
