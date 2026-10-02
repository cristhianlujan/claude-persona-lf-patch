-- N-4 / PAULO-169 — micro-lot B.
-- Preconditions: micro-lot A is applied and declarative applicability is exactly equivalent
-- to the legacy positive binding set for the 32 migrated VIGENTE transversal rules.
-- Only after those gates pass do the 13 verified Input Governance readers stop consuming
-- lf_ops.reglas_pantallas directly. Non-migrated/local rules remain legacy-linked.

begin;

do $precutover$
declare
  v_loaded integer;
  v_diff integer;
  v_baseline_diff integer;
begin
  select count(*) into v_loaded
  from lf_ops.reglas
  where estado='VIGENTE' and es_transversal=true
    and jsonb_typeof(valor_config->'applicability_v1')='object';
  if v_loaded <> 32 then raise exception 'N4_CUTOVER_REQUIRES_32_APPLICABILITY_ROWS:%',v_loaded; end if;

  with rules as (select id from lf_ops.reglas where estado='VIGENTE' and es_transversal=true),
       targets as (select id as pantalla_id from lf_ops.pantallas),
       cmp as (
         select r.id,t.pantalla_id,
           exists(select 1 from lf_ops.reglas_pantallas rp where rp.regla_id=r.id and rp.pantalla_id=t.pantalla_id) as legacy_applies,
           exists(select 1 from programacion.fn_input_declared_rule_links_v1(t.pantalla_id,'INPUT_GOVERNANCE') d where d.regla_id=r.id) as declared_applies
         from rules r cross join targets t
       )
  select count(*) into v_diff from cmp where legacy_applies is distinct from declared_applies;
  if v_diff <> 0 then raise exception 'N4_CUTOVER_ALL_TARGET_EQUIVALENCE_FAILED:%',v_diff; end if;

  with rules as (select id from lf_ops.reglas where estado='VIGENTE' and es_transversal=true),
       targets(pantalla_id) as (values (1),(2),(3),(5),(43),(51),(52),(53),(54),(55),(56),(57),(58)),
       cmp as (
         select r.id,t.pantalla_id,
           exists(select 1 from lf_ops.reglas_pantallas rp where rp.regla_id=r.id and rp.pantalla_id=t.pantalla_id) as legacy_applies,
           exists(select 1 from programacion.fn_input_declared_rule_links_v1(t.pantalla_id,'INPUT_GOVERNANCE') d where d.regla_id=r.id) as declared_applies
         from rules r cross join targets t
       )
  select count(*) into v_baseline_diff from cmp where legacy_applies is distinct from declared_applies;
  if v_baseline_diff <> 0 then raise exception 'N4_CUTOVER_13X32_EQUIVALENCE_FAILED:%',v_baseline_diff; end if;
end;
$precutover$;

create temporary table n4_graph_before on commit drop as
with v as (select max(id) as version_id from programacion.versiones_agente),
     s(pantalla_id) as (values (1),(2),(3),(5),(43),(51),(52),(53),(54),(55),(56),(57),(58))
select s.pantalla_id, md5(programacion.fn_input_screen_canonical_graph(s.pantalla_id,v.version_id)::text) as graph_md5
from s cross join v;

create or replace function programacion.fn_input_effective_rule_links_v1(
  p_pantalla_id integer,
  p_consumer text default 'INPUT_GOVERNANCE'
)
returns table(pantalla_id integer, regla_id integer, binding_source text)
language sql
stable
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
  with legacy as (
    select rp.pantalla_id,rp.regla_id,'LEGACY_EXPLICIT'::text as binding_source
    from lf_ops.reglas_pantallas rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and jsonb_typeof(r.valor_config->'applicability_v1') is distinct from 'object'
  ), declared as (
    select d.pantalla_id,d.regla_id,d.binding_source
    from programacion.fn_input_declared_rule_links_v1(p_pantalla_id,p_consumer) d
  )
  select * from legacy
  union all
  select * from declared
$function$;

comment on function programacion.fn_input_effective_rule_links_v1(integer,text) is
  'N-4 effective IG relation: governed applicability_v1 for migrated rules; legacy explicit links only for rules without applicability_v1.';

do $effective_gate$
declare
  v_missing integer;
  v_extra integer;
begin
  with legacy as (select rp.pantalla_id,rp.regla_id from lf_ops.reglas_pantallas rp),
       effective as (
         select p.id as pantalla_id,e.regla_id
         from lf_ops.pantallas p
         cross join lateral programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') e
       )
  select
    (select count(*) from (select * from legacy except select * from effective) x),
    (select count(*) from (select * from effective except select * from legacy) x)
  into v_missing,v_extra;
  if v_missing <> 0 or v_extra <> 0 then
    raise exception 'N4_EFFECTIVE_PAIRSET_REGRESSION:missing=% extra=%',v_missing,v_extra;
  end if;
end;
$effective_gate$;

do $patch$
declare
  v_row record;
  v_def text;
  v_new text;
  v_before integer;
  v_after integer;
begin
  for v_row in
    select * from (values
      ('programacion.fn_input_api_contract_resolution(integer)'::regprocedure,'80e934fa700e8d0014cee77f6b377ccf'),
      ('programacion.fn_input_design_binding_graph(integer)'::regprocedure,'48ed44ca56f00b790bb7694b60c31322'),
      ('programacion.fn_input_design_system_resolution_v1(integer)'::regprocedure,'9fedf8afcf6fa7b7772d5020fbfd2e08'),
      ('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'::regprocedure,'131d3d43204984ea646fe4536f83ad11'),
      ('programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)'::regprocedure,'2a3e2f583c1c08d070039a1d85480d5f'),
      ('programacion.fn_input_governance_shadow_priority_oracle_v2(integer,text,bigint)'::regprocedure,'d4e8c28fefab8a2cc7a4b95cc4bdb745'),
      ('programacion.fn_input_resolve_source_ref_v510(jsonb,integer,bigint)'::regprocedure,'035753b88e1e03259c11a96f9fd5706a'),
      ('programacion.fn_input_screen_canonical_graph(integer,bigint)'::regprocedure,'454e90aba0760cb5dd727e50bffc99be'),
      ('programacion.fn_input_security_capability_profile(integer)'::regprocedure,'d2801802d1dccf02f663fbc5e5a24f20'),
      ('programacion.fn_input_security_threat_expected_v510(integer)'::regprocedure,'01bdf9f01f57d1d2506fd437277dce93'),
      ('programacion.fn_input_subject_depth_expected(integer,text)'::regprocedure,'05fa302a4acce07c7d2395743dc14e8b'),
      ('programacion.fn_input_subject_depth_expected_v510(integer,text)'::regprocedure,'032b571cdf8ef629eb2ada1305a36251')
    ) as x(proc_oid,expected_md5)
  loop
    v_def := pg_get_functiondef(v_row.proc_oid);
    if md5(v_def) is distinct from v_row.expected_md5 then
      raise exception 'N4_FUNCTION_PREIMAGE_DRIFT:% expected=% actual=%',v_row.proc_oid,v_row.expected_md5,md5(v_def);
    end if;
    v_before :=
      (length(lower(v_def))-length(replace(lower(v_def),'from lf_ops.reglas_pantallas','')))/length('from lf_ops.reglas_pantallas')
      +
      (length(lower(v_def))-length(replace(lower(v_def),'join lf_ops.reglas_pantallas','')))/length('join lf_ops.reglas_pantallas');
    if v_before < 1 then raise exception 'N4_EXPECTED_RULE_LINK_READ_MISSING:%',v_row.proc_oid; end if;
    v_new := replace(v_def,'from lf_ops.reglas_pantallas','from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,''INPUT_GOVERNANCE'')');
    v_new := replace(v_new,'join lf_ops.reglas_pantallas','join programacion.fn_input_effective_rule_links_v1(p_pantalla_id,''INPUT_GOVERNANCE'')');
    execute v_new;
    select (length(lower(pg_get_functiondef(v_row.proc_oid)))-length(replace(lower(pg_get_functiondef(v_row.proc_oid)),'lf_ops.reglas_pantallas','')))/length('lf_ops.reglas_pantallas') into v_after;
    if v_after <> 0 then raise exception 'N4_RULE_LINK_READ_RESIDUAL:% count=%',v_row.proc_oid,v_after; end if;
  end loop;

  v_def := pg_get_functiondef('programacion.fn_input_actionable_remediation_summary_v1(bigint)'::regprocedure);
  if md5(v_def) <> '1fc06a6f4b3a70af92dcff7efcf9a821' then
    raise exception 'N4_FUNCTION_PREIMAGE_DRIFT:fn_input_actionable_remediation_summary_v1 actual=%',md5(v_def);
  end if;
  v_before := (length(lower(v_def))-length(replace(lower(v_def),'join lf_ops.reglas_pantallas','')))/length('join lf_ops.reglas_pantallas');
  if v_before <> 2 then raise exception 'N4_REMEDIATION_RULE_LINK_COUNT_DRIFT:%',v_before; end if;
  v_new := replace(v_def,'join lf_ops.reglas_pantallas','join programacion.fn_input_effective_rule_links_v1((select pantalla_id from rc limit 1),''INPUT_GOVERNANCE'')');
  execute v_new;
  if position('lf_ops.reglas_pantallas' in lower(pg_get_functiondef('programacion.fn_input_actionable_remediation_summary_v1(bigint)'::regprocedure))) > 0 then
    raise exception 'N4_REMEDIATION_RULE_LINK_RESIDUAL';
  end if;
end;
$patch$;

do $readback$
declare
  v_direct integer;
  v_consumers integer;
  v_graph_diff integer;
  v_missing integer;
  v_extra integer;
begin
  select count(*) into v_direct
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname in (
      'fn_input_actionable_remediation_summary_v1','fn_input_api_contract_resolution','fn_input_design_binding_graph',
      'fn_input_design_system_resolution_v1','fn_input_governance_semantic_probe_v3','fn_input_governance_semantic_probe_v3_cached_v1',
      'fn_input_governance_shadow_priority_oracle_v2','fn_input_resolve_source_ref_v510','fn_input_screen_canonical_graph',
      'fn_input_security_capability_profile','fn_input_security_threat_expected_v510','fn_input_subject_depth_expected',
      'fn_input_subject_depth_expected_v510'
    )
    and position('lf_ops.reglas_pantallas' in p.prosrc)>0;
  if v_direct <> 0 then raise exception 'N4_DIRECT_MANUAL_DEPENDENCY_REMAINS:%',v_direct; end if;

  select count(*) into v_consumers
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname in (
      'fn_input_actionable_remediation_summary_v1','fn_input_api_contract_resolution','fn_input_design_binding_graph',
      'fn_input_design_system_resolution_v1','fn_input_governance_semantic_probe_v3','fn_input_governance_semantic_probe_v3_cached_v1',
      'fn_input_governance_shadow_priority_oracle_v2','fn_input_resolve_source_ref_v510','fn_input_screen_canonical_graph',
      'fn_input_security_capability_profile','fn_input_security_threat_expected_v510','fn_input_subject_depth_expected',
      'fn_input_subject_depth_expected_v510'
    )
    and position('fn_input_effective_rule_links_v1' in p.prosrc)>0;
  if v_consumers <> 13 then raise exception 'N4_EFFECTIVE_CONSUMER_COUNT:%',v_consumers; end if;

  with v as (select max(id) as version_id from programacion.versiones_agente),
       after as (
         select b.pantalla_id,md5(programacion.fn_input_screen_canonical_graph(b.pantalla_id,v.version_id)::text) as graph_md5
         from n4_graph_before b cross join v
       )
  select count(*) into v_graph_diff
  from n4_graph_before b join after a using(pantalla_id)
  where b.graph_md5 is distinct from a.graph_md5;
  if v_graph_diff <> 0 then raise exception 'N4_BASELINE_GRAPH_REGRESSION:%',v_graph_diff; end if;

  with legacy as (select rp.pantalla_id,rp.regla_id from lf_ops.reglas_pantallas rp),
       effective as (
         select p.id as pantalla_id,e.regla_id
         from lf_ops.pantallas p
         cross join lateral programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') e
       )
  select
    (select count(*) from (select * from legacy except select * from effective) x),
    (select count(*) from (select * from effective except select * from legacy) x)
  into v_missing,v_extra;
  if v_missing <> 0 or v_extra <> 0 then
    raise exception 'N4_POSTCUTOVER_PAIRSET_REGRESSION:missing=% extra=%',v_missing,v_extra;
  end if;

  if position('es_transversal' in lower(pg_get_functiondef('programacion.fn_input_effective_rule_links_v1(integer,text)'::regprocedure))) > 0 then
    raise exception 'N4_EFFECTIVE_RUNTIME_ES_TRANSVERSAL_DEPENDENCY_FORBIDDEN';
  end if;
end;
$readback$;

commit;
