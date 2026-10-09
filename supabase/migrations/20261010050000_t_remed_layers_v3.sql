-- T-REMED v3: the three remediation layers as one transversal capability, wired to the data itself.
-- No domain registry and no per-gap code: a reference "<x>_policy_id" found in a rule resolves its own target table from the catalog
-- (single-column primary key of a lf_ops table whose name the key ends with). Verdicts follow a decision policy:
--   LINK_CANDIDATE | ABSTAIN | ESCALATE | DENY   (layer 1 reconcile + layer 2 complete)
--   independent judge (layer 3) valuates every link from raw tables; promotion happens only on judge PASS and is reversible.
-- Every write is logged in programacion.t_remed_change_log with before/after and can be undone with fn_t_remed_undo_v3.
-- v1/v2 objects are left untouched.

create table if not exists programacion.t_remed_links (
  link_id        bigint generated always as identity primary key,
  subject_kind   text   not null,
  subject_id     bigint not null,
  reference_role text   not null,
  target_table   text   not null,
  target_id      bigint not null,
  status         text   not null default 'CANDIDATO' check (status in ('CANDIDATO','VIGENTE','INACTIVO')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint t_remed_links_unique unique (subject_kind, subject_id, reference_role, target_table, target_id)
);
create table if not exists programacion.t_remed_link_sources (
  link_id bigint not null references programacion.t_remed_links(link_id) on delete cascade,
  rule_id bigint not null,
  primary key (link_id, rule_id)
);
create table if not exists programacion.t_remed_change_log (
  change_id   bigint generated always as identity primary key,
  layer       text   not null check (layer in ('COMPLETE','PROMOTE')),
  subject_kind text  not null,
  subject_id  bigint not null,
  kind        text   not null check (kind in ('LINK_INSERT','STATUS_CHANGE')),
  target_table text  not null,
  pk_col      text   not null,
  pk_value    bigint not null,
  col_name    text,
  before_value text,
  after_value text,
  actor       text   not null,
  created_at  timestamptz not null default now(),
  reverted_at timestamptz
);
alter table programacion.t_remed_links        enable row level security;
alter table programacion.t_remed_link_sources enable row level security;
alter table programacion.t_remed_change_log   enable row level security;
revoke all on programacion.t_remed_links, programacion.t_remed_link_sources, programacion.t_remed_change_log from anon, authenticated;

-- target discovery from the catalog ----------------------------------------------------------------------------------------------
create or replace function programacion.fn_t_remed_target_of_key_v3(p_key text)
 returns table(target_table text, pk_col text)
 language sql stable security definer set search_path to 'pg_catalog'
as $fn$
  select n.nspname||'.'||c.relname, a.attname::text
  from pg_index i
  join pg_class c on c.oid=i.indrelid
  join pg_namespace n on n.oid=c.relnamespace
  join pg_attribute a on a.attrelid=c.oid and a.attnum=i.indkey[0]
  where n.nspname='lf_ops' and i.indisprimary and i.indnatts=1
    and a.attname ~ '_policy_id$' and a.attname<>'policy_id'
    and right(p_key,length(a.attname))=a.attname
    and exists(select 1 from pg_attribute s where s.attrelid=c.oid and s.attname='status' and s.attnum>0 and not s.attisdropped)
  order by length(a.attname) desc
  limit 1
$fn$;

-- Layer 1: reconcile (read-only) ---------------------------------------------------------------------------------------------------
create or replace function programacion.fn_t_remed_reconcile_v3(p_pantalla_id integer)
 returns jsonb
 language plpgsql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
declare g record; t record; v_props jsonb:='[]'::jsonb; v_tstatus text; v_verdict text; v_generic boolean;
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
  return jsonb_build_object('capability','T_REMED','layer','RECONCILE','version',3,'subject',jsonb_build_object('kind','PANTALLA','id',p_pantalla_id),
    'proposals',v_props,
    'summary',(select jsonb_object_agg(v,n) from (select p->>'verdict' v,count(*) n from jsonb_array_elements(v_props) p group by 1) a));
end;
$fn$;

-- Layer 2: complete (explicit values only, candidates allowed, weakest-state inheritance, change log + readback) --------------------
create or replace function programacion.fn_t_remed_complete_v3(p_pantalla_id integer, p_consumer text default 'IG_CURATOR')
 returns jsonb
 language plpgsql security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
declare
  v_rec jsonb; p jsonb; v_link_id bigint; v_status text; v_applied int:=0; v_already int:=0; v_skipped int:=0; v_actions jsonb:='[]'::jsonb; v_action jsonb; v_back record; v_exists bigint;
begin
  if nullif(trim(p_consumer),'') is null then raise exception 'T_REMED_CONSUMER_REQUIRED'; end if;
  v_rec:=programacion.fn_t_remed_reconcile_v3(p_pantalla_id);
  for p in select value from jsonb_array_elements(v_rec->'proposals') loop
    if p->>'verdict'<>'LINK_CANDIDATE' then
      v_skipped:=v_skipped+1;
      v_action:=jsonb_build_object('action','NO_WRITE','reason',p->>'verdict','reference_role',p->>'reference_role','target_id',p->'target_id','rule_codes',p->'rule_codes');
    else
      select link_id into v_exists from programacion.t_remed_links
       where subject_kind='PANTALLA' and subject_id=p_pantalla_id and reference_role=p->>'reference_role'
         and target_table=p->>'target_table' and target_id=(p->>'target_id')::bigint;
      if v_exists is not null then
        v_already:=v_already+1;
        v_action:=jsonb_build_object('action','ALREADY_LINKED','link_id',v_exists,'reference_role',p->>'reference_role','target_id',p->'target_id');
      else
        v_status:=case when p->'rule_states'='["VIGENTE"]'::jsonb and p->>'target_status'='VIGENTE' then 'VIGENTE' else 'CANDIDATO' end;
        insert into programacion.t_remed_links(subject_kind,subject_id,reference_role,target_table,target_id,status)
        values('PANTALLA',p_pantalla_id,p->>'reference_role',p->>'target_table',(p->>'target_id')::bigint,v_status) returning link_id into v_link_id;
        insert into programacion.t_remed_link_sources(link_id,rule_id) select v_link_id,x::bigint from jsonb_array_elements_text(p->'rule_ids') x;
        select l.status, l.target_id, (select count(*) from programacion.t_remed_link_sources s where s.link_id=l.link_id) n into v_back
          from programacion.t_remed_links l where l.link_id=v_link_id;
        if v_back.status is distinct from v_status or v_back.target_id is distinct from (p->>'target_id')::bigint
           or v_back.n<>jsonb_array_length(p->'rule_ids') then raise exception 'T_REMED_READBACK_FAILED:%',v_link_id; end if;
        insert into programacion.t_remed_change_log(layer,subject_kind,subject_id,kind,target_table,pk_col,pk_value,after_value,actor)
        values('COMPLETE','PANTALLA',p_pantalla_id,'LINK_INSERT','programacion.t_remed_links','link_id',v_link_id,v_status,p_consumer);
        v_applied:=v_applied+1;
        v_action:=jsonb_build_object('action','LINK_EXPLICIT_REFERENCE','link_id',v_link_id,'reference_role',p->>'reference_role','target_id',p->'target_id','link_status',v_status);
      end if;
    end if;
    v_actions:=v_actions||jsonb_build_array(v_action);
    insert into programacion.t_remed_receipts(layer,subject_kind,subject_id,consumer,action,result,evidence,evidence_sha256)
    values('COMPLETE','PANTALLA',p_pantalla_id,p_consumer,v_action->>'action',
           case v_action->>'action' when 'LINK_EXPLICIT_REFERENCE' then 'APPLIED' when 'ALREADY_LINKED' then 'NOOP' else 'NO_WRITE' end,
           v_action,encode(sha256(convert_to(v_action::text,'UTF8')),'hex'));
  end loop;
  return jsonb_build_object('capability','T_REMED','layer','COMPLETE','version',3,'consumer',p_consumer,'pantalla_id',p_pantalla_id,
    'applied_count',v_applied,'already_linked_count',v_already,'skipped_count',v_skipped,'actions',v_actions);
end;
$fn$;

-- Layer 3 judge: independent. Recomputes from raw tables; never calls reconcile/complete; returns verdict + failed criteria only. -----
create or replace function public.lf_t_remed_judge_v3(p_pantalla_id integer)
 returns jsonb
 language plpgsql stable security definer set search_path to 'pg_catalog'
as $fn$
declare
  l record; v_row jsonb; v_fail text[]; v_items jsonb:='[]'::jsonb; v_cited int; v_pending int; v_targets int; v_pk text;
begin
  for l in select * from programacion.t_remed_links where subject_kind='PANTALLA' and subject_id=p_pantalla_id order by link_id loop
    v_fail:=array[]::text[];
    select a.attname::text into v_pk from pg_index i join pg_attribute a on a.attrelid=i.indrelid and a.attnum=i.indkey[0]
      where i.indrelid=to_regclass(l.target_table) and i.indisprimary limit 1;
    execute format('select to_jsonb(x) from %s x where x.%I=$1',l.target_table,v_pk) into v_row using l.target_id;
    if v_row is null then v_fail:=v_fail||'TARGET_EXISTS';
    else
      if coalesce(v_row->>'source_decision_number',v_row->>'source_decision_id') is null then v_fail:=v_fail||'SOURCE_DECISION_DECLARED'; end if;
      if v_row->>'status' not in ('CANDIDATO','EN_REVISION','VIGENTE') then v_fail:=v_fail||'TARGET_ACTIVE'; end if;
    end if;
    select count(distinct r.id), count(distinct r.id) filter (where coalesce(r.pendiente_decision,false))
      into v_cited, v_pending
    from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.estado in ('VIGENTE','CANDIDATO') and jsonb_typeof(r.valor_config)='object'
      and jsonb_path_exists(r.valor_config, format('$."%s" ? (@ == %s)',l.reference_role,l.target_id)::jsonpath);
    if v_cited=0 then v_fail:=v_fail||'CITED_BY_A_RULE'; end if;
    if v_pending>0 then v_fail:=v_fail||'NO_PENDING_RULE'; end if;
    select count(distinct (r.valor_config->>l.reference_role)) into v_targets
    from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.estado in ('VIGENTE','CANDIDATO') and jsonb_typeof(r.valor_config)='object' and r.valor_config ? l.reference_role;
    if v_targets>1 and l.reference_role<>v_pk then v_fail:=v_fail||'NO_CONFLICT'; end if;
    v_items:=v_items||jsonb_build_array(jsonb_build_object('link_id',l.link_id,'verdict',case when cardinality(v_fail)=0 then 'PASS' else 'FAIL' end,'failed',to_jsonb(v_fail)));
  end loop;
  return jsonb_build_object('schema_version','LF_T_REMED_JUDGE_V3','pantalla_id',p_pantalla_id,'checked_count',jsonb_array_length(v_items),
    'failed_count',(select count(*) from jsonb_array_elements(v_items) i where i->>'verdict'='FAIL'),'items',v_items);
end;
$fn$;

-- Layer 3 promote: only on judge PASS; policies first, then rules whose every reference is vigente; every change logged. --------------
create or replace function programacion.fn_t_remed_promote_v3(p_pantalla_id integer, p_consumer text default 'IG_CURATOR')
 returns jsonb
 language plpgsql security definer set search_path to 'pg_catalog','programacion','lf_ops','public'
as $fn$
declare
  l record; rl record; v_j jsonb; item jsonb; v_pk text; v_before text; v_after text; v_actions jsonb:='[]'::jsonb; v_action jsonb;
  v_pol int:=0; v_rules int:=0; v_held int:=0;
begin
  if nullif(trim(p_consumer),'') is null then raise exception 'T_REMED_CONSUMER_REQUIRED'; end if;
  v_j:=public.lf_t_remed_judge_v3(p_pantalla_id);
  for l in select * from programacion.t_remed_links where subject_kind='PANTALLA' and subject_id=p_pantalla_id and status='CANDIDATO' order by link_id loop
    select x into item from jsonb_array_elements(v_j->'items') x where (x->>'link_id')::bigint=l.link_id;
    if item->>'verdict'='PASS' then
      select a.attname into v_pk from pg_index i join pg_attribute a on a.attrelid=i.indrelid and a.attnum=i.indkey[0]
       where i.indrelid=to_regclass(l.target_table) and i.indisprimary limit 1;
      execute format('select status::text from %s where %I=$1',l.target_table,v_pk) into v_before using l.target_id;
      if v_before in ('CANDIDATO','EN_REVISION') then
        execute format('update %s set status=''VIGENTE'' where %I=$1 and status=$2',l.target_table,v_pk) using l.target_id,v_before;
        execute format('select status::text from %s where %I=$1',l.target_table,v_pk) into v_after using l.target_id;
        if v_after is distinct from 'VIGENTE' then raise exception 'T_REMED_READBACK_FAILED:%:%',l.target_table,l.target_id; end if;
        insert into programacion.t_remed_change_log(layer,subject_kind,subject_id,kind,target_table,pk_col,pk_value,col_name,before_value,after_value,actor)
        values('PROMOTE','PANTALLA',p_pantalla_id,'STATUS_CHANGE',l.target_table,v_pk,l.target_id,'status',v_before,'VIGENTE',p_consumer);
      end if;
      update programacion.t_remed_links set status='VIGENTE',updated_at=now() where link_id=l.link_id;
      insert into programacion.t_remed_change_log(layer,subject_kind,subject_id,kind,target_table,pk_col,pk_value,col_name,before_value,after_value,actor)
      values('PROMOTE','PANTALLA',p_pantalla_id,'STATUS_CHANGE','programacion.t_remed_links','link_id',l.link_id,'status','CANDIDATO','VIGENTE',p_consumer);
      v_pol:=v_pol+1;
      v_action:=jsonb_build_object('action','PROMOTE_POLICY','target_table',l.target_table,'target_id',l.target_id,'from',v_before,'to','VIGENTE');
    else
      v_held:=v_held+1;
      v_action:=jsonb_build_object('action','HOLD','link_id',l.link_id,'reference_role',l.reference_role,'target_id',l.target_id,'failed',item->'failed');
    end if;
    v_actions:=v_actions||jsonb_build_array(v_action);
    insert into programacion.t_remed_receipts(layer,subject_kind,subject_id,consumer,action,result,evidence,evidence_sha256)
    values('PROMOTE','PANTALLA',p_pantalla_id,p_consumer,v_action->>'action',case when v_action->>'action'='HOLD' then 'HELD' else 'APPLIED' end,
           v_action,encode(sha256(convert_to(v_action::text,'UTF8')),'hex'));
  end loop;
  -- rules: promote when not pending and every policy reference of the rule is covered by a VIGENTE link
  for rl in
    select r.id, r.codigo, r.estado from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.estado='CANDIDATO' and not coalesce(r.pendiente_decision,false) and jsonb_typeof(r.valor_config)='object'
      and exists(select 1 from jsonb_each(r.valor_config) e where e.key ~ '_policy_id$' and jsonb_typeof(e.value)='number')
      and not exists(
        select 1 from jsonb_each(r.valor_config) e
        where e.key ~ '_policy_id$' and jsonb_typeof(e.value)='number'
          and not exists(select 1 from programacion.t_remed_links tl
                         where tl.subject_kind='PANTALLA' and tl.subject_id=p_pantalla_id and tl.reference_role=e.key
                           and tl.target_id=(e.value #>> '{}')::bigint and tl.status='VIGENTE'))
    order by r.id
  loop
    update lf_ops.reglas set estado='VIGENTE' where id=rl.id and estado='CANDIDATO';
    select estado into v_after from lf_ops.reglas where id=rl.id;
    if v_after is distinct from 'VIGENTE' then raise exception 'T_REMED_READBACK_FAILED:reglas:%',rl.id; end if;
    insert into programacion.t_remed_change_log(layer,subject_kind,subject_id,kind,target_table,pk_col,pk_value,col_name,before_value,after_value,actor)
    values('PROMOTE','PANTALLA',p_pantalla_id,'STATUS_CHANGE','lf_ops.reglas','id',rl.id,'estado','CANDIDATO','VIGENTE',p_consumer);
    v_rules:=v_rules+1;
    v_action:=jsonb_build_object('action','PROMOTE_RULE','rule',rl.codigo,'from','CANDIDATO','to','VIGENTE');
    v_actions:=v_actions||jsonb_build_array(v_action);
    insert into programacion.t_remed_receipts(layer,subject_kind,subject_id,consumer,action,result,evidence,evidence_sha256)
    values('PROMOTE','PANTALLA',p_pantalla_id,p_consumer,'PROMOTE_RULE','APPLIED',v_action,encode(sha256(convert_to(v_action::text,'UTF8')),'hex'));
  end loop;
  return jsonb_build_object('capability','T_REMED','layer','PROMOTE','version',3,'consumer',p_consumer,'pantalla_id',p_pantalla_id,
    'judge_failed_count',v_j->'failed_count','policies_promoted',v_pol,'rules_promoted',v_rules,'held',v_held,'actions',v_actions);
end;
$fn$;

-- Undo: restores the before value of a logged change. -----------------------------------------------------------------------------
create or replace function programacion.fn_t_remed_undo_v3(p_change_id bigint, p_actor text default 'IG_CURATOR')
 returns jsonb
 language plpgsql security definer set search_path to 'pg_catalog','programacion'
as $fn$
declare c programacion.t_remed_change_log; v_now text;
begin
  select * into c from programacion.t_remed_change_log where change_id=p_change_id for update;
  if not found then raise exception 'T_REMED_CHANGE_NOT_FOUND:%',p_change_id; end if;
  if c.reverted_at is not null then raise exception 'T_REMED_CHANGE_ALREADY_REVERTED:%',p_change_id; end if;
  if c.kind='LINK_INSERT' then
    delete from programacion.t_remed_links where link_id=c.pk_value;
  else
    execute format('select %I::text from %s where %I=$1',c.col_name,c.target_table,c.pk_col) into v_now using c.pk_value;
    if v_now is distinct from c.after_value then raise exception 'T_REMED_UNDO_STATE_DRIFT:%:%',p_change_id,v_now; end if;
    execute format('update %s set %I=$1 where %I=$2',c.target_table,c.col_name,c.pk_col) using c.before_value,c.pk_value;
  end if;
  update programacion.t_remed_change_log set reverted_at=now() where change_id=p_change_id;
  return jsonb_build_object('undone',p_change_id,'kind',c.kind,'target_table',c.target_table,'pk_value',c.pk_value,'restored',c.before_value,'actor',p_actor);
end;
$fn$;

-- Entry point for any consumer (Curator, UX profile, ...). ----------------------------------------------------------------------------
create or replace function programacion.fn_t_remed_run_v3(p_pantalla_id integer, p_consumer text default 'IG_CURATOR')
 returns jsonb
 language plpgsql security definer set search_path to 'pg_catalog','programacion'
as $fn$
declare v_c jsonb; v_p jsonb;
begin
  v_c:=programacion.fn_t_remed_complete_v3(p_pantalla_id,p_consumer);
  v_p:=programacion.fn_t_remed_promote_v3(p_pantalla_id,p_consumer);
  return jsonb_build_object('capability','T_REMED','version',3,'pantalla_id',p_pantalla_id,'consumer',p_consumer,'complete',v_c,'promote',v_p);
end;
$fn$;

revoke all on function programacion.fn_t_remed_target_of_key_v3(text), programacion.fn_t_remed_reconcile_v3(integer), programacion.fn_t_remed_complete_v3(integer,text),
  programacion.fn_t_remed_promote_v3(integer,text), programacion.fn_t_remed_undo_v3(bigint,text), programacion.fn_t_remed_run_v3(integer,text),
  public.lf_t_remed_judge_v3(integer) from public, anon, authenticated;
