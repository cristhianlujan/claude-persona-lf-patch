-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M2.1 / PAULO-017
-- Residual IG only: declarative family -> source-kind mapping.
-- Generic source identity remains owned by T-SOURCE / SOURCE_RESOLUTION_POLICY.
-- No runtime deploy, no production activation.

begin;

do $pre$
declare
  v_count integer;
  v_md5 text;
begin
  select count(*), min(md5(especificacion::text))
    into v_count,v_md5
  from programacion.contratos
  where id=46 and version_id=19
    and contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
    and fail_closed;
  if v_count<>1 then raise exception 'M2_1_FAMILY_REGISTRY_CARDINALITY:%',v_count; end if;
  if v_md5 is distinct from '07858e213bf984c078efdab01dad7139' then
    raise exception 'M2_1_FAMILY_REGISTRY_PREIMAGE_DRIFT:%',v_md5;
  end if;

  if md5(pg_get_functiondef('programacion.fn_input_resolve_source_ref_v510(jsonb,integer,bigint)'::regprocedure))
       <> 'ae48babb67fcbd4f60937932dc8d8f51' then
    raise exception 'M2_1_RESOLVER_V510_PREIMAGE_DRIFT';
  end if;
  if md5(pg_get_functiondef('programacion.fn_input_resolve_source_ref(jsonb,integer,bigint)'::regprocedure))
       <> '4bcc3bfff640ee86005389835f61389c' then
    raise exception 'M2_1_RESOLVER_WRAPPER_PREIMAGE_DRIFT';
  end if;
  if not exists(
    select 1 from public.lf_policy_versions
    where policy_code='POL-LF-SOURCE-RESOLUTION' and status='ACTIVE'
  ) then
    raise exception 'M2_1_T_SOURCE_POLICY_NOT_ACTIVE';
  end if;
end
$pre$;

do $materialize$
declare
  v_spec jsonb;
  v_family text;
  v_mapping jsonb;
  v_family_count integer:=0;
  v_payload constant jsonb := '{"ACCESSIBILITY":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"ACTIONS":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"ANALYTICS":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"API_DATA_CONTRACT":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"APPLICABILITY_READINESS":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["EKB_DECISION_SET","EKB_PREVENTION_SET","SCREEN_CANONICAL_GRAPH","CAPABILITY_ABSENCE","SECURITY_POLICY_SET","ROUTE_SET","SCREEN_STATE_SET","TRANSITION_SET"]},"ASSETS_ICONS":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"AUDIT":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"BROWSER_PLATFORM":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"CONFLICT_PRECEDENCE":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["EKB_DECISION_SET","EKB_PREVENTION_SET"]},"CONTEXT_BUDGET_RETRIEVAL_POLICY":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["CONTRACT","SCREEN_CANONICAL_GRAPH"]},"DEPENDENCIES":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"DESIGN_SYSTEM":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"EKB":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["EKB_ERROR_SET","EKB_PREVENTION_SET","EKB_DECISION_SET"]},"ERRORS":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH","ERROR_SET"]},"FEATURE_FLAGS":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["CAPABILITY_ABSENCE","SCREEN_CANONICAL_GRAPH"]},"FIELDS":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"FORCED_COLORS_CONTRAST":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"FRESHNESS_INVALIDATION":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["EKB_DECISION_SET","EKB_PREVENTION_SET"]},"I18N_FORMATS":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["CAPABILITY_ABSENCE","SCREEN_CANONICAL_GRAPH"]},"IDEMPOTENCY_CONCURRENCY":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"LOADING_EMPTY_ERROR_STATES":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"MFA_OTP_SSO":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"NEGATIVE_REQUIREMENTS":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["EKB_DECISION_SET","EKB_PREVENTION_SET"]},"OBJECTIVE_OUTCOMES":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"OBSERVABILITY":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"PERFORMANCE":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"PERMISSIONS":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH","RULE"]},"PRIVACY_PII":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"PROFILES":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"RATE_LIMIT":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"REDUCED_MOTION":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"RESPONSIVE":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"ROLLOUT_PRODUCTION_GATES":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"ROUTING_NAVIGATION":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["ROUTE_SET","SCREEN_CANONICAL_GRAPH"]},"RUNTIME_CONFIG":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SECURITY_POLICY_SET","SCREEN_CANONICAL_GRAPH"]},"SCREEN_IDENTITY":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN","SCREEN_CANONICAL_GRAPH"]},"SECURITY":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SECURITY_POLICY_SET","SCREEN_CANONICAL_GRAPH"]},"SESSION":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"SOURCE_AUTHORITY_PROVENANCE":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["EKB_DECISION_SET","EKB_PREVENTION_SET"]},"STATES":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_STATE_SET"]},"TESTING_OBLIGATIONS":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"THEME_LIGHT_DARK_SYSTEM":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"TIMEOUT_RETRY":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH"]},"TRANSITIONS":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_STATE_SET","TRANSITION_SET"]},"UI_MESSAGES":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH","MESSAGE_SET"]},"VALIDATIONS":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["SCREEN_CANONICAL_GRAPH","SECURITY_POLICY_SET"]},"VISUAL_EVIDENCE":{"schema_version":"input-family-source-kind-mapping/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","allowed_kinds":["CURRENT_VISUAL_ARTIFACT","SCREEN_CANONICAL_GRAPH"]}}'::jsonb;
  v_catalog constant jsonb := '{"schema_version":"input-source-kind-identity-catalog/v1","identity_authority":"SOURCE_RESOLUTION_POLICY","resolution_policy":"POL-LF-SOURCE-RESOLUTION","transversal_owner":"T-SOURCE","no_generic_identity_engine":true,"kinds":{"SCREEN":{"required_ref_fields":["pantalla_id"],"context_fields":["pantalla_id"],"resolver":"fn_input_resolve_source_ref_v510","adapter":"SCREEN_BY_CONTEXT"},"SCREEN_RULE_SET":{"required_ref_fields":["pantalla_id"],"context_fields":["pantalla_id"],"resolver":"fn_input_resolve_source_ref_v510","adapter":"SCREEN_RULE_SET_BY_CONTEXT"},"RULE":{"required_ref_fields":["codigo"],"context_fields":[],"resolver":"fn_input_resolve_source_ref_v510","adapter":"RULE_BY_CODE"},"ROUTE_SET":{"required_ref_fields":["ids"],"context_fields":[],"resolver":"fn_input_resolve_source_ref_v510","adapter":"ROUTE_SET_BY_IDS"},"SECURITY_POLICY_SET":{"required_ref_fields":["ids"],"context_fields":[],"resolver":"fn_input_resolve_source_ref_v510","adapter":"SECURITY_POLICY_SET_BY_IDS"},"TRANSITION_SET":{"required_ref_fields":["ids"],"context_fields":[],"resolver":"fn_input_resolve_source_ref_v510","adapter":"TRANSITION_SET_BY_IDS"},"SCREEN_STATE_SET":{"required_ref_fields":["pantalla_id"],"context_fields":["pantalla_id"],"resolver":"fn_input_resolve_source_ref_v510","adapter":"SCREEN_STATE_SET_BY_CONTEXT"},"CURRENT_VISUAL_ARTIFACT":{"required_ref_fields":["pantalla_id"],"context_fields":["pantalla_id"],"resolver":"fn_input_resolve_source_ref_v510","adapter":"CURRENT_VISUAL_ARTIFACT_BY_CONTEXT"},"EKB_ERROR_SET":{"required_ref_fields":["codes"],"context_fields":[],"resolver":"fn_input_resolve_source_ref_v510","adapter":"EKB_ERROR_SET_BY_CODES"},"EKB_PREVENTION_SET":{"required_ref_fields":["codes"],"context_fields":[],"resolver":"fn_input_resolve_source_ref_v510","adapter":"EKB_PREVENTION_SET_BY_CODES"},"EKB_DECISION_SET":{"required_ref_fields":["adrs"],"context_fields":[],"resolver":"fn_input_resolve_source_ref_v510","adapter":"EKB_DECISION_SET_BY_ADRS"},"CONTRACT":{"required_ref_fields":["codigo"],"context_fields":["version_id"],"resolver":"fn_input_resolve_source_ref_v510","adapter":"CONTRACT_BY_CODE_VERSION_CONTEXT"},"CAPABILITY_ABSENCE":{"required_ref_fields":["capability","pantalla_id"],"context_fields":["pantalla_id"],"resolver":"fn_input_resolve_source_ref_v510","adapter":"CAPABILITY_ABSENCE_BY_CONTEXT"},"SCREEN_CANONICAL_GRAPH":{"required_ref_fields":["pantalla_id"],"context_fields":["version_id"],"resolver":"fn_input_resolve_source_ref","adapter":"SCREEN_CANONICAL_GRAPH_BY_EXPLICIT_SCREEN"},"ERROR_SET":{"required_ref_fields":["ids"],"context_fields":[],"resolver":"fn_input_resolve_source_ref","adapter":"ERROR_SET_BY_IDS"},"MESSAGE_SET":{"required_ref_fields":["ids"],"context_fields":[],"resolver":"fn_input_resolve_source_ref","adapter":"MESSAGE_SET_BY_IDS"}}}'::jsonb;
begin
  select especificacion into v_spec
  from programacion.contratos
  where id=46 for update;

  if (select count(*) from jsonb_object_keys(v_spec->'families'))<>47 then
    raise exception 'M2_1_FAMILY_UNIVERSE_DRIFT';
  end if;
  if (select count(*) from jsonb_object_keys(v_catalog->'kinds'))<>16 then
    raise exception 'M2_1_KIND_CATALOG_COUNT';
  end if;

  for v_family,v_mapping in
    select key,value from jsonb_each(v_payload)
  loop
    if not (v_spec->'families' ? v_family) then
      raise exception 'M2_1_FAMILY_NOT_IN_REGISTRY:%',v_family;
    end if;
    v_spec:=jsonb_set(
      v_spec,
      array['families',v_family,'source_kind_mapping_v1'],
      v_mapping,
      true
    );
    v_family_count:=v_family_count+1;
  end loop;
  if v_family_count<>47 then raise exception 'M2_1_MAPPING_COUNT:%',v_family_count; end if;

  v_spec:=jsonb_set(v_spec,'{source_kind_identity_catalog_v1}',v_catalog,true);
  v_spec:=jsonb_set(v_spec,'{source_kind_mapping_contract_version}','"M2.1"'::jsonb,true);
  v_spec:=jsonb_set(v_spec,'{source_kind_mapping_family_count}','47'::jsonb,true);
  v_spec:=jsonb_set(v_spec,'{source_kind_identity_kind_count}','16'::jsonb,true);

  update programacion.contratos
  set especificacion=v_spec
  where id=46;
end
$materialize$;

create or replace function programacion.fn_input_source_kind_identity_v1(
  p_kind text,
  p_version_id bigint default 19
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
  select c.especificacion->'source_kind_identity_catalog_v1'->'kinds'->p_kind
  from programacion.contratos c
  where c.version_id=p_version_id
    and c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
    and c.fail_closed
  order by c.id desc
  limit 1
$function$;

create or replace function programacion.fn_input_family_source_kind_allowed_v1(
  p_family_code text,
  p_kind text,
  p_version_id bigint default 19
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
  select coalesce(
    (c.especificacion->'families'->p_family_code->'source_kind_mapping_v1'->'allowed_kinds') ? p_kind,
    false
  )
  from programacion.contratos c
  where c.version_id=p_version_id
    and c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
    and c.fail_closed
  order by c.id desc
  limit 1
$function$;

create or replace function programacion.fn_guard_input_family_source_kind_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_version_id bigint;
  v_ref jsonb;
  v_kind text;
  v_identity jsonb;
  v_field text;
begin
  select r.version_id into v_version_id
  from programacion.input_readiness_runs r
  where r.id=new.run_id;
  if v_version_id is null then
    raise exception 'INPUT_FAMILY_SOURCE_KIND_RUN_NOT_FOUND:%',new.run_id;
  end if;
  if jsonb_typeof(new.source_refs)<>'array' then
    raise exception 'INPUT_FAMILY_SOURCE_KIND_REFS_NOT_ARRAY:%',new.family_code;
  end if;

  for v_ref in select value from jsonb_array_elements(new.source_refs)
  loop
    v_kind:=nullif(v_ref->>'kind','');
    if v_kind is null then
      raise exception 'INPUT_FAMILY_SOURCE_KIND_MISSING:%',new.family_code;
    end if;
    if not programacion.fn_input_family_source_kind_allowed_v1(new.family_code,v_kind,v_version_id) then
      raise exception 'INPUT_FAMILY_SOURCE_KIND_NOT_ALLOWED:%:%',new.family_code,v_kind;
    end if;
    v_identity:=programacion.fn_input_source_kind_identity_v1(v_kind,v_version_id);
    if jsonb_typeof(v_identity)<>'object' then
      raise exception 'INPUT_SOURCE_KIND_IDENTITY_UNDECLARED:%',v_kind;
    end if;
    if v_identity->>'resolver' not in ('fn_input_resolve_source_ref','fn_input_resolve_source_ref_v510') then
      raise exception 'INPUT_SOURCE_KIND_IDENTITY_RESOLVER_INVALID:%',v_kind;
    end if;
    for v_field in select value from jsonb_array_elements_text(v_identity->'required_ref_fields')
    loop
      if not (v_ref ? v_field) then
        raise exception 'INPUT_SOURCE_KIND_REQUIRED_FIELD_MISSING:%:%:%',new.family_code,v_kind,v_field;
      end if;
    end loop;
  end loop;
  return new;
end
$function$;

drop trigger if exists trg_input_family_source_kind_v1
on programacion.input_family_assessments;
create trigger trg_input_family_source_kind_v1
before insert or update of source_refs,family_code,run_id
on programacion.input_family_assessments
for each row execute function programacion.fn_guard_input_family_source_kind_v1();

do $post$
declare
  v_count integer;
begin
  select count(*) into v_count
  from jsonb_object_keys((
    select especificacion->'source_kind_identity_catalog_v1'->'kinds'
    from programacion.contratos where id=46
  ));
  if v_count<>16 then raise exception 'M2_1_POST_KIND_COUNT:%',v_count; end if;

  select count(*) into v_count
  from jsonb_each((
    select especificacion->'families'
    from programacion.contratos where id=46
  )) f
  where jsonb_typeof(f.value->'source_kind_mapping_v1')='object';
  if v_count<>47 then raise exception 'M2_1_POST_FAMILY_MAPPING_COUNT:%',v_count; end if;

  if not programacion.fn_input_family_source_kind_allowed_v1('PERMISSIONS','RULE',19)
     or programacion.fn_input_family_source_kind_allowed_v1('PROFILES','SCREEN_RULE_SET',19)
     or not programacion.fn_input_family_source_kind_allowed_v1('SOURCE_AUTHORITY_PROVENANCE','EKB_DECISION_SET',19)
     or programacion.fn_input_family_source_kind_allowed_v1('SOURCE_AUTHORITY_PROVENANCE','CONTRACT',19)
  then
    raise exception 'M2_1_POS_NEG_MAPPING_SELFTEST';
  end if;

  select count(*) into v_count
  from programacion.input_family_assessments a
  join programacion.input_readiness_runs r on r.id=a.run_id
  cross join lateral jsonb_array_elements(a.source_refs) ref
  where r.status='COMPLETED'
    and r.invalidated_at is null
    and programacion.fn_input_readiness_run_is_current(r.id)
    and not programacion.fn_input_family_source_kind_allowed_v1(
      a.family_code,ref->>'kind',r.version_id
    );
  if v_count<>0 then raise exception 'M2_1_CURRENT_SOURCE_REF_MAPPING_REGRESSION:%',v_count; end if;
end
$post$;

comment on function programacion.fn_input_family_source_kind_allowed_v1(text,text,bigint) is
'M2.1 residual IG mapping only. T-SOURCE / SOURCE_RESOLUTION_POLICY owns generic source identity and resolution.';
comment on function programacion.fn_input_source_kind_identity_v1(text,bigint) is
'Declarative adapter metadata for the 16 existing Input Governance source kinds. Does not resolve identity; resolution remains T-SOURCE-owned.';

commit;
