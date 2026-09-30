alter table programacion.input_readiness_runs
  alter column source_snapshot_sha256 drop not null,
  add column if not exists contract_version integer not null default 1,
  add column if not exists source_manifest jsonb not null default '[]'::jsonb,
  add column if not exists source_observed_at timestamptz,
  add column if not exists curator_component_id bigint,
  add column if not exists validator_component_id bigint;

alter table programacion.input_readiness_runs alter column contract_version set default 2;

alter table programacion.input_readiness_runs
  add constraint input_readiness_runs_contract_version_check check (contract_version in (1,2)),
  add constraint input_readiness_runs_source_manifest_check check (jsonb_typeof(source_manifest)='array'),
  add constraint input_readiness_runs_curator_component_id_fkey foreign key (curator_component_id) references programacion.componentes(id),
  add constraint input_readiness_runs_validator_component_id_fkey foreign key (validator_component_id) references programacion.componentes(id);

create or replace function programacion.fn_input_resolve_source_ref(
  p_ref jsonb,
  p_pantalla_id integer,
  p_version_id bigint
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, programacion, lf_ops, transversal, storage
as $$
declare
  v_kind text := p_ref->>'kind';
  v_observed jsonb;
  v_code text;
  v_codes text[];
  v_ids bigint[];
  v_expected integer;
  v_actual integer;
  v_capability text;
  v_relations jsonb := '[]'::jsonb;
  v_rules jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_ref) <> 'object' or coalesce(v_kind,'')='' then
    raise exception 'INVALID_STRUCTURED_SOURCE_REF';
  end if;

  case v_kind
    when 'SCREEN' then
      select to_jsonb(p) into v_observed from lf_ops.pantallas p where p.id=p_pantalla_id;
      if v_observed is null then raise exception 'SOURCE_REF_UNRESOLVED:SCREEN:%',p_pantalla_id; end if;

    when 'SCREEN_RULE_SET' then
      select jsonb_build_object(
        'screen',to_jsonb(p),
        'rules',coalesce((
          select jsonb_agg(jsonb_build_object('link',to_jsonb(rp),'rule',to_jsonb(r)) order by r.id)
          from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
          where rp.pantalla_id=p.id
        ),'[]'::jsonb)
      ) into v_observed
      from lf_ops.pantallas p where p.id=p_pantalla_id;
      if v_observed is null then raise exception 'SOURCE_REF_UNRESOLVED:SCREEN_RULE_SET:%',p_pantalla_id; end if;

    when 'RULE' then
      v_code:=p_ref->>'codigo';
      select to_jsonb(r) into v_observed from lf_ops.reglas r where r.codigo=v_code;
      if v_observed is null then raise exception 'SOURCE_REF_UNRESOLVED:RULE:%',coalesce(v_code,'NULL'); end if;

    when 'ROUTE_SET' then
      select array_agg(x::bigint order by x::bigint) into v_ids from jsonb_array_elements_text(p_ref->'ids') x;
      if v_ids is null or cardinality(v_ids)=0 then raise exception 'INVALID_ROUTE_SET_REF'; end if;
      v_expected:=cardinality(v_ids);
      select count(*),jsonb_agg(to_jsonb(r) order by r.route_id) into v_actual,v_observed from lf_ops.rutas r where r.route_id=any(v_ids);
      if v_actual<>v_expected then raise exception 'SOURCE_REF_UNRESOLVED:ROUTE_SET expected=% actual=%',v_expected,v_actual; end if;

    when 'SECURITY_POLICY_SET' then
      select array_agg(x::bigint order by x::bigint) into v_ids from jsonb_array_elements_text(p_ref->'ids') x;
      if v_ids is null or cardinality(v_ids)=0 then raise exception 'INVALID_SECURITY_POLICY_SET_REF'; end if;
      v_expected:=cardinality(v_ids);
      select count(*),jsonb_agg(to_jsonb(s) order by s.security_policy_id) into v_actual,v_observed from lf_ops.politicas_seguridad s where s.security_policy_id=any(v_ids);
      if v_actual<>v_expected then raise exception 'SOURCE_REF_UNRESOLVED:SECURITY_POLICY_SET expected=% actual=%',v_expected,v_actual; end if;

    when 'TRANSITION_SET' then
      select array_agg(x::bigint order by x::bigint) into v_ids from jsonb_array_elements_text(p_ref->'ids') x;
      if v_ids is null or cardinality(v_ids)=0 then raise exception 'INVALID_TRANSITION_SET_REF'; end if;
      v_expected:=cardinality(v_ids);
      select count(*),jsonb_agg(to_jsonb(t) order by t.transition_id) into v_actual,v_observed from lf_ops.estados_transiciones t where t.transition_id=any(v_ids);
      if v_actual<>v_expected then raise exception 'SOURCE_REF_UNRESOLVED:TRANSITION_SET expected=% actual=%',v_expected,v_actual; end if;

    when 'SCREEN_STATE_SET' then
      select jsonb_agg(to_jsonb(s) order by s.state_id) into v_observed from lf_ops.pantallas_estados s where s.pantalla_id=p_pantalla_id;
      if v_observed is null or jsonb_array_length(v_observed)=0 then raise exception 'SOURCE_REF_UNRESOLVED:SCREEN_STATE_SET:%',p_pantalla_id; end if;

    when 'CURRENT_VISUAL_ARTIFACT' then
      select jsonb_agg(
        jsonb_build_object(
          'artifact',to_jsonb(a),
          'storage_exists',case when a.storage_bucket is not null and a.storage_object_path is not null
            then exists(select 1 from storage.objects o where o.bucket_id=a.storage_bucket and o.name=a.storage_object_path)
            else false end
        ) order by a.id
      ) into v_observed
      from lf_ops.pantalla_artefactos a where a.pantalla_id=p_pantalla_id and a.is_current=true;
      if v_observed is null or jsonb_array_length(v_observed)=0 then raise exception 'SOURCE_REF_UNRESOLVED:CURRENT_VISUAL_ARTIFACT:%',p_pantalla_id; end if;

    when 'EKB_ERROR_SET' then
      select array_agg(x order by x) into v_codes from jsonb_array_elements_text(p_ref->'codes') x;
      if v_codes is null or cardinality(v_codes)=0 then raise exception 'INVALID_EKB_ERROR_SET_REF'; end if;
      v_expected:=cardinality(v_codes);
      select count(*),jsonb_agg(to_jsonb(e) order by e.codigo) into v_actual,v_observed from transversal.error_knowledge e where e.codigo=any(v_codes);
      if v_actual<>v_expected then raise exception 'SOURCE_REF_UNRESOLVED:EKB_ERROR_SET expected=% actual=%',v_expected,v_actual; end if;

    when 'EKB_PREVENTION_SET' then
      select array_agg(x order by x) into v_codes from jsonb_array_elements_text(p_ref->'codes') x;
      if v_codes is null or cardinality(v_codes)=0 then raise exception 'INVALID_EKB_PREVENTION_SET_REF'; end if;
      v_expected:=cardinality(v_codes);
      select count(*),jsonb_agg(to_jsonb(e) order by e.regla_codigo) into v_actual,v_observed from transversal.prevention_rules e where e.regla_codigo=any(v_codes);
      if v_actual<>v_expected then raise exception 'SOURCE_REF_UNRESOLVED:EKB_PREVENTION_SET expected=% actual=%',v_expected,v_actual; end if;

    when 'EKB_DECISION_SET' then
      select array_agg(x order by x) into v_codes from jsonb_array_elements_text(p_ref->'adrs') x;
      if v_codes is null or cardinality(v_codes)=0 then raise exception 'INVALID_EKB_DECISION_SET_REF'; end if;
      v_expected:=cardinality(v_codes);
      select count(*),jsonb_agg(to_jsonb(d) order by d.adr) into v_actual,v_observed from transversal.decision_log d where d.adr=any(v_codes);
      if v_actual<>v_expected then raise exception 'SOURCE_REF_UNRESOLVED:EKB_DECISION_SET expected=% actual=%',v_expected,v_actual; end if;

    when 'CONTRACT' then
      v_code:=p_ref->>'codigo';
      select to_jsonb(c) into v_observed from programacion.contratos c where c.version_id=p_version_id and c.contrato_codigo=v_code;
      if v_observed is null then raise exception 'SOURCE_REF_UNRESOLVED:CONTRACT:%',coalesce(v_code,'NULL'); end if;

    when 'CAPABILITY_ABSENCE' then
      v_capability:=upper(p_ref->>'capability');
      if v_capability not in ('FEATURE_FLAGS','I18N_FORMATS') then raise exception 'UNSUPPORTED_CAPABILITY_ABSENCE:%',coalesce(v_capability,'NULL'); end if;
      if v_capability='FEATURE_FLAGS' then
        select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname) order by n.nspname,c.relname),'[]'::jsonb) into v_relations
        from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname in ('lf_ops','lf_design') and c.relkind in ('r','v','m') and lower(c.relname) ~ '(feature.*flag|flag.*feature)';
        select coalesce(jsonb_agg(jsonb_build_object('codigo',r.codigo,'categoria',r.categoria) order by r.codigo),'[]'::jsonb) into v_rules
        from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
        where rp.pantalla_id=p_pantalla_id and r.codigo<>'B2B-RULE-STORY-READINESS-001'
          and (upper(coalesce(r.categoria,'')) in ('FEATURE_FLAG','FEATURE_FLAGS') or upper(r.codigo) like '%FEATURE%FLAG%');
      else
        select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname) order by n.nspname,c.relname),'[]'::jsonb) into v_relations
        from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname in ('lf_ops','lf_design') and c.relkind in ('r','v','m') and lower(c.relname) ~ '(i18n|locale|localization|localisation)';
        select coalesce(jsonb_agg(jsonb_build_object('codigo',r.codigo,'categoria',r.categoria) order by r.codigo),'[]'::jsonb) into v_rules
        from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
        where rp.pantalla_id=p_pantalla_id and r.codigo<>'B2B-RULE-STORY-READINESS-001'
          and upper(coalesce(r.categoria,'')) in ('I18N','LOCALIZATION','LOCALISATION','LOCALE');
      end if;
      if jsonb_array_length(v_relations)>0 or jsonb_array_length(v_rules)>0 then raise exception 'CAPABILITY_ABSENCE_ASSERTION_FALSE:%',v_capability; end if;
      v_observed:=jsonb_build_object('capability',v_capability,'matching_relations',v_relations,'matching_linked_rules',v_rules,'pantalla_id',p_pantalla_id);

    else
      raise exception 'UNSUPPORTED_SOURCE_REF_KIND:%',v_kind;
  end case;

  return jsonb_build_object('ref',p_ref,'observed',v_observed,'observed_sha256',programacion.fn_v09_sha256_jsonb(v_observed));
end;
$$;

create or replace function programacion.fn_input_build_source_manifest(p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, programacion
as $$
declare
  v_pantalla_id integer;
  v_version_id bigint;
  v_manifest jsonb;
begin
  select pantalla_id,version_id into v_pantalla_id,v_version_id from programacion.input_readiness_runs where id=p_run_id;
  if v_pantalla_id is null then raise exception 'INPUT_READINESS_RUN_NOT_FOUND:%',p_run_id; end if;
  with refs as (
    select distinct e.ref
    from programacion.input_family_assessments a cross join lateral jsonb_array_elements(a.source_refs) e(ref)
    where a.run_id=p_run_id
  ), resolved as (
    select ref,programacion.fn_input_resolve_source_ref(ref,v_pantalla_id,v_version_id) as receipt from refs
  )
  select coalesce(jsonb_agg(receipt order by ref::text),'[]'::jsonb) into v_manifest from resolved;
  if jsonb_array_length(v_manifest)=0 then raise exception 'SOURCE_MANIFEST_EMPTY:%',p_run_id; end if;
  return v_manifest;
end;
$$;

create or replace function programacion.fn_input_readiness_run_is_current(p_run_id bigint)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, programacion
as $$
declare
  v_status text;
  v_contract_version integer;
  v_stored_manifest jsonb;
  v_stored_sha text;
  v_current_manifest jsonb;
  v_current_sha text;
begin
  select status,contract_version,source_manifest,source_snapshot_sha256 into v_status,v_contract_version,v_stored_manifest,v_stored_sha
  from programacion.input_readiness_runs where id=p_run_id;
  if v_status<>'COMPLETED' or v_contract_version<>2 or v_stored_sha is null then return false; end if;
  v_current_manifest:=programacion.fn_input_build_source_manifest(p_run_id);
  v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  return v_current_sha=v_stored_sha and v_current_manifest=v_stored_manifest;
exception when others then return false;
end;
$$;

create or replace function programacion.fn_guard_input_family_assessment_insert()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, programacion, lf_ops
as $$
declare
  v_status text;
  v_contract_version integer;
  v_pantalla_id integer;
  v_version_id bigint;
  v_families jsonb;
  v_payload jsonb;
  v_ref jsonb;
begin
  select r.status,r.contract_version,r.pantalla_id,r.version_id,q.valor_config->'families'
    into v_status,v_contract_version,v_pantalla_id,v_version_id,v_families
  from programacion.input_readiness_runs r join lf_ops.reglas q on q.id=r.universe_rule_id where r.id=new.run_id;
  if v_status is null then raise exception 'INPUT_READINESS_RUN_NOT_FOUND'; end if;
  if v_contract_version<>2 then raise exception 'LEGACY_INPUT_READINESS_RUN_NOT_WRITABLE'; end if;
  if v_status<>'CURATING' then raise exception 'CURATOR_INSERT_CLOSED_FOR_RUN_STATUS_%',v_status; end if;
  if jsonb_typeof(v_families)<>'array' or not (v_families ? new.family_code) then raise exception 'FAMILY_NOT_IN_CANONICAL_UNIVERSE:%',new.family_code; end if;
  if jsonb_typeof(new.source_refs)<>'array' or jsonb_array_length(new.source_refs)=0 then raise exception 'SOURCE_REFS_REQUIRED:%',new.family_code; end if;
  for v_ref in select value from jsonb_array_elements(new.source_refs) loop
    perform programacion.fn_input_resolve_source_ref(v_ref,v_pantalla_id,v_version_id);
  end loop;
  if new.applicability='UNRESOLVED' and new.story_ready_status='READY' then raise exception 'UNRESOLVED_APPLICABILITY_CANNOT_BE_STORY_READY:%',new.family_code; end if;
  if new.validator_outcome<>'PENDING' or new.validator_identity is not null or new.validator_sha256 is not null
     or new.validator_assessed_at is not null or new.validator_findings<>'[]'::jsonb or new.validator_evidence<>'{}'::jsonb then
    raise exception 'CURATOR_CANNOT_PREVALIDATE:%',new.family_code;
  end if;
  new.freshness:=jsonb_build_object('mode','DB_MANIFEST_V2','status','PENDING_RUN_SNAPSHOT');
  v_payload:=jsonb_build_object('run_id',new.run_id,'family_code',new.family_code,'severity',new.severity,'applicability',new.applicability,
    'coverage_status',new.coverage_status,'well_defined_status',new.well_defined_status,'story_ready_status',new.story_ready_status,
    'implementation_ready_status',new.implementation_ready_status,'qa_ready_status',new.qa_ready_status,'production_ready_status',new.production_ready_status,
    'source_refs',new.source_refs,'rationale',new.rationale,'blockers',new.blockers,'negative_requirements',new.negative_requirements,
    'test_obligations',new.test_obligations,'freshness',new.freshness,'curator_evidence',new.curator_evidence);
  new.curator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$$;

create or replace function programacion.fn_guard_input_family_assessment_update()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, programacion
as $$
declare
  v_payload jsonb;
  v_run_status text;
  v_run_sha text;
  v_curator_identity text;
  v_validator_identity text;
  v_validator_component_id bigint;
  v_current_manifest jsonb;
  v_current_sha text;
  v_bad_assertions integer;
begin
  if new.run_id is distinct from old.run_id or new.family_code is distinct from old.family_code or new.severity is distinct from old.severity
     or new.applicability is distinct from old.applicability or new.coverage_status is distinct from old.coverage_status
     or new.well_defined_status is distinct from old.well_defined_status or new.story_ready_status is distinct from old.story_ready_status
     or new.implementation_ready_status is distinct from old.implementation_ready_status or new.qa_ready_status is distinct from old.qa_ready_status
     or new.production_ready_status is distinct from old.production_ready_status or new.source_refs is distinct from old.source_refs
     or new.rationale is distinct from old.rationale or new.blockers is distinct from old.blockers
     or new.negative_requirements is distinct from old.negative_requirements or new.test_obligations is distinct from old.test_obligations
     or new.freshness is distinct from old.freshness or new.curator_evidence is distinct from old.curator_evidence
     or new.curator_sha256 is distinct from old.curator_sha256 or new.created_at is distinct from old.created_at then
    raise exception 'CURATOR_FIELDS_IMMUTABLE:%',old.family_code;
  end if;
  if old.validator_outcome<>'PENDING' then raise exception 'VALIDATOR_RECEIPT_IMMUTABLE:%',old.family_code; end if;
  if new.validator_outcome='PENDING' then raise exception 'VALIDATOR_UPDATE_MUST_BE_TERMINAL:%',old.family_code; end if;
  select status,source_snapshot_sha256,curator_identity,validator_identity,validator_component_id
    into v_run_status,v_run_sha,v_curator_identity,v_validator_identity,v_validator_component_id
  from programacion.input_readiness_runs where id=old.run_id;
  if v_run_status<>'VALIDATING' then raise exception 'VALIDATOR_REQUIRES_VALIDATING_RUN:%',old.family_code; end if;
  if v_validator_component_id is null then raise exception 'RUN_VALIDATOR_COMPONENT_REQUIRED'; end if;
  if v_validator_identity is null or v_validator_identity=v_curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;
  if new.validator_identity is distinct from v_validator_identity then raise exception 'VALIDATOR_IDENTITY_MISMATCH:%',old.family_code; end if;
  if new.validator_assessed_at is null then new.validator_assessed_at:=now(); end if;
  if jsonb_typeof(new.validator_evidence)<>'object' or new.validator_evidence='{}'::jsonb then raise exception 'VALIDATOR_EVIDENCE_REQUIRED:%',old.family_code; end if;
  if new.validator_evidence->>'source_snapshot_sha256' is distinct from v_run_sha then raise exception 'VALIDATOR_EVIDENCE_SOURCE_SNAPSHOT_MISMATCH:%',old.family_code; end if;
  if new.validator_evidence->>'curator_sha256' is distinct from old.curator_sha256 then raise exception 'VALIDATOR_EVIDENCE_CURATOR_HASH_MISMATCH:%',old.family_code; end if;
  if coalesce((new.validator_evidence->>'direct_source_readback')::boolean,false) is not true then raise exception 'VALIDATOR_DIRECT_SOURCE_READBACK_REQUIRED:%',old.family_code; end if;
  if new.validator_evidence->>'execution_mode'<>'INDEPENDENT_VALIDATOR' then raise exception 'VALIDATOR_EXECUTION_MODE_REQUIRED:%',old.family_code; end if;
  if jsonb_typeof(new.validator_evidence->'assertions')<>'array' or jsonb_array_length(new.validator_evidence->'assertions')=0 then raise exception 'VALIDATOR_ASSERTIONS_REQUIRED:%',old.family_code; end if;
  select count(*) into v_bad_assertions from jsonb_array_elements(new.validator_evidence->'assertions') a
  where jsonb_typeof(a)<>'object' or not (a ? 'actual') or not (a ? 'expected') or not (a ? 'operator') or not (a ? 'source_ref');
  if v_bad_assertions>0 then raise exception 'VALIDATOR_ASSERTION_SCHEMA_INVALID:%',old.family_code; end if;
  v_current_manifest:=programacion.fn_input_build_source_manifest(old.run_id);
  v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  if v_current_sha<>v_run_sha then raise exception 'SOURCE_SNAPSHOT_STALE_DURING_VALIDATION:%',old.family_code; end if;
  v_payload:=jsonb_build_object('curator_sha256',old.curator_sha256,'source_snapshot_sha256',v_run_sha,
    'validator_outcome',new.validator_outcome,'validator_findings',new.validator_findings,'validator_evidence',new.validator_evidence,
    'validator_identity',new.validator_identity,'validator_assessed_at',new.validator_assessed_at);
  new.validator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$$;

create or replace function programacion.fn_guard_input_readiness_run()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, programacion, lf_ops
as $$
declare
  v_agent_code text;
  v_rule_code text;
  v_families jsonb;
  v_universe_payload jsonb;
  v_expected_count integer;
  v_assessment_count integer;
  v_pass_count integer;
  v_bad_validator integer;
  v_curator_code text;
  v_validator_code text;
  v_component_version bigint;
  v_manifest jsonb;
  v_current_manifest jsonb;
  v_current_sha text;
begin
  if tg_op='INSERT' then
    if new.contract_version<>2 then raise exception 'NEW_INPUT_READINESS_RUN_REQUIRES_CONTRACT_V2'; end if;
    if new.status<>'CURATING' or new.curator_completed_at is not null or new.validator_identity is not null
       or new.validator_completed_at is not null or new.validator_component_id is not null or new.blocked_reason is not null
       or new.source_snapshot_sha256 is not null or new.source_manifest<>'[]'::jsonb or new.source_observed_at is not null then
      raise exception 'INPUT_READINESS_RUN_MUST_START_CLEAN_CURATING_V2';
    end if;
    if new.curator_identity !~ '^INPUT_CURATOR:' then raise exception 'INVALID_CURATOR_IDENTITY'; end if;
    select a.agente_codigo into v_agent_code from programacion.versiones_agente v join programacion.agentes a on a.id=v.agente_id where v.id=new.version_id;
    if v_agent_code<>'INPUT_GOVERNANCE_AGENT' then raise exception 'INVALID_INPUT_GOVERNANCE_AGENT_VERSION'; end if;
    select c.componente_codigo,c.version_id into v_curator_code,v_component_version from programacion.componentes c where c.id=new.curator_component_id;
    if v_curator_code<>'INPUT_CURATOR' or v_component_version<>new.version_id then raise exception 'INVALID_CURATOR_COMPONENT'; end if;
    select q.codigo,q.valor_config->'families' into v_rule_code,v_families from lf_ops.reglas q where q.id=new.universe_rule_id;
    if v_rule_code<>'B2B-RULE-STORY-READINESS-001' then raise exception 'INVALID_INPUT_FAMILY_UNIVERSE_RULE:%',coalesce(v_rule_code,'NULL'); end if;
    if jsonb_typeof(v_families)<>'array' then raise exception 'INVALID_CANONICAL_FAMILY_UNIVERSE'; end if;
    v_expected_count:=jsonb_array_length(v_families);
    if new.family_count<>v_expected_count then raise exception 'FAMILY_COUNT_MISMATCH expected=% actual=%',v_expected_count,new.family_count; end if;
    v_universe_payload:=jsonb_build_object('rule_code',v_rule_code,'families',v_families);
    if new.universe_snapshot_sha256<>programacion.fn_v09_sha256_jsonb(v_universe_payload) then raise exception 'UNIVERSE_SNAPSHOT_DIGEST_MISMATCH'; end if;
    return new;
  end if;

  if new.contract_version=1 then
    if old.status in ('COMPLETED','BLOCKED') then raise exception 'TERMINAL_INPUT_READINESS_RUN_IMMUTABLE'; end if;
    raise exception 'LEGACY_INPUT_READINESS_RUN_NOT_MUTABLE';
  end if;

  if new.version_id is distinct from old.version_id or new.pantalla_id is distinct from old.pantalla_id or new.universe_rule_id is distinct from old.universe_rule_id
     or new.supersedes_run_id is distinct from old.supersedes_run_id or new.scope is distinct from old.scope
     or new.universe_snapshot_sha256 is distinct from old.universe_snapshot_sha256 or new.family_count is distinct from old.family_count
     or new.curator_identity is distinct from old.curator_identity or new.curator_component_id is distinct from old.curator_component_id
     or new.contract_version is distinct from old.contract_version or new.created_at is distinct from old.created_at then raise exception 'INPUT_READINESS_RUN_IDENTITY_IMMUTABLE'; end if;
  if old.status in ('COMPLETED','BLOCKED') then raise exception 'TERMINAL_INPUT_READINESS_RUN_IMMUTABLE'; end if;
  if old.status='CURATING' and new.status not in ('CURATING','VALIDATING','BLOCKED') then raise exception 'INVALID_RUN_TRANSITION:%->%',old.status,new.status; end if;
  if old.status='VALIDATING' and new.status not in ('VALIDATING','COMPLETED','BLOCKED') then raise exception 'INVALID_RUN_TRANSITION:%->%',old.status,new.status; end if;
  if not (old.status='CURATING' and new.status='VALIDATING') then
    if new.source_snapshot_sha256 is distinct from old.source_snapshot_sha256 or new.source_manifest is distinct from old.source_manifest
       or new.source_observed_at is distinct from old.source_observed_at then raise exception 'SOURCE_MANIFEST_FIELDS_IMMUTABLE'; end if;
    if new.validator_identity is distinct from old.validator_identity or new.validator_component_id is distinct from old.validator_component_id then raise exception 'RUN_VALIDATOR_IDENTITY_IMMUTABLE'; end if;
  end if;
  if old.status='CURATING' and new.status='VALIDATING' then
    if new.source_snapshot_sha256 is distinct from old.source_snapshot_sha256 or new.source_manifest is distinct from old.source_manifest
       or new.source_observed_at is distinct from old.source_observed_at then raise exception 'SOURCE_MANIFEST_MUST_BE_DB_GENERATED'; end if;
    if new.validator_identity is null or new.validator_identity !~ '^INPUT_VALIDATOR:' or new.validator_identity=new.curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;
    if new.validator_component_id is null then raise exception 'VALIDATOR_COMPONENT_REQUIRED'; end if;
    select c.componente_codigo,c.version_id into v_validator_code,v_component_version from programacion.componentes c where c.id=new.validator_component_id;
    if v_validator_code<>'INPUT_VALIDATOR' or v_component_version<>new.version_id or new.validator_component_id=new.curator_component_id then raise exception 'INVALID_VALIDATOR_COMPONENT'; end if;
    select count(*) into v_assessment_count from programacion.input_family_assessments where run_id=old.id;
    if v_assessment_count<>old.family_count then raise exception 'CURATOR_UNIVERSE_INCOMPLETE expected=% actual=%',old.family_count,v_assessment_count; end if;
    v_manifest:=programacion.fn_input_build_source_manifest(old.id);
    new.source_manifest:=v_manifest;
    new.source_snapshot_sha256:=programacion.fn_v09_sha256_jsonb(v_manifest);
    new.source_observed_at:=now();
    new.curator_completed_at:=coalesce(new.curator_completed_at,now());
  end if;
  if new.status='COMPLETED' then
    if new.validator_identity is null or new.validator_component_id is null then raise exception 'RUN_VALIDATOR_AUTHORITY_REQUIRED'; end if;
    v_current_manifest:=programacion.fn_input_build_source_manifest(old.id);
    v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
    if v_current_sha<>old.source_snapshot_sha256 or v_current_manifest<>old.source_manifest then raise exception 'SOURCE_SNAPSHOT_STALE_AT_COMPLETION'; end if;
    select count(*),count(*) filter(where validator_outcome='PASS'),count(*) filter(where validator_identity is distinct from old.validator_identity or validator_evidence->>'source_snapshot_sha256' is distinct from old.source_snapshot_sha256)
      into v_assessment_count,v_pass_count,v_bad_validator from programacion.input_family_assessments where run_id=old.id;
    if v_assessment_count<>old.family_count or v_pass_count<>old.family_count or v_bad_validator>0 then raise exception 'VALIDATOR_UNIVERSE_NOT_FULL_AUTHORIZED_PASS expected=% assessed=% pass=% bad=%',old.family_count,v_assessment_count,v_pass_count,v_bad_validator; end if;
    new.validator_completed_at:=coalesce(new.validator_completed_at,now());
  end if;
  return new;
end;
$$;

update programacion.contratos c
set especificacion = c.especificacion || jsonb_build_object(
  'schema_version',2,'source_ref_contract','STRUCTURED_ALLOWLIST_V2','source_manifest','DB_GENERATED_DURABLE_OBSERVED_PAYLOAD',
  'source_snapshot_binding','SHA256(source_manifest)','freshness_gate','RECOMPUTE_AT_VALIDATION_AND_COMPLETION_AND_CONSUMPTION',
  'validator_component_binding',true,'validator_identity_must_differ_from_curator',true,'validator_requires_run_status','VALIDATING',
  'validator_evidence_required_fields',jsonb_build_array('source_snapshot_sha256','curator_sha256','direct_source_readback','execution_mode','assertions'),
  'legacy_contract_v1_authoritative',false,'audit_remediation',jsonb_build_array('AUD-IGA-001','AUD-IGA-002','AUD-IGA-003'))
where c.version_id=(select v.id from programacion.versiones_agente v join programacion.agentes a on a.id=v.agente_id where a.agente_codigo='INPUT_GOVERNANCE_AGENT' and v.version_codigo='v0.1-input-readiness-governance')
  and c.contrato_codigo='INPUT_READINESS_CONTRACT';

comment on function programacion.fn_input_resolve_source_ref(jsonb,integer,bigint) is 'Input Governance v2: source refs estructurados allowlisted contra fuentes canónicas; devuelve payload observado + SHA.';
comment on function programacion.fn_input_build_source_manifest(bigint) is 'Input Governance v2: manifest durable deduplicado generado por DB desde refs resolubles.';
comment on function programacion.fn_input_readiness_run_is_current(bigint) is 'Gate de consumo: TRUE sólo para COMPLETED v2 cuyo manifest coincide con fuentes actuales.';