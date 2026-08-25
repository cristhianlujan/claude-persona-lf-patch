-- INPUT_GOVERNANCE_AGENT 5.12
-- Canonicalize the owner-approved API Story/Implementation stage boundary.
-- Fail closed: incomplete API coverage is Story-eligible only when a positive behavioral contract
-- exists and has no broken contract references. Screens without that authority remain P0/blocked.

do $decision$
declare
  v_decision_number bigint;
  v_batch uuid := gen_random_uuid();
begin
  perform pg_advisory_xact_lock(hashtext('lf_decisiones_gov:decision_number')::bigint);
  if not exists (
    select 1 from public.lf_decisiones_gov
    where id_decision='DEC-INPUT-GOV-512-API-STAGE-HUMAN-001'
  ) then
    select coalesce(max(decision_number),0)+1
      into v_decision_number
    from public.lf_decisiones_gov;

    insert into public.lf_decisiones_gov(
      id_decision,fecha,decision,contexto,impacto,
      estado_original,estado_normalizado,documento_relacionado,observaciones,
      source_sheet_name,migration_batch_id,raw_payload,decision_number,
      created_by_execution_id
    ) values (
      'DEC-INPUT-GOV-512-API-STAGE-HUMAN-001',
      '2026-08-25',
      'Para INPUT_GOVERNANCE_AGENT 5.12, un API_DATA_CONTRACT con contrato conductual positivo y sin referencias rotas puede quedar READY para Story aunque falte materializar el operation/schema; esa ausencia bloquea desde Implementation. Sin contrato conductual positivo, Story permanece fail-closed.',
      'El owner aprobó explícitamente la recomendación durante la remediación gobernada de REC_001 con el texto "Ok conforme". La aprobación cubre la corrección de falso P0 API ya implementada y verificada en el successor run206; no autoriza inventar schemas, operaciones ni contratos conductuales ausentes.',
      'Canonicaliza la frontera Story->Implementation para API_DATA_CONTRACT de forma condicional. REC_001, ONB_001, ONB_002, ONB_004 y B2B-AUTH-001 conservan Story READY cuando existe contrato conductual; ONB_003 y cualquier pantalla sin autoridad conductual siguen bloqueadas. No autoriza merge, promoción ni producción.',
      'OWNER_APPROVED',
      'CANDIDATO_CONTROLADO',
      'INPUT_GOVERNANCE_AGENT_5_12_REC_001',
      'Fail-closed. La excepción de etapa depende de readback de fn_input_api_contract_resolution: has_behavioral_contract=true y broken_contract_ref_count=0. La propuesta no crea API canon ni sustituye operation/schema authority.',
      '06_DECISIONES',
      v_batch,
      jsonb_build_object(
        'approval_text','Ok conforme',
        'approval_scope','INPUT_GOVERNANCE_AGENT_5_12_REC_001_API_STAGE',
        'evidence_run_id',206,
        'authority_mode','OWNER_POSITIVE_APPROVAL',
        'production_authorized',false
      ),
      v_decision_number,
      'INPUT_GOVERNANCE_REC001_REMEDIATION_20260825'
    );
  end if;
end;
$decision$;

update programacion.contratos
set especificacion=jsonb_set(
  especificacion,
  '{family_stage_requirements,API_DATA_CONTRACT}',
  jsonb_build_object(
    'authority','DEC-INPUT-GOV-512-API-STAGE-HUMAN-001',
    'coverage_required_by','IMPLEMENTATION',
    'allow_story_ready_when_incomplete',true,
    'allow_implementation_ready_when_incomplete',false,
    'allow_qa_ready_when_incomplete',false,
    'allow_production_ready_when_incomplete',false,
    'conditional',true,
    'eligibility_contract','API_BEHAVIORAL_CONTRACT_PRESENT_NO_BROKEN_REFS'
  ),
  true
)
where version_id=19
  and contrato_codigo='INPUT_READINESS_CONTRACT';

create or replace function programacion.fn_input_stage_authority_applies_v1(
  p_family_code text,
  p_pantalla_id integer,
  p_version_id bigint,
  p_coverage_status text,
  p_well_defined_status text
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_cfg jsonb;
  v_api jsonb;
begin
  select coalesce(c.especificacion->'family_stage_requirements'->p_family_code,'{}'::jsonb)
    into v_cfg
  from programacion.contratos c
  where c.version_id=p_version_id
    and c.contrato_codigo='INPUT_READINESS_CONTRACT';

  if coalesce(v_cfg,'{}'::jsonb)='{}'::jsonb then
    return false;
  end if;

  if coalesce((v_cfg->>'conditional')::boolean,false) is false then
    return true;
  end if;

  if v_cfg->>'eligibility_contract'='API_BEHAVIORAL_CONTRACT_PRESENT_NO_BROKEN_REFS'
     and p_family_code='API_DATA_CONTRACT' then
    v_api:=programacion.fn_input_api_contract_resolution(p_pantalla_id);
    return coalesce((v_api->>'has_behavioral_contract')::boolean,false)
       and coalesce((v_api->>'broken_contract_ref_count')::integer,0)=0;
  end if;

  return false;
end;
$function$;

create or replace function programacion.fn_guard_input_stage_earliest_boundary()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_revision text;
  v_version_id bigint;
  v_cfg jsonb;
  v_stage text;
  v_incomplete boolean;
begin
  select r.contract_revision,r.version_id
    into v_revision,v_version_id
  from programacion.input_readiness_runs r
  where r.id=new.run_id;

  if v_revision not in ('5.10','5.11','5.12') or new.applicability<>'APPLICABLE' then
    return new;
  end if;

  select coalesce(c.especificacion->'family_stage_requirements'->new.family_code,'{}'::jsonb)
    into v_cfg
  from programacion.contratos c
  where c.version_id=v_version_id
    and c.contrato_codigo='INPUT_READINESS_CONTRACT';

  if coalesce(v_cfg,'{}'::jsonb)='{}'::jsonb then
    return new;
  end if;

  if not programacion.fn_input_stage_authority_applies_v1(
    new.family_code,
    (select pantalla_id from programacion.input_readiness_runs where id=new.run_id),
    v_version_id,
    new.coverage_status,
    new.well_defined_status
  ) then
    return new;
  end if;

  v_stage:=upper(coalesce(v_cfg->>'coverage_required_by',''));
  v_incomplete:=new.coverage_status<>'COMPLETE' or new.well_defined_status<>'COMPLETE';
  if not v_incomplete then
    return new;
  end if;

  if v_stage='IMPLEMENTATION' then
    if new.story_ready_status<>'READY' then
      raise exception 'STAGE_AUTHORITY_EARLIER_STAGE_OVERBLOCK:%:STORY',new.family_code;
    end if;
    if new.severity<>'P1' then
      raise exception 'STAGE_AUTHORITY_SEVERITY_MISMATCH:% expected=P1 actual=%',new.family_code,new.severity;
    end if;
  elsif v_stage='QA' then
    if new.story_ready_status<>'READY' or new.implementation_ready_status<>'READY' then
      raise exception 'STAGE_AUTHORITY_EARLIER_STAGE_OVERBLOCK:%:PRE_QA',new.family_code;
    end if;
    if new.severity<>'P2' then
      raise exception 'STAGE_AUTHORITY_SEVERITY_MISMATCH:% expected=P2 actual=%',new.family_code,new.severity;
    end if;
  elsif v_stage='PRODUCTION' then
    if new.story_ready_status<>'READY' or new.implementation_ready_status<>'READY' or new.qa_ready_status<>'READY' then
      raise exception 'STAGE_AUTHORITY_EARLIER_STAGE_OVERBLOCK:%:PRE_PRODUCTION',new.family_code;
    end if;
    if new.severity<>'P3' then
      raise exception 'STAGE_AUTHORITY_SEVERITY_MISMATCH:% expected=P3 actual=%',new.family_code,new.severity;
    end if;
  end if;

  return new;
end;
$function$;

create or replace function programacion.fn_input_stage_gate_summary(p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_run programacion.input_readiness_runs%rowtype;
  v_summary jsonb;
  v_violations jsonb;
  v_contract jsonb;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then raise exception 'INPUT_STAGE_GATE_RUN_NOT_FOUND:%',p_run_id; end if;
  select c.especificacion into v_contract
  from programacion.contratos c
  where c.version_id=v_run.version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';

  select jsonb_build_object(
    'families_total',count(*),
    'validator_pass',count(*) filter(where validator_outcome='PASS'),
    'applicable',count(*) filter(where applicability='APPLICABLE'),
    'not_applicable',count(*) filter(where applicability='NOT_APPLICABLE'),
    'unresolved',count(*) filter(where applicability='UNRESOLVED'),
    'applicable_p0_story_open',count(*) filter(where applicability='APPLICABLE' and severity='P0' and story_ready_status<>'READY'),
    'story_stage_open',count(*) filter(where applicability='UNRESOLVED' or (applicability='APPLICABLE' and story_ready_status<>'READY')),
    'implementation_stage_open',count(*) filter(where applicability='UNRESOLVED' or (applicability='APPLICABLE' and implementation_ready_status<>'READY')),
    'qa_stage_open',count(*) filter(where applicability='UNRESOLVED' or (applicability='APPLICABLE' and qa_ready_status<>'READY')),
    'production_stage_open',count(*) filter(where applicability='UNRESOLVED' or (applicability='APPLICABLE' and production_ready_status<>'READY')),
    'severity_unresolved',count(*) filter(where severity not in ('P0','P1','P2','P3','P4')),
    'story_open_not_p0',count(*) filter(where applicability in ('APPLICABLE','UNRESOLVED') and story_ready_status<>'READY' and severity<>'P0'),
    'story_ready_bad_coverage',count(*) filter(
      where applicability='APPLICABLE'
        and story_ready_status='READY'
        and (coverage_status in ('MISSING','PENDING','BLOCKED') or well_defined_status in ('MISSING','PENDING','BLOCKED'))
        and not (
          coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_story_ready_when_incomplete')::boolean,false)
          and programacion.fn_input_stage_authority_applies_v1(family_code,v_run.pantalla_id,v_run.version_id,coverage_status,well_defined_status)
        )
    ),
    'implementation_ready_incomplete_coverage',count(*) filter(
      where applicability='APPLICABLE'
        and implementation_ready_status='READY'
        and (coverage_status<>'COMPLETE' or well_defined_status<>'COMPLETE')
        and not (
          coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_implementation_ready_when_incomplete')::boolean,false)
          and programacion.fn_input_stage_authority_applies_v1(family_code,v_run.pantalla_id,v_run.version_id,coverage_status,well_defined_status)
        )
    ),
    'stage_specific_incomplete_allowed',count(*) filter(
      where applicability='APPLICABLE'
        and (
          (
            story_ready_status='READY'
            and (coverage_status in ('MISSING','PENDING','BLOCKED') or well_defined_status in ('MISSING','PENDING','BLOCKED'))
            and coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_story_ready_when_incomplete')::boolean,false)
            and programacion.fn_input_stage_authority_applies_v1(family_code,v_run.pantalla_id,v_run.version_id,coverage_status,well_defined_status)
          )
          or (
            implementation_ready_status='READY'
            and (coverage_status<>'COMPLETE' or well_defined_status<>'COMPLETE')
            and coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_implementation_ready_when_incomplete')::boolean,false)
            and programacion.fn_input_stage_authority_applies_v1(family_code,v_run.pantalla_id,v_run.version_id,coverage_status,well_defined_status)
          )
        )
    ),
    'na_only_absence_authority',count(*) filter(
      where applicability='NOT_APPLICABLE'
        and not exists(select 1 from jsonb_array_elements(source_refs) r where r->>'kind'<>'CAPABILITY_ABSENCE')
    )
  ) into v_summary
  from programacion.input_family_assessments
  where run_id=p_run_id;

  select coalesce(jsonb_agg(v order by v->>'family_code',v->>'code'),'[]'::jsonb)
    into v_violations
  from (
    select jsonb_build_object('family_code',family_code,'code','IMPLEMENTATION_READY_WHILE_STORY_NOT_READY') v
    from programacion.input_family_assessments
    where run_id=p_run_id and applicability='APPLICABLE' and implementation_ready_status='READY' and story_ready_status<>'READY'
    union all
    select jsonb_build_object('family_code',family_code,'code','QA_READY_WHILE_IMPLEMENTATION_NOT_READY')
    from programacion.input_family_assessments
    where run_id=p_run_id and applicability='APPLICABLE' and qa_ready_status='READY' and implementation_ready_status<>'READY'
    union all
    select jsonb_build_object('family_code',family_code,'code','PRODUCTION_READY_WHILE_QA_NOT_READY')
    from programacion.input_family_assessments
    where run_id=p_run_id and applicability='APPLICABLE' and production_ready_status='READY' and qa_ready_status<>'READY'
    union all
    select jsonb_build_object('family_code',family_code,'code','STORY_OPEN_WITHOUT_P0')
    from programacion.input_family_assessments
    where run_id=p_run_id and applicability in ('APPLICABLE','UNRESOLVED') and story_ready_status<>'READY' and severity<>'P0'
    union all
    select jsonb_build_object('family_code',family_code,'code','STORY_READY_WITH_INCOMPLETE_COVERAGE_WITHOUT_STAGE_AUTHORITY')
    from programacion.input_family_assessments
    where run_id=p_run_id
      and applicability='APPLICABLE'
      and story_ready_status='READY'
      and (coverage_status in ('MISSING','PENDING','BLOCKED') or well_defined_status in ('MISSING','PENDING','BLOCKED'))
      and not (
        coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_story_ready_when_incomplete')::boolean,false)
        and programacion.fn_input_stage_authority_applies_v1(family_code,v_run.pantalla_id,v_run.version_id,coverage_status,well_defined_status)
      )
    union all
    select jsonb_build_object('family_code',family_code,'code','IMPLEMENTATION_READY_WITH_INCOMPLETE_COVERAGE')
    from programacion.input_family_assessments
    where run_id=p_run_id
      and applicability='APPLICABLE'
      and implementation_ready_status='READY'
      and (coverage_status<>'COMPLETE' or well_defined_status<>'COMPLETE')
      and not (
        coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_implementation_ready_when_incomplete')::boolean,false)
        and programacion.fn_input_stage_authority_applies_v1(family_code,v_run.pantalla_id,v_run.version_id,coverage_status,well_defined_status)
      )
  ) z;

  return jsonb_build_object(
    'stage_gate_contract','INPUT_STAGE_GATE_SUMMARY_V4_CONDITIONAL_STAGE_AUTHORITY',
    'run_id',p_run_id,
    'run_status',v_run.status,
    'run_current',case when v_run.status='COMPLETED' then programacion.fn_input_readiness_run_is_current(p_run_id) else false end,
    'summary',v_summary,
    'canonical_story_gate_pass',coalesce((v_summary->>'story_stage_open')::integer,0)=0 and coalesce((v_summary->>'severity_unresolved')::integer,0)=0 and coalesce((v_summary->>'story_open_not_p0')::integer,0)=0,
    'legacy_no_applicable_p0_open_pass',coalesce((v_summary->>'applicable_p0_story_open')::integer,0)=0,
    'full_story_stage_closed',coalesce((v_summary->>'story_stage_open')::integer,0)=0,
    'full_implementation_stage_closed',coalesce((v_summary->>'implementation_stage_open')::integer,0)=0,
    'full_qa_stage_closed',coalesce((v_summary->>'qa_stage_open')::integer,0)=0,
    'full_production_stage_closed',coalesce((v_summary->>'production_stage_open')::integer,0)=0,
    'hierarchy_violation_count',jsonb_array_length(v_violations),
    'hierarchy_violations',v_violations
  );
end;
$function$;

do $selftest$
declare
  v_cfg jsonb;
  v_j jsonb;
  v_decision_number bigint;
begin
  select decision_number into v_decision_number
  from public.lf_decisiones_gov
  where id_decision='DEC-INPUT-GOV-512-API-STAGE-HUMAN-001';
  if v_decision_number is null then
    raise exception 'SELFTEST_API_STAGE_OWNER_DECISION_MISSING';
  end if;

  select especificacion->'family_stage_requirements'->'API_DATA_CONTRACT'
    into v_cfg
  from programacion.contratos
  where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT';

  if v_cfg->>'authority'<>'DEC-INPUT-GOV-512-API-STAGE-HUMAN-001'
     or v_cfg->>'coverage_required_by'<>'IMPLEMENTATION'
     or coalesce((v_cfg->>'allow_story_ready_when_incomplete')::boolean,false) is not true
     or v_cfg->>'eligibility_contract'<>'API_BEHAVIORAL_CONTRACT_PRESENT_NO_BROKEN_REFS' then
    raise exception 'SELFTEST_API_STAGE_CONTRACT_AUTHORITY_INVALID:%',v_cfg;
  end if;

  if programacion.fn_input_stage_authority_applies_v1('API_DATA_CONTRACT',58,19,'PARTIAL','COMPLETE') is not true then
    raise exception 'SELFTEST_REC001_API_STAGE_AUTHORITY_EXPECTED_TRUE';
  end if;

  if programacion.fn_input_stage_authority_applies_v1('API_DATA_CONTRACT',3,19,'MISSING','MISSING') is not false then
    raise exception 'SELFTEST_ONB003_API_STAGE_AUTHORITY_MUST_FAIL_CLOSED';
  end if;

  if programacion.fn_input_stage_authority_applies_v1('ANALYTICS',58,19,'MISSING','MISSING') is not true then
    raise exception 'SELFTEST_EXISTING_UNCONDITIONAL_STAGE_AUTHORITY_REGRESSION';
  end if;

  v_j:=programacion.fn_input_governance_bootstrap_classify_v2(58,'API_DATA_CONTRACT',19);
  if v_j->>'story_ready_status'<>'READY'
     or v_j->>'implementation_ready_status'<>'NOT_READY'
     or v_j->>'severity'<>'P1' then
    raise exception 'SELFTEST_REC001_API_STAGE_CLASSIFICATION_INVALID:%',v_j;
  end if;

  v_j:=programacion.fn_input_governance_bootstrap_classify_v2(3,'API_DATA_CONTRACT',19);
  if v_j->>'story_ready_status'<>'BLOCKED' or v_j->>'severity'<>'P0' then
    raise exception 'SELFTEST_ONB003_API_FAIL_CLOSED_REGRESSION:%',v_j;
  end if;
end;
$selftest$;

comment on function programacion.fn_input_stage_authority_applies_v1(text,integer,bigint,text,text)
is 'Resolves conditional stage authority from INPUT_READINESS_CONTRACT. Conditional families fail closed unless their positive eligibility contract resolves.';

comment on function programacion.fn_guard_input_stage_earliest_boundary()
is 'Enforces earliest-stage authority only when the family stage rule is positively applicable to the current screen; conditional rules fail closed.';

comment on function programacion.fn_input_stage_gate_summary(bigint)
is 'INPUT_STAGE_GATE_SUMMARY_V4_CONDITIONAL_STAGE_AUTHORITY. Counts incomplete readiness as stage-authorized only when the canonical family rule and its conditional eligibility both resolve.';
