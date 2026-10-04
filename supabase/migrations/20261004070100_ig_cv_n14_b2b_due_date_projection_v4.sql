-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / N-14 / PAULO-179
-- IGQ-004: reconcile B2B-CARGA-002 V4 contract projection vs stale B2B_IMP_DUE_DATE metadata.
-- Classification proven before mutation: REACHABLE_CURRENT.
-- V4 semantic authority: B2B-RULE-INSTALLMENT-ASSISTED-LOAD-001 / APPROVED_2026-09-17_V4.
-- The field is preserved for internal generated schedule consumers; it is no longer an Excel file input.

begin;

do $n14_pre$
declare
  v_count integer;
  v_rule jsonb;
begin
  select count(*) into v_count
  from lf_ops.campos c
  where c.codigo='B2B_IMP_DUE_DATE'
    and c.source_type='FILE'
    and c.es_requerido=true
    and c.source_decision_id='DEC-B2B-HANDOFF-SCREEN-PACKAGE-001'
    and c.source_decision_number=52;
  if v_count<>1 then
    raise exception 'N14_PRECONDITION_FIELD_DRIFT: expected exactly one stale FILE+required B2B_IMP_DUE_DATE, got %',v_count;
  end if;

  select r.valor_config into v_rule
  from lf_ops.reglas r
  where r.codigo='B2B-RULE-INSTALLMENT-ASSISTED-LOAD-001';
  if v_rule is null
     or coalesce(v_rule->>'owner_decision','')<>'APPROVED_2026-09-17_V4'
     or coalesce(v_rule#>>'{contract_field_matrix_v4,absolute_due_dates_in_standard_excel}','')<>'DENY'
     or coalesce(v_rule->>'first_installment_date_policy','')<>'DERIVED_BY_LF_AFTER_CUOTA0_PAYMENT_CONFIRMED_NOT_FILE_INPUT'
     or coalesce(v_rule->>'date_source_policy','')<>'GOVERNED_CONFIGURATION_AFTER_CUOTA0_PAYMENT_CONFIRMED_FOR_STANDARD_DYNAMIC_DATE_MODEL' then
    raise exception 'N14_CONTRACT_AUTHORITY_NOT_V4';
  end if;

  select count(*) into v_count
  from lf_ops.campos_pantallas cp
  join lf_ops.campos c on c.id=cp.campo_id
  join lf_ops.pantallas p on p.id=cp.pantalla_id
  where p.codigo='B2B-CARGA-002'
    and c.codigo='B2B_IMP_DUE_DATE'
    and cp.context_key='IMPORT_INSTALLMENTS'
    and cp.visibility_mode='SYSTEM_ONLY'
    and cp.required_override=true;
  if v_count<>1 then
    raise exception 'N14_PRECONDITION_SCREEN_PROJECTION_DRIFT: expected one reachable stale binding, got %',v_count;
  end if;
end;
$n14_pre$;

-- Preserve the canonical field and its historical source decision. Reclassify only its effective input semantics.
update lf_ops.campos
set source_type='SYSTEM',
    es_requerido=false,
    descripcion='Fecha de vencimiento generada por LF para el cronograma interno después de la confirmación de pago de cuota 0 y según configuración gobernada; no es input del Excel estándar V4.',
    updated_at=now()
where codigo='B2B_IMP_DUE_DATE'
  and source_decision_id='DEC-B2B-HANDOFF-SCREEN-PACKAGE-001'
  and source_decision_number=52;

update lf_ops.campos_pantallas cp
set required_override=false,
    nota='V4: campo interno generado por LF; SYSTEM_ONLY; no header ni input requerido del Excel estándar. Se conserva el binding para consumers internos y la trazabilidad histórica.',
    updated_at=now()
where cp.pantalla_id=(select id from lf_ops.pantallas where codigo='B2B-CARGA-002')
  and cp.campo_id=(select id from lf_ops.campos where codigo='B2B_IMP_DUE_DATE')
  and cp.context_key='IMPORT_INSTALLMENTS';

do $n14_post$
declare
  v_count integer;
  v_field_id bigint;
begin
  select c.id into v_field_id
  from lf_ops.campos c
  where c.codigo='B2B_IMP_DUE_DATE'
    and c.source_type='SYSTEM'
    and c.es_requerido=false
    and c.source_decision_id='DEC-B2B-HANDOFF-SCREEN-PACKAGE-001'
    and c.source_decision_number=52;
  if v_field_id is null then
    raise exception 'N14_POST_FIELD_NOT_RECONCILED';
  end if;

  select count(*) into v_count
  from lf_ops.campos_pantallas cp
  join lf_ops.pantallas p on p.id=cp.pantalla_id
  where p.codigo='B2B-CARGA-002'
    and cp.campo_id=v_field_id
    and cp.context_key='IMPORT_INSTALLMENTS'
    and cp.visibility_mode='SYSTEM_ONLY'
    and cp.required_override=false;
  if v_count<>1 then
    raise exception 'N14_POST_SCREEN_BINDING_NOT_RECONCILED:%',v_count;
  end if;

  -- Negative legacy/currentness proof: history and downstream validation metadata remain present;
  -- no field/link deletion and no blind activation/deactivation was performed.
  select count(*) into v_count
  from lf_ops.campos_validaciones cv
  where cv.campo_id=v_field_id
    and cv.codigo='B2B_IMP_VAL_DUE_DATE_ORDER'
    and cv.estado='CANDIDATO'
    and cv.blocking=true;
  if v_count<>1 then
    raise exception 'N14_HISTORY_OR_COMPATIBILITY_DRIFT:%',v_count;
  end if;

  if not exists (
    select 1
    from lf_ops.reglas r
    where r.codigo='B2B-RULE-INSTALLMENT-ASSISTED-LOAD-001'
      and r.valor_config->>'owner_decision'='APPROVED_2026-09-17_V4'
      and r.valor_config#>>'{contract_field_matrix_v4,absolute_due_dates_in_standard_excel}'='DENY'
      and r.valor_config->>'first_installment_date_policy'='DERIVED_BY_LF_AFTER_CUOTA0_PAYMENT_CONFIRMED_NOT_FILE_INPUT'
  ) then
    raise exception 'N14_POST_CONTRACT_AUTHORITY_DRIFT';
  end if;
end;
$n14_post$;

commit;
