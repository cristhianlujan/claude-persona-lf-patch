-- INPUT_GOVERNANCE_AGENT / Strategy 28 / IG-C direct-authority extension
-- Rollback-only source candidate. No live runtime switch, no message/decision mutation, no promotion.
-- Frozen holdout: runs 213 ONB_003 and 214 ONB_004, contract revision 5.12.
-- Adds three independently sourced patterns to the two already demonstrated in PR578:
--   OBJECTIVE_OUTCOMES <- lf_ops.pantallas + exact source decision currentness
--   RUNTIME_CONFIG     <- direct screen rules + reuse_rules technical sources, never COMPLETE without dedicated authority
--   UI_MESSAGES        <- exact message_ids consumed by SCREEN_CANONICAL_GRAPH + message/source-decision currentness
-- I18N_FORMATS intentionally remains blocked: positive applicability authority for CLIENT_ONBOARDING is absent.

begin;

create or replace function programacion.fn_input_governance_shadow_objective_oracle_candidate_v1(
  p_pantalla_id integer,
  p_override jsonb default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v jsonb;
  v_ok boolean:=false;
  v_classification text;
begin
  if p_override is null then
    select jsonb_build_object(
      'pantalla_id',p.id,
      'screen_code',p.codigo,
      'objective',p.objective,
      'source_decision_id',p.source_decision_id,
      'source_decision_number',p.source_decision_number,
      'decision_id',d.id_decision,
      'decision_number',d.decision_number,
      'decision_status',d.estado_normalizado
    ) into v
    from lf_ops.pantallas p
    left join public.lf_decisiones_gov d on d.decision_number=p.source_decision_number
    where p.id=p_pantalla_id;
  else
    v:=p_override;
  end if;

  v_ok:=nullif(btrim(coalesce(v->>'objective','')),'') is not null
    and nullif(v->>'source_decision_id','') is not null
    and nullif(v->>'source_decision_number','') is not null
    and v->>'decision_status'='VIGENTE'
    and v->>'decision_id'=v->>'source_decision_id'
    and v->>'decision_number'=v->>'source_decision_number';

  v_classification:=case when v_ok then 'COMPLETE' else 'MISSING' end;

  return jsonb_build_object(
    'shadow_contract','INPUT_GOVERNANCE_SHADOW_OBJECTIVE_ORACLE_CANDIDATE_V1',
    'family_code','OBJECTIVE_OUTCOMES','pantalla_id',p_pantalla_id,
    'implemented',true,'decisional',false,'comparison_only',true,'mutates_readiness',false,
    'classification',v_classification,
    'reason',case when v_ok then 'OBJECTIVE_AND_CURRENT_SOURCE_DECISION_RESOLVED' else 'OBJECTIVE_OR_SOURCE_DECISION_CURRENTNESS_MISSING' end,
    'observed_authority',v,
    'source_refs',jsonb_build_array(
      jsonb_build_object('kind','SCREEN_OBJECTIVE','pantalla_id',p_pantalla_id),
      jsonb_build_object('kind','GOV_DECISION','ref',v->>'source_decision_id','decision_number',v->>'source_decision_number')
    )
  );
end
$function$;

create or replace function programacion.fn_input_governance_shadow_runtime_config_oracle_candidate_v1(
  p_pantalla_id integer,
  p_override jsonb default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v jsonb;
  v_direct integer:=0;
  v_direct_current integer:=0;
  v_reused integer:=0;
  v_reused_candidate integer:=0;
  v_classification text;
begin
  if p_override is null then
    with direct_rules as (
      select r.id,r.codigo,r.categoria,r.estado,r.origen,r.valor_config
      from lf_ops.reglas_pantallas rp
      join lf_ops.reglas r on r.id=rp.regla_id
      where rp.pantalla_id=p_pantalla_id
    ), runtime_direct as (
      select * from direct_rules
      where coalesce(valor_config,'{}'::jsonb) ?| array[
        'auth_provider','account_store','phone_binding_store','session_context_contract',
        'client_validation','server_validation','idempotency','automatic_retry'
      ]
    ), reuse_codes as (
      select distinct x.value as codigo
      from direct_rules d
      cross join lateral jsonb_array_elements_text(coalesce(d.valor_config->'reuse_rules','[]'::jsonb)) x(value)
    ), reused_technical as (
      select r.* from lf_ops.reglas r
      where r.codigo in (select codigo from reuse_codes)
        and lower(coalesce(r.categoria,''))='tecnico'
    )
    select jsonb_build_object(
      'direct_runtime_count',(select count(*) from runtime_direct),
      'direct_current_authority_count',(
        select count(*) from runtime_direct r
        join public.lf_decisiones_gov d on d.id_decision=r.origen
        where d.estado_normalizado='VIGENTE'
      ),
      'reused_technical_count',(select count(*) from reused_technical),
      'reused_technical_candidate_count',(select count(*) from reused_technical where estado='CANDIDATO'),
      'dedicated_runtime_contract_count',0
    ) into v;
  else
    v:=p_override;
  end if;

  v_direct:=coalesce((v->>'direct_runtime_count')::integer,0);
  v_direct_current:=coalesce((v->>'direct_current_authority_count')::integer,0);
  v_reused:=coalesce((v->>'reused_technical_count')::integer,0);
  v_reused_candidate:=coalesce((v->>'reused_technical_candidate_count')::integer,0);

  if v_direct+v_reused=0 then
    v_classification:='MISSING';
  else
    -- Source presence is not sufficient for COMPLETE under contract 5.12.
    -- No dedicated runtime authority exists for these screens, so this oracle deliberately caps at PARTIAL.
    v_classification:='PARTIAL';
  end if;

  return jsonb_build_object(
    'shadow_contract','INPUT_GOVERNANCE_SHADOW_RUNTIME_CONFIG_ORACLE_CANDIDATE_V1',
    'family_code','RUNTIME_CONFIG','pantalla_id',p_pantalla_id,
    'implemented',true,'decisional',false,'comparison_only',true,'mutates_readiness',false,
    'classification',v_classification,
    'reason',case when v_classification='MISSING' then 'NO_DIRECT_OR_REUSED_RUNTIME_SOURCE' else 'RUNTIME_SOURCES_PRESENT_BUT_DEDICATED_SUFFICIENCY_AUTHORITY_ABSENT' end,
    'observed_authority',v,
    'source_refs',jsonb_build_array(
      jsonb_build_object('kind','SCREEN_RULE_BINDINGS','pantalla_id',p_pantalla_id),
      jsonb_build_object('kind','RULE_REUSE_TECHNICAL','pantalla_id',p_pantalla_id)
    ),
    'authority_summary',jsonb_build_object(
      'direct_runtime_count',v_direct,'direct_current_authority_count',v_direct_current,
      'reused_technical_count',v_reused,'reused_technical_candidate_count',v_reused_candidate,
      'complete_authority_present',false
    )
  );
end
$function$;

create or replace function programacion.fn_input_governance_shadow_ui_messages_oracle_candidate_v1(
  p_pantalla_id integer,
  p_override jsonb default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v jsonb;
  v_total integer:=0;
  v_current integer:=0;
  v_stale integer:=0;
  v_classification text;
  v_stage jsonb;
begin
  if p_override is null then
    with field_ids as (
      select cp.campo_id,cp.message_id
      from lf_ops.campos_pantallas cp
      where cp.pantalla_id=p_pantalla_id
    ), timeout_policy_ids as (
      select distinct e.value::bigint timeout_policy_id
      from lf_ops.reglas_pantallas rp
      join lf_ops.reglas r on r.id=rp.regla_id
      cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e
      where rp.pantalla_id=p_pantalla_id
        and (e.key='timeout_policy_id' or e.key like '%_timeout_policy_id')
        and e.value~'^[0-9]+$'
    ), rule_message_ids as (
      select distinct e.value::bigint message_id
      from lf_ops.reglas_pantallas rp
      join lf_ops.reglas r on r.id=rp.regla_id
      cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e
      where rp.pantalla_id=p_pantalla_id
        and (e.key='message_id' or e.key like '%_message_id')
        and e.value~'^[0-9]+$'
    ), message_ids as (
      select message_id from field_ids where message_id is not null
      union
      select cv.message_id from lf_ops.campos_validaciones cv join field_ids f on f.campo_id=cv.campo_id where cv.message_id is not null
      union
      select tp.message_id from lf_ops.politicas_timeout tp where tp.timeout_policy_id in (select timeout_policy_id from timeout_policy_ids) and tp.message_id is not null
      union
      select message_id from rule_message_ids
    ), resolved as (
      select mu.message_id,mu.message_code,mu.status as message_status,
             mu.source_decision_id,mu.source_decision_number,
             d.id_decision,d.decision_number,d.estado_normalizado as decision_status
      from lf_ops.mensajes_ui mu
      left join public.lf_decisiones_gov d on d.decision_number=mu.source_decision_number
      where mu.message_id in (select message_id from message_ids)
    )
    select jsonb_build_object(
      'total_messages',count(*),
      'current_messages',count(*) filter(where message_status='VIGENTE' and decision_status='VIGENTE' and id_decision=source_decision_id and decision_number=source_decision_number),
      'stale_messages',count(*)-count(*) filter(where message_status='VIGENTE' and decision_status='VIGENTE' and id_decision=source_decision_id and decision_number=source_decision_number),
      'messages',coalesce(jsonb_agg(jsonb_build_object(
        'message_id',message_id,'message_code',message_code,'message_status',message_status,
        'source_decision_id',source_decision_id,'source_decision_number',source_decision_number,
        'decision_status',decision_status
      ) order by message_id),'[]'::jsonb)
    ) into v
    from resolved;
  else
    v:=p_override;
  end if;

  v_total:=coalesce((v->>'total_messages')::integer,0);
  v_current:=coalesce((v->>'current_messages')::integer,0);
  v_stale:=coalesce((v->>'stale_messages')::integer,greatest(v_total-v_current,0));

  if v_total=0 or v_current=0 then
    v_classification:='MISSING';
  elsif v_current=v_total and v_stale=0 then
    v_classification:='COMPLETE';
  else
    v_classification:='PARTIAL';
  end if;

  v_stage:=case when v_classification='COMPLETE' then
    jsonb_build_object('story','READY','implementation','READY','qa','READY','production','READY')
  else
    jsonb_build_object('story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED')
  end;

  return jsonb_build_object(
    'shadow_contract','INPUT_GOVERNANCE_SHADOW_UI_MESSAGES_CURRENTNESS_ORACLE_CANDIDATE_V1',
    'family_code','UI_MESSAGES','pantalla_id',p_pantalla_id,
    'implemented',true,'decisional',false,'comparison_only',true,'mutates_readiness',false,
    'classification',v_classification,
    'reason',case
      when v_classification='COMPLETE' then 'ALL_EFFECTIVELY_CONSUMED_MESSAGES_HAVE_CURRENT_SOURCE_DECISION'
      when v_classification='PARTIAL' then 'SOME_EFFECTIVELY_CONSUMED_MESSAGES_HAVE_STALE_OR_UNRESOLVED_SOURCE_DECISION'
      else 'NO_CURRENT_EFFECTIVELY_CONSUMED_MESSAGE_AUTHORITY' end,
    'stage_statuses',v_stage,
    'observed_authority',v,
    'source_refs',jsonb_build_array(
      jsonb_build_object('kind','MESSAGE_GRAPH_DIRECT_RESOLUTION','pantalla_id',p_pantalla_id),
      jsonb_build_object('kind','GOV_DECISION_CURRENTNESS','pantalla_id',p_pantalla_id)
    )
  );
end
$function$;

do $tests$
declare
  v jsonb;
  v_base jsonb;
  v_mut jsonb;
begin
  -- OBJECTIVE_OUTCOMES positive controls on both current holdout screens.
  v:=programacion.fn_input_governance_shadow_objective_oracle_candidate_v1(3,null);
  if v->>'classification'<>'COMPLETE' then raise exception 'S28_OBJECTIVE_ONB003_POSITIVE_FAIL:%',v; end if;
  if (select coverage_status from programacion.input_family_assessments where run_id=213 and family_code='OBJECTIVE_OUTCOMES')<>v->>'classification' then raise exception 'S28_OBJECTIVE_ONB003_COVERAGE_DIVERGENCE'; end if;

  v:=programacion.fn_input_governance_shadow_objective_oracle_candidate_v1(57,null);
  if v->>'classification'<>'COMPLETE' then raise exception 'S28_OBJECTIVE_ONB004_POSITIVE_FAIL:%',v; end if;
  if (select coverage_status from programacion.input_family_assessments where run_id=214 and family_code='OBJECTIVE_OUTCOMES')<>v->>'classification' then raise exception 'S28_OBJECTIVE_ONB004_COVERAGE_DIVERGENCE'; end if;
  v_base:=v->'observed_authority';
  if programacion.fn_input_governance_shadow_objective_oracle_candidate_v1(57,jsonb_set(v_base,'{objective}',to_jsonb(''::text),true))->>'classification'<>'MISSING' then raise exception 'S28_OBJECTIVE_BLANK_NOT_DETECTED'; end if;
  if programacion.fn_input_governance_shadow_objective_oracle_candidate_v1(57,jsonb_set(v_base,'{decision_status}',to_jsonb('SUPERADO'::text),true))->>'classification'<>'MISSING' then raise exception 'S28_OBJECTIVE_SUPERSEDED_NOT_DETECTED'; end if;
  if programacion.fn_input_governance_shadow_objective_oracle_candidate_v1(57,jsonb_set(v_base,'{decision_id}',to_jsonb('DEC-MISMATCH'::text),true))->>'classification'<>'MISSING' then raise exception 'S28_OBJECTIVE_DECISION_ID_MISMATCH_NOT_DETECTED'; end if;

  -- RUNTIME_CONFIG direct-source oracle: no source => MISSING, source without dedicated authority => PARTIAL.
  v:=programacion.fn_input_governance_shadow_runtime_config_oracle_candidate_v1(3,null);
  if v->>'classification'<>'MISSING' then raise exception 'S28_RUNTIME_ONB003_EXPECTED_MISSING:%',v; end if;
  if (select coverage_status from programacion.input_family_assessments where run_id=213 and family_code='RUNTIME_CONFIG')<>v->>'classification' then raise exception 'S28_RUNTIME_ONB003_COVERAGE_DIVERGENCE'; end if;

  v:=programacion.fn_input_governance_shadow_runtime_config_oracle_candidate_v1(57,null);
  if v->>'classification'<>'PARTIAL' then raise exception 'S28_RUNTIME_ONB004_EXPECTED_PARTIAL:%',v; end if;
  if (select coverage_status from programacion.input_family_assessments where run_id=214 and family_code='RUNTIME_CONFIG')<>v->>'classification' then raise exception 'S28_RUNTIME_ONB004_COVERAGE_DIVERGENCE'; end if;
  v_base:=v->'observed_authority';
  v_mut:=jsonb_set(v_base,'{direct_current_authority_count}',v_base->'direct_runtime_count',true);
  v_mut:=jsonb_set(v_mut,'{reused_technical_candidate_count}','0'::jsonb,true);
  if programacion.fn_input_governance_shadow_runtime_config_oracle_candidate_v1(57,v_mut)->>'classification'<>'PARTIAL' then raise exception 'S28_RUNTIME_FALSE_COMPLETE_FROM_LINEAGE_CURRENTNESS'; end if;
  v_mut:=jsonb_set(jsonb_set(v_base,'{direct_runtime_count}','0'::jsonb,true),'{reused_technical_count}','0'::jsonb,true);
  if programacion.fn_input_governance_shadow_runtime_config_oracle_candidate_v1(57,v_mut)->>'classification'<>'MISSING' then raise exception 'S28_RUNTIME_REMOVE_SOURCES_NOT_DETECTED'; end if;

  -- UI_MESSAGES exact consumed-message currentness controls.
  v:=programacion.fn_input_governance_shadow_ui_messages_oracle_candidate_v1(3,null);
  if v->>'classification'<>'COMPLETE' then raise exception 'S28_UI_MESSAGES_ONB003_POSITIVE_FAIL:%',v; end if;
  if (select coverage_status from programacion.input_family_assessments where run_id=213 and family_code='UI_MESSAGES')<>v->>'classification' then raise exception 'S28_UI_MESSAGES_ONB003_COVERAGE_DIVERGENCE'; end if;
  v_base:=v->'observed_authority';
  v_mut:=jsonb_set(jsonb_set(v_base,'{current_messages}','1'::jsonb,true),'{stale_messages}','1'::jsonb,true);
  if programacion.fn_input_governance_shadow_ui_messages_oracle_candidate_v1(3,v_mut)->>'classification'<>'PARTIAL' then raise exception 'S28_UI_MESSAGES_ONE_DECISION_MISSING_NOT_DETECTED'; end if;
  if programacion.fn_input_governance_shadow_ui_messages_oracle_candidate_v1(3,v_mut)->>'classification'<>'PARTIAL' then raise exception 'S28_UI_MESSAGES_ONE_DECISION_SUPERSEDED_NOT_DETECTED'; end if;
  v_mut:=jsonb_set(jsonb_set(v_base,'{current_messages}','0'::jsonb,true),'{stale_messages}','2'::jsonb,true);
  if programacion.fn_input_governance_shadow_ui_messages_oracle_candidate_v1(3,v_mut)->>'classification'<>'MISSING' then raise exception 'S28_UI_MESSAGES_NO_CURRENT_NOT_DETECTED'; end if;

  v:=programacion.fn_input_governance_shadow_ui_messages_oracle_candidate_v1(57,null);
  if v->>'classification'<>'PARTIAL' then raise exception 'S28_UI_MESSAGES_ONB004_FALSE_COMPLETE_NOT_DETECTED:%',v; end if;
  if (select coverage_status from programacion.input_family_assessments where run_id=214 and family_code='UI_MESSAGES')<>'COMPLETE' then raise exception 'S28_UI_MESSAGES_ONB004_LIVE_BASELINE_CHANGED'; end if;
  if v->'stage_statuses'->>'story'<>'READY' or v->'stage_statuses'->>'implementation'<>'NOT_READY' or v->'stage_statuses'->>'qa'<>'BLOCKED' or v->'stage_statuses'->>'production'<>'BLOCKED' then raise exception 'S28_UI_MESSAGES_STAGE_EFFECT_MISMATCH:%',v; end if;
  v_base:=v->'observed_authority';
  v_mut:=jsonb_set(jsonb_set(v_base,'{current_messages}','3'::jsonb,true),'{stale_messages}','0'::jsonb,true);
  if programacion.fn_input_governance_shadow_ui_messages_oracle_candidate_v1(57,v_mut)->>'classification'<>'COMPLETE' then raise exception 'S28_UI_MESSAGES_EXPLICIT_CURRENT_REBIND_METAMORPHIC_FAIL'; end if;
end
$tests$;

select jsonb_build_object(
  'status','PASS_ROLLBACK_ONLY',
  'frozen_holdout_pairs_total',6,
  'previously_demonstrated_independent_oracle_patterns',2,
  'new_independent_oracle_patterns_demonstrated',3,
  'combined_independent_oracle_patterns_demonstrated',5,
  'demonstrated_families',jsonb_build_array('APPLICABILITY_READINESS','ROLLOUT_PRODUCTION_GATES','OBJECTIVE_OUTCOMES','RUNTIME_CONFIG','UI_MESSAGES'),
  'remaining_blocked_family','I18N_FORMATS',
  'remaining_blocker','POSITIVE_APPLICABILITY_AUTHORITY_ABSENT_FOR_CLIENT_ONBOARDING',
  'ui_messages_onb004_false_complete_detected',true,
  'live_runtime_changed',false,
  'claim_ceiling','PREVALIDATION_ONLY_5_OF_6_INDEPENDENT_ORACLE_PATTERNS_NO_IGC_CLOSURE_NO_LIVE_ORACLE'
) as receipt;

rollback;

select jsonb_build_object(
  'status','PASS_POST_ROLLBACK_READBACK',
  'candidate_function_residue',(
    select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='programacion' and p.proname in (
      'fn_input_governance_shadow_objective_oracle_candidate_v1',
      'fn_input_governance_shadow_runtime_config_oracle_candidate_v1',
      'fn_input_governance_shadow_ui_messages_oracle_candidate_v1'
    )
  )
) as post_rollback;