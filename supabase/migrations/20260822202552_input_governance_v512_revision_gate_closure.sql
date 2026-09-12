-- Close contract-revision gate coverage for 5.12 and register ARC-011 recurrence.

update programacion.contratos
set especificacion = jsonb_set(
  especificacion,
  '{negative_tests}',
  (especificacion->'negative_tests') || '["V512_SEMANTIC_DEPTH_GUARD_ACTIVE","V512_STAGE_BOUNDARY_GUARD_ACTIVE"]'::jsonb,
  true
)
where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT'
  and not ((especificacion->'negative_tests') ? 'V512_SEMANTIC_DEPTH_GUARD_ACTIVE');

create or replace function programacion.fn_guard_input_family_semantic_depth_v510()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare v_revision text; v_pantalla_id integer; v_expected_subject jsonb:='[]'::jsonb; v_expected_threat jsonb:='[]'::jsonb; v_bad integer:=0; v_expected_count integer:=0;
begin
  select r.contract_revision,r.pantalla_id into v_revision,v_pantalla_id from programacion.input_readiness_runs r where r.id=coalesce(new.run_id,old.run_id);
  if v_revision not in ('5.10','5.11','5.12') then return new; end if;
  if tg_op='INSERT' then
    if new.family_code in ('DESIGN_SYSTEM','SECURITY') then new.subject_coverage:=programacion.fn_input_subject_depth_expected(v_pantalla_id,new.family_code); else new.subject_coverage:='[]'::jsonb; end if;
    if new.family_code='SECURITY' then new.threat_coverage:=programacion.fn_input_security_threat_expected(v_pantalla_id); else new.threat_coverage:='[]'::jsonb; end if;
    new.semantic_depth_sha256:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('family_code',new.family_code,'subject_coverage',new.subject_coverage,'threat_coverage',new.threat_coverage));
    new.curator_evidence:=jsonb_set(coalesce(new.curator_evidence,'{}'::jsonb),'{semantic_depth_sha256}',to_jsonb(new.semantic_depth_sha256),true);
    if new.family_code in ('DESIGN_SYSTEM','SECURITY') then select count(*) into v_bad from jsonb_array_elements(new.subject_coverage) s where s->>'status' not in ('COMPLETE','NOT_APPLICABLE'); if v_bad>0 and new.coverage_status='COMPLETE' then raise exception 'FAMILY_COMPLETE_WITH_INCOMPLETE_SUBJECT:%:%',new.family_code,v_bad; end if; if v_bad>0 and new.well_defined_status='COMPLETE' then raise exception 'FAMILY_WELL_DEFINED_WITH_INCOMPLETE_SUBJECT:%:%',new.family_code,v_bad; end if; end if;
    if new.family_code='SECURITY' then
      select count(*) into v_bad from jsonb_array_elements(new.threat_coverage) t where t->>'status' not in ('COMPLETE','NOT_APPLICABLE');
      if v_bad>0 and new.coverage_status='COMPLETE' then raise exception 'SECURITY_COMPLETE_WITH_UNRESOLVED_THREAT:%',v_bad; end if;
      if v_bad>0 and new.well_defined_status='COMPLETE' then raise exception 'SECURITY_WELL_DEFINED_WITH_UNRESOLVED_THREAT:%',v_bad; end if;
      if exists(select 1 from jsonb_array_elements(new.threat_coverage) t where t->>'applicability'='NOT_APPLICABLE' and (t->'applicability_authority'->>'authority_rule' is null or nullif(t->>'rationale','') is null)) then raise exception 'SECURITY_THREAT_NA_REQUIRES_POSITIVE_PROFILE_AUTHORITY'; end if;
      select jsonb_array_length(c.especificacion->'semantic_depth_contract'->'security_threat_catalog') into v_expected_count from programacion.contratos c join programacion.input_readiness_runs r on r.version_id=c.version_id where r.id=new.run_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
      if jsonb_array_length(new.threat_coverage)<>v_expected_count then raise exception 'SECURITY_THREAT_CATALOG_CARDINALITY_MISMATCH expected=% actual=%',v_expected_count,jsonb_array_length(new.threat_coverage); end if;
    end if;
    return new;
  end if;
  if new.subject_coverage is distinct from old.subject_coverage or new.threat_coverage is distinct from old.threat_coverage or new.semantic_depth_sha256 is distinct from old.semantic_depth_sha256 then raise exception 'SEMANTIC_DEPTH_IMMUTABLE:%',old.family_code; end if;
  if old.validator_outcome='PENDING' and new.validator_outcome<>'PENDING' then
    if new.validator_evidence->>'semantic_depth_sha256' is distinct from old.semantic_depth_sha256 then raise exception 'VALIDATOR_SEMANTIC_DEPTH_HASH_MISMATCH:%',old.family_code; end if;
    if old.family_code in ('DESIGN_SYSTEM','SECURITY') then v_expected_subject:=programacion.fn_input_subject_depth_expected(v_pantalla_id,old.family_code); if old.subject_coverage is distinct from v_expected_subject then raise exception 'SEMANTIC_SUBJECT_DEPTH_STALE_DURING_VALIDATION:%',old.family_code; end if; end if;
    if old.family_code='SECURITY' then v_expected_threat:=programacion.fn_input_security_threat_expected(v_pantalla_id); if old.threat_coverage is distinct from v_expected_threat then raise exception 'SEMANTIC_THREAT_DEPTH_STALE_DURING_VALIDATION'; end if; end if;
  end if;
  return new;
end$function$;
revoke all on function programacion.fn_guard_input_family_semantic_depth_v510() from public;
grant execute on function programacion.fn_guard_input_family_semantic_depth_v510() to postgres;

create or replace function programacion.fn_guard_input_stage_earliest_boundary()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare v_revision text; v_version_id bigint; v_cfg jsonb; v_stage text; v_incomplete boolean;
begin
  select r.contract_revision,r.version_id into v_revision,v_version_id from programacion.input_readiness_runs r where r.id=new.run_id;
  if v_revision not in ('5.10','5.11','5.12') or new.applicability<>'APPLICABLE' then return new; end if;
  select coalesce(c.especificacion->'family_stage_requirements'->new.family_code,'{}'::jsonb) into v_cfg from programacion.contratos c where c.version_id=v_version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  if v_cfg='{}'::jsonb then return new; end if;
  v_stage:=upper(coalesce(v_cfg->>'coverage_required_by','')); v_incomplete:=new.coverage_status<>'COMPLETE' or new.well_defined_status<>'COMPLETE'; if not v_incomplete then return new; end if;
  if v_stage='IMPLEMENTATION' then if new.story_ready_status<>'READY' then raise exception 'STAGE_AUTHORITY_EARLIER_STAGE_OVERBLOCK:%:STORY',new.family_code; end if; if new.severity<>'P1' then raise exception 'STAGE_AUTHORITY_SEVERITY_MISMATCH:% expected=P1 actual=%',new.family_code,new.severity; end if;
  elsif v_stage='QA' then if new.story_ready_status<>'READY' or new.implementation_ready_status<>'READY' then raise exception 'STAGE_AUTHORITY_EARLIER_STAGE_OVERBLOCK:%:PRE_QA',new.family_code; end if; if new.severity<>'P2' then raise exception 'STAGE_AUTHORITY_SEVERITY_MISMATCH:% expected=P2 actual=%',new.family_code,new.severity; end if;
  elsif v_stage='PRODUCTION' then if new.story_ready_status<>'READY' or new.implementation_ready_status<>'READY' or new.qa_ready_status<>'READY' then raise exception 'STAGE_AUTHORITY_EARLIER_STAGE_OVERBLOCK:%:PRE_PRODUCTION',new.family_code; end if; if new.severity<>'P3' then raise exception 'STAGE_AUTHORITY_SEVERITY_MISMATCH:% expected=P3 actual=%',new.family_code,new.severity; end if; end if;
  return new;
end$function$;
revoke all on function programacion.fn_guard_input_stage_earliest_boundary() from public;
grant execute on function programacion.fn_guard_input_stage_earliest_boundary() to postgres;

update public.lf_error_knowledge
set frecuencia=coalesce(frecuencia,0)+1,
    ultima_vez=now(),
    evidencia=concat_ws(E'\n',nullif(evidencia,''),'2026-08-22 INPUT_GOVERNANCE v5.12 recurrence: preflight found fn_guard_input_family_semantic_depth_v510 and fn_guard_input_stage_earliest_boundary limited to revisions 5.10/5.11, which would silently skip their protections for new 5.12 runs.'),
    prevencion=concat_ws(E'\n',nullif(prevencion,''),'V5.12 recurrence control: every contract revision migration must scan active programacion input-governance functions for N-1 revision literals and migrate all guards/consumers atomically before successor runs are created.'),
    validacion=concat_ws(E'\n',nullif(validacion,''),'V5.12 regression: semantic-depth and earliest-stage guards must explicitly execute for contract_revision=5.12; catalog scan must show no active input-governance guard that recognizes 5.11 but omits 5.12.'),
    source_context='INPUT_GOVERNANCE_V512_REVISION_GATE_CLOSURE_20260822',
    source_ref='programacion.fn_guard_input_family_semantic_depth_v510 + programacion.fn_guard_input_stage_earliest_boundary'
where codigo='ARC-011';

update public.lf_prevention_rules
set regla=concat_ws(E'\n',nullif(regla,''),'V5.12: antes de crear sucesores, escanear funciones runtime del Input Governance por literales N-1. Cualquier guard que acepte 5.11 y omita 5.12 bloquea el rollout hasta ser migrado y probado.'),
    justificacion=concat_ws(E'\n',nullif(justificacion,''),'Recurrencia 2026-08-22: semantic-depth y earliest-stage guards habrían quedado inertes en 5.12 por lista de revisiones no actualizada.')
where regla_codigo='PRV-ARC-011';