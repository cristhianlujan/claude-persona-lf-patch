-- Isolated PG17 fixture only. Exact canonical function sources read from Supabase (2026-11-10), no credentials/data.
-- Only runs on temporary GitHub Actions service postgres:17.6.

CREATE OR REPLACE FUNCTION public.lf_regla_pantalla_link_v1(p_execution_id text, p_regla_codigo text, p_pantalla_id integer, p_nota text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'lf_ops'
AS $function$
declare
  v_exec public.lf_operation_execution%rowtype;
  v_rule lf_ops.reglas%rowtype;
  v_screen lf_ops.pantallas%rowtype;
  v_rule_after lf_ops.reglas%rowtype;
  v_screen_after lf_ops.pantallas%rowtype;
  v_rel lf_ops.reglas_pantallas%rowtype;
  v_inserted boolean:=false;
  v_count integer;
  v_expected_target text;
begin
  if btrim(coalesce(p_execution_id,''))='' or btrim(coalesce(p_regla_codigo,''))='' or p_pantalla_id is null then
    raise exception 'LF_RULE_SCREEN_RELATION_REQUIRED_INPUT_MISSING';
  end if;

  v_expected_target:=p_regla_codigo||'@'||p_pantalla_id::text;
  select * into v_exec from public.lf_operation_execution where execution_id=p_execution_id;
  if not found then raise exception 'LF_RULE_SCREEN_RELATION_EXECUTION_NOT_FOUND:%',p_execution_id; end if;
  if v_exec.operation_code<>'VINCULACION_REGLA_PANTALLA_LF'
     or v_exec.status<>'IN_PROGRESS'
     or v_exec.target_type<>'REGLA_PANTALLA_RELATION'
     or v_exec.target_code<>v_expected_target then
    raise exception 'LF_RULE_SCREEN_RELATION_EXECUTION_BINDING_MISMATCH';
  end if;

  select * into v_rule from lf_ops.reglas where codigo=p_regla_codigo;
  if not found then raise exception 'LF_RULE_SCREEN_RULE_NOT_FOUND:%',p_regla_codigo; end if;
  if v_rule.estado not in ('CANDIDATO','VIGENTE') then
    raise exception 'LF_RULE_SCREEN_RULE_STATE_NOT_SUPPORTED:%:%',p_regla_codigo,v_rule.estado;
  end if;

  select * into v_screen from lf_ops.pantallas where id=p_pantalla_id;
  if not found then raise exception 'LF_RULE_SCREEN_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;

  insert into lf_ops.reglas_pantallas(regla_id,pantalla_id,nota)
  values(v_rule.id,v_screen.id,nullif(btrim(coalesce(p_nota,'')),''))
  on conflict(regla_id,pantalla_id) do nothing
  returning * into v_rel;

  if v_rel.id is not null then
    v_inserted:=true;
  else
    select * into v_rel from lf_ops.reglas_pantallas
    where regla_id=v_rule.id and pantalla_id=v_screen.id;
  end if;

  if v_rel.id is null then raise exception 'LF_RULE_SCREEN_RELATION_READBACK_MISSING'; end if;
  select count(*) into v_count from lf_ops.reglas_pantallas
  where regla_id=v_rule.id and pantalla_id=v_screen.id;
  if v_count<>1 then raise exception 'LF_RULE_SCREEN_RELATION_CARDINALITY_INVALID:%',v_count; end if;

  select * into v_rule_after from lf_ops.reglas where id=v_rule.id;
  select * into v_screen_after from lf_ops.pantallas where id=v_screen.id;
  if to_jsonb(v_rule_after) is distinct from to_jsonb(v_rule) then raise exception 'LF_RULE_SCREEN_RULE_MUTATED'; end if;
  if to_jsonb(v_screen_after) is distinct from to_jsonb(v_screen) then raise exception 'LF_RULE_SCREEN_SCREEN_MUTATED'; end if;

  return jsonb_build_object(
    'result',case when v_inserted then 'RULE_SCREEN_RELATION_CREATED' else 'RULE_SCREEN_RELATION_ALREADY_EXISTS' end,
    'operation_code','VINCULACION_REGLA_PANTALLA_LF',
    'execution_id',p_execution_id,
    'rule_code',v_rule.codigo,
    'rule_id',v_rule.id,
    'rule_state',v_rule.estado,
    'pantalla_id',v_screen.id,
    'screen_code',v_screen.codigo,
    'screen_active',v_screen.activa,
    'relation_row',to_jsonb(v_rel),
    'relation_count',v_count,
    'rule_unchanged',true,
    'screen_unchanged',true,
    'no_delete',true,
    'production_authorized',true,
    'runtime_activation',false,
    'promotion_authorized',false
  );
end $function$

CREATE OR REPLACE FUNCTION public.lf_skill_h_rule_link_propose_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
 if p_input->>'target_type'<>'REGLA_PANTALLA_RELATION' or p_input->>'target_code' is distinct from (p_input->>'regla_codigo')||'@'||(p_input->>'pantalla_id') then raise exception 'LINK_TARGET_INVALID: target_code debe ser regla@pantalla_id'; end if;
 if not exists(select 1 from lf_ops.reglas r where r.codigo=p_input->>'regla_codigo' and r.estado in ('CANDIDATO','VIGENTE')) then raise exception 'RULE_NOT_LINKABLE:%', p_input->>'regla_codigo'; end if;
 if not exists(select 1 from lf_ops.pantallas p where p.id=(p_input->>'pantalla_id')::int) then raise exception 'SCREEN_NOT_FOUND:%', p_input->>'pantalla_id'; end if;
 return jsonb_build_object('regla_codigo',p_input->>'regla_codigo','pantalla_id',p_input->>'pantalla_id','operacion_requerida','VINCULACION_REGLA_PANTALLA_LF','escribe',false);
end $function$

