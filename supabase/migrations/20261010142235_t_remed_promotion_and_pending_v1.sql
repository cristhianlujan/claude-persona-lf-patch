-- T-REMED: (1) pending-dependency classifier, (2) judge-gated promotion step with change log, (3) revert.
-- (1) fn_t_remed_pending_deps_v1(rule): every string in a rule's config that names an open dependency, classified by its own token structure.
--     kind: CANONICAL_SOURCE (PENDING_CANONICAL_*), LEGAL_BUSINESS, COPY, OTHER_PENDING (other PENDING_*), STATE_WORD (word appears inside a status name, not an open dependency).
-- (2) fn_t_remed_promote_v1(apply, min_screens, limit): promotes CANDIDATO -> VIGENTE only rules with verdict PASS from fn_t_remed_rule_promotion_verdicts_v1.
--     p_apply=false (default) only reports. With apply=true each change is written to programacion.t_remed_change_log (layer PROMOTE, kind STATUS_CHANGE) in the same call.
-- (3) fn_t_remed_revert_promotion_v1(change_id): returns one promoted rule to its previous state if it was not changed since.
create or replace function programacion.fn_t_remed_pending_deps_v1(p_regla_id bigint default null)
 returns table(regla_id bigint, regla_codigo text, path text, value text, kind text)
 language sql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
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
$fn$;

create or replace function programacion.fn_t_remed_promote_v1(p_apply boolean default false, p_min_screens integer default 5, p_limit integer default null)
 returns table(regla_id bigint, regla_codigo text, applied boolean, change_id bigint)
 language plpgsql volatile security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
declare v record; v_cid bigint; n int:=0;
begin
  for v in select x.regla_id rid, x.regla_codigo cod from programacion.fn_t_remed_rule_promotion_verdicts_v1(p_min_screens,null) x
           where x.verdict='PASS' order by x.regla_id loop
    exit when p_limit is not null and n>=p_limit;
    n:=n+1; v_cid:=null;
    if coalesce(p_apply,false) then
      update lf_ops.reglas set estado='VIGENTE' where id=v.rid and estado='CANDIDATO';
      if found then
        insert into programacion.t_remed_change_log(layer,subject_kind,subject_id,kind,target_table,pk_col,pk_value,col_name,before_value,after_value,actor)
        values ('PROMOTE','REGLA',v.rid,'STATUS_CHANGE','lf_ops.reglas','id',v.rid,'estado','CANDIDATO','VIGENTE','fn_t_remed_promote_v1') returning t_remed_change_log.change_id into v_cid;
      end if;
    end if;
    regla_id:=v.rid; regla_codigo:=v.cod; applied:=(v_cid is not null); change_id:=v_cid; return next;
  end loop;
end $fn$;

create or replace function programacion.fn_t_remed_revert_promotion_v1(p_change_id bigint)
 returns text
 language plpgsql volatile security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
declare c record;
begin
  select * into c from programacion.t_remed_change_log l where l.change_id=p_change_id and l.layer='PROMOTE' and l.kind='STATUS_CHANGE' and l.target_table='lf_ops.reglas' and l.col_name='estado' and l.reverted_at is null;
  if not found then return 'NOT_REVERTIBLE'; end if;
  update lf_ops.reglas set estado=c.before_value where id=c.pk_value and estado=c.after_value;
  if not found then return 'CHANGED_SINCE'; end if;
  update programacion.t_remed_change_log set reverted_at=now() where change_id=p_change_id;
  return 'REVERTED';
end $fn$;

comment on function programacion.fn_t_remed_pending_deps_v1(bigint) is 'T-REMED: open dependencies named inside rule configs, classified by token structure. Read-only.';
comment on function programacion.fn_t_remed_promote_v1(boolean,integer,integer) is 'T-REMED promotion step. Only judge PASS rules; default is report-only; apply=true logs every change in t_remed_change_log.';
comment on function programacion.fn_t_remed_revert_promotion_v1(bigint) is 'T-REMED: reverts one logged promotion if the rule state was not changed since.';
revoke all on function programacion.fn_t_remed_pending_deps_v1(bigint), programacion.fn_t_remed_promote_v1(boolean,integer,integer), programacion.fn_t_remed_revert_promotion_v1(bigint) from public, anon, authenticated;
