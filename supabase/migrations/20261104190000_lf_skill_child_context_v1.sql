-- LF skill invoker: the child execution opened by PROFILE_UPDATE_APPLY carries the same starting context
-- as a direct Profile Update init execution, so stages 35..130 find every key they read.
-- Trusted values (main revision, target blob, authenticated caller) come from the Edge transport under the
-- reserved key "_trusted"; the Router receipt is derived here through the registered governed caller.
CREATE OR REPLACE FUNCTION public.lf_skill_o_profile_update_v1(p_child text, p_input jsonb, p_parent text, p_run text, p_request_sha text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
 par record; a record; t jsonb; c jsonb; g jsonb; r jsonb; asset record; v_root text; v_path text; v_code text;
begin
 select * into par from public.lf_operation_execution e where e.execution_id=p_parent;
 v_code := upper(btrim(coalesce(p_input->>'target_code','')));
 v_path := btrim(coalesce(p_input->>'target_path',''));
 t := p_input->'_trusted';
 if jsonb_typeof(coalesce(t,'null'::jsonb)) <> 'object'
    or coalesce(t->>'main_sha','') !~ '^[0-9a-f]{40}$'
    or coalesce(t->>'target_blob_sha','') !~ '^[0-9a-f]{40}$'
    or jsonb_typeof(coalesce(t->'caller','null'::jsonb)) <> 'object' then
  raise exception 'SKILL_TRUSTED_CONTEXT_MISSING: el contexto verificado (main, blob del archivo, llamador) lo pone el transporte Edge; reenviar la solicitud por la ruta nativa del perfil';
 end if;
 select * into asset from public.lf_activos x where x.codigo_activo=v_code and x.archived_at is null limit 1;
 v_root := regexp_replace(coalesce(asset.ruta_esperada,''),'/+$','');
 if not found or asset.tipo_activo is distinct from 'PERFIL' or v_root='' or not (v_path like v_root||'/%') then
  raise exception 'SKILL_TARGET_NOT_OWNED_BY_PROFILE: target_path debe ser un archivo exacto dentro de la carpeta del perfil % (ruta recibida: %)', v_code, v_path;
 end if;
 if public.lf_profile_family_v1(par.target_code)=public.lf_profile_family_v1(v_code) and not exists(select 1 from public.lf_profile_write_authority_v1 w where w.profile_code=par.target_code and w.operation_code='ACTUALIZACION_PERFIL_LF' and w.status='ACTIVE' and w.self_update_allowed) then
  select * into a from public.lf_profile_self_update_approval_v1 x where x.profile_code=par.target_code and x.target_code=v_code and x.target_path=v_path and x.request_sha256=p_request_sha and x.status='APPROVED' order by x.created_at limit 1 for update;
  if not found then raise exception 'SELF_UPDATE_REQUIRES_HUMAN_APPROVAL: un perfil que se actualiza a si mismo necesita aprobacion humana. Pedirla con lf_profile_self_update_request_v1 y esperar la aprobacion'; end if;
  update public.lf_profile_self_update_approval_v1 set status='USED', used_at=now() where approval_id=a.approval_id;
 end if;
 -- The Router derives the receipt for the registered caller identity of this skill; run and workflow sha are the authenticated ones.
 c := public.lf_skill_child_caller_manifest_v1('PROFILE_UPDATE_APPLY');
 g := public.lf_router_governed_caller_route_v1(
   jsonb_build_object('method',c->>'governed_caller_method','repository',c->>'caller_repository','workflow_ref',c->>'caller_workflow_ref',
     'run_id',t->'caller'->>'run_id','workflow_sha',t->'caller'->>'workflow_sha'), v_code, v_path);
 r := g->'router_result';
 if g->>'status' is distinct from 'ROUTER_REDERIVED' or coalesce((g->>'downstream_execution_allowed')::boolean,true) is distinct from false
    or r->>'status' is distinct from 'READY_TO_EXECUTE' or r->>'operation_code' is distinct from 'ACTUALIZACION_PERFIL_LF'
    or r->>'action_code' is distinct from 'PROFILE_UPDATE' or coalesce(g->>'semantic_receipt_sha256','') !~ '^[0-9a-f]{64}$' then
  raise exception 'SKILL_ROUTER_UPDATE_NOT_AUTHORIZED: %', coalesce(g->>'blocking_code', r->>'status', 'sin detalle');
 end if;
 return public.lf_profile_update_begin_v1(p_child, v_code, 'cristhianlujan/claude-persona-lf-patch', v_path, p_request_sha, 'skill-child-v1:'||p_run, p_parent,
   jsonb_build_object('schema_version',1,'router','ACT-0001',
     'profile_handoff',jsonb_build_object('source_execution_id',p_parent,'skill_run_id',p_run,'via','SKILL_INVOKER'),
     'caller_run_id',t->'caller'->>'run_id','caller_workflow_sha',t->'caller'->>'workflow_sha',
     'router_governed_caller_code',g->>'caller_code','router_semantic_receipt_sha256',g->>'semantic_receipt_sha256',
     'router_semantic_request',g->'semantic_request',
     'runtime_write_executed',false,'github_write_executed',false,'production_authorized',false,'automatic_runtime_promotion',false,
     'target_root_path',v_root,'initial_main_revision',t->>'main_sha','initial_target_blob_sha',t->>'target_blob_sha',
     'research_baseline_mode','NOT_REQUIRED') || c);
end $function$;

revoke all on function public.lf_skill_o_profile_update_v1(text,jsonb,text,text,text) from public, anon, authenticated;
grant execute on function public.lf_skill_o_profile_update_v1(text,jsonb,text,text,text) to service_role;
