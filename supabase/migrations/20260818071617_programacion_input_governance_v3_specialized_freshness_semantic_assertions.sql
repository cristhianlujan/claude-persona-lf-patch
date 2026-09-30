alter table programacion.input_readiness_runs drop constraint if exists input_readiness_runs_contract_version_check;
alter table programacion.input_readiness_runs add constraint input_readiness_runs_contract_version_check check (contract_version = any(array[1,2,3]));
alter table programacion.input_readiness_runs alter column contract_version set default 3;

create or replace function programacion.fn_input_screen_canonical_graph(p_pantalla_id integer, p_version_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops, lf_design
as $$
declare
  v_screen_code text;
  v_module_code text;
  v_shell_code text;
  v_contract jsonb;
  v_permissions jsonb := '[]'::jsonb;
  v_profile_permissions jsonb := '[]'::jsonb;
  v_messages jsonb := '[]'::jsonb;
begin
  select p.codigo,m.module_code,s.app_shell_code
    into v_screen_code,v_module_code,v_shell_code
  from lf_ops.pantallas p
  join lf_ops.modulos m on m.module_id=p.module_id
  join lf_ops.app_shells s on s.app_shell_id=m.app_shell_id
  where p.id=p_pantalla_id;
  if v_screen_code is null then raise exception 'SCREEN_CANONICAL_GRAPH_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;

  select f.contract into v_contract
  from lf_ops.fn_b2b_backoffice_login_contract(v_shell_code,v_module_code,v_screen_code) f
  limit 1;
  if v_contract is null then raise exception 'SCREEN_CANONICAL_CONTRACT_UNRESOLVED:%',p_pantalla_id; end if;
  v_contract := v_contract #- '{metadata,generated_at}'::text[];

  select coalesce(jsonb_agg(jsonb_build_object('link',to_jsonb(pp),'permission',to_jsonb(pm)) order by pp.permission_id),'[]'::jsonb)
    into v_permissions
  from lf_ops.pantallas_permisos pp
  join lf_ops.permisos pm on pm.permission_id=pp.permission_id
  where pp.pantalla_id=p_pantalla_id;

  select coalesce(jsonb_agg(jsonb_build_object('screen_profile',to_jsonb(sp),'profile_permission',to_jsonb(pp),'permission',to_jsonb(pm)) order by sp.profile_id,pp.permission_id),'[]'::jsonb)
    into v_profile_permissions
  from lf_ops.pantallas_perfiles sp
  join lf_ops.perfiles_permisos pp on pp.profile_id=sp.profile_id
  join lf_ops.permisos pm on pm.permission_id=pp.permission_id
  where sp.pantalla_id=p_pantalla_id;

  with field_ids as (
    select cp.campo_id,cp.message_id from lf_ops.campos_pantallas cp where cp.pantalla_id=p_pantalla_id
  ), timeout_policy_ids as (
    select distinct e.value::bigint timeout_policy_id
    from lf_ops.reglas_pantallas rp
    join lf_ops.reglas r on r.id=rp.regla_id
    cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e
    where rp.pantalla_id=p_pantalla_id and (e.key='timeout_policy_id' or e.key like '%_timeout_policy_id') and e.value ~ '^[0-9]+$'
  ), message_ids as (
    select message_id from field_ids where message_id is not null
    union
    select cv.message_id from lf_ops.campos_validaciones cv join field_ids f on f.campo_id=cv.campo_id where cv.message_id is not null
    union
    select tp.message_id from lf_ops.politicas_timeout tp where tp.timeout_policy_id in (select timeout_policy_id from timeout_policy_ids) and tp.message_id is not null
  )
  select coalesce(jsonb_agg(to_jsonb(mu) order by mu.message_id),'[]'::jsonb)
    into v_messages
  from lf_ops.mensajes_ui mu
  where mu.message_id in (select message_id from message_ids);

  return jsonb_build_object(
    'screen_code',v_screen_code,
    'module_code',v_module_code,
    'app_shell_code',v_shell_code,
    'canonical_contract',v_contract,
    'screen_permissions',v_permissions,
    'profile_permissions',v_profile_permissions,
    'messages',v_messages,
    'agent_contract_version_id',p_version_id
  );
end;
$$;

create or replace function programacion.fn_input_build_source_manifest(p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion
as $$
declare
  v_pantalla_id integer;
  v_version_id bigint;
  v_manifest jsonb;
  v_graph jsonb;
  v_graph_receipt jsonb;
begin
  select pantalla_id,version_id into v_pantalla_id,v_version_id from programacion.input_readiness_runs where id=p_run_id;
  if v_pantalla_id is null then raise exception 'INPUT_READINESS_RUN_NOT_FOUND:%',p_run_id; end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
  v_graph_receipt:=jsonb_build_object(
    'ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH'),
    'observed',v_graph,
    'observed_sha256',programacion.fn_v09_sha256_jsonb(v_graph)
  );

  with refs as (
    select distinct e.ref
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(a.source_refs) e(ref)
    where a.run_id=p_run_id and coalesce(e.ref->>'kind','')<>'SCREEN_CANONICAL_GRAPH'
  ), resolved as (
    select ref,programacion.fn_input_resolve_source_ref(ref,v_pantalla_id,v_version_id) as receipt from refs
  ), all_receipts as (
    select ref::text sort_key,receipt from resolved
    union all
    select '{"kind":"SCREEN_CANONICAL_GRAPH"}'::text,v_graph_receipt
  )
  select coalesce(jsonb_agg(receipt order by sort_key),'[]'::jsonb) into v_manifest from all_receipts;
  if jsonb_array_length(v_manifest)=0 then raise exception 'SOURCE_MANIFEST_EMPTY:%',p_run_id; end if;
  return v_manifest;
end;
$$;

create or replace function programacion.fn_input_evaluate_assertion(p_run_id bigint,p_family_code text,p_assertion jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion
as $$
declare
  v_pantalla_id integer;
  v_version_id bigint;
  v_source_ref jsonb;
  v_receipt jsonb;
  v_graph jsonb;
  v_path text[];
  v_actual_db jsonb;
  v_actual_claim jsonb;
  v_expected jsonb;
  v_operator text;
  v_pass boolean:=false;
  v_allowed boolean:=false;
begin
  if jsonb_typeof(p_assertion)<>'object' then raise exception 'ASSERTION_NOT_OBJECT:%',p_family_code; end if;
  if not (p_assertion ? 'source_ref') or not (p_assertion ? 'path') or not (p_assertion ? 'actual') or not (p_assertion ? 'expected') or not (p_assertion ? 'operator') then
    raise exception 'ASSERTION_REQUIRED_FIELDS_MISSING:%',p_family_code;
  end if;
  v_source_ref:=p_assertion->'source_ref';
  if jsonb_typeof(v_source_ref)<>'object' then raise exception 'ASSERTION_SOURCE_REF_INVALID:%',p_family_code; end if;
  if jsonb_typeof(p_assertion->'path')<>'array' or jsonb_array_length(p_assertion->'path')=0 then raise exception 'ASSERTION_PATH_INVALID:%',p_family_code; end if;

  select r.pantalla_id,r.version_id into v_pantalla_id,v_version_id from programacion.input_readiness_runs r where r.id=p_run_id;
  if v_pantalla_id is null then raise exception 'ASSERTION_RUN_NOT_FOUND:%',p_run_id; end if;

  if v_source_ref->>'kind'='SCREEN_CANONICAL_GRAPH' then
    v_allowed:=true;
    v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
    v_receipt:=jsonb_build_object('ref',v_source_ref,'observed',v_graph,'observed_sha256',programacion.fn_v09_sha256_jsonb(v_graph));
  else
    select exists(
      select 1 from programacion.input_family_assessments a
      cross join lateral jsonb_array_elements(a.source_refs) e(ref)
      where a.run_id=p_run_id and a.family_code=p_family_code and e.ref=v_source_ref
    ) into v_allowed;
    if not v_allowed then raise exception 'ASSERTION_SOURCE_NOT_DECLARED:%',p_family_code; end if;
    v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_pantalla_id,v_version_id);
  end if;

  select array_agg(x.value order by x.ord) into v_path
  from jsonb_array_elements_text(p_assertion->'path') with ordinality x(value,ord);
  v_actual_db:=v_receipt #> v_path;
  v_actual_claim:=p_assertion->'actual';
  v_expected:=p_assertion->'expected';
  v_operator:=upper(p_assertion->>'operator');

  if v_actual_claim is distinct from v_actual_db then
    raise exception 'ASSERTION_ACTUAL_NOT_SOURCE_DERIVED:%',p_family_code;
  end if;

  case v_operator
    when 'EQ' then v_pass := v_actual_db = v_expected;
    when 'NE' then v_pass := v_actual_db is distinct from v_expected;
    when 'CONTAINS' then v_pass := coalesce(v_actual_db @> v_expected,false);
    when 'ARRAY_LENGTH_EQ' then
      if jsonb_typeof(v_actual_db)<>'array' or jsonb_typeof(v_expected)<>'number' then raise exception 'ASSERTION_ARRAY_LENGTH_TYPES_INVALID:%',p_family_code; end if;
      v_pass := jsonb_array_length(v_actual_db) = (v_expected #>> '{}')::integer;
    else raise exception 'ASSERTION_OPERATOR_UNSUPPORTED:%:%',p_family_code,v_operator;
  end case;

  return jsonb_build_object(
    'passed',v_pass,
    'actual',v_actual_db,
    'expected',v_expected,
    'operator',v_operator,
    'source_ref',v_source_ref,
    'path',p_assertion->'path',
    'source_observed_sha256',v_receipt->>'observed_sha256'
  );
end;
$$;

create or replace function programacion.fn_guard_input_family_assessment_update()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, programacion
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
  v_assertion jsonb;
  v_eval jsonb;
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
  where jsonb_typeof(a)<>'object' or not (a ? 'actual') or not (a ? 'expected') or not (a ? 'operator') or not (a ? 'source_ref') or not (a ? 'path');
  if v_bad_assertions>0 then raise exception 'VALIDATOR_ASSERTION_SCHEMA_INVALID:%',old.family_code; end if;

  for v_assertion in select value from jsonb_array_elements(new.validator_evidence->'assertions') loop
    v_eval:=programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion);
    if new.validator_outcome='PASS' and coalesce((v_eval->>'passed')::boolean,false) is not true then
      raise exception 'VALIDATOR_ASSERTION_FAILED:%',old.family_code;
    end if;
  end loop;

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
set search_path = pg_catalog, programacion, lf_ops
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
    if new.contract_version<>3 then raise exception 'NEW_INPUT_READINESS_RUN_REQUIRES_CONTRACT_V3'; end if;
    if new.status<>'CURATING' or new.curator_completed_at is not null or new.validator_identity is not null
       or new.validator_completed_at is not null or new.validator_component_id is not null or new.blocked_reason is not null
       or new.source_snapshot_sha256 is not null or new.source_manifest<>'[]'::jsonb or new.source_observed_at is not null then
      raise exception 'INPUT_READINESS_RUN_MUST_START_CLEAN_CURATING_V3';
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

  if new.contract_version in (1,2) then
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

create or replace function programacion.fn_input_readiness_run_is_current(p_run_id bigint)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, programacion
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
  if v_status<>'COMPLETED' or v_contract_version<>3 or v_stored_sha is null then return false; end if;
  v_current_manifest:=programacion.fn_input_build_source_manifest(p_run_id);
  v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  return v_current_sha=v_stored_sha and v_current_manifest=v_stored_manifest;
exception when others then return false;
end;
$$;

update programacion.contratos
set especificacion = especificacion || jsonb_build_object(
  'schema_version',3,
  'legacy_contract_v1_authoritative',false,
  'legacy_contract_v2_authoritative',false,
  'source_manifest','DB_GENERATED_WITH_SCREEN_CANONICAL_GRAPH_V3',
  'freshness_gate','RECOMPUTE_SPECIALIZED_GRAPH_AT_VALIDATION_AND_COMPLETION_AND_CONSUMPTION',
  'assertion_contract','DB_RESOLVED_SOURCE_PATH_V3',
  'assertion_truth_evaluated',true,
  'assertion_required_fields',jsonb_build_array('source_ref','path','actual','expected','operator'),
  'audit_remediation',jsonb_build_array('AUD-IGA-001','AUD-IGA-002','AUD-IGA-003','AUD-IGA-003-R1','AUD-IGA-004')
)
where version_id=(select id from programacion.versiones_agente where agente_id=(select id from programacion.agentes where agente_codigo='INPUT_GOVERNANCE_AGENT') and version_codigo='v0.1-input-readiness-governance')
  and contrato_codigo='INPUT_READINESS_CONTRACT';

revoke execute on function programacion.fn_input_screen_canonical_graph(integer,bigint) from public;
revoke execute on function programacion.fn_input_evaluate_assertion(bigint,text,jsonb) from public;
revoke execute on function programacion.fn_input_build_source_manifest(bigint) from public;
revoke execute on function programacion.fn_input_readiness_run_is_current(bigint) from public;
grant execute on function programacion.fn_input_readiness_run_is_current(bigint) to programacion_auditor,programacion_builder,programacion_verifier,programacion_human_authority;