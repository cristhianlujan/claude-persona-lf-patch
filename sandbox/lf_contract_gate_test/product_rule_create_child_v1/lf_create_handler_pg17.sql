-- Frozen live handler for synthetic PG17 tests only; current source md5 e2cf37423e91f7d2921e9470605ca474
CREATE OR REPLACE FUNCTION public.lf_skill_h_rule_create_propose_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
 if exists(select 1 from lf_ops.reglas r where r.codigo=p_input->>'regla_codigo') then raise exception 'RULE_ALREADY_EXISTS:%', p_input->>'regla_codigo'; end if;
 return jsonb_build_object('regla_codigo',p_input->>'regla_codigo','existe',false,'operacion_requerida','CREACION_REGLA_LF','escribe',false);
end $function$;
