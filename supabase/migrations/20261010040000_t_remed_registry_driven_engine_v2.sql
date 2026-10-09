-- T-REMED v2: registry-driven engine. Replaces the hardcoded v1 policy-link slice with a declarative mechanism.
-- A "domain" is a ROW in programacion.t_remed_domains: where explicit references live (source rows linked to a subject, a payload column and a key regex),
-- which table/id/status the reference points to, and which decision authority gates promotion. The engine functions contain no domain names,
-- no table names and no column names: adding a domain is an INSERT, not a code change. Rows are validated by a trigger (tables/columns must exist).
-- v1 objects (lf_ops.pantallas_politicas*, fn_t_remed_*_v1) are left untouched and deprecated; they are not dropped here.
-- Layers: reconcile (read-only) -> complete (explicit values only, candidates allowed, weakest-state inheritance, receipt + readback)
--         -> independent judge (recomputes from raw tables, never calls reconcile/complete) -> promote (only if sources, target and root decision are vigente).

create table if not exists programacion.t_remed_domains (
  domain_code               text primary key,
  subject_kind              text not null,
  subject_table             text not null,
  subject_id_col            text not null,
  source_link_table         text not null,
  source_link_subject_col   text not null,
  source_link_source_col    text not null,
  source_table              text not null,
  source_id_col             text not null,
  source_code_col           text not null,
  source_state_col          text not null,
  source_pending_col        text,
  source_payload_col        text not null,
  reference_key_regex       text not null,
  generic_role_regex        text,
  reference_family_regex    text,
  target_table              text not null,
  target_id_col             text not null,
  target_code_col           text,
  target_status_col         text not null,
  target_decision_col       text,
  decision_table            text,
  decision_number_col       text,
  decision_state_col        text,
  promotable_decision_states text[] not null default array['VIGENTE','APROBADA','LOCKED'],
  active_source_states      text[] not null default array['VIGENTE','CANDIDATO'],
  vigente_state             text not null default 'VIGENTE',
  candidate_state           text not null default 'CANDIDATO',
  priority                  integer not null default 100,
  is_active                 boolean not null default true,
  created_at                timestamptz not null default now()
);

create or replace function programacion.fn_t_remed_domain_validate_trg() returns trigger
 language plpgsql set search_path to 'pg_catalog'
as $fn$
declare t record; r regclass;
begin
  for t in
    select * from (values
      (new.subject_table,new.subject_id_col),(new.source_link_table,new.source_link_subject_col),(new.source_link_table,new.source_link_source_col),
      (new.source_table,new.source_id_col),(new.source_table,new.source_code_col),(new.source_table,new.source_state_col),(new.source_table,new.source_payload_col),
      (new.target_table,new.target_id_col),(new.target_table,new.target_status_col),
      (new.source_table,new.source_pending_col),(new.target_table,new.target_code_col),(new.target_table,new.target_decision_col),
      (new.decision_table,new.decision_number_col),(new.decision_table,new.decision_state_col)) v(tbl,col)
    where col is not null
  loop
    r:=to_regclass(t.tbl);
    if r is null then raise exception 'T_REMED_DOMAIN_TABLE_NOT_FOUND:%',t.tbl; end if;
    if not exists(select 1 from pg_attribute where attrelid=r and attname=t.col and attnum>0 and not attisdropped) then
      raise exception 'T_REMED_DOMAIN_COLUMN_NOT_FOUND:%.%',t.tbl,t.col;
    end if;
  end loop;
  if new.decision_table is not null and (new.decision_number_col is null or new.decision_state_col is null) then
    raise exception 'T_REMED_DOMAIN_DECISION_COLUMNS_REQUIRED';
  end if;
  return new;
end;
$fn$;
drop trigger if exists t_remed_domains_validate on programacion.t_remed_domains;
create trigger t_remed_domains_validate before insert or update on programacion.t_remed_domains
  for each row execute function programacion.fn_t_remed_domain_validate_trg();

create table if not exists programacion.t_remed_links (
  link_id        bigint generated always as identity primary key,
  subject_kind   text   not null,
  subject_id     bigint not null,
  domain_code    text   not null references programacion.t_remed_domains(domain_code),
  reference_role text   not null,
  target_id      bigint not null,
  status         text   not null default 'CANDIDATO' check (status in ('CANDIDATO','VIGENTE','INACTIVO')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint t_remed_links_unique unique (subject_kind, subject_id, domain_code, reference_role, target_id)
);
create table if not exists programacion.t_remed_link_sources (
  link_id   bigint not null references programacion.t_remed_links(link_id) on delete cascade,
  source_id bigint not null,
  primary key (link_id, source_id)
);

create or replace function programacion.fn_t_remed_link_integrity_trg() returns trigger
 language plpgsql set search_path to 'pg_catalog','programacion'
as $fn$
declare d programacion.t_remed_domains; v_ok boolean;
begin
  select * into d from programacion.t_remed_domains where domain_code=new.domain_code;
  if not found then raise exception 'T_REMED_LINK_DOMAIN_NOT_FOUND:%',new.domain_code; end if;
  if d.subject_kind<>new.subject_kind then raise exception 'T_REMED_LINK_SUBJECT_KIND_MISMATCH:%',new.domain_code; end if;
  execute format('select exists(select 1 from %s where %I=$1)',to_regclass(d.subject_table)::text,d.subject_id_col) into v_ok using new.subject_id;
  if not v_ok then raise exception 'T_REMED_LINK_SUBJECT_NOT_FOUND:%',new.subject_id; end if;
  execute format('select exists(select 1 from %s where %I=$1)',to_regclass(d.target_table)::text,d.target_id_col) into v_ok using new.target_id;
  if not v_ok then raise exception 'T_REMED_LINK_TARGET_NOT_FOUND:%:%',new.domain_code,new.target_id; end if;
  return new;
end;
$fn$;
drop trigger if exists t_remed_links_integrity on programacion.t_remed_links;
create trigger t_remed_links_integrity before insert or update of subject_kind,subject_id,domain_code,target_id on programacion.t_remed_links
  for each row execute function programacion.fn_t_remed_link_integrity_trg();

alter table programacion.t_remed_domains      enable row level security;
alter table programacion.t_remed_links        enable row level security;
alter table programacion.t_remed_link_sources enable row level security;
revoke all on programacion.t_remed_domains, programacion.t_remed_links, programacion.t_remed_link_sources from anon, authenticated;

-- helpers (dynamic, registry-driven) ---------------------------------------------------------------------------------------------
create or replace function programacion.fn_t_remed_raw_v2(p_domain text, p_subject_id bigint) returns jsonb
 language plpgsql stable security definer set search_path to 'pg_catalog','programacion'
as $fn$
declare d programacion.t_remed_domains; v jsonb; v_pend text;
begin
  select * into d from programacion.t_remed_domains where domain_code=p_domain and is_active;
  if not found then raise exception 'T_REMED_DOMAIN_NOT_FOUND:%',p_domain; end if;
  v_pend:=case when d.source_pending_col is null then 'false' else format('coalesce(s.%I,false)',d.source_pending_col) end;
  execute format($q$
    select coalesce(jsonb_agg(jsonb_build_object('source_id',s.%1$I::bigint,'source_code',s.%2$I::text,'source_state',s.%3$I::text,'pending',%4$s,
                                                 'ref_key',e.key,'target_id',(e.value #>> '{}')::bigint)),'[]'::jsonb)
    from %5$s lt join %6$s s on s.%1$I=lt.%7$I
    cross join lateral jsonb_each(case when jsonb_typeof(s.%8$I)='object' then s.%8$I else '{}'::jsonb end) e
    where lt.%9$I=$1 and s.%3$I::text=any($2) and e.key ~ $3
      and jsonb_typeof(e.value)='number' and (e.value #>> '{}') ~ '^[0-9]+$'$q$,
    d.source_id_col,d.source_code_col,d.source_state_col,v_pend,
    to_regclass(d.source_link_table)::text,to_regclass(d.source_table)::text,d.source_link_source_col,
    d.source_payload_col,d.source_link_subject_col)
  into v using p_subject_id,d.active_source_states,d.reference_key_regex;
  return v;
end;
$fn$;

create or replace function programacion.fn_t_remed_target_v2(p_domain text, p_target_id bigint) returns jsonb
 language plpgsql stable security definer set search_path to 'pg_catalog','programacion'
as $fn$
declare d programacion.t_remed_domains; v jsonb;
begin
  select * into d from programacion.t_remed_domains where domain_code=p_domain;
  if not found then raise exception 'T_REMED_DOMAIN_NOT_FOUND:%',p_domain; end if;
  execute format('select jsonb_build_object(''code'',%s,''status'',t.%I::text,''decision'',%s) from %s t where t.%I=$1',
    case when d.target_code_col is null then 'null' else format('t.%I::text',d.target_code_col) end,
    d.target_status_col,
    case when d.target_decision_col is null then 'null' else format('t.%I::bigint',d.target_decision_col) end,
    to_regclass(d.target_table)::text,d.target_id_col)
  into v using p_target_id;
  return v;
end;
$fn$;

create or replace function programacion.fn_t_remed_decision_state_v2(p_domain text, p_decision bigint) returns text
 language plpgsql stable security definer set search_path to 'pg_catalog','programacion'
as $fn$
declare d programacion.t_remed_domains; v text;
begin
  select * into d from programacion.t_remed_domains where domain_code=p_domain;
  if not found or d.decision_table is null or p_decision is null then return null; end if;
  execute format('select %I::text from %s where %I=$1 limit 1',d.decision_state_col,to_regclass(d.decision_table)::text,d.decision_number_col) into v using p_decision;
  return v;
end;
$fn$;

-- Layer 1 -----------------------------------------------------------------------------------------------------------------------
create or replace function programacion.fn_t_remed_reconcile_v2(p_subject_kind text, p_subject_id bigint) returns jsonb
 language plpgsql stable security definer set search_path to 'pg_catalog','programacion'
as $fn$
declare
  d programacion.t_remed_domains; g record;
  v_domains jsonb:='[]'::jsonb; v_unm jsonb:='[]'::jsonb; v_raw jsonb; v_refs jsonb; v_conf jsonb; v_t jsonb; v_link text; v_ok boolean;
  v_all_regex text[]; v_n integer:=0; v_pend jsonb:='[]'::jsonb; v_unm_one jsonb; v_refcount integer:=0; v_confcount integer:=0;
begin
  select array_agg(reference_key_regex) into v_all_regex from programacion.t_remed_domains where subject_kind=p_subject_kind and is_active;
  if v_all_regex is null then raise exception 'T_REMED_NO_DOMAINS_FOR_SUBJECT_KIND:%',p_subject_kind; end if;

  for d in select * from programacion.t_remed_domains where subject_kind=p_subject_kind and is_active order by priority,domain_code loop
    execute format('select exists(select 1 from %s where %I=$1)',to_regclass(d.subject_table)::text,d.subject_id_col) into v_ok using p_subject_id;
    if not v_ok then raise exception 'T_REMED_SUBJECT_NOT_FOUND:%:%',p_subject_kind,p_subject_id; end if;
    v_raw:=programacion.fn_t_remed_raw_v2(d.domain_code,p_subject_id);
    v_refs:='[]'::jsonb;
    for g in
      select r.ref_key,r.target_id,array_agg(distinct r.source_id) ids,array_agg(distinct r.source_code) codes,
             array_agg(distinct r.source_state) states,bool_or(r.pending) pend
      from jsonb_to_recordset(v_raw) as r(source_id bigint,source_code text,source_state text,pending boolean,ref_key text,target_id bigint)
      group by r.ref_key,r.target_id order by r.ref_key,r.target_id
    loop
      v_t:=programacion.fn_t_remed_target_v2(d.domain_code,g.target_id);
      select l.status into v_link from programacion.t_remed_links l
       where l.subject_kind=p_subject_kind and l.subject_id=p_subject_id and l.domain_code=d.domain_code
         and l.reference_role=g.ref_key and l.target_id=g.target_id;
      v_refs:=v_refs||jsonb_build_array(jsonb_build_object('reference_role',g.ref_key,'target_id',g.target_id,
        'source_ids',to_jsonb(g.ids),'source_codes',to_jsonb(g.codes),'source_states',to_jsonb(g.states),'source_pending',g.pend,
        'target_exists',(v_t is not null),'target_code',v_t->>'code','target_status',v_t->>'status','target_decision',v_t->'decision','link_status',v_link));
      if g.pend then v_pend:=v_pend||to_jsonb(g.codes); end if;
    end loop;
    select coalesce(jsonb_agg(jsonb_build_object('reference_role',c.ref_key,'target_ids',c.tids,'source_codes',c.codes)),'[]'::jsonb) into v_conf
    from (select r.ref_key,array_agg(distinct r.target_id) tids,array_agg(distinct r.source_code) codes
          from jsonb_to_recordset(v_raw) as r(source_id bigint,source_code text,source_state text,pending boolean,ref_key text,target_id bigint)
          where d.generic_role_regex is null or r.ref_key !~ d.generic_role_regex
          group by r.ref_key having count(distinct r.target_id)>1) c;
    v_domains:=v_domains||jsonb_build_array(jsonb_build_object('domain_code',d.domain_code,'references',v_refs,'conflicts',v_conf));
    v_refcount:=v_refcount+jsonb_array_length(v_refs); v_confcount:=v_confcount+jsonb_array_length(v_conf);

    if d.reference_family_regex is not null then
      execute format($q$
        select coalesce(jsonb_agg(jsonb_build_object('reference_role',x.k,'source_codes',x.codes)),'[]'::jsonb) from (
          select e.key k,array_agg(distinct s.%1$I::text) codes
          from %2$s lt join %3$s s on s.%4$I=lt.%5$I
          cross join lateral jsonb_each(case when jsonb_typeof(s.%6$I)='object' then s.%6$I else '{}'::jsonb end) e
          where lt.%7$I=$1 and s.%8$I::text=any($2) and e.key ~ $3 and not (e.key ~ any($4)) and jsonb_typeof(e.value)='number'
          group by e.key) x$q$,
        d.source_code_col,to_regclass(d.source_link_table)::text,to_regclass(d.source_table)::text,d.source_id_col,d.source_link_source_col,
        d.source_payload_col,d.source_link_subject_col,d.source_state_col)
      into v_unm_one using p_subject_id,d.active_source_states,d.reference_family_regex,v_all_regex;
      v_unm:=v_unm||v_unm_one;
    end if;
  end loop;

  select coalesce(jsonb_agg(distinct u),'[]'::jsonb) into v_unm from jsonb_array_elements(v_unm) u;
  select coalesce(jsonb_agg(distinct p),'[]'::jsonb) into v_pend from jsonb_array_elements(v_pend) p;
  return jsonb_build_object('capability','T_REMED','layer','RECONCILE','version',2,
    'subject',jsonb_build_object('kind',p_subject_kind,'id',p_subject_id),'domains',v_domains,'unmapped_references',v_unm,'pending_decision_sources',v_pend,
    'summary',jsonb_build_object('reference_count',v_refcount,'conflict_count',v_confcount,'unmapped_count',jsonb_array_length(v_unm),'pending_source_count',jsonb_array_length(v_pend)));
end;
$fn$;

-- Layer 2 -----------------------------------------------------------------------------------------------------------------------
create or replace function programacion.fn_t_remed_complete_v2(p_subject_kind text, p_subject_id bigint, p_consumer text default 'IG_CURATOR') returns jsonb
 language plpgsql security definer set search_path to 'pg_catalog','programacion'
as $fn$
declare
  v_rec jsonb; dm jsonb; r jsonb; d programacion.t_remed_domains;
  v_actions jsonb:='[]'::jsonb; v_applied integer:=0; v_skipped integer:=0; v_already integer:=0;
  v_reason text; v_action jsonb; v_status text; v_link_id bigint; v_back record; v_role text; v_tid bigint; v_nsrc integer;
begin
  if nullif(trim(p_consumer),'') is null then raise exception 'T_REMED_CONSUMER_REQUIRED'; end if;
  v_rec:=programacion.fn_t_remed_reconcile_v2(p_subject_kind,p_subject_id);
  for dm in select value from jsonb_array_elements(v_rec->'domains') loop
    select * into d from programacion.t_remed_domains where domain_code=dm->>'domain_code';
    for r in select value from jsonb_array_elements(dm->'references') loop
      v_role:=r->>'reference_role'; v_tid:=(r->>'target_id')::bigint; v_reason:=null;
      if exists(select 1 from jsonb_array_elements(dm->'conflicts') c where c->>'reference_role'=v_role) then v_reason:='SOURCE_CONFLICT_MULTIPLE_TARGETS';
      elsif coalesce((r->>'source_pending')::boolean,false) then v_reason:='SOURCE_PENDING_DECISION';
      elsif not coalesce((r->>'target_exists')::boolean,false) then v_reason:='TARGET_NOT_FOUND';
      elsif not ((r->>'target_status')=any(d.active_source_states)) then v_reason:='TARGET_NOT_ACTIVE';
      end if;
      if v_reason is not null then
        v_skipped:=v_skipped+1;
        v_action:=jsonb_build_object('action','NO_WRITE','reason',v_reason,'domain_code',d.domain_code,'reference_role',v_role,'target_id',v_tid,'source_codes',r->'source_codes');
      elsif r->>'link_status' is not null then
        v_already:=v_already+1;
        v_action:=jsonb_build_object('action','ALREADY_LINKED','domain_code',d.domain_code,'reference_role',v_role,'target_id',v_tid,'link_status',r->>'link_status');
      else
        v_status:=case when r->>'target_status'=d.vigente_state
                        and not exists(select 1 from jsonb_array_elements_text(r->'source_states') s where s<>d.vigente_state)
                       then d.vigente_state else d.candidate_state end;
        insert into programacion.t_remed_links(subject_kind,subject_id,domain_code,reference_role,target_id,status)
        values(p_subject_kind,p_subject_id,d.domain_code,v_role,v_tid,v_status) returning link_id into v_link_id;
        insert into programacion.t_remed_link_sources(link_id,source_id)
        select v_link_id,x::bigint from jsonb_array_elements_text(r->'source_ids') x;
        select l.status,l.target_id,(select count(*) from programacion.t_remed_link_sources s where s.link_id=l.link_id) n into v_back
          from programacion.t_remed_links l where l.link_id=v_link_id;
        v_nsrc:=jsonb_array_length(r->'source_ids');
        if v_back.target_id is distinct from v_tid or v_back.status is distinct from v_status or v_back.n<>v_nsrc then
          raise exception 'T_REMED_READBACK_FAILED:%',v_link_id;
        end if;
        v_applied:=v_applied+1;
        v_action:=jsonb_build_object('action','LINK_EXPLICIT_REFERENCE','link_id',v_link_id,'domain_code',d.domain_code,'reference_role',v_role,
          'target_id',v_tid,'target_code',r->>'target_code','link_status',v_status,
          'inherited_from',jsonb_build_object('source_codes',r->'source_codes','source_states',r->'source_states','target_status',r->>'target_status'));
      end if;
      v_actions:=v_actions||jsonb_build_array(v_action);
      insert into programacion.t_remed_receipts(layer,subject_kind,subject_id,consumer,action,result,evidence,evidence_sha256)
      values('COMPLETE',p_subject_kind,p_subject_id,p_consumer,v_action->>'action',
             case v_action->>'action' when 'LINK_EXPLICIT_REFERENCE' then 'APPLIED' when 'ALREADY_LINKED' then 'NOOP' else 'NO_WRITE' end,
             v_action,encode(sha256(convert_to(v_action::text,'UTF8')),'hex'));
    end loop;
  end loop;
  return jsonb_build_object('capability','T_REMED','layer','COMPLETE','version',2,'consumer',p_consumer,
    'subject',jsonb_build_object('kind',p_subject_kind,'id',p_subject_id),'applied_count',v_applied,'already_linked_count',v_already,'skipped_count',v_skipped,
    'unmapped_reference_count',(v_rec->'summary'->>'unmapped_count')::int,'actions',v_actions,'promotion_authorized',false,'production_authorized',false);
end;
$fn$;

-- Layer 3 judge: independent. Reads registry + raw tables only; never calls reconcile/complete. -------------------------------------
create or replace function public.lf_t_remed_independent_review_v2(p_subject_kind text, p_subject_id bigint) returns jsonb
 language plpgsql stable security definer set search_path to 'pg_catalog'
as $fn$
declare
  l record; d programacion.t_remed_domains;
  v_findings jsonb:='[]'::jsonb; v_checked integer:=0; v_tstatus text; v_cite integer; v_allvig boolean; v_expected text; v_ok boolean;
begin
  for l in select * from programacion.t_remed_links where subject_kind=p_subject_kind and subject_id=p_subject_id order by link_id loop
    v_checked:=v_checked+1;
    select * into d from programacion.t_remed_domains where domain_code=l.domain_code;
    execute format('select t.%I::text from %s t where t.%I=$1',d.target_status_col,to_regclass(d.target_table)::text,d.target_id_col) into v_tstatus using l.target_id;
    if v_tstatus is null then v_findings:=v_findings||jsonb_build_object('link_id',l.link_id,'code','TARGET_NOT_FOUND'); end if;
    execute format($q$
      select count(*),coalesce(bool_and(s.%1$I::text=$5),false)
      from programacion.t_remed_link_sources ls
      join %2$s s on s.%3$I=ls.source_id
      join %4$s lt on lt.%6$I=s.%3$I and lt.%7$I=$1
      where ls.link_id=$2 and jsonb_typeof(s.%8$I)='object'
        and exists(select 1 from jsonb_each(s.%8$I) e where e.key=$3 and jsonb_typeof(e.value)='number' and (e.value #>> '{}') ~ '^[0-9]+$' and (e.value #>> '{}')::bigint=$4)
        and not %9$s$q$,
      d.source_state_col,to_regclass(d.source_table)::text,d.source_id_col,to_regclass(d.source_link_table)::text,null,
      d.source_link_source_col,d.source_link_subject_col,d.source_payload_col,
      case when d.source_pending_col is null then 'false' else format('coalesce(s.%I,false)',d.source_pending_col) end)
    into v_cite,v_allvig using p_subject_id,l.link_id,l.reference_role,l.target_id,d.vigente_state;
    if v_cite=0 then v_findings:=v_findings||jsonb_build_object('link_id',l.link_id,'code','NO_SOURCE_CITES_THIS_TARGET'); end if;
    v_expected:=case when v_cite>0 and v_allvig and v_tstatus=d.vigente_state then d.vigente_state else d.candidate_state end;
    if l.status<>'INACTIVO' and l.status<>v_expected then
      v_findings:=v_findings||jsonb_build_object('link_id',l.link_id,'code','STATUS_MISMATCH','detail','status='||l.status||' expected '||v_expected);
    end if;
  end loop;
  return jsonb_build_object('schema_version','LF_T_REMED_INDEPENDENT_REVIEW_V2','subject',jsonb_build_object('kind',p_subject_kind,'id',p_subject_id),
    'checked_count',v_checked,'failed_count',jsonb_array_length(v_findings),
    'verdict',case when v_checked=0 then 'NOT_APPLICABLE' when jsonb_array_length(v_findings)=0 then 'PASS' else 'FAIL' end,'findings',v_findings);
end;
$fn$;

-- Layer 3 promotion -------------------------------------------------------------------------------------------------------------
create or replace function programacion.fn_t_remed_promote_v2(p_subject_kind text, p_subject_id bigint, p_consumer text default 'IG_CURATOR') returns jsonb
 language plpgsql security definer set search_path to 'pg_catalog','programacion','public'
as $fn$
declare
  l record; d programacion.t_remed_domains; v_review jsonb; v_t jsonb; v_src_states text[]; v_dec_state text; v_hold text; v_action jsonb;
  v_actions jsonb:='[]'::jsonb; v_promoted integer:=0; v_held integer:=0;
begin
  if nullif(trim(p_consumer),'') is null then raise exception 'T_REMED_CONSUMER_REQUIRED'; end if;
  v_review:=public.lf_t_remed_independent_review_v2(p_subject_kind,p_subject_id);
  for l in select * from programacion.t_remed_links where subject_kind=p_subject_kind and subject_id=p_subject_id and status='CANDIDATO' order by link_id loop
    select * into d from programacion.t_remed_domains where domain_code=l.domain_code;
    v_t:=programacion.fn_t_remed_target_v2(l.domain_code,l.target_id);
    execute format('select array_agg(distinct s.%I::text) from %s s where s.%I in (select source_id from programacion.t_remed_link_sources where link_id=$1)',
      d.source_state_col,to_regclass(d.source_table)::text,d.source_id_col) into v_src_states using l.link_id;
    v_dec_state:=programacion.fn_t_remed_decision_state_v2(l.domain_code,(v_t->>'decision')::bigint);
    v_hold:=case
      when v_review->>'verdict'<>'PASS' then 'INDEPENDENT_REVIEW_'||(v_review->>'verdict')
      when exists(select 1 from unnest(v_src_states) s where s<>d.vigente_state) then 'SOURCE_NOT_VIGENTE'
      when v_t->>'status' is distinct from d.vigente_state then 'TARGET_NOT_VIGENTE'
      when d.decision_table is not null and (v_t->'decision') is null then 'ROOT_DECISION_NOT_DECLARED'
      when d.decision_table is not null and v_dec_state is null then 'ROOT_DECISION_NOT_FOUND'
      when d.decision_table is not null and not (v_dec_state=any(d.promotable_decision_states)) then 'ROOT_DECISION_'||v_dec_state
      else null end;
    if v_hold is null then
      update programacion.t_remed_links set status=d.vigente_state,updated_at=now() where link_id=l.link_id and status='CANDIDATO';
      if not found then raise exception 'T_REMED_PROMOTE_CONCURRENT_CHANGE:%',l.link_id; end if;
      v_promoted:=v_promoted+1;
      v_action:=jsonb_build_object('action','PROMOTE_LINK','link_id',l.link_id,'from','CANDIDATO','to',d.vigente_state,'root_decision_state',v_dec_state);
    else
      v_held:=v_held+1;
      v_action:=jsonb_build_object('action','HOLD','link_id',l.link_id,'domain_code',l.domain_code,'reference_role',l.reference_role,'blocked_by',v_hold,
        'chain',jsonb_build_object('source_states',to_jsonb(v_src_states),'target_status',v_t->>'status','root_decision',v_t->'decision','root_decision_state',v_dec_state));
    end if;
    insert into programacion.t_remed_receipts(layer,subject_kind,subject_id,consumer,action,result,evidence,evidence_sha256)
    values('PROMOTE',p_subject_kind,p_subject_id,p_consumer,v_action->>'action',case when v_hold is null then 'APPLIED' else 'HELD' end,
           v_action,encode(sha256(convert_to(v_action::text,'UTF8')),'hex'));
    v_actions:=v_actions||jsonb_build_array(v_action);
  end loop;
  return jsonb_build_object('capability','T_REMED','layer','PROMOTE','version',2,'consumer',p_consumer,
    'subject',jsonb_build_object('kind',p_subject_kind,'id',p_subject_id),'independent_review',v_review->'verdict',
    'promoted_count',v_promoted,'held_count',v_held,'actions',v_actions,'production_authorized',false);
end;
$fn$;

-- Convenience: run complete + promote over every subject of a kind (single-subject calls remain the unit of test). ----------------
create or replace function programacion.fn_t_remed_run_v2(p_subject_kind text, p_consumer text default 'IG_CURATOR') returns jsonb
 language plpgsql security definer set search_path to 'pg_catalog','programacion'
as $fn$
declare d programacion.t_remed_domains; v_id bigint; v_c jsonb; v_p jsonb; v_rows jsonb:='[]'::jsonb;
begin
  select * into d from programacion.t_remed_domains where subject_kind=p_subject_kind and is_active order by priority,domain_code limit 1;
  if not found then raise exception 'T_REMED_NO_DOMAINS_FOR_SUBJECT_KIND:%',p_subject_kind; end if;
  for v_id in execute format('select %I::bigint from %s order by 1',d.subject_id_col,to_regclass(d.subject_table)::text) loop
    v_c:=programacion.fn_t_remed_complete_v2(p_subject_kind,v_id,p_consumer);
    v_p:=programacion.fn_t_remed_promote_v2(p_subject_kind,v_id,p_consumer);
    v_rows:=v_rows||jsonb_build_array(jsonb_build_object('subject_id',v_id,'applied',v_c->'applied_count','already',v_c->'already_linked_count','skipped',v_c->'skipped_count',
      'unmapped',v_c->'unmapped_reference_count','promoted',v_p->'promoted_count','held',v_p->'held_count','review',v_p->'independent_review'));
  end loop;
  return jsonb_build_object('capability','T_REMED','version',2,'subject_kind',p_subject_kind,'consumer',p_consumer,'subjects',v_rows);
end;
$fn$;

-- Seed: four policy domains, all as data. -------------------------------------------------------------------------------------------
insert into programacion.t_remed_domains(domain_code,subject_kind,subject_table,subject_id_col,source_link_table,source_link_subject_col,source_link_source_col,
  source_table,source_id_col,source_code_col,source_state_col,source_pending_col,source_payload_col,reference_key_regex,generic_role_regex,reference_family_regex,
  target_table,target_id_col,target_code_col,target_status_col,target_decision_col,decision_table,decision_number_col,decision_state_col,priority)
values
 ('SCREEN_POLICY_RATE_LIMIT','PANTALLA','lf_ops.pantallas','id','lf_ops.reglas_pantallas','pantalla_id','regla_id','lf_ops.reglas','id','codigo','estado','pendiente_decision','valor_config',
  'rate_limit_policy_id$',null,'policy_id$','lf_ops.politicas_rate_limit','rate_limit_policy_id','policy_code','status','source_decision_number','public.lf_decisiones_gov','decision_number','estado_normalizado',10),
 ('SCREEN_POLICY_TIMEOUT','PANTALLA','lf_ops.pantallas','id','lf_ops.reglas_pantallas','pantalla_id','regla_id','lf_ops.reglas','id','codigo','estado','pendiente_decision','valor_config',
  'timeout_policy_id$',null,'policy_id$','lf_ops.politicas_timeout','timeout_policy_id','policy_code','status','source_decision_number','public.lf_decisiones_gov','decision_number','estado_normalizado',20),
 ('SCREEN_POLICY_SESSION','PANTALLA','lf_ops.pantallas','id','lf_ops.reglas_pantallas','pantalla_id','regla_id','lf_ops.reglas','id','codigo','estado','pendiente_decision','valor_config',
  'session_policy_id$',null,'policy_id$','lf_ops.politicas_sesion','session_policy_id','policy_code','status','source_decision_number','public.lf_decisiones_gov','decision_number','estado_normalizado',30),
 ('SCREEN_POLICY_SECURITY','PANTALLA','lf_ops.pantallas','id','lf_ops.reglas_pantallas','pantalla_id','regla_id','lf_ops.reglas','id','codigo','estado','pendiente_decision','valor_config',
  'security_policy_id$','^security_policy_id$','policy_id$','lf_ops.politicas_seguridad','security_policy_id','policy_code','status','source_decision_number','public.lf_decisiones_gov','decision_number','estado_normalizado',40)
on conflict (domain_code) do nothing;

revoke all on function programacion.fn_t_remed_raw_v2(text,bigint), programacion.fn_t_remed_target_v2(text,bigint), programacion.fn_t_remed_decision_state_v2(text,bigint),
  programacion.fn_t_remed_reconcile_v2(text,bigint), programacion.fn_t_remed_complete_v2(text,bigint,text), programacion.fn_t_remed_promote_v2(text,bigint,text),
  programacion.fn_t_remed_run_v2(text,text), public.lf_t_remed_independent_review_v2(text,bigint) from public, anon, authenticated;
