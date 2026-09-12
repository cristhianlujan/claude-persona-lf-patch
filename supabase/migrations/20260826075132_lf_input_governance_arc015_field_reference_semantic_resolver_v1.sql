-- ARC-015 / AUD-040: resolve explicit *_field_code authority before declaring FIELDS/VALIDATIONS missing.
-- Scope is fail-closed and narrow: existing canonical graph fields retain the prior classifier path.

create or replace function programacion.fn_input_governance_field_reference_probe_v1(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
declare
  v_graph jsonb;
  v_graph_field_count integer:=0;
  v_ref_count integer:=0;
  v_distinct_field_count integer:=0;
  v_unresolved integer:=0;
  v_inactive integer:=0;
  v_field_metadata_missing integer:=0;
  v_required_without_validation integer:=0;
  v_active_validation_total integer:=0;
  v_validation_metadata_missing integer:=0;
  v_refs jsonb:='[]'::jsonb;
  v_level text:='MISSING';
  v_blocker text:=null;
begin
  if p_family_code not in ('FIELDS','VALIDATIONS') then
    return jsonb_build_object('handled',false,'family_code',p_family_code);
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
  v_graph_field_count:=jsonb_array_length(coalesce(v_graph->'canonical_contract'->'fields','[]'::jsonb));

  -- Preserve the existing canonical graph path when it already resolves fields.
  if v_graph_field_count>0 then
    return jsonb_build_object(
      'handled',false,
      'family_code',p_family_code,
      'reason','CANONICAL_GRAPH_FIELDS_ALREADY_RESOLVED',
      'graph_field_count',v_graph_field_count
    );
  end if;

  with recursive seed as (
    select
      r.value->>'rule_code' as rule_code,
      r.value as rule,
      array[r.value->>'rule_code']::text[] as path
    from jsonb_array_elements(coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb)) r(value)
    where r.value->>'status'='VIGENTE'
  ), walk as (
    select * from seed
    union all
    select
      rr.codigo,
      jsonb_build_object(
        'rule_code',rr.codigo,
        'status',rr.estado,
        'category',rr.categoria,
        'title',rr.titulo,
        'description',rr.descripcion,
        'config',rr.valor_config
      ),
      w.path||rr.codigo
    from walk w
    cross join lateral jsonb_array_elements_text(
      case
        when jsonb_typeof(w.rule->'config'->'reuse_rules')='array' then w.rule->'config'->'reuse_rules'
        else '[]'::jsonb
      end
    ) rc(value)
    join lf_ops.reglas rr on rr.codigo=rc.value and rr.estado='VIGENTE'
    where not rr.codigo=any(w.path)
      and cardinality(w.path)<12
  ), effective_rules as (
    select distinct on (rule_code) rule_code,rule
    from walk
    order by rule_code
  ), refs as (
    select er.rule_code,e.key as ref_key,e.value as field_code
    from effective_rules er
    cross join lateral jsonb_each_text(
      case when jsonb_typeof(er.rule->'config')='object' then er.rule->'config' else '{}'::jsonb end
    ) e
    where e.key ~ '_field_code$'
  ), resolved as (
    select
      r.rule_code,r.ref_key,r.field_code,
      c.id as field_id,c.estado as field_status,c.tipo_dato,c.es_requerido,c.es_sensible,
      c.source_type,c.pii_classification,c.masking_rule,c.retention_class,c.analytics_allowed,c.logs_allowed,
      coalesce(v.active_validation_count,0) as active_validation_count,
      coalesce(v.validation_metadata_missing,0) as validation_metadata_missing,
      coalesce(v.validations,'[]'::jsonb) as validations
    from refs r
    left join lf_ops.campos c on c.codigo=r.field_code
    left join lateral (
      select
        count(*) filter(where cv.estado='ACTIVO')::integer as active_validation_count,
        count(*) filter(where cv.estado='ACTIVO' and (
          cv.tipo_validacion is null or cv.validation_level is null or cv.blocking is null
        ))::integer as validation_metadata_missing,
        coalesce(jsonb_agg(
          jsonb_build_object(
            'validation_code',cv.codigo,
            'status',cv.estado,
            'validation_type',cv.tipo_validacion,
            'validation_level',cv.validation_level,
            'blocking',cv.blocking
          ) order by cv.validation_order nulls last,cv.id
        ) filter(where cv.estado='ACTIVO'),'[]'::jsonb) as validations
      from lf_ops.campos_validaciones cv
      where cv.campo_id=c.id
    ) v on true
  )
  select
    count(*)::integer,
    count(distinct field_code)::integer,
    count(*) filter(where field_id is null)::integer,
    count(*) filter(where field_id is not null and field_status<>'ACTIVO')::integer,
    count(*) filter(where field_id is not null and (
      tipo_dato is null or es_requerido is null or es_sensible is null or source_type is null
      or pii_classification is null or retention_class is null or analytics_allowed is null or logs_allowed is null
      or (es_sensible and masking_rule is null)
    ))::integer,
    count(*) filter(where coalesce(es_requerido,false) and active_validation_count=0)::integer,
    coalesce(sum(active_validation_count),0)::integer,
    coalesce(sum(validation_metadata_missing),0)::integer,
    coalesce(jsonb_agg(jsonb_build_object(
      'rule_code',rule_code,
      'reference_key',ref_key,
      'field_code',field_code,
      'field_status',coalesce(field_status,'ABSENT'),
      'field_type',tipo_dato,
      'required',es_requerido,
      'sensitive',es_sensible,
      'source_type',source_type,
      'pii_classification',pii_classification,
      'masking_rule',masking_rule,
      'retention_class',retention_class,
      'analytics_allowed',analytics_allowed,
      'logs_allowed',logs_allowed,
      'active_validations',validations
    ) order by rule_code,ref_key),'[]'::jsonb)
  into
    v_ref_count,v_distinct_field_count,v_unresolved,v_inactive,v_field_metadata_missing,
    v_required_without_validation,v_active_validation_total,v_validation_metadata_missing,v_refs
  from resolved;

  if v_ref_count=0 then
    return jsonb_build_object(
      'handled',false,
      'family_code',p_family_code,
      'reason','NO_EXPLICIT_FIELD_REFERENCE_RESOLVED'
    );
  end if;

  if v_unresolved>0 then
    v_level:='PARTIAL'; v_blocker:='EXPLICIT_FIELD_REFERENCE_UNRESOLVED';
  elsif v_inactive>0 then
    v_level:='PARTIAL'; v_blocker:='EXPLICIT_FIELD_REFERENCE_NONCURRENT';
  elsif v_field_metadata_missing>0 then
    v_level:='PARTIAL'; v_blocker:='EXPLICIT_FIELD_CATALOG_METADATA_INCOMPLETE';
  elsif p_family_code='VALIDATIONS' and v_required_without_validation>0 then
    v_level:='PARTIAL'; v_blocker:='REQUIRED_FIELD_VALIDATION_MISSING';
  elsif p_family_code='VALIDATIONS' and v_validation_metadata_missing>0 then
    v_level:='PARTIAL'; v_blocker:='FIELD_VALIDATION_METADATA_INCOMPLETE';
  else
    v_level:='COMPLETE'; v_blocker:=null;
  end if;

  return jsonb_build_object(
    'handled',true,
    'family_code',p_family_code,
    'level',v_level,
    'blocker_code',v_blocker,
    'probe',jsonb_build_object(
      'resolution_contract','EXPLICIT_FIELD_REFERENCE_RESOLUTION_V1',
      'reference_discovery','EXPLICIT_CONFIG_KEY_SUFFIX_NOT_SEMANTIC_SIMILARITY',
      'canonical_graph_field_count',v_graph_field_count,
      'explicit_reference_count',v_ref_count,
      'distinct_field_count',v_distinct_field_count,
      'unresolved_field_count',v_unresolved,
      'inactive_field_count',v_inactive,
      'field_metadata_missing_count',v_field_metadata_missing,
      'required_field_without_validation_count',v_required_without_validation,
      'active_validation_total',v_active_validation_total,
      'validation_metadata_missing_count',v_validation_metadata_missing,
      'resolved_references',v_refs
    )
  );
end;
$function$;

revoke all on function programacion.fn_input_governance_field_reference_probe_v1(integer,text,bigint) from public,anon,authenticated;
grant execute on function programacion.fn_input_governance_field_reference_probe_v1(integer,text,bigint) to service_role;

create or replace function programacion.fn_input_governance_semantic_probe_v3(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
declare
  v_base jsonb;
  v_field_probe jsonb;
  v_graph jsonb;
  v_rules jsonb;
  v_branch_count integer:=0;
  v_outcome_count integer:=0;
  v_commit_count integer:=0;
  v_post_success_count integer:=0;
  v_outcome_integrity_failures integer:=0;
  v_action_rule_codes jsonb:='[]'::jsonb;
begin
  v_base:=programacion.fn_input_governance_semantic_probe_v2(p_pantalla_id,p_family_code,p_version_id);

  if p_family_code in ('FIELDS','VALIDATIONS') then
    v_field_probe:=programacion.fn_input_governance_field_reference_probe_v1(p_pantalla_id,p_family_code,p_version_id);
    if coalesce((v_field_probe->>'handled')::boolean,false) then
      return v_field_probe;
    end if;
    return v_base;
  end if;

  if p_family_code<>'ACTIONS' then
    return v_base;
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
  v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_branch_count
  from direct_vigente_rules d
  where coalesce((d.rule->'config'->>'ask_old_phone_access')::boolean,false)=true
    and nullif(d.rule->'config'->>'old_phone_accessible','') is not null
    and nullif(d.rule->'config'->>'old_phone_unavailable','') is not null;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_outcome_count
  from direct_vigente_rules d
  where jsonb_typeof(d.rule->'config'->'allowed_outcomes')='array'
    and jsonb_array_length(d.rule->'config'->'allowed_outcomes')>0
    and jsonb_typeof(d.rule->'config'->'outcomes')='object';

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
      and jsonb_typeof(r.value->'config'->'allowed_outcomes')='array'
      and jsonb_array_length(r.value->'config'->'allowed_outcomes')>0
      and jsonb_typeof(r.value->'config'->'outcomes')='object'
  ), allowed as (
    select d.rule, a.value as outcome_code
    from direct_vigente_rules d
    cross join lateral jsonb_array_elements_text(d.rule->'config'->'allowed_outcomes') a(value)
  )
  select count(*) into v_outcome_integrity_failures
  from allowed a
  where not (a.rule->'config'->'outcomes' ? a.outcome_code)
     or nullif(a.rule->'config'->'outcomes'->a.outcome_code->>'rebind','') is null
     or nullif(a.rule->'config'->'outcomes'->a.outcome_code->>'operational_access','') is null;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_commit_count
  from direct_vigente_rules d
  where d.rule->'config'->>'atomic_commit'='REQUIRED'
    and d.rule->'config'->>'operational_access_before_commit'='DENY'
    and jsonb_typeof(d.rule->'config'->'accepted_recovery_proofs')='array'
    and jsonb_array_length(d.rule->'config'->'accepted_recovery_proofs')>0;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_post_success_count
  from direct_vigente_rules d
  where nullif(d.rule->'config'->>'success_outcome','') is not null
    and nullif(d.rule->'config'->>'post_auth_route','') is not null
    and nullif(d.rule->'config'->>'invalid_session_action','') is not null
    and nullif(d.rule->'config'->>'required_rebind_outcome','') is not null;

  select coalesce(jsonb_agg(distinct r.value->>'rule_code' order by r.value->>'rule_code'),'[]'::jsonb)
    into v_action_rule_codes
  from jsonb_array_elements(v_rules) r(value)
  where r.value->>'status'='VIGENTE'
    and (
      coalesce((r.value->'config'->>'ask_old_phone_access')::boolean,false)=true
      or jsonb_typeof(r.value->'config'->'allowed_outcomes')='array'
      or r.value->'config'->>'atomic_commit'='REQUIRED'
      or nullif(r.value->'config'->>'success_outcome','') is not null
    );

  if v_branch_count>0
     and v_outcome_count>0
     and v_outcome_integrity_failures=0
     and v_commit_count>0
     and v_post_success_count>0 then
    return jsonb_build_object(
      'handled',true,
      'family_code',p_family_code,
      'level','COMPLETE',
      'blocker_code',null,
      'probe',jsonb_build_object(
        'resolution_contract','STRUCTURED_ACTION_TOPOLOGY_RESOLUTION_V3',
        'branch_contract_count',v_branch_count,
        'outcome_contract_count',v_outcome_count,
        'outcome_integrity_failures',v_outcome_integrity_failures,
        'atomic_commit_contract_count',v_commit_count,
        'post_success_contract_count',v_post_success_count,
        'action_rule_codes',v_action_rule_codes,
        'pending_provider_copy_visual_does_not_authorize_missing_action_dimensions',true
      )
    );
  end if;

  return v_base;
end;
$function$;

-- Fail closed negative regression: screens whose canonical graph already has fields must preserve the prior path.
do $block$
declare
  v_screen integer;
  v_family text;
  v_graph_count integer;
  v_probe jsonb;
begin
  foreach v_screen in array array[1,2,3] loop
    select jsonb_array_length(coalesce(programacion.fn_input_screen_canonical_graph(v_screen,19)->'canonical_contract'->'fields','[]'::jsonb)) into v_graph_count;
    if v_graph_count<=0 then raise exception 'ARC015_REGRESSION_FIXTURE_GRAPH_FIELDS_MISSING:%',v_screen; end if;
    foreach v_family in array array['FIELDS','VALIDATIONS'] loop
      v_probe:=programacion.fn_input_governance_field_reference_probe_v1(v_screen,v_family,19);
      if coalesce((v_probe->>'handled')::boolean,true) then
        raise exception 'ARC015_REGRESSION_EXISTING_GRAPH_PATH_CHANGED:%:%',v_screen,v_family;
      end if;
    end loop;
  end loop;

  foreach v_family in array array['FIELDS','VALIDATIONS'] loop
    v_probe:=programacion.fn_input_governance_field_reference_probe_v1(58,v_family,19);
    if not coalesce((v_probe->>'handled')::boolean,false)
       or v_probe->>'level'<>'COMPLETE'
       or coalesce((v_probe->'probe'->>'explicit_reference_count')::integer,0)<>1
       or coalesce((v_probe->'probe'->>'unresolved_field_count')::integer,-1)<>0
       or coalesce((v_probe->'probe'->>'field_metadata_missing_count')::integer,-1)<>0 then
      raise exception 'ARC015_REC001_FIELD_REFERENCE_REGRESSION_FAILED:%:%',v_family,v_probe;
    end if;
  end loop;

  v_probe:=programacion.fn_input_governance_field_reference_probe_v1(58,'VALIDATIONS',19);
  if coalesce((v_probe->'probe'->>'required_field_without_validation_count')::integer,-1)<>0
     or coalesce((v_probe->'probe'->>'active_validation_total')::integer,0)<>5
     or coalesce((v_probe->'probe'->>'validation_metadata_missing_count')::integer,-1)<>0 then
    raise exception 'ARC015_REC001_VALIDATION_REGRESSION_FAILED:%',v_probe;
  end if;
end;
$block$;
