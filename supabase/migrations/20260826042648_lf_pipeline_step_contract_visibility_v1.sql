-- LF knowledge pipeline readiness hardening.
-- RTE-010: keep canonical step-contract reads aligned with the active status vocabulary.
-- Scope: read surface only; CANDIDATO rows remain hidden.

begin;

create or replace view public.v_lf_operation_step_contracts
with (security_invoker = true)
as
select
  operation_code,
  step_id,
  step_order,
  execution_order,
  contract_code,
  purpose,
  input_required,
  resolver_ref,
  output_payload,
  pass_condition,
  block_condition,
  blocking_code,
  mini_judge_code,
  required_evidence_keys,
  next_if_pass,
  next_if_blocked,
  status,
  notes,
  created_at,
  updated_at
from public.lf_operation_step_contracts
where status in ('ACTIVE', 'ACTIVO');

comment on view public.v_lf_operation_step_contracts is
  'Canonical active operation-step contracts. ACTIVE and ACTIVO are accepted active vocabularies; candidate/inactive rows remain excluded.';

do $$
declare
  v_mismatch_count integer;
  v_candidate_leak_count integer;
begin
  with target_operations(operation_code) as (
    values
      ('ORQUESTACION_PIPELINE_LF'),
      ('EXTRACCION_FUENTES_DIGITALES_LF'),
      ('HOMOLOGACION_FUENTES_DIGITALES_LF'),
      ('EXTRACCION_NOTICIAS_FINANCIERAS_LF'),
      ('EXTRACCION_DOCUMENTOS_REGULATORIOS_LF'),
      ('ANALISIS_RIESGO_CONTENIDO_LF'),
      ('ESCRITURA_BASE_CONOCIMIENTO_LF')
  ), counts as (
    select
      t.operation_code,
      (
        select count(*)
        from public.lf_operation_step_contracts s
        where s.operation_code = t.operation_code
          and s.status in ('ACTIVE', 'ACTIVO')
      ) as physical_active_steps,
      (
        select count(*)
        from public.v_lf_operation_step_contracts v
        where v.operation_code = t.operation_code
      ) as canonical_visible_steps
    from target_operations t
  )
  select count(*)
    into v_mismatch_count
  from counts
  where physical_active_steps <> canonical_visible_steps
     or physical_active_steps = 0;

  if v_mismatch_count <> 0 then
    raise exception 'RTE-010 self-test failed: canonical active step counts diverge for % target operations', v_mismatch_count;
  end if;

  select count(*)
    into v_candidate_leak_count
  from public.v_lf_operation_step_contracts v
  join public.lf_operation_step_contracts s
    on s.operation_code = v.operation_code
   and s.step_id = v.step_id
  where s.status not in ('ACTIVE', 'ACTIVO');

  if v_candidate_leak_count <> 0 then
    raise exception 'RTE-010 self-test failed: canonical view leaked % non-active steps', v_candidate_leak_count;
  end if;
end
$$;

commit;
