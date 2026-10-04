-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / N-14 / PAULO-179
-- IGQ-004: reconcile B2B-CARGA-002 V4 against stale B2B_IMP_DUE_DATE projection metadata.
-- Owner: SUPER_ADMIN.
-- Scope: metadata/contract projection only. No production/runtime activation.
-- Runtime reachability is intentional and must be judged by N-9 rollback-only before persistence.
-- History preservation: stable physical IDs remain; contract_field_matrix_v3 remains unchanged.

begin;

DO $pre$
DECLARE
  v_rule_count integer;
  v_link_count integer;
  v_projected_required_count integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING (capability_code)
    WHERE r.capability_code='CURRENTNESS_AUTHORITY'
      AND r.status='ACTIVE'
      AND c.version='1.0.0'
  ) THEN
    RAISE EXCEPTION 'BLOCK_N14_CURRENTNESS_AUTHORITY_NOT_CURRENT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING (capability_code)
    WHERE r.capability_code='CAPABILITY_VERSION_COMPATIBILITY'
      AND r.status='ACTIVE'
      AND c.version='1.0.0'
  ) THEN
    RAISE EXCEPTION 'BLOCK_N14_VERSION_COMPATIBILITY_NOT_CURRENT';
  END IF;

  SELECT count(*) INTO v_rule_count
  FROM lf_ops.reglas r
  JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
  JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
  WHERE r.codigo='B2B-RULE-INSTALLMENT-ASSISTED-LOAD-001'
    AND p.codigo='B2B-CARGA-002'
    AND r.valor_config->>'owner_decision'='APPROVED_2026-09-17_V4'
    AND r.valor_config->'contract_field_matrix_v4'->>'absolute_due_dates_in_standard_excel'='DENY'
    AND NOT coalesce(r.valor_config->'contract_field_matrix_v4'->'standard_excel_schedule_headers','[]'::jsonb)
            ? 'B2B_IMP_DUE_DATE';
  IF v_rule_count <> 1 THEN
    RAISE EXCEPTION 'BLOCK_N14_V4_AUTHORITY_UNRESOLVED count=%',v_rule_count;
  END IF;

  SELECT count(*) INTO v_link_count
  FROM lf_ops.campos c
  JOIN lf_ops.campos_pantallas cp ON cp.campo_id=c.id
  JOIN lf_ops.pantallas p ON p.id=cp.pantalla_id
  WHERE p.codigo='B2B-CARGA-002'
    AND c.codigo='B2B_IMP_DUE_DATE'
    AND coalesce(cp.required_override,c.es_requerido)
    AND cp.context_key='IMPORT_INSTALLMENTS';
  IF v_link_count <> 1 THEN
    RAISE EXCEPTION 'BLOCK_N14_STALE_METADATA_PREIMAGE_UNRESOLVED count=%',v_link_count;
  END IF;

  SELECT count(*) INTO v_projected_required_count
  FROM lf_ops.fn_b2b_backoffice_login_contract('B2B_APP_SHELL','B2B_CARGAS','B2B-CARGA-002') x
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(x.contract->'fields','[]'::jsonb)) f
  WHERE f->>'field_code'='B2B_IMP_DUE_DATE'
    AND coalesce((f->>'required')::boolean,false)
    AND f->'ui'->>'context_key'='IMPORT_INSTALLMENTS';
  IF v_projected_required_count <> 1 THEN
    RAISE EXCEPTION 'BLOCK_N14_REACHABILITY_NOT_PROVEN projected_required=%',v_projected_required_count;
  END IF;
END
$pre$;

UPDATE lf_ops.campos c
SET es_requerido=false,
    descripcion='Fecha de vencimiento canónica generada por LF para el cronograma interno. En B2B-CARGA-002 V4 no es columna del Excel estándar ni dato requerido al partner; se genera después de confirmar la cuota 0 usando configuración gobernada de empresa o plan. La identidad B2B_IMP_DUE_DATE se conserva por compatibilidad e historia.',
    updated_at=now()
WHERE c.codigo='B2B_IMP_DUE_DATE';

UPDATE lf_ops.campos_pantallas cp
SET required_override=false,
    context_key='GENERATED_INSTALLMENT_SCHEDULE',
    nota='N-14 / APPROVED_2026-09-17_V4: identidad legacy preservada; B2B_IMP_DUE_DATE deja de ser input del Excel estándar y pasa a dato SYSTEM_ONLY generado por LF después de CUOTA_0. No borrar: compatibilidad/historia.',
    updated_at=now()
FROM lf_ops.campos c, lf_ops.pantallas p
WHERE cp.campo_id=c.id
  AND cp.pantalla_id=p.id
  AND c.codigo='B2B_IMP_DUE_DATE'
  AND p.codigo='B2B-CARGA-002';

UPDATE lf_ops.campos_validaciones cv
SET titulo='Orden cronológico del cronograma generado',
    descripcion='Validación posterior a la generación server-side de fechas por LF; no exige ni valida una columna de fecha absoluta en el Excel estándar V4.',
    valor_config=coalesce(cv.valor_config,'{}'::jsonb)
      || jsonb_build_object(
           'standard_excel_input','DENY',
           'evaluation_stage','POST_CUOTA0_LF_GENERATION',
           'date_authority','GOVERNED_COMPANY_OR_PLAN_CONFIGURATION',
           'authority_ref','B2B-RULE-INSTALLMENT-ASSISTED-LOAD-001#APPROVED_2026-09-17_V4'
         ),
    updated_at=now()
FROM lf_ops.campos c
WHERE cv.campo_id=c.id
  AND c.codigo='B2B_IMP_DUE_DATE'
  AND cv.codigo='B2B_IMP_VAL_DUE_DATE_ORDER';

UPDATE lf_ops.reglas r
SET descripcion='En modalidad Cuotas, LF admite únicamente dos contratos Excel versionados y estrictos. EXCEL_ASISTIDO aporta la base común y activa el asistente para completar oferta, plan y cronograma; EXCEL_COMPLETO aporta la base, oferta, plan y cronograma. En V4 el cronograma estándar del archivo es autoridad para PLAN, CUOTA y MONTO, pero no para fechas absolutas: B2B_IMP_DUE_DATE no es input del Excel estándar. LF genera las fechas regulares después de confirmar CUOTA_0 usando configuración gobernada de empresa o plan. La identidad física legacy de B2B_IMP_DUE_DATE se conserva como dato interno para compatibilidad e historia, no como requisito de importación.',
    valor_config=jsonb_set(
      jsonb_set(
        r.valor_config,
        '{contract_field_matrix_v4,physical_field_mutation_status}',
        to_jsonb('EXECUTED_N14_DUE_DATE_PROJECTION_RECONCILIATION'::text),
        true
      ),
      '{contract_field_matrix_v4,due_date_physical_semantic}',
      jsonb_build_object(
        'field_code','B2B_IMP_DUE_DATE',
        'standard_excel_input','DENY',
        'runtime_role','LF_GENERATED_INTERNAL_SCHEDULE_DATE',
        'generation_anchor','PAYMENT_CONFIRMED_FOR_CUOTA_0',
        'date_authority','GOVERNED_COMPANY_OR_PLAN_CONFIGURATION',
        'legacy_identity_preserved',true
      ),
      true
    ),
    updated_at=now()
WHERE r.codigo='B2B-RULE-INSTALLMENT-ASSISTED-LOAD-001';

DO $post$
DECLARE
  v_bad_projection integer;
  v_good_projection integer;
  v_legacy_identity integer;
  v_history_v3 boolean;
  v_v4_deny boolean;
BEGIN
  SELECT count(*) INTO v_bad_projection
  FROM lf_ops.fn_b2b_backoffice_login_contract('B2B_APP_SHELL','B2B_CARGAS','B2B-CARGA-002') x
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(x.contract->'fields','[]'::jsonb)) f
  WHERE f->>'field_code'='B2B_IMP_DUE_DATE'
    AND (
      coalesce((f->>'required')::boolean,false)
      OR f->'ui'->>'context_key'='IMPORT_INSTALLMENTS'
    );
  IF v_bad_projection <> 0 THEN
    RAISE EXCEPTION 'BLOCK_N14_V4_PROJECTION_CONTRADICTION_REMAINS count=%',v_bad_projection;
  END IF;

  SELECT count(*) INTO v_good_projection
  FROM lf_ops.fn_b2b_backoffice_login_contract('B2B_APP_SHELL','B2B_CARGAS','B2B-CARGA-002') x
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(x.contract->'fields','[]'::jsonb)) f
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(f->'validations','[]'::jsonb)) v
  WHERE f->>'field_code'='B2B_IMP_DUE_DATE'
    AND NOT coalesce((f->>'required')::boolean,true)
    AND f->'ui'->>'context_key'='GENERATED_INSTALLMENT_SCHEDULE'
    AND f->'ui'->>'visibility_mode'='SYSTEM_ONLY'
    AND v->>'validation_code'='B2B_IMP_VAL_DUE_DATE_ORDER'
    AND v->'config'->>'standard_excel_input'='DENY'
    AND v->'config'->>'evaluation_stage'='POST_CUOTA0_LF_GENERATION';
  IF v_good_projection <> 1 THEN
    RAISE EXCEPTION 'BLOCK_N14_RECONCILED_PROJECTION_NOT_EXACT count=%',v_good_projection;
  END IF;

  SELECT count(*) INTO v_legacy_identity
  FROM lf_ops.campos c
  JOIN lf_ops.campos_pantallas cp ON cp.campo_id=c.id
  JOIN lf_ops.pantallas p ON p.id=cp.pantalla_id
  WHERE c.codigo='B2B_IMP_DUE_DATE'
    AND p.codigo='B2B-CARGA-002';
  IF v_legacy_identity <> 1 THEN
    RAISE EXCEPTION 'BLOCK_N14_LEGACY_IDENTITY_NOT_PRESERVED count=%',v_legacy_identity;
  END IF;

  SELECT
    coalesce(r.valor_config->'contract_field_matrix_v3'->'excel_complete_required_schedule','[]'::jsonb)
      ? 'B2B_IMP_DUE_DATE',
    r.valor_config->'contract_field_matrix_v4'->>'absolute_due_dates_in_standard_excel'='DENY'
      AND NOT coalesce(r.valor_config->'contract_field_matrix_v4'->'standard_excel_schedule_headers','[]'::jsonb)
                ? 'B2B_IMP_DUE_DATE'
  INTO v_history_v3,v_v4_deny
  FROM lf_ops.reglas r
  WHERE r.codigo='B2B-RULE-INSTALLMENT-ASSISTED-LOAD-001';

  IF NOT coalesce(v_history_v3,false) THEN
    RAISE EXCEPTION 'BLOCK_N14_V3_HISTORY_NOT_PRESERVED';
  END IF;
  IF NOT coalesce(v_v4_deny,false) THEN
    RAISE EXCEPTION 'BLOCK_N14_V4_DENY_NOT_PRESERVED';
  END IF;
END
$post$;

commit;
