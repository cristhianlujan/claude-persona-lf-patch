create or replace function programacion.fn_guard_input_family_execution_insert()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $$
declare v_curator_component_id bigint;
begin
  select curator_component_id into v_curator_component_id from programacion.input_readiness_runs where id=new.run_id;
  if v_curator_component_id is null then raise exception 'CURATOR_COMPONENT_NOT_RESOLVABLE:%',new.run_id; end if;
  if nullif(btrim(coalesce(new.curator_evidence->>'execution_id','')),'') is null then raise exception 'CURATOR_EXECUTION_ID_REQUIRED:%',new.family_code; end if;
  if coalesce((new.curator_evidence->>'component_id')::bigint,-1)<>v_curator_component_id then raise exception 'CURATOR_EVIDENCE_COMPONENT_MISMATCH:%',new.family_code; end if;
  return new;
end;
$$;

create or replace function programacion.fn_guard_input_family_execution_update()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $$
declare
  v_validator_component_id bigint; v_curator_execution_id text; v_validator_execution_id text; v_assertion jsonb; v_eval jsonb; v_expected_result text;
begin
  if old.validator_outcome<>'PENDING' or new.validator_outcome='PENDING' then return new; end if;
  select validator_component_id into v_validator_component_id from programacion.input_readiness_runs where id=old.run_id;
  v_curator_execution_id:=old.curator_evidence->>'execution_id';
  v_validator_execution_id:=new.validator_evidence->>'execution_id';
  if nullif(btrim(coalesce(v_validator_execution_id,'')),'') is null then raise exception 'VALIDATOR_EXECUTION_ID_REQUIRED:%',old.family_code; end if;
  if v_validator_execution_id=v_curator_execution_id then raise exception 'VALIDATOR_EXECUTION_ID_NOT_INDEPENDENT:%',old.family_code; end if;
  if coalesce((new.validator_evidence->>'component_id')::bigint,-1)<>v_validator_component_id then raise exception 'VALIDATOR_EVIDENCE_COMPONENT_MISMATCH:%',old.family_code; end if;
  if new.validator_evidence->>'validated_curator_execution_id' is distinct from v_curator_execution_id then raise exception 'VALIDATOR_CURATOR_EXECUTION_BINDING_MISMATCH:%',old.family_code; end if;
  if jsonb_typeof(new.validator_evidence->'assertions')<>'array' then raise exception 'VALIDATOR_ASSERTIONS_REQUIRED:%',old.family_code; end if;
  for v_assertion in select value from jsonb_array_elements(new.validator_evidence->'assertions') loop
    if upper(coalesce(v_assertion->>'result','')) not in ('PASS','FAIL') then raise exception 'ASSERTION_RESULT_REQUIRED:%',old.family_code; end if;
    if nullif(coalesce(v_assertion->>'source_observed_sha256',''),'') is null then raise exception 'ASSERTION_SOURCE_SHA_REQUIRED:%',old.family_code; end if;
    v_eval:=programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion);
    v_expected_result:=case when coalesce((v_eval->>'passed')::boolean,false) then 'PASS' else 'FAIL' end;
    if upper(v_assertion->>'result')<>v_expected_result then raise exception 'ASSERTION_STORED_RESULT_MISMATCH:%',old.family_code; end if;
    if v_assertion->>'source_observed_sha256' is distinct from v_eval->>'source_observed_sha256' then raise exception 'ASSERTION_STORED_SOURCE_SHA_MISMATCH:%',old.family_code; end if;
    if new.validator_outcome='PASS' and v_expected_result<>'PASS' then raise exception 'VALIDATOR_PASS_CONTAINS_FAILED_ASSERTION:%',old.family_code; end if;
  end loop;
  return new;
end;
$$;

revoke all on function programacion.fn_guard_input_family_execution_insert() from public,anon,authenticated;
revoke all on function programacion.fn_guard_input_family_execution_update() from public,anon,authenticated;

drop trigger if exists trg_input_family_assessment_00_execution_insert on programacion.input_family_assessments;
create trigger trg_input_family_assessment_00_execution_insert before insert on programacion.input_family_assessments for each row execute function programacion.fn_guard_input_family_execution_insert();

drop trigger if exists trg_input_family_assessment_00_execution_update on programacion.input_family_assessments;
create trigger trg_input_family_assessment_00_execution_update before update on programacion.input_family_assessments for each row execute function programacion.fn_guard_input_family_execution_update();

update programacion.contratos c
set especificacion=jsonb_set(c.especificacion,'{semantic_fail_closed,independent_execution_receipts_required}','true'::jsonb,true)
where c.version_id=19 and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.especificacion->>'contract_revision'='5.6';

update programacion.contratos c
set especificacion=jsonb_set(c.especificacion,'{semantic_fail_closed,assertion_result_and_source_sha_required}','true'::jsonb,true)
where c.version_id=19 and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.especificacion->>'contract_revision'='5.6';

update programacion.contratos c
set especificacion=jsonb_set(c.especificacion,'{assertion_contract}','"ASSERTION_RECEIPT_V2_RESULT_BOUND"'::jsonb,true)
where c.version_id=19 and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.especificacion->>'contract_revision'='5.6';

update programacion.contratos c
set especificacion=jsonb_set(c.especificacion,'{negative_tests}',coalesce(c.especificacion->'negative_tests','[]'::jsonb)||jsonb_build_array('CURATOR_VALIDATOR_SAME_EXECUTION_ID','ASSERTION_STORED_RESULT_MISMATCH','ASSERTION_STORED_SOURCE_SHA_MISMATCH'),true)
where c.version_id=19 and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.especificacion->>'contract_revision'='5.6';