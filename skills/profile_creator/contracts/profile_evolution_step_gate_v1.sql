-- PROFILE_EVOLUTION_STEP_GATE_V1
-- Applies only to ACTUALIZACION_PERFIL_LF executions bound to v0.2.
-- Blocked/retry rows remain durable; semantic assertions are enforced on clean rows.

create or replace function public.lf_profile_evolution_step_gate_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','public'
as $function$
declare
  v_manifest jsonb;
  v_admitted_sha text;
begin
  select manifest into v_manifest
  from public.lf_operation_execution
  where execution_id=new.execution_id and operation_code='ACTUALIZACION_PERFIL_LF';

  if v_manifest is null
     or coalesce(v_manifest->>'contract_code','') <> 'CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2'
     or new.status <> 'STEP_PASS_WITH_EVIDENCE' then
    return new;
  end if;

  if new.step_id='profile_assessment' then
    if new.evidence_payload->>'schema' <> 'PROFILE_ASSESSMENT_V1'
       or coalesce(new.evidence_payload->'write_authorized','true'::jsonb) <> 'false'::jsonb
       or coalesce(new.evidence_payload->'admission_required','false'::jsonb) <> 'true'::jsonb then
      raise exception 'PROFILE_EVOLUTION_ASSESSMENT_BOUNDARY_INVALID';
    end if;
  elsif new.step_id='evolution_mode_selection' then
    if coalesce(new.evidence_payload->>'evolution_mode','') not in
       ('NO_CHANGE','PATCH','SPECIALIZE','ADAPT','REARCHITECT','OPTIMIZE') then
      raise exception 'PROFILE_EVOLUTION_MODE_INVALID';
    end if;
  elsif new.step_id='method_capability_composition' then
    if coalesce(new.evidence_payload->'execution_authorized','true'::jsonb) <> 'false'::jsonb
       or coalesce(new.evidence_payload->'admission_required','false'::jsonb) <> 'true'::jsonb then
      raise exception 'PROFILE_EVOLUTION_SELECTION_AUTHORITY_LEAK';
    end if;
  elsif new.step_id='candidate_materialization' then
    if coalesce(new.evidence_payload->'reversible','false'::jsonb) <> 'true'::jsonb
       or new.evidence_payload->>'authority_state' <> 'NON_AUTHORITY_CANDIDATE'
       or coalesce(new.evidence_payload->>'candidate_sha','') !~ '^[0-9a-f]{40}$' then
      raise exception 'PROFILE_EVOLUTION_CANDIDATE_BOUNDARY_INVALID';
    end if;
  elsif new.step_id='benchmark_eval' then
    if new.evidence_payload->>'benchmark_verdict' <> 'PASS'
       or coalesce((new.evidence_payload->>'critical_regressions')::integer,1) <> 0
       or coalesce(new.evidence_payload->'false_pass_not_worse','false'::jsonb) <> 'true'::jsonb
       or coalesce(new.evidence_payload->'valid_behavior_preserved','false'::jsonb) <> 'true'::jsonb then
      raise exception 'PROFILE_EVOLUTION_BENCHMARK_NOT_ADMISSIBLE';
    end if;
  elsif new.step_id='challenge_assurance' then
    if coalesce(new.evidence_payload->>'assurance_verdict','') not in ('PASS','NOT_REQUIRED_WITH_EVIDENCE') then
      raise exception 'PROFILE_EVOLUTION_ASSURANCE_NOT_CLEAN';
    end if;
  elsif new.step_id='admission' then
    if new.evidence_payload->>'admission_verdict' <> 'PASS'
       or coalesce(new.evidence_payload->>'admitted_candidate_sha','') !~ '^[0-9a-f]{40}$' then
      raise exception 'PROFILE_EVOLUTION_ADMISSION_NOT_PASS';
    end if;
  elsif new.step_id='github_write' then
    select evidence_payload->>'admitted_candidate_sha' into v_admitted_sha
    from public.lf_operation_execution_steps
    where execution_id=new.execution_id and step_id='admission';
    if v_admitted_sha is null
       or new.evidence_payload->>'candidate_source_sha' <> v_admitted_sha then
      raise exception 'PROFILE_EVOLUTION_WRITE_NOT_BOUND_TO_ADMITTED_CANDIDATE';
    end if;
  elsif new.step_id='evolution_state_record' then
    if new.evidence_payload->>'schema' <> 'PROFILE_EVOLUTION_STATE_V1'
       or new.evidence_payload->>'result' <> 'ADMITTED'
       or coalesce(new.evidence_payload->>'benchmark_ref','')=''
       or coalesce(new.evidence_payload->>'admission_ref','')='' then
      raise exception 'PROFILE_EVOLUTION_STATE_NOT_PROVEN';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_profile_evolution_step_gate_v1 on public.lf_operation_execution_steps;
create trigger trg_profile_evolution_step_gate_v1
before insert or update on public.lf_operation_execution_steps
for each row execute function public.lf_profile_evolution_step_gate_v1();
