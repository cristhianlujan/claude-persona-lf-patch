-- Captured via SELECT pg_get_functiondef of current deployed functions on 2026-11-14.
-- Historical SQL source must remain unchanged in the V2 tests.
CREATE OR REPLACE FUNCTION programacion.fn_t_remed_pending_deps_v1(p_regla_id bigint DEFAULT NULL::bigint)
 RETURNS TABLE(regla_id bigint, regla_codigo text, path text, value text, kind text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
  with recursive j(rid, codigo, path, val) as (
    select r.id, r.codigo, ''::text, r.valor_config from lf_ops.reglas r
     where r.estado in ('VIGENTE','CANDIDATO') and (p_regla_id is null or r.id=p_regla_id) and jsonb_typeof(r.valor_config) in ('object','array')
    union all
    select j.rid, j.codigo, j.path||'/'||e.k, e.v from j,
     lateral (select k, v from jsonb_each(case when jsonb_typeof(j.val)='object' then j.val else '{}'::jsonb end) x(k,v)
              union all select (a.i-1)::text, a.v from jsonb_array_elements(case when jsonb_typeof(j.val)='array' then j.val else '[]'::jsonb end) with ordinality a(v,i)) e
     where jsonb_typeof(j.val) in ('object','array')
  )
  select rid::bigint, codigo::text, path, val#>>'{}',
    case when (val#>>'{}') ~ '^PENDING_CANONICAL_' then 'CANONICAL_SOURCE'
         when (val#>>'{}') ~* '^PENDING_.*(LEGAL|BUSINESS)' then 'LEGAL_BUSINESS'
         when (val#>>'{}') ~* '^PENDING_.*COPY' then 'COPY'
         when (val#>>'{}') ~* '^(PENDING|PENDIENTE)([_ ].*)?$' then 'OTHER_PENDING'
         else 'STATE_WORD' end
  from j where jsonb_typeof(val)='string' and (val#>>'{}') ~* '(pending|pendiente)'
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_t_remed_rule_promotion_verdicts_v1(p_min_screens integer DEFAULT 5, p_regla_id bigint DEFAULT NULL::bigint)
 RETURNS TABLE(regla_id bigint, regla_codigo text, screens integer, criteria jsonb, verdict text, failed text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
  with r as (
    select * from lf_ops.reglas where estado='CANDIDATO' and (p_regla_id is null or id=p_regla_id)
  ), n as (
    select z.regla_id rid, count(distinct z.pantalla_id)::int c from lf_ops.reglas_pantallas z group by 1
  ), pr as (
    select d.regla_id rid, count(*)::int pm from programacion.fn_t_remed_pending_deps_v1(p_regla_id) d
    where d.kind<>'STATE_WORD' and d.path<>'/implementation_status' group by 1
  ), dup as (
    select r.id, (r.valor_config is not null and r.valor_config<>'{}'::jsonb and exists(
      select 1 from lf_ops.reglas o where o.id<>r.id and o.estado in ('VIGENTE','CANDIDATO')
        and o.categoria is not distinct from r.categoria and o.valor_config=r.valor_config)) d
    from r
  ), c as (
    select r.id, r.codigo, coalesce(n.c,0) screens,
      jsonb_build_object(
        'NO_PENDING_DECISION', not coalesce(r.pendiente_decision,false),
        'NO_PENDING_MARKER', coalesce(pr.pm,0)=0,
        'HAS_STATED_REASON', nullif(btrim(coalesce(r.razon,'')),'') is not null,
        'USED_BY_ENOUGH_SCREENS', coalesce(n.c,0)>=p_min_screens,
        'NO_DUPLICATE_ACTIVE_RULE', not dup.d) crit
    from r left join n on n.rid=r.id left join pr on pr.rid=r.id join dup on dup.id=r.id
  )
  select c.id::bigint, c.codigo::text, c.screens, c.crit,
    case when exists(select 1 from jsonb_each(c.crit) e where e.value='false'::jsonb) then 'HOLD' else 'PASS' end,
    array(select e.key::text from jsonb_each(c.crit) e where e.value='false'::jsonb order by e.key)
  from c order by c.id
$function$
;
