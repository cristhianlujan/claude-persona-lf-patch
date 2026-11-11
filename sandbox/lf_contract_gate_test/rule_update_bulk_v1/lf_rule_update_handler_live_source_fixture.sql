-- Canonical live skill handler, frozen for isolated PG17 suite only; MD5 c9696418d7404df55b3af28082abaa4f
CREATE OR REPLACE FUNCTION public.lf_skill_h_rule_update_propose_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 select jsonb_build_object('regla_codigo',p_input->>'regla_codigo','existe',exists(select 1 from lf_ops.reglas r where r.codigo=p_input->>'regla_codigo'),
  'operacion_requerida','ACTUALIZACION_REGLA_LF','escribe',false,'analysis_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',p_input->>'regla_codigo'));
$function$;
