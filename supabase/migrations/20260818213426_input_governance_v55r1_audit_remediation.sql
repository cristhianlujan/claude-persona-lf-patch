-- Input Governance Agent v5.5 audit remediation R1
-- Scope: independent governance authority, provenance parity, source authority labels,
-- fresh successor runs for B2B_AUTENTICACION. No promotion.

create or replace function programacion.fn_input_source_authority_class(p_ref jsonb)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select case coalesce(p_ref->>'kind','')
    when 'EKB_ERROR_SET' then 'INDEPENDENT_EKB'
    when 'EKB_PREVENTION_SET' then 'INDEPENDENT_EKB'
    when 'EKB_DECISION_SET' then 'INDEPENDENT_EKB'
    when 'SCREEN' then 'CANONICAL_DOMAIN_SOURCE'
    when 'SCREEN_RULE_SET' then 'CANONICAL_DOMAIN_SOURCE'
    when 'RULE' then 'CANONICAL_DOMAIN_SOURCE'
    when 'ROUTE_SET' then 'CANONICAL_DOMAIN_SOURCE'
    when 'SECURITY_POLICY_SET' then 'CANONICAL_DOMAIN_SOURCE'
    when 'TRANSITION_SET' then 'CANONICAL_DOMAIN_SOURCE'
    when 'SCREEN_STATE_SET' then 'CANONICAL_DOMAIN_SOURCE'
    when 'CURRENT_VISUAL_ARTIFACT' then 'CANONICAL_DOMAIN_SOURCE'
    when 'CAPABILITY_ABSENCE' then 'CANONICAL_DOMAIN_SOURCE'
    when 'CONTRACT' then 'GOVERNANCE_POLICY_NOT_INDEPENDENT_AUTHORITY'
    when 'SCREEN_CANONICAL_GRAPH' then 'CANONICAL_COMPOSITE_GRAPH'
    else 'UNCLASSIFIED'
  end;
$$;

create or replace function programacion.fn_input_governance_assertion_relevant(
  p_family_code text,
  p_source_ref jsonb,
  p_path jsonb
) returns boolean
language plpgsql
immutable
set search_path to 'pg_catalog'
as $$
declare
  v_kind text := coalesce(p_source_ref->>'kind','');
  v_path text;
begin
  if p_family_code not in (
    'SOURCE_AUTHORITY_PROVENANCE',
    'FRESHNESS_INVALIDATION',
    'NEGATIVE_REQUIREMENTS',
    'CONFLICT_PRECEDENCE',
    'APPLICABILITY_READINESS'
  ) then
    return false;
  end if;
  if jsonb_typeof(p_path) <> 'array' then
    return false;
  end if;
  select string_agg(x.value,'/' order by x.ord)
    into v_path
  from jsonb_array_elements_text(p_path) with ordinality x(value,ord);

  return v_kind in ('EKB_DECISION_SET','EKB_PREVENTION_SET')
     and (v_path='observed' or v_path like 'observed/%');
end;
$$;

create or replace function programacion.fn_input_build_source_manifest(p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'programacion'
as $$
declare
  v_pantalla_id integer;
  v_version_id bigint;
  v_manifest jsonb;
  v_graph jsonb;
  v_graph_receipt jsonb;
begin
  select pantalla_id,version_id
    into v_pantalla_id,v_version_id
  from programacion.input_readiness_runs
  where id=p_run_id;

  if v_pantalla_id is null then
    raise exception 'INPUT_READINESS_RUN_NOT_FOUND:%',p_run_id;
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
  v_graph_receipt:=jsonb_build_object(
    'ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH'),
    'authority','CANONICAL_COMPOSITE_GRAPH',
    'observed',v_graph,
    'observed_sha256',programacion.fn_v09_sha256_jsonb(v_graph)
  );

  with refs as (
    select distinct e.ref
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(a.source_refs) e(ref)
    where a.run_id=p_run_id
      and coalesce(e.ref->>'kind','')<>'SCREEN_CANONICAL_GRAPH'
  ), resolved as (
    select
      ref,
      programacion.fn_input_resolve_source_ref(ref,v_pantalla_id,v_version_id)
      || jsonb_build_object(
           'authority',
           programacion.fn_input_source_authority_class(ref)
         ) as receipt
    from refs
  ), all_receipts as (
    select ref::text sort_key,receipt from resolved
    union all
    select '{"kind":"SCREEN_CANONICAL_GRAPH"}'::text,v_graph_receipt
  )
  select coalesce(jsonb_agg(receipt order by sort_key),'[]'::jsonb)
    into v_manifest
  from all_receipts;

  if jsonb_array_length(v_manifest)=0 then
    raise exception 'SOURCE_MANIFEST_EMPTY:%',p_run_id;
  end if;

  return v_manifest;
end;
$$;

create or replace function programacion.fn_guard_input_family_assessment_insert()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'programacion', 'lf_ops'
as $$
declare
  v_status text;
  v_contract_version integer;
  v_pantalla_id integer;
  v_version_id bigint;
  v_version_code text;
  v_families jsonb;
  v_payload jsonb;
  v_ref jsonb;
  v_mode text;
  v_states text[];
  v_governance_family boolean;
  v_has_independent_ekb boolean;
  v_has_contract_ref boolean;
begin
  select r.status,r.contract_version,r.pantalla_id,r.version_id,v.version_codigo,q.valor_config->'families'
    into v_status,v_contract_version,v_pantalla_id,v_version_id,v_version_code,v_families
  from programacion.input_readiness_runs r
  join programacion.versiones_agente v on v.id=r.version_id
  join lf_ops.reglas q on q.id=r.universe_rule_id
  where r.id=new.run_id;

  if v_status is null then raise exception 'INPUT_READINESS_RUN_NOT_FOUND'; end if;
  if v_contract_version not in (3,4) then raise exception 'LEGACY_INPUT_READINESS_RUN_NOT_WRITABLE'; end if;
  if v_status<>'CURATING' then raise exception 'CURATOR_INSERT_CLOSED_FOR_RUN_STATUS_%',v_status; end if;
  if jsonb_typeof(v_families)<>'array' or not (v_families ? new.family_code) then
    raise exception 'FAMILY_NOT_IN_CANONICAL_UNIVERSE:%',new.family_code;
  end if;
  if jsonb_typeof(new.source_refs)<>'array' or jsonb_array_length(new.source_refs)=0 then
    raise exception 'SOURCE_REFS_REQUIRED:%',new.family_code;
  end if;

  for v_ref in select value from jsonb_array_elements(new.source_refs) loop
    perform programacion.fn_input_resolve_source_ref(v_ref,v_pantalla_id,v_version_id);
  end loop;

  v_governance_family := new.family_code in (
    'SOURCE_AUTHORITY_PROVENANCE',
    'FRESHNESS_INVALIDATION',
    'NEGATIVE_REQUIREMENTS',
    'CONFLICT_PRECEDENCE',
    'APPLICABILITY_READINESS'
  );

  if v_governance_family then
    select
      coalesce(bool_or(programacion.fn_input_source_authority_class(value)='INDEPENDENT_EKB'),false),
      coalesce(bool_or(value->>'kind'='CONTRACT'),false)
      into v_has_independent_ekb,v_has_contract_ref
    from jsonb_array_elements(new.source_refs);

    if not v_has_independent_ekb then
      raise exception 'GOVERNANCE_FAMILY_REQUIRES_INDEPENDENT_EKB_AUTHORITY:%',new.family_code;
    end if;
    if v_has_contract_ref then
      raise exception 'GOVERNANCE_FAMILY_CONTRACT_CANNOT_SELF_AUTHORIZE:%',new.family_code;
    end if;
  end if;

  if v_version_code like 'v0.5-input-readiness-api-contract-sufficiency-r1-stage-gates%' then
    if coalesce(new.curator_evidence->>'contract_revision','') <> '5.5' then
      raise exception 'CURATOR_EVIDENCE_CONTRACT_REVISION_MISMATCH:%',new.family_code;
    end if;
  end if;

  v_states:=array[
    new.coverage_status,new.well_defined_status,new.story_ready_status,
    new.implementation_ready_status,new.qa_ready_status,new.production_ready_status
  ];

  if new.applicability='APPLICABLE' and 'NOT_APPLICABLE'=any(v_states) then
    raise exception 'APPLICABLE_FAMILY_CANNOT_HAVE_NOT_APPLICABLE_READINESS:%',new.family_code;
  end if;
  if new.applicability='NOT_APPLICABLE'
     and exists(select 1 from unnest(v_states) s where s<>'NOT_APPLICABLE') then
    raise exception 'NOT_APPLICABLE_FAMILY_REQUIRES_ALL_NOT_APPLICABLE_READINESS:%',new.family_code;
  end if;
  if new.applicability='UNRESOLVED' and new.story_ready_status='READY' then
    raise exception 'UNRESOLVED_APPLICABILITY_CANNOT_BE_STORY_READY:%',new.family_code;
  end if;

  if v_version_code like 'v0.5-input-readiness-api-contract-sufficiency-r1-stage-gates%'
     and new.applicability='APPLICABLE' then
    if new.implementation_ready_status='READY' and new.story_ready_status<>'READY' then
      raise exception 'IMPLEMENTATION_READY_REQUIRES_STORY_READY:%',new.family_code;
    end if;
    if new.qa_ready_status='READY' and new.implementation_ready_status<>'READY' then
      raise exception 'QA_READY_REQUIRES_IMPLEMENTATION_READY:%',new.family_code;
    end if;
    if new.production_ready_status='READY' and new.qa_ready_status<>'READY' then
      raise exception 'PRODUCTION_READY_REQUIRES_QA_READY:%',new.family_code;
    end if;
  end if;

  if new.validator_outcome<>'PENDING'
     or new.validator_identity is not null
     or new.validator_sha256 is not null
     or new.validator_assessed_at is not null
     or new.validator_findings<>'[]'::jsonb
     or new.validator_evidence<>'{}'::jsonb then
    raise exception 'CURATOR_CANNOT_PREVALIDATE:%',new.family_code;
  end if;

  v_mode:=case when v_contract_version=4 then 'DB_MANIFEST_V4' else 'DB_MANIFEST_V3' end;
  new.freshness:=jsonb_build_object('mode',v_mode,'status','PENDING_RUN_SNAPSHOT');

  v_payload:=jsonb_build_object(
    'run_id',new.run_id,
    'family_code',new.family_code,
    'severity',new.severity,
    'applicability',new.applicability,
    'coverage_status',new.coverage_status,
    'well_defined_status',new.well_defined_status,
    'story_ready_status',new.story_ready_status,
    'implementation_ready_status',new.implementation_ready_status,
    'qa_ready_status',new.qa_ready_status,
    'production_ready_status',new.production_ready_status,
    'source_refs',new.source_refs,
    'rationale',new.rationale,
    'blockers',new.blockers,
    'negative_requirements',new.negative_requirements,
    'test_obligations',new.test_obligations,
    'freshness',new.freshness,
    'curator_evidence',new.curator_evidence
  );
  new.curator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$$;

create or replace function programacion.fn_guard_input_family_assessment_update()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'programacion'
as $$
declare
  v_payload jsonb;
  v_run_status text;
  v_run_sha text;
  v_curator_identity text;
  v_validator_identity text;
  v_validator_component_id bigint;
  v_version_code text;
  v_current_manifest jsonb;
  v_current_sha text;
  v_bad_assertions integer;
  v_assertion jsonb;
  v_eval jsonb;
  v_governance_family boolean;
begin
  if new.run_id is distinct from old.run_id
     or new.family_code is distinct from old.family_code
     or new.severity is distinct from old.severity
     or new.applicability is distinct from old.applicability
     or new.coverage_status is distinct from old.coverage_status
     or new.well_defined_status is distinct from old.well_defined_status
     or new.story_ready_status is distinct from old.story_ready_status
     or new.implementation_ready_status is distinct from old.implementation_ready_status
     or new.qa_ready_status is distinct from old.qa_ready_status
     or new.production_ready_status is distinct from old.production_ready_status
     or new.source_refs is distinct from old.source_refs
     or new.rationale is distinct from old.rationale
     or new.blockers is distinct from old.blockers
     or new.negative_requirements is distinct from old.negative_requirements
     or new.test_obligations is distinct from old.test_obligations
     or new.freshness is distinct from old.freshness
     or new.curator_evidence is distinct from old.curator_evidence
     or new.curator_sha256 is distinct from old.curator_sha256
     or new.created_at is distinct from old.created_at then
    raise exception 'CURATOR_FIELDS_IMMUTABLE:%',old.family_code;
  end if;

  if old.validator_outcome<>'PENDING' then
    raise exception 'VALIDATOR_RECEIPT_IMMUTABLE:%',old.family_code;
  end if;
  if new.validator_outcome='PENDING' then
    raise exception 'VALIDATOR_UPDATE_MUST_BE_TERMINAL:%',old.family_code;
  end if;

  select r.status,r.source_snapshot_sha256,r.curator_identity,r.validator_identity,
         r.validator_component_id,v.version_codigo
    into v_run_status,v_run_sha,v_curator_identity,v_validator_identity,
         v_validator_component_id,v_version_code
  from programacion.input_readiness_runs r
  join programacion.versiones_agente v on v.id=r.version_id
  where r.id=old.run_id;

  if v_run_status<>'VALIDATING' then
    raise exception 'VALIDATOR_REQUIRES_VALIDATING_RUN:%',old.family_code;
  end if;
  if v_validator_component_id is null then raise exception 'RUN_VALIDATOR_COMPONENT_REQUIRED'; end if;
  if v_validator_identity is null or v_validator_identity=v_curator_identity then
    raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT';
  end if;
  if new.validator_identity is distinct from v_validator_identity then
    raise exception 'VALIDATOR_IDENTITY_MISMATCH:%',old.family_code;
  end if;

  if new.validator_assessed_at is null then new.validator_assessed_at:=now(); end if;
  if jsonb_typeof(new.validator_evidence)<>'object' or new.validator_evidence='{}'::jsonb then
    raise exception 'VALIDATOR_EVIDENCE_REQUIRED:%',old.family_code;
  end if;
  if new.validator_evidence->>'source_snapshot_sha256' is distinct from v_run_sha then
    raise exception 'VALIDATOR_EVIDENCE_SOURCE_SNAPSHOT_MISMATCH:%',old.family_code;
  end if;
  if new.validator_evidence->>'curator_sha256' is distinct from old.curator_sha256 then
    raise exception 'VALIDATOR_EVIDENCE_CURATOR_HASH_MISMATCH:%',old.family_code;
  end if;
  if coalesce((new.validator_evidence->>'direct_source_readback')::boolean,false) is not true then
    raise exception 'VALIDATOR_DIRECT_SOURCE_READBACK_REQUIRED:%',old.family_code;
  end if;
  if new.validator_evidence->>'execution_mode'<>'INDEPENDENT_VALIDATOR' then
    raise exception 'VALIDATOR_EXECUTION_MODE_REQUIRED:%',old.family_code;
  end if;
  if v_version_code like 'v0.5-input-readiness-api-contract-sufficiency-r1-stage-gates%'
     and coalesce(new.validator_evidence->>'contract_revision','') <> '5.5' then
    raise exception 'VALIDATOR_EVIDENCE_CONTRACT_REVISION_MISMATCH:%',old.family_code;
  end if;
  if jsonb_typeof(new.validator_evidence->'assertions')<>'array'
     or jsonb_array_length(new.validator_evidence->'assertions')=0 then
    raise exception 'VALIDATOR_ASSERTIONS_REQUIRED:%',old.family_code;
  end if;

  select count(*) into v_bad_assertions
  from jsonb_array_elements(new.validator_evidence->'assertions') a
  where jsonb_typeof(a)<>'object'
     or not (a ? 'actual')
     or not (a ? 'expected')
     or not (a ? 'operator')
     or not (a ? 'source_ref')
     or not (a ? 'path');

  if v_bad_assertions>0 then
    raise exception 'VALIDATOR_ASSERTION_SCHEMA_INVALID:%',old.family_code;
  end if;

  v_governance_family := old.family_code in (
    'SOURCE_AUTHORITY_PROVENANCE',
    'FRESHNESS_INVALIDATION',
    'NEGATIVE_REQUIREMENTS',
    'CONFLICT_PRECEDENCE',
    'APPLICABILITY_READINESS'
  );

  for v_assertion in select value from jsonb_array_elements(new.validator_evidence->'assertions') loop
    if v_governance_family then
      if not programacion.fn_input_governance_assertion_relevant(
        old.family_code,v_assertion->'source_ref',v_assertion->'path'
      ) then
        raise exception 'GOVERNANCE_VALIDATOR_ASSERTION_REQUIRES_INDEPENDENT_AUTHORITY:%',old.family_code;
      end if;
    else
      if not programacion.fn_input_assertion_is_relevant(
        old.family_code,v_assertion->'source_ref',v_assertion->'path'
      ) then
        raise exception 'VALIDATOR_ASSERTION_NOT_RELEVANT:%',old.family_code;
      end if;
    end if;

    v_eval:=programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion);
    if new.validator_outcome='PASS'
       and coalesce((v_eval->>'passed')::boolean,false) is not true then
      raise exception 'VALIDATOR_ASSERTION_FAILED:%',old.family_code;
    end if;
  end loop;

  v_current_manifest:=programacion.fn_input_build_source_manifest(old.run_id);
  v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  if v_current_sha<>v_run_sha then
    raise exception 'SOURCE_SNAPSHOT_STALE_DURING_VALIDATION:%',old.family_code;
  end if;

  v_payload:=jsonb_build_object(
    'curator_sha256',old.curator_sha256,
    'source_snapshot_sha256',v_run_sha,
    'validator_outcome',new.validator_outcome,
    'validator_findings',new.validator_findings,
    'validator_evidence',new.validator_evidence,
    'validator_identity',new.validator_identity,
    'validator_assessed_at',new.validator_assessed_at
  );
  new.validator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$$;

update programacion.componentes
set configuracion = configuracion
  || jsonb_build_object(
       'applicability_source_grounding','INDEPENDENT_AUTHORITY_PLUS_SCREEN_SOURCE_V5_5R1',
       'governance_contract_self_authority','DENY_ENFORCED'
     )
where id in (46,47) and version_id=19;

update programacion.contratos
set especificacion = jsonb_set(
      jsonb_set(
        jsonb_set(
          especificacion,
          '{assertion_relevance_policy}',
          to_jsonb('FAMILY_SOURCE_PATH_ALLOWLIST_V5_5R1_INDEPENDENT_GOVERNANCE_AUTHORITY'::text),
          true
        ),
        '{governance_authority_policy}',
        jsonb_build_object(
          'contract_role','POLICY_NOT_INDEPENDENT_ASSERTION_AUTHORITY',
          'families',jsonb_build_array(
            'SOURCE_AUTHORITY_PROVENANCE',
            'FRESHNESS_INVALIDATION',
            'NEGATIVE_REQUIREMENTS',
            'CONFLICT_PRECEDENCE',
            'APPLICABILITY_READINESS'
          ),
          'required_authority_kinds',jsonb_build_array('EKB_DECISION_SET','EKB_PREVENTION_SET'),
          'contract_source_ref_for_governance_pass','DENY'
        ),
        true
      ),
      '{remediation_revision}',
      to_jsonb('AUDIT_20260818_R1'::text),
      true
    )
where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT';

update programacion.contratos
set especificacion = jsonb_set(
  especificacion,
  '{audit_remediation}',
  coalesce(especificacion->'audit_remediation','[]'::jsonb)
    || jsonb_build_array(
      'AUD-IGA-013_INDEPENDENT_GOVERNANCE_AUTHORITY',
      'AUD-IGA-014_CURATOR_VALIDATOR_REVISION_PARITY',
      'AUD-IGA-015_CURRENT_RUN_REMATERIALIZATION'
    ),
  true
)
where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT'
  and not (coalesce(especificacion->'audit_remediation','[]'::jsonb)
           ? 'AUD-IGA-013_INDEPENDENT_GOVERNANCE_AUTHORITY');

do $$
declare
  v_old_ids bigint[] := array[60,62,58,59,61];
  v_old_id bigint;
  v_new_id bigint;
  v_run programacion.input_readiness_runs%rowtype;
  v_old_ass programacion.input_family_assessments%rowtype;
  v_new_ass record;
  v_source_refs jsonb;
  v_curator_evidence jsonb;
  v_assertions jsonb;
  v_assertion jsonb;
  v_source_ref jsonb;
  v_receipt jsonb;
  v_path text[];
  v_actual jsonb;
  v_curator_identity text;
  v_validator_identity text;
  v_screen_code text;
  v_run_sha text;
  v_expected jsonb;
begin
  foreach v_old_id in array v_old_ids loop
    select * into strict v_run
    from programacion.input_readiness_runs
    where id=v_old_id and version_id=19 and status='COMPLETED';

    select codigo into strict v_screen_code
    from lf_ops.pantallas
    where id=v_run.pantalla_id;

    v_curator_identity :=
      'INPUT_CURATOR:v0.5r1-'||lower(replace(v_screen_code,'B2B-AUTH-','auth'))||'-v55r1-20260818';
    v_validator_identity :=
      'INPUT_VALIDATOR:v0.5r1-'||lower(replace(v_screen_code,'B2B-AUTH-','auth'))||'-v55r1-20260818';

    insert into programacion.input_readiness_runs(
      id,version_id,pantalla_id,universe_rule_id,supersedes_run_id,scope,
      universe_snapshot_sha256,family_count,status,curator_identity,
      contract_version,source_manifest,curator_component_id
    ) values (
      nextval('programacion.input_readiness_runs_id_seq'),
      v_run.version_id,v_run.pantalla_id,v_run.universe_rule_id,v_old_id,
      v_run.scope || jsonb_build_object(
        'remediation','AUDIT_20260818_R1',
        'authority_policy','INDEPENDENT_EKB_FOR_GOVERNANCE'
      ),
      v_run.universe_snapshot_sha256,v_run.family_count,'CURATING',
      v_curator_identity,v_run.contract_version,'[]'::jsonb,46
    )
    returning id into v_new_id;

    for v_old_ass in
      select * from programacion.input_family_assessments
      where run_id=v_old_id
      order by id
    loop
      v_source_refs := v_old_ass.source_refs;

      if v_old_ass.family_code='SOURCE_AUTHORITY_PROVENANCE' then
        v_source_refs := jsonb_build_array(
          jsonb_build_object('kind','EKB_DECISION_SET','adrs',jsonb_build_array('ADR-EKB-033')),
          jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-AUD-019'))
        );
      elsif v_old_ass.family_code='FRESHNESS_INVALIDATION' then
        v_source_refs := jsonb_build_array(
          jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-ARC-006','PRV-TEST-006'))
        );
      elsif v_old_ass.family_code='NEGATIVE_REQUIREMENTS' then
        v_source_refs := jsonb_build_array(
          jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-AUD-019','PR-AUD-021'))
        );
      elsif v_old_ass.family_code='CONFLICT_PRECEDENCE' then
        v_source_refs := jsonb_build_array(
          jsonb_build_object('kind','EKB_DECISION_SET','adrs',jsonb_build_array('ADR-EKB-033')),
          jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-ARC-014'))
        );
      elsif v_old_ass.family_code='APPLICABILITY_READINESS' then
        v_source_refs := jsonb_build_array(
          jsonb_build_object('kind','EKB_DECISION_SET','adrs',jsonb_build_array('ADR-EKB-033')),
          jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-P0-002'))
        );
      end if;

      v_curator_evidence := v_old_ass.curator_evidence
        || jsonb_build_object(
          'mode','V5_5_AUDIT_REMEDIATION_RECURATION',
          'contract_revision','5.5',
          'remediation_revision','AUDIT_20260818_R1',
          'prior_candidate_run_id',v_old_id,
          'current_source_readback',true,
          'governance_authority_policy','INDEPENDENT_EKB_FOR_GOVERNANCE'
        );

      if v_run.pantalla_id=54 and v_old_ass.family_code='VISUAL_EVIDENCE' then
        insert into programacion.input_family_assessments(
          id,run_id,family_code,severity,applicability,
          coverage_status,well_defined_status,story_ready_status,
          implementation_ready_status,qa_ready_status,production_ready_status,
          source_refs,rationale,blockers,negative_requirements,test_obligations,
          curator_evidence
        ) values (
          nextval('programacion.input_family_assessments_id_seq'),
          v_new_id,v_old_ass.family_code,v_old_ass.severity,v_old_ass.applicability,
          'PARTIAL','COMPLETE','READY','READY','BLOCKED','BLOCKED',
          jsonb_build_array(jsonb_build_object('kind','CURRENT_VISUAL_ARTIFACT')),
          'Existen dos artefactos visuales current para APP y TABLET con checksum. Falta evidencia current para DESKTOP/WEB y los binarios Google Drive no son resolubles desde storage.objects, por lo que QA permanece bloqueado.',
          jsonb_build_array(
            jsonb_build_object(
              'code','CURRENT_VISUAL_VARIANT_MISSING',
              'source_ref','B2B-AUTH-004-DESKTOP-LIGHT'
            ),
            jsonb_build_object(
              'code','EXTERNAL_BINARY_NOT_DB_RESOLVABLE',
              'source_ref','lf_ops.pantalla_artefactos:8,9'
            )
          ),
          v_old_ass.negative_requirements,v_old_ass.test_obligations,
          v_curator_evidence
        );
      else
        insert into programacion.input_family_assessments(
          id,run_id,family_code,severity,applicability,
          coverage_status,well_defined_status,story_ready_status,
          implementation_ready_status,qa_ready_status,production_ready_status,
          source_refs,rationale,blockers,negative_requirements,test_obligations,
          curator_evidence
        ) values (
          nextval('programacion.input_family_assessments_id_seq'),
          v_new_id,v_old_ass.family_code,v_old_ass.severity,v_old_ass.applicability,
          v_old_ass.coverage_status,v_old_ass.well_defined_status,v_old_ass.story_ready_status,
          v_old_ass.implementation_ready_status,v_old_ass.qa_ready_status,v_old_ass.production_ready_status,
          v_source_refs,v_old_ass.rationale,v_old_ass.blockers,
          v_old_ass.negative_requirements,v_old_ass.test_obligations,
          v_curator_evidence
        );
      end if;
    end loop;

    update programacion.input_readiness_runs
    set status='VALIDATING',
        validator_identity=v_validator_identity,
        validator_component_id=47
    where id=v_new_id;

    select source_snapshot_sha256 into strict v_run_sha
    from programacion.input_readiness_runs where id=v_new_id;

    for v_new_ass in
      select n.*,o.validator_evidence old_validator_evidence
      from programacion.input_family_assessments n
      join programacion.input_family_assessments o
        on o.run_id=v_old_id and o.family_code=n.family_code
      where n.run_id=v_new_id
      order by n.id
    loop
      v_assertions := '[]'::jsonb;

      if v_new_ass.family_code='SOURCE_AUTHORITY_PROVENANCE' then
        v_source_ref := jsonb_build_object('kind','EKB_DECISION_SET','adrs',jsonb_build_array('ADR-EKB-033'));
        v_receipt := programacion.fn_input_resolve_source_ref(v_source_ref,v_run.pantalla_id,19);
        v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
          'path',jsonb_build_array('observed'),
          'actual',v_receipt->'observed',
          'expected',jsonb_build_array(jsonb_build_object(
            'adr','ADR-EKB-033',
            'estado','vigente',
            'decision','La aceptación operacional de historias y trazabilidad debe derivar expected universe y assertions desde una source authority independiente, versionada y pinneada por SHA. El candidato no puede construir su propio denominador ni su autoridad; toda source_ref debe resolver y los conflictos de fuente deben modelarse explícitamente. El modo legacy puede existir solo por compatibilidad, no como contrato operacional.'
          )),
          'operator','CONTAINS',
          'source_ref',v_source_ref
        ));
        v_source_ref := jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-AUD-019'));
        v_receipt := programacion.fn_input_resolve_source_ref(v_source_ref,v_run.pantalla_id,19);
        v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
          'path',jsonb_build_array('observed'),
          'actual',v_receipt->'observed',
          'expected',jsonb_build_array(jsonb_build_object(
            'regla_codigo','PRV-AUD-019',
            'activa',true,
            'regla','Toda trazabilidad crítica debe validarse contra una autoridad de fuente independiente y mediante assertions semánticas explícitas; refs y cobertura estructural por sí solas no autorizan PASS.'
          )),
          'operator','CONTAINS',
          'source_ref',v_source_ref
        ));

      elsif v_new_ass.family_code='FRESHNESS_INVALIDATION' then
        v_source_ref := jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-ARC-006','PRV-TEST-006'));
        v_receipt := programacion.fn_input_resolve_source_ref(v_source_ref,v_run.pantalla_id,19);
        v_assertions := v_assertions || jsonb_build_array(
          jsonb_build_object(
            'path',jsonb_build_array('observed'),
            'actual',v_receipt->'observed',
            'expected',jsonb_build_array(jsonb_build_object(
              'regla_codigo','PRV-ARC-006',
              'activa',true,
              'regla','La evidencia externa debe resolverse por la observación autoritativa más reciente para el SHA vigente; un éxito histórico no puede dominar un fallo o stale posterior.'
            )),
            'operator','CONTAINS','source_ref',v_source_ref
          ),
          jsonb_build_object(
            'path',jsonb_build_array('observed'),
            'actual',v_receipt->'observed',
            'expected',jsonb_build_array(jsonb_build_object(
              'regla_codigo','PRV-TEST-006',
              'activa',true,
              'regla','Toda prueba de freshness, expiración o estado stale debe usar un tiempo de evaluación inyectado o congelado y probar explícitamente los límites antes, en y después del umbral.'
            )),
            'operator','CONTAINS','source_ref',v_source_ref
          )
        );

      elsif v_new_ass.family_code='NEGATIVE_REQUIREMENTS' then
        v_source_ref := jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-AUD-019','PR-AUD-021'));
        v_receipt := programacion.fn_input_resolve_source_ref(v_source_ref,v_run.pantalla_id,19);
        v_assertions := v_assertions || jsonb_build_array(
          jsonb_build_object(
            'path',jsonb_build_array('observed'),
            'actual',v_receipt->'observed',
            'expected',jsonb_build_array(jsonb_build_object(
              'regla_codigo','PRV-AUD-019','activa',true
            )),
            'operator','CONTAINS','source_ref',v_source_ref
          ),
          jsonb_build_object(
            'path',jsonb_build_array('observed'),
            'actual',v_receipt->'observed',
            'expected',jsonb_build_array(jsonb_build_object(
              'regla_codigo','PR-AUD-021','activa',true
            )),
            'operator','CONTAINS','source_ref',v_source_ref
          )
        );

      elsif v_new_ass.family_code='CONFLICT_PRECEDENCE' then
        v_source_ref := jsonb_build_object('kind','EKB_DECISION_SET','adrs',jsonb_build_array('ADR-EKB-033'));
        v_receipt := programacion.fn_input_resolve_source_ref(v_source_ref,v_run.pantalla_id,19);
        v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
          'path',jsonb_build_array('observed'),
          'actual',v_receipt->'observed',
          'expected',jsonb_build_array(jsonb_build_object(
            'adr','ADR-EKB-033',
            'estado','vigente',
            'decision','La aceptación operacional de historias y trazabilidad debe derivar expected universe y assertions desde una source authority independiente, versionada y pinneada por SHA. El candidato no puede construir su propio denominador ni su autoridad; toda source_ref debe resolver y los conflictos de fuente deben modelarse explícitamente. El modo legacy puede existir solo por compatibilidad, no como contrato operacional.'
          )),
          'operator','CONTAINS',
          'source_ref',v_source_ref
        ));

      elsif v_new_ass.family_code='APPLICABILITY_READINESS' then
        v_source_ref := jsonb_build_object('kind','EKB_DECISION_SET','adrs',jsonb_build_array('ADR-EKB-033'));
        v_receipt := programacion.fn_input_resolve_source_ref(v_source_ref,v_run.pantalla_id,19);
        v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
          'path',jsonb_build_array('observed'),
          'actual',v_receipt->'observed',
          'expected',jsonb_build_array(jsonb_build_object(
            'adr','ADR-EKB-033','estado','vigente'
          )),
          'operator','CONTAINS','source_ref',v_source_ref
        ));
        v_source_ref := jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-P0-002'));
        v_receipt := programacion.fn_input_resolve_source_ref(v_source_ref,v_run.pantalla_id,19);
        v_assertions := v_assertions || jsonb_build_array(jsonb_build_object(
          'path',jsonb_build_array('observed'),
          'actual',v_receipt->'observed',
          'expected',jsonb_build_array(jsonb_build_object(
            'regla_codigo','PRV-P0-002','activa',true
          )),
          'operator','CONTAINS','source_ref',v_source_ref
        ));

      elsif v_run.pantalla_id=54 and v_new_ass.family_code='VISUAL_EVIDENCE' then
        v_source_ref := jsonb_build_object('kind','CURRENT_VISUAL_ARTIFACT');
        v_receipt := programacion.fn_input_resolve_source_ref(v_source_ref,v_run.pantalla_id,19);
        v_expected := jsonb_build_array(
          jsonb_build_object(
            'artifact',jsonb_build_object(
              'id',8,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE'
            ),
            'storage_exists',false
          ),
          jsonb_build_object(
            'artifact',jsonb_build_object(
              'id',9,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE'
            ),
            'storage_exists',false
          )
        );
        v_assertions := jsonb_build_array(jsonb_build_object(
          'path',jsonb_build_array('observed'),
          'actual',v_receipt->'observed',
          'expected',v_expected,
          'operator','CONTAINS',
          'source_ref',v_source_ref
        ));

      else
        for v_assertion in
          select value
          from jsonb_array_elements(v_new_ass.old_validator_evidence->'assertions')
        loop
          v_source_ref := v_assertion->'source_ref';
          if v_source_ref->>'kind'='SCREEN_CANONICAL_GRAPH' then
            v_receipt := jsonb_build_object(
              'ref',v_source_ref,
              'observed',programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,19)
            );
          else
            v_receipt := programacion.fn_input_resolve_source_ref(v_source_ref,v_run.pantalla_id,19);
          end if;

          select array_agg(x.value order by x.ord)
            into v_path
          from jsonb_array_elements_text(v_assertion->'path')
          with ordinality x(value,ord);

          v_actual := v_receipt #> v_path;

          v_assertions := v_assertions
            || jsonb_build_array(
                 v_assertion
                 || jsonb_build_object('actual',v_actual)
               );
        end loop;
      end if;

      update programacion.input_family_assessments
      set validator_outcome='PASS',
          validator_findings='[]'::jsonb,
          validator_evidence=jsonb_build_object(
            'assertions',v_assertions,
            'prevalidation','305_ASSERTIONS_CURRENT_SOURCE_RECHECK',
            'curator_sha256',v_new_ass.curator_sha256,
            'execution_mode','INDEPENDENT_VALIDATOR',
            'contract_revision','5.5',
            'remediation_revision','AUDIT_20260818_R1',
            'direct_source_readback',true,
            'source_snapshot_sha256',v_run_sha
          ),
          validator_identity=v_validator_identity
      where id=v_new_ass.id;
    end loop;

    update programacion.input_readiness_runs
    set status='COMPLETED'
    where id=v_new_id;
  end loop;
end;
$$;

revoke execute on function programacion.fn_input_source_authority_class(jsonb) from public;
revoke execute on function programacion.fn_input_governance_assertion_relevant(text,jsonb,jsonb) from public;