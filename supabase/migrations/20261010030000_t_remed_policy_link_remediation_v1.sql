-- T-REMED v1: transversal remediation capability (reconcile -> complete -> promote).
-- Generic by design: the subject is a screen today, but nothing here is tied to Input Governance or to a screen type;
-- any profile/agent (IG Curator, UX, ...) can call the same functions and the same receipts table.
--
-- Slice delivered in v1: POLICY LINKS. A rule linked to a screen may declare an explicit numeric policy id in its config
-- (e.g. rate_limit_policy_id, timeout_policy_id, session_policy_id, *_security_policy_id). No table linked screens to policies,
-- so evidence that already existed in the database was invisible to the classifiers.
--   Layer 1  programacion.fn_t_remed_reconcile_v1(pantalla)        read-only inventory of explicit references, conflicts, pending rules.
--   Layer 2  programacion.fn_t_remed_complete_v1(pantalla,consumer) writes lf_ops.pantallas_politicas from explicit values only (no invention),
--            candidates allowed, link inherits the weakest state of its sources, receipt + readback per action.
--   Layer 3  public.lf_t_remed_independent_review_v1(pantalla)      independent judge: recomputes from raw tables, never calls Layer 1/2.
--            programacion.fn_t_remed_promote_v1(pantalla)            promotes a link CANDIDATO -> VIGENTE only if sources, policy and root decision
--            are VIGENTE and the judge says PASS; otherwise reports the exact blocking link in the chain. Never edits rules/policies/decisions.
-- Not in v1: consumption of these links by the classifier (separate change), promotion of rules/policies themselves.

create table if not exists lf_ops.pantallas_politicas (
  pantalla_politica_id bigint generated always as identity primary key,
  pantalla_id          integer not null references lf_ops.pantallas(id) on delete cascade,
  policy_kind          text    not null check (policy_kind in ('RATE_LIMIT','TIMEOUT','SESSION','SECURITY')),
  reference_role       text    not null,
  rate_limit_policy_id bigint  references lf_ops.politicas_rate_limit(rate_limit_policy_id),
  timeout_policy_id    bigint  references lf_ops.politicas_timeout(timeout_policy_id),
  session_policy_id    bigint  references lf_ops.politicas_sesion(session_policy_id),
  security_policy_id   bigint  references lf_ops.politicas_seguridad(security_policy_id),
  status               text    not null default 'CANDIDATO' check (status in ('CANDIDATO','VIGENTE','INACTIVO')),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint pantallas_politicas_one_policy_matching_kind check (
    (policy_kind='RATE_LIMIT' and rate_limit_policy_id is not null and timeout_policy_id is null and session_policy_id is null and security_policy_id is null) or
    (policy_kind='TIMEOUT'    and timeout_policy_id    is not null and rate_limit_policy_id is null and session_policy_id is null and security_policy_id is null) or
    (policy_kind='SESSION'    and session_policy_id    is not null and rate_limit_policy_id is null and timeout_policy_id is null and security_policy_id is null) or
    (policy_kind='SECURITY'   and security_policy_id   is not null and rate_limit_policy_id is null and timeout_policy_id is null and session_policy_id is null)),
  constraint pantallas_politicas_unique_role unique (pantalla_id, reference_role)
);

create table if not exists lf_ops.pantallas_politicas_reglas (
  pantalla_politica_id bigint  not null references lf_ops.pantallas_politicas(pantalla_politica_id) on delete cascade,
  regla_id             integer not null references lf_ops.reglas(id),
  primary key (pantalla_politica_id, regla_id)
);

create table if not exists programacion.t_remed_receipts (
  receipt_id      bigint generated always as identity primary key,
  layer           text   not null check (layer in ('RECONCILE','COMPLETE','PROMOTE')),
  subject_kind    text   not null,
  subject_id      bigint not null,
  consumer        text   not null,
  action          text   not null,
  result          text   not null,
  evidence        jsonb  not null,
  evidence_sha256 text   not null,
  created_at      timestamptz not null default now()
);

alter table lf_ops.pantallas_politicas        enable row level security;
alter table lf_ops.pantallas_politicas_reglas enable row level security;
alter table programacion.t_remed_receipts     enable row level security;
revoke all on lf_ops.pantallas_politicas, lf_ops.pantallas_politicas_reglas, programacion.t_remed_receipts from anon, authenticated;

-- Layer 1 -----------------------------------------------------------------------------------------------------------------
create or replace function programacion.fn_t_remed_raw_refs_v1(p_pantalla_id integer)
 returns table(regla_id integer, codigo text, estado text, pend boolean, ref_key text, pid bigint, kind text)
 language sql
 stable
 security definer
 set search_path to 'pg_catalog','lf_ops'
as $fn$
  select rg.id, rg.codigo, rg.estado, coalesce(rg.pendiente_decision,false), e.key, (e.value #>> '{}')::bigint,
         case when e.key ~ 'security_policy_id$'   then 'SECURITY'
              when e.key ~ 'rate_limit_policy_id$' then 'RATE_LIMIT'
              when e.key ~ 'timeout_policy_id$'    then 'TIMEOUT'
              when e.key ~ 'session_policy_id$'    then 'SESSION' end
  from lf_ops.reglas_pantallas rp
  join lf_ops.reglas rg on rg.id=rp.regla_id
  cross join lateral jsonb_each(case when jsonb_typeof(rg.valor_config)='object' then rg.valor_config else '{}'::jsonb end) e
  where rp.pantalla_id=p_pantalla_id and rg.estado in ('VIGENTE','CANDIDATO')
    and e.key ~ 'policy_id$' and jsonb_typeof(e.value)='number' and (e.value #>> '{}') ~ '^[0-9]+$';
$fn$;

create or replace function programacion.fn_t_remed_reconcile_v1(p_pantalla_id integer)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
declare
  v_refs jsonb;
  v_conflicts jsonb;
  v_unmapped jsonb;
  v_pending jsonb;
begin
  if not exists(select 1 from lf_ops.pantallas where id=p_pantalla_id) then
    raise exception 'T_REMED_SUBJECT_NOT_FOUND:%',p_pantalla_id;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('reference_role',ref_key,'rule_codes',codes,'rule_states',states) order by ref_key),'[]'::jsonb)
    into v_unmapped
  from (select ref_key, array_agg(distinct codigo) codes, array_agg(distinct estado) states
        from programacion.fn_t_remed_raw_refs_v1(p_pantalla_id) where kind is null group by ref_key) u;

  select coalesce(jsonb_agg(jsonb_build_object('policy_kind',kind,'reference_role',ref_key,'policy_ids',pids,'rule_codes',codes) order by kind,ref_key),'[]'::jsonb)
    into v_conflicts
  from (select kind, ref_key, array_agg(distinct pid) pids, array_agg(distinct codigo) codes
        from programacion.fn_t_remed_raw_refs_v1(p_pantalla_id) where kind is not null group by kind, ref_key having count(distinct pid)>1) c;

  select coalesce(jsonb_agg(distinct codigo),'[]'::jsonb) into v_pending
  from programacion.fn_t_remed_raw_refs_v1(p_pantalla_id) where pend and kind is not null;

  select coalesce(jsonb_agg(jsonb_build_object(
           'policy_kind',g.kind,'reference_role',g.ref_key,'policy_id',g.pid,
           'rule_codes',g.codes,'rule_states',g.states,'rule_pending',g.any_pend,
           'policy_exists',(p.code is not null),'policy_code',p.code,'policy_status',p.status,
           'link_status',l.status) order by g.kind,g.ref_key,g.pid),'[]'::jsonb)
    into v_refs
  from (select kind, ref_key, pid, array_agg(distinct codigo) codes, array_agg(distinct estado) states, bool_or(pend) any_pend
        from programacion.fn_t_remed_raw_refs_v1(p_pantalla_id) where kind is not null group by kind, ref_key, pid) g
  left join lateral (
    select code, status from (
      select policy_code code, status, 'RATE_LIMIT' k, rate_limit_policy_id id from lf_ops.politicas_rate_limit
      union all select policy_code, status, 'TIMEOUT', timeout_policy_id from lf_ops.politicas_timeout
      union all select policy_code, status, 'SESSION', session_policy_id from lf_ops.politicas_sesion
      union all select policy_code, status, 'SECURITY', security_policy_id from lf_ops.politicas_seguridad) x
    where x.k=g.kind and x.id=g.pid) p on true
  left join lf_ops.pantallas_politicas l
    on l.pantalla_id=p_pantalla_id and l.reference_role=g.ref_key and l.policy_kind=g.kind
   and coalesce(l.rate_limit_policy_id,l.timeout_policy_id,l.session_policy_id,l.security_policy_id)=g.pid;

  return jsonb_build_object(
    'capability','T_REMED','layer','RECONCILE','version',1,
    'subject',jsonb_build_object('kind','PANTALLA','id',p_pantalla_id),
    'references',v_refs,'conflicts',v_conflicts,'unmapped_references',v_unmapped,'pending_decision_rules',v_pending,
    'summary',jsonb_build_object(
       'reference_count',jsonb_array_length(v_refs),'conflict_count',jsonb_array_length(v_conflicts),
       'unmapped_count',jsonb_array_length(v_unmapped),'pending_rule_count',jsonb_array_length(v_pending)));
end;
$fn$;

-- Layer 2 -----------------------------------------------------------------------------------------------------------------
create or replace function programacion.fn_t_remed_complete_v1(p_pantalla_id integer, p_consumer text default 'IG_CURATOR')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
declare
  v_rec jsonb;
  r jsonb;
  v_actions jsonb:='[]'::jsonb;
  v_applied integer:=0; v_skipped integer:=0; v_already integer:=0;
  v_conflict boolean; v_status text; v_link_id bigint; v_reason text; v_action jsonb;
  v_kind text; v_role text; v_pid bigint; v_rules text[]; v_back record;
begin
  if nullif(trim(p_consumer),'') is null then raise exception 'T_REMED_CONSUMER_REQUIRED'; end if;
  v_rec:=programacion.fn_t_remed_reconcile_v1(p_pantalla_id);

  for r in select value from jsonb_array_elements(v_rec->'references') loop
    v_kind:=r->>'policy_kind'; v_role:=r->>'reference_role'; v_pid:=(r->>'policy_id')::bigint;
    select array_agg(x) into v_rules from jsonb_array_elements_text(r->'rule_codes') x;
    v_reason:=null;

    select exists(select 1 from jsonb_array_elements(v_rec->'conflicts') c
                  where c->>'policy_kind'=v_kind and c->>'reference_role'=v_role) into v_conflict;
    if v_conflict then v_reason:='SOURCE_CONFLICT_MULTIPLE_POLICY_IDS';
    elsif coalesce((r->>'rule_pending')::boolean,false) then v_reason:='SOURCE_RULE_PENDING_DECISION';
    elsif not coalesce((r->>'policy_exists')::boolean,false) then v_reason:='POLICY_NOT_FOUND';
    elsif r->>'policy_status' not in ('VIGENTE','CANDIDATO') then v_reason:='POLICY_NOT_ACTIVE';
    end if;

    if v_reason is not null then
      v_skipped:=v_skipped+1;
      v_action:=jsonb_build_object('action','NO_WRITE','reason',v_reason,'policy_kind',v_kind,'reference_role',v_role,'policy_id',v_pid,'rule_codes',to_jsonb(v_rules));
    elsif r->>'link_status' is not null then
      v_already:=v_already+1;
      v_action:=jsonb_build_object('action','ALREADY_LINKED','policy_kind',v_kind,'reference_role',v_role,'policy_id',v_pid,'link_status',r->>'link_status');
    else
      v_status:=case when r->>'policy_status'='VIGENTE'
                      and not exists(select 1 from jsonb_array_elements_text(r->'rule_states') s where s<>'VIGENTE')
                     then 'VIGENTE' else 'CANDIDATO' end;
      insert into lf_ops.pantallas_politicas(pantalla_id,policy_kind,reference_role,rate_limit_policy_id,timeout_policy_id,session_policy_id,security_policy_id,status)
      values(p_pantalla_id,v_kind,v_role,
             case when v_kind='RATE_LIMIT' then v_pid end, case when v_kind='TIMEOUT' then v_pid end,
             case when v_kind='SESSION' then v_pid end,    case when v_kind='SECURITY' then v_pid end, v_status)
      returning pantalla_politica_id into v_link_id;
      insert into lf_ops.pantallas_politicas_reglas(pantalla_politica_id,regla_id)
      select v_link_id, rg.id from lf_ops.reglas rg where rg.codigo=any(v_rules);

      select l.status, coalesce(l.rate_limit_policy_id,l.timeout_policy_id,l.session_policy_id,l.security_policy_id) pid,
             (select count(*) from lf_ops.pantallas_politicas_reglas j where j.pantalla_politica_id=l.pantalla_politica_id) nrules
        into v_back from lf_ops.pantallas_politicas l where l.pantalla_politica_id=v_link_id;
      if v_back.pid is distinct from v_pid or v_back.status is distinct from v_status or v_back.nrules<>cardinality(v_rules) then
        raise exception 'T_REMED_READBACK_FAILED:%',v_link_id;
      end if;
      v_applied:=v_applied+1;
      v_action:=jsonb_build_object('action','LINK_POLICY_EXPLICIT_REFERENCE','link_id',v_link_id,'policy_kind',v_kind,'reference_role',v_role,
                 'policy_id',v_pid,'policy_code',r->>'policy_code','link_status',v_status,'inherited_from',jsonb_build_object('rules',to_jsonb(v_rules),'rule_states',r->'rule_states','policy_status',r->>'policy_status'));
    end if;

    v_actions:=v_actions||jsonb_build_array(v_action);
    insert into programacion.t_remed_receipts(layer,subject_kind,subject_id,consumer,action,result,evidence,evidence_sha256)
    values('COMPLETE','PANTALLA',p_pantalla_id,p_consumer,v_action->>'action',
           case when v_action->>'action'='LINK_POLICY_EXPLICIT_REFERENCE' then 'APPLIED' when v_action->>'action'='ALREADY_LINKED' then 'NOOP' else 'NO_WRITE' end,
           v_action, encode(sha256(convert_to(v_action::text,'UTF8')),'hex'));
  end loop;

  return jsonb_build_object('capability','T_REMED','layer','COMPLETE','version',1,'consumer',p_consumer,
    'subject',jsonb_build_object('kind','PANTALLA','id',p_pantalla_id),
    'applied_count',v_applied,'already_linked_count',v_already,'skipped_count',v_skipped,
    'unmapped_reference_count',(v_rec->'summary'->>'unmapped_count')::int,
    'actions',v_actions,'promotion_authorized',false,'production_authorized',false);
end;
$fn$;

-- Layer 3 judge (independent: reads raw tables only, never calls Layer 1 or Layer 2) ------------------------------------------
create or replace function public.lf_t_remed_independent_review_v1(p_pantalla_id integer)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'pg_catalog'
as $fn$
declare
  l record;
  v_findings jsonb:='[]'::jsonb;
  v_checked integer:=0;
  v_pid bigint; v_pstatus text; v_cite integer; v_any_cand boolean; v_all_vig boolean; v_cfg_key text; v_expected text;
begin
  for l in select * from lf_ops.pantallas_politicas where pantalla_id=p_pantalla_id order by pantalla_politica_id loop
    v_checked:=v_checked+1;
    v_pid:=case l.policy_kind when 'RATE_LIMIT' then l.rate_limit_policy_id when 'TIMEOUT' then l.timeout_policy_id
                              when 'SESSION' then l.session_policy_id else l.security_policy_id end;
    v_pstatus:=case l.policy_kind
      when 'RATE_LIMIT' then (select status from lf_ops.politicas_rate_limit where rate_limit_policy_id=v_pid)
      when 'TIMEOUT'    then (select status from lf_ops.politicas_timeout    where timeout_policy_id=v_pid)
      when 'SESSION'    then (select status from lf_ops.politicas_sesion     where session_policy_id=v_pid)
      else (select status from lf_ops.politicas_seguridad where security_policy_id=v_pid) end;
    if v_pstatus is null then
      v_findings:=v_findings||jsonb_build_object('link_id',l.pantalla_politica_id,'code','POLICY_NOT_FOUND');
    end if;

    select count(*), coalesce(bool_or(rg.estado='CANDIDATO'),false), coalesce(bool_and(rg.estado='VIGENTE'),false)
      into v_cite, v_any_cand, v_all_vig
    from lf_ops.pantallas_politicas_reglas j
    join lf_ops.reglas rg on rg.id=j.regla_id
    join lf_ops.reglas_pantallas rp on rp.regla_id=rg.id and rp.pantalla_id=l.pantalla_id
    where j.pantalla_politica_id=l.pantalla_politica_id
      and jsonb_typeof(rg.valor_config)='object'
      and (rg.valor_config->>l.reference_role) ~ '^[0-9]+$'
      and (rg.valor_config->>l.reference_role)::bigint=v_pid
      and not coalesce(rg.pendiente_decision,false);
    if v_cite=0 then
      v_findings:=v_findings||jsonb_build_object('link_id',l.pantalla_politica_id,'code','NO_SOURCE_RULE_CITES_THIS_POLICY');
    end if;

    v_expected:=case when v_cite>0 and v_all_vig and v_pstatus='VIGENTE' then 'VIGENTE' else 'CANDIDATO' end;
    if l.status<>'INACTIVO' and l.status<>v_expected then
      v_findings:=v_findings||jsonb_build_object('link_id',l.pantalla_politica_id,'code','STATUS_MISMATCH','detail','status='||l.status||' expected '||v_expected);
    end if;
  end loop;

  return jsonb_build_object('schema_version','LF_T_REMED_INDEPENDENT_REVIEW_V1','pantalla_id',p_pantalla_id,
    'checked_count',v_checked,'failed_count',jsonb_array_length(v_findings),
    'verdict',case when v_checked=0 then 'NOT_APPLICABLE' when jsonb_array_length(v_findings)=0 then 'PASS' else 'FAIL' end,
    'findings',v_findings);
end;
$fn$;

-- Layer 3 promotion -------------------------------------------------------------------------------------------------------
create or replace function programacion.fn_t_remed_promote_v1(p_pantalla_id integer, p_consumer text default 'IG_CURATOR')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog','programacion','lf_ops','public'
as $fn$
declare
  l record;
  v_review jsonb;
  v_actions jsonb:='[]'::jsonb;
  v_promoted integer:=0; v_held integer:=0;
  v_pid bigint; v_pstatus text; v_pdec bigint; v_dec_state text; v_rule_states text[]; v_hold text; v_action jsonb;
begin
  if nullif(trim(p_consumer),'') is null then raise exception 'T_REMED_CONSUMER_REQUIRED'; end if;
  v_review:=public.lf_t_remed_independent_review_v1(p_pantalla_id);

  for l in select * from lf_ops.pantallas_politicas where pantalla_id=p_pantalla_id and status='CANDIDATO' order by pantalla_politica_id loop
    v_pid:=case l.policy_kind when 'RATE_LIMIT' then l.rate_limit_policy_id when 'TIMEOUT' then l.timeout_policy_id
                              when 'SESSION' then l.session_policy_id else l.security_policy_id end;
    select status, source_decision_number into v_pstatus, v_pdec from (
      select status, source_decision_number, 'RATE_LIMIT' k, rate_limit_policy_id id from lf_ops.politicas_rate_limit
      union all select status, source_decision_number, 'TIMEOUT', timeout_policy_id from lf_ops.politicas_timeout
      union all select status, source_decision_number, 'SESSION', session_policy_id from lf_ops.politicas_sesion
      union all select status, source_decision_number, 'SECURITY', security_policy_id from lf_ops.politicas_seguridad) x
    where x.k=l.policy_kind and x.id=v_pid;
    select array_agg(distinct rg.estado) into v_rule_states
      from lf_ops.pantallas_politicas_reglas j join lf_ops.reglas rg on rg.id=j.regla_id where j.pantalla_politica_id=l.pantalla_politica_id;
    select estado_normalizado into v_dec_state from public.lf_decisiones_gov where decision_number=v_pdec;

    v_hold:=case
      when v_review->>'verdict'<>'PASS' then 'INDEPENDENT_REVIEW_'||(v_review->>'verdict')
      when exists(select 1 from unnest(v_rule_states) s where s<>'VIGENTE') then 'SOURCE_RULE_CANDIDATO'
      when v_pstatus is distinct from 'VIGENTE' then 'POLICY_CANDIDATO'
      when v_dec_state is null then 'ROOT_DECISION_NOT_FOUND'
      when v_dec_state not in ('VIGENTE','APROBADA','LOCKED') then 'ROOT_DECISION_'||v_dec_state
      else null end;

    if v_hold is null then
      update lf_ops.pantallas_politicas set status='VIGENTE', updated_at=now()
       where pantalla_politica_id=l.pantalla_politica_id and status='CANDIDATO';
      if not found then raise exception 'T_REMED_PROMOTE_CONCURRENT_CHANGE:%',l.pantalla_politica_id; end if;
      v_promoted:=v_promoted+1;
      v_action:=jsonb_build_object('action','PROMOTE_LINK','link_id',l.pantalla_politica_id,'from','CANDIDATO','to','VIGENTE','root_decision_number',v_pdec,'root_decision_state',v_dec_state);
    else
      v_held:=v_held+1;
      v_action:=jsonb_build_object('action','HOLD','link_id',l.pantalla_politica_id,'policy_kind',l.policy_kind,'reference_role',l.reference_role,'blocked_by',v_hold,
                 'chain',jsonb_build_object('rule_states',to_jsonb(v_rule_states),'policy_status',v_pstatus,'root_decision_number',v_pdec,'root_decision_state',v_dec_state));
    end if;
    insert into programacion.t_remed_receipts(layer,subject_kind,subject_id,consumer,action,result,evidence,evidence_sha256)
    values('PROMOTE','PANTALLA',p_pantalla_id,p_consumer,v_action->>'action',case when v_hold is null then 'APPLIED' else 'HELD' end,
           v_action,encode(sha256(convert_to(v_action::text,'UTF8')),'hex'));
    v_actions:=v_actions||jsonb_build_array(v_action);
  end loop;

  return jsonb_build_object('capability','T_REMED','layer','PROMOTE','version',1,'consumer',p_consumer,
    'subject',jsonb_build_object('kind','PANTALLA','id',p_pantalla_id),'independent_review',v_review->'verdict',
    'promoted_count',v_promoted,'held_count',v_held,'actions',v_actions,'production_authorized',false);
end;
$fn$;

revoke all on function programacion.fn_t_remed_raw_refs_v1(integer) from public, anon, authenticated;
revoke all on function programacion.fn_t_remed_reconcile_v1(integer) from public, anon, authenticated;
revoke all on function programacion.fn_t_remed_complete_v1(integer,text) from public, anon, authenticated;
revoke all on function programacion.fn_t_remed_promote_v1(integer,text) from public, anon, authenticated;
revoke all on function public.lf_t_remed_independent_review_v1(integer) from public, anon, authenticated;
