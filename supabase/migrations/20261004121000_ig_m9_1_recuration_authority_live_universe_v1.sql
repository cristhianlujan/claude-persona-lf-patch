-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M9.1 / PAULO-149
-- Shared-root repair: extend the governed Input Governance recuration/currentness
-- authority to the live joinable active-screen universe. This does NOT grant
-- implementation or navigation authority and preserves screen 55 TRACEABILITY_ONLY.
-- R16 Git-first. R17/N-9 applies because the rule is consumed by the runtime caller.

begin;

do $preflight$
declare
  v_joinable_ids integer[];
  v_joinable_count integer;
  v_orphan_count integer;
  v_rule lf_ops.reglas%rowtype;
begin
  select array_agg(id order by id), count(*)
    into v_joinable_ids, v_joinable_count
  from lf_ops.pantallas
  where activa and module_id is not null;

  select count(*)
    into v_orphan_count
  from lf_ops.pantallas
  where activa and module_id is null;

  if v_joinable_count <> 42 or v_orphan_count <> 12 then
    raise exception 'M9_1_LIVE_UNIVERSE_DRIFT joinable=% orphan=%', v_joinable_count, v_orphan_count;
  end if;

  select * into v_rule
  from lf_ops.reglas
  where codigo='INPUT-GOV-RECURATION-AUTHORIZED-SCREENS-001';

  if not found
     or v_rule.id <> 661
     or v_rule.estado <> 'VIGENTE'
     or v_rule.pendiente_decision
     or v_rule.valor_config->>'scope' <> 'INPUT_GOVERNANCE_RECURATION_CURRENTNESS'
     or v_rule.valor_config->>'contract_version' <> '1.0.0'
     or coalesce((v_rule.valor_config->>'fail_closed')::boolean,false) is not true
     or v_rule.valor_config->>'implementation_authority' <> 'NOT_GRANTED_BY_THIS_RULE'
     or v_rule.valor_config#>>'{consumer_mode_overrides,55}' <> 'TRACEABILITY_ONLY'
     or v_rule.valor_config#>>'{screen_55_authority,operational_navigation}' <> 'DENY'
     or v_rule.valor_config#>>'{screen_55_authority,input_governance_scope}' <> 'IN_SCOPE'
  then
    raise exception 'M9_1_RECURATION_AUTHORITY_PRECONDITION_FAILED';
  end if;

  if not (55 = any(v_joinable_ids)) then
    raise exception 'M9_1_SCREEN_55_MISSING_FROM_LIVE_JOINABLE_UNIVERSE';
  end if;
end
$preflight$;

with live as (
  select to_jsonb(array_agg(id order by id)) as screen_ids,
         count(*)::integer as screen_count
  from lf_ops.pantallas
  where activa and module_id is not null
)
update lf_ops.reglas r
set valor_config = jsonb_set(
                     jsonb_set(r.valor_config,'{screen_ids}',live.screen_ids,true),
                     '{authorized_screen_count}',to_jsonb(live.screen_count),true
                   ) || jsonb_build_object(
                     'm9_1_baseline_authority',jsonb_build_object(
                       'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
                       'unit_code','M9.1',
                       'work_code','PAULO-149',
                       'selection','ACTIVE_AND_MODULE_ID_NOT_NULL',
                       'live_joinable_count',live.screen_count,
                       'live_orphan_policy','PRECHECK_BLOCKED_MODULE_OR_SHELL_GRAPH_LINK_MISSING',
                       'universe_sha256','b06500cf01e3844bb16fbef5d6ec3d5539065c3b4e72dbb67e56b7b1b6ebaaf3'
                     )
                   ),
    updated_at = now()
from live
where r.codigo='INPUT-GOV-RECURATION-AUTHORIZED-SCREENS-001';

do $postconditions$
declare
  v_ids integer[];
  v_count integer;
  v_orphan_overlap integer;
  v_rule lf_ops.reglas%rowtype;
begin
  select * into v_rule
  from lf_ops.reglas
  where codigo='INPUT-GOV-RECURATION-AUTHORIZED-SCREENS-001';

  select array_agg((x.value)::integer order by (x.value)::integer)
    into v_ids
  from jsonb_array_elements_text(v_rule.valor_config->'screen_ids') x(value);

  v_count := coalesce((v_rule.valor_config->>'authorized_screen_count')::integer,0);

  select count(*) into v_orphan_overlap
  from lf_ops.pantallas p
  where p.activa and p.module_id is null and p.id=any(v_ids);

  if v_count <> 42
     or cardinality(v_ids) <> 42
     or v_orphan_overlap <> 0
     or v_rule.estado <> 'VIGENTE'
     or coalesce((v_rule.valor_config->>'fail_closed')::boolean,false) is not true
     or v_rule.valor_config->>'implementation_authority' <> 'NOT_GRANTED_BY_THIS_RULE'
     or v_rule.valor_config#>>'{consumer_mode_overrides,55}' <> 'TRACEABILITY_ONLY'
     or v_rule.valor_config#>>'{traceability_only_policy,story_creator}' <> 'DO_NOT_GENERATE_IMPLEMENTABLE_STORY'
     or v_rule.valor_config#>>'{traceability_only_policy,router}' <> 'DO_NOT_ROUTE_TO_IMPLEMENTATION'
     or v_rule.valor_config#>>'{screen_55_authority,operational_navigation}' <> 'DENY'
     or v_rule.valor_config#>>'{m9_1_baseline_authority,unit_code}' <> 'M9.1'
  then
    raise exception 'M9_1_RECURATION_AUTHORITY_POSTCONDITION_FAILED:%',to_jsonb(v_rule);
  end if;
end
$postconditions$;

commit;
