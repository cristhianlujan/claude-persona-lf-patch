-- T-REMED layer 1 (reconcile): findings for information that cannot be linked but must not stay silent.
--   INCOMPLETE_REFERENCE : a "<x>_policy_id" key whose value is null, text or not an integer      (partial information)
--   EMPTY_RULE_CONFIG    : a rule with no configuration at all                                      (absent information)
--   DUPLICATE_RULES      : two or more rules of the screen with identical configuration            (duplicates, with or without references)
-- Output gains a "findings" array. "proposals" and "summary" are unchanged, so layers 2 and 3 are not affected. Still read-only.
create or replace function programacion.fn_t_remed_reconcile_v3(p_pantalla_id integer)
 returns jsonb
 language plpgsql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
declare g record; t record; v_props jsonb:='[]'::jsonb; v_tstatus text; v_verdict text; v_generic boolean; v_find jsonb;
begin
  if not exists(select 1 from lf_ops.pantallas where id=p_pantalla_id) then
    raise exception 'T_REMED_SUBJECT_NOT_FOUND:%',p_pantalla_id;
  end if;
  for g in
    with ref as (
      select r.id rid, r.codigo, r.estado, coalesce(r.pendiente_decision,false) pend, e.key, (e.value #>> '{}')::bigint tid
      from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
      cross join lateral jsonb_each(case when jsonb_typeof(r.valor_config)='object' then r.valor_config else '{}'::jsonb end) e
      where rp.pantalla_id=p_pantalla_id and r.estado in ('VIGENTE','CANDIDATO') and e.key ~ '_policy_id$'
        and jsonb_typeof(e.value)='number' and (e.value #>> '{}') ~ '^[0-9]+$')
    select ref.key, ref.tid, array_agg(distinct ref.codigo) codes, array_agg(distinct ref.rid) rids,
           array_agg(distinct ref.estado) states, bool_or(ref.pend) pend,
           (select count(distinct r2.tid) from ref r2 where r2.key=ref.key) n_targets
    from ref group by ref.key, ref.tid order by ref.key, ref.tid
  loop
    select * into t from programacion.fn_t_remed_target_of_key_v3(g.key);
    v_tstatus:=null; v_generic:=false;
    if t.target_table is not null then
      execute format('select x.status::text from %s x where x.%I=$1',t.target_table,t.pk_col) into v_tstatus using g.tid;
      v_generic:=(g.key=t.pk_col);
    end if;
    v_verdict:=case
      when t.target_table is null then 'ABSTAIN:NO_TARGET_FAMILY'
      when v_tstatus is null then 'ESCALATE:TARGET_NOT_FOUND'
      when v_tstatus not in ('VIGENTE','CANDIDATO','EN_REVISION') then 'DENY:TARGET_NOT_ACTIVE'
      when g.pend then 'DENY:SOURCE_PENDING_DECISION'
      when not v_generic and g.n_targets>1 then 'ESCALATE:SOURCE_CONFLICT'
      else 'LINK_CANDIDATE' end;
    v_props:=v_props||jsonb_build_array(jsonb_build_object('reference_role',g.key,'target_id',g.tid,'target_table',t.target_table,'pk_col',t.pk_col,
      'rule_codes',to_jsonb(g.codes),'rule_ids',to_jsonb(g.rids),'rule_states',to_jsonb(g.states),'target_status',v_tstatus,'verdict',v_verdict));
  end loop;
  -- findings: information that cannot be linked but must not stay silent (read-only, reported next to the proposals)
  with rr as (
    select r.id, r.codigo, r.valor_config from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.estado in ('VIGENTE','CANDIDATO')
  ), inc as (
    select e.key role, array_agg(distinct rr.codigo order by rr.codigo) codes, array_agg(distinct jsonb_typeof(e.value)) kinds
    from rr cross join lateral jsonb_each(case when jsonb_typeof(rr.valor_config)='object' then rr.valor_config else '{}'::jsonb end) e
    where e.key ~ '_policy_id$' and not (jsonb_typeof(e.value)='number' and (e.value #>> '{}') ~ '^[0-9]+$')
    group by e.key
  ), emp as (
    select array_agg(rr.codigo order by rr.codigo) codes from rr
    where rr.valor_config is null or jsonb_typeof(rr.valor_config)<>'object' or rr.valor_config='{}'::jsonb
  ), dup as (
    select array_agg(rr.codigo order by rr.codigo) codes from rr
    where jsonb_typeof(rr.valor_config)='object' and rr.valor_config<>'{}'::jsonb
    group by rr.valor_config having count(*)>1
  )
  select coalesce(jsonb_agg(f order by f->>'type', f->>'reference_role', f->>'rule_codes'),'[]'::jsonb) into v_find from (
    select jsonb_build_object('type','INCOMPLETE_REFERENCE','verdict','ESCALATE:INCOMPLETE_REFERENCE','reference_role',role,'rule_codes',to_jsonb(codes),'value_kinds',to_jsonb(kinds)) f from inc
    union all
    select jsonb_build_object('type','EMPTY_RULE_CONFIG','verdict','ESCALATE:ABSENT_INFORMATION','reference_role',null,'rule_codes',to_jsonb(codes)) from emp where codes is not null
    union all
    select jsonb_build_object('type','DUPLICATE_RULES','verdict','REPORT:DUPLICATE_RULES','reference_role',null,'rule_codes',to_jsonb(codes)) from dup
  ) q;
  return jsonb_build_object('capability','T_REMED','layer','RECONCILE','version',3,'subject',jsonb_build_object('kind','PANTALLA','id',p_pantalla_id),
    'proposals',v_props,'findings',v_find,
    'summary',(select jsonb_object_agg(v,n) from (select p->>'verdict' v,count(*) n from jsonb_array_elements(v_props) p group by 1) a));
end;
$fn$;
comment on function programacion.fn_t_remed_reconcile_v3(integer) is
  'T-REMED layer 1 reconcile (read-only). Output: proposals (LINK_CANDIDATE|ABSTAIN|ESCALATE|DENY per reference), summary, findings (INCOMPLETE_REFERENCE, EMPTY_RULE_CONFIG, DUPLICATE_RULES).';
