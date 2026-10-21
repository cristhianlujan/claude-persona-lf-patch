-- IG M10.8: adopt FIX_FORWARD as the operational recovery strategy.
-- Owner decision 2026-10-21: do not return operationally to archived M9.0.
-- M9.0 remains evidence/history only.
--
-- IMPORTANT: this decision does NOT remove database transaction rollback,
-- Migration Train rollback, sandbox/canary reversibility, or negative-test cleanup.
-- It does not authorize production.

BEGIN;

DO $m108$
DECLARE
  v_progress numeric;
  v_cp4 record;
  v_cp5 record;
  v_decision_count integer;
  v_spec jsonb;
  v_transition jsonb;
BEGIN
  SELECT progress_pct INTO v_progress
  FROM programacion.v_engineering_work_progress
  WHERE id=479;

  IF v_progress IS DISTINCT FROM 60.00 THEN
    RAISE EXCEPTION 'M108_FIX_FORWARD_PRE_PROGRESS_DRIFT:%',v_progress;
  END IF;

  SELECT status,evidence_ref,title INTO v_cp4
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=479 AND checkpoint_code='EXPIRY_DECISION'
  FOR UPDATE;

  SELECT status,evidence_ref,title INTO v_cp5
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=479 AND checkpoint_code='GATE_READBACK'
  FOR UPDATE;

  IF v_cp4.status IS DISTINCT FROM 'PENDING'
     OR v_cp4.evidence_ref IS NOT NULL
     OR v_cp5.status IS DISTINCT FROM 'PENDING'
     OR v_cp5.evidence_ref IS NOT NULL
  THEN
    RAISE EXCEPTION 'M108_FIX_FORWARD_CHECKPOINT_PRESTATE_DRIFT:cp4=% cp5=%',
      row_to_json(v_cp4),row_to_json(v_cp5);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
    WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      AND u.unit_code='M10.7'
      AND u.disposition='ASSIGNED'
      AND w.status='DONE'
  ) THEN
    RAISE EXCEPTION 'M108_FIX_FORWARD_M107_NOT_DONE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=479
      AND checkpoint_code='ARCHIVED_BUNDLE_RECOVERABLE'
      AND status='DONE'
      AND evidence_ref IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'M108_FIX_FORWARD_ARCHIVE_EVIDENCE_MISSING';
  END IF;

  SELECT count(*) INTO v_decision_count
  FROM transversal.decision_log
  WHERE adr='DEC-IG-M10.8-FIX-FORWARD-20261021';

  IF v_decision_count <> 0 THEN
    RAISE EXCEPTION 'M108_FIX_FORWARD_DECISION_ALREADY_EXISTS:%',v_decision_count;
  END IF;

  INSERT INTO transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
  VALUES(
    'DEC-IG-M10.8-FIX-FORWARD-20261021',
    'M10.8 — estrategia operativa de recuperación FIX_FORWARD',
    'ADOPT_FIX_FORWARD. Ante una falla operativa del Input Governance no se regresará automáticamente ni por defecto al bundle archivado M9.0. La recuperación es detectar, aislar, corregir, validar y desplegar la corrección. El bundle M9.0 queda solo como evidencia histórica/auditoría.',
    'Decisión explícita del owner: si la versión anterior es peor o contiene defectos conocidos, volver a ella no es una recuperación válida.',
    'M10.8 se convierte en gate preoperativo de estrategia FIX_FORWARD. Se preservan rollback transaccional de DB/migraciones, reversibilidad sandbox/canary y cleanup de pruebas. Esta decisión no autoriza producción.',
    'VIGENTE'
  );

  UPDATE programacion.engineering_work_items
  SET title='M10.8 — Recovery strategy gate (FIX_FORWARD)',
      objective='Fijar FIX_FORWARD como estrategia operativa: corregir hacia adelante ante fallas y no volver al bundle M9.0.',
      expected_result='FIX_FORWARD documentado; M9.0 solo evidencia histórica; controles técnicos reversibles preservados.',
      acceptance_criteria=jsonb_build_array(
        'M10.7 DONE',
        'M9.0 archivado queda EVIDENCE_HISTORY_ONLY',
        'operational_recovery_mode=FIX_FORWARD',
        'operational_rollback_to_m9_0=FORBIDDEN',
        'rollback transaccional y reversibilidad de pruebas preservados',
        'readback terminal PASS',
        'sin autorización de producción'
      ),
      updated_at=now(),
      updated_by_execution_id='IG_M108_FIX_FORWARD_DECISION_V1'
  WHERE id=479
    AND status='IN_PROGRESS';

  UPDATE programacion.engineering_plan_units
  SET exit_criterion=
    'M10.8 cierra cuando M10.7 está DONE, el bundle M9.0 permanece recuperable solo como evidencia histórica, el owner adopta FIX_FORWARD como estrategia operativa y el readback terminal demuestra que no existe dependencia de rollback operativo hacia M9.0. Se preservan rollback transaccional, reversibilidad de pruebas y controles de seguridad. No autoriza producción.'
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND unit_code='M10.8'
    AND disposition='ASSIGNED';

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=jsonb_set(
    unit_metadata,
    '{operational_maturity_policy_v1}',
    coalesce(unit_metadata#>'{operational_maturity_policy_v1}','{}'::jsonb)
      || jsonb_build_object(
           'state','SUPERSEDED_BY_FIX_FORWARD',
           'superseded_by','recovery_policy_v2',
           'expiry_decision_eligible',false,
           'production_authorized',false
         ),
    true
  )
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND unit_code='M10.8'
    AND disposition='ASSIGNED';

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=jsonb_set(
    unit_metadata,
    '{recovery_policy_v2}',
    jsonb_build_object(
      'schema_version','M10_8_RECOVERY_POLICY_V2',
      'status','OWNER_APPROVED',
      'operational_recovery_mode','FIX_FORWARD',
      'operational_rollback_to_m9_0','FORBIDDEN',
      'archived_m9_0_role','EVIDENCE_HISTORY_ONLY',
      'failure_flow',jsonb_build_array(
        'DETECT','ISOLATE','CORRECT','VALIDATE','DEPLOY_CORRECTION'
      ),
      'preserve_controls',jsonb_build_array(
        'DATABASE_TRANSACTION_ROLLBACK',
        'MIGRATION_TRAIN_ROLLBACK',
        'SANDBOX_REVERSIBILITY',
        'CANARY_REVERSIBILITY',
        'NEGATIVE_TEST_CLEANUP'
      ),
      'decision_ref','transversal.decision_log#DEC-IG-M10.8-FIX-FORWARD-20261021',
      'production_authorized',false
    ),
    true
  )
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND unit_code='M10.8'
    AND disposition='ASSIGNED';

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=jsonb_set(
    unit_metadata,
    '{action_specs_v1,EXPIRY_DECISION}',
    jsonb_build_object(
      'status','READY',
      'target',jsonb_build_object(
        'declared_assets','[]'::jsonb,
        'declared_events','[]'::jsonb,
        'declared_objects',jsonb_build_array(
          'transversal.decision_log',
          'programacion.engineering_plan_units',
          'programacion.engineering_work_checkpoints'
        ),
        'declared_artifacts','[]'::jsonb,
        'mutation_artifacts','[]'::jsonb
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'expected','Owner decision is FIX_FORWARD: no operational rollback to archived M9.0; archived bundle remains evidence/history only; transactional and reversible safety controls remain intact.',
      'forbidden',jsonb_build_array(
        'OPERATIONAL_ROLLBACK_TO_ARCHIVED_M9_0',
        'TREAT_ARCHIVED_BUNDLE_AS_RUNTIME_ROLLBACK_TARGET',
        'REMOVE_DATABASE_TRANSACTION_ROLLBACK',
        'REMOVE_MIGRATION_TRAIN_ROLLBACK',
        'REMOVE_SANDBOX_OR_CANARY_REVERSIBILITY',
        'PRODUCTION_ACTIVATION_BY_THIS_CHECKPOINT'
      ),
      'precision','OWNER_FIX_FORWARD_DECISION_V1',
      'action_kind','DECISION_GATE',
      'recipe_mode','OWNER_DECISION_LOG_READBACK_V1',
      'action_steps',jsonb_build_array(
        'READ_OWNER_DECISION',
        'ASSERT_FIX_FORWARD_POLICY',
        'PERSIST_CHECKPOINT_ONLY',
        'USE_RETURNED_BOOTSTRAP'
      ),
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'checkpoint_code','EXPIRY_DECISION',
      'logical_checkpoint_code','RECOVERY_STRATEGY_DECISION',
      'contract_family','FIX_FORWARD_RECOVERY_DECISION',
      'contract_source','OWNER_EXPLICIT_APPROVAL_2026_10_21',
      'mutation_policy','NO_DOMAIN_MUTATION',
      'verification_queries',jsonb_build_array(
        'select adr,decision,razon,impacto,estado from transversal.decision_log where adr=''DEC-IG-M10.8-FIX-FORWARD-20261021''',
        'select unit_metadata#>>''{recovery_policy_v2,operational_recovery_mode}'' recovery_mode, unit_metadata#>>''{recovery_policy_v2,operational_rollback_to_m9_0}'' rollback_to_m9, unit_metadata#>>''{recovery_policy_v2,archived_m9_0_role}'' archive_role from programacion.engineering_plan_units where plan_code=''IG_CURATOR_VALIDATOR_REFACTOR_V2'' and unit_code=''M10.8'''
      ),
      'required_contract',jsonb_build_object(
        'decision_ref','transversal.decision_log#DEC-IG-M10.8-FIX-FORWARD-20261021',
        'operational_recovery_mode','FIX_FORWARD',
        'archived_bundle_role','EVIDENCE_HISTORY_ONLY'
      ),
      'source_pack_missing_typed','[]'::jsonb,
      'requires_material_execution',false
    ),
    true
  )
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND unit_code='M10.8'
    AND disposition='ASSIGNED';

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=jsonb_set(
    unit_metadata,
    '{action_specs_v1,GATE_READBACK}',
    jsonb_build_object(
      'status','READY',
      'target',jsonb_build_object(
        'declared_assets','[]'::jsonb,
        'declared_events','[]'::jsonb,
        'declared_objects',jsonb_build_array(
          'transversal.decision_log',
          'programacion.engineering_plan_units',
          'programacion.engineering_work_checkpoints'
        ),
        'declared_artifacts','[]'::jsonb,
        'mutation_artifacts','[]'::jsonb
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','TERMINAL_UNIT_READBACK'
      ),
      'expected','Terminal readback proves FIX_FORWARD is the operational recovery mode, rollback to M9.0 is forbidden, M9.0 is evidence/history only, and technical safety rollback controls remain preserved.',
      'forbidden',jsonb_build_array(
        'CLAIM_PRODUCTION_AUTHORIZATION',
        'CLAIM_OPERATIONAL_ROLLBACK_TO_M9_0',
        'REMOVE_TRANSACTIONAL_SAFETY_ROLLBACK'
      ),
      'precision','FIX_FORWARD_TERMINAL_READBACK_V1',
      'action_kind','READBACK_ONCE',
      'recipe_mode','READBACK_ONCE',
      'action_steps',jsonb_build_array(
        'READ_DECLARED_AUTHORITY_ONCE',
        'ASSERT_FIX_FORWARD_POLICY',
        'ASSERT_PRIOR_CHECKPOINT_DONE',
        'PERSIST_CHECKPOINT_ONLY'
      ),
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'checkpoint_code','GATE_READBACK',
      'contract_family','FIX_FORWARD_TERMINAL_READBACK',
      'contract_source','OWNER_EXPLICIT_APPROVAL_2026_10_21',
      'mutation_policy','NO_DOMAIN_MUTATION',
      'verification_queries',jsonb_build_array(
        'select progress_pct,status from programacion.v_engineering_work_progress where id=479',
        'select checkpoint_code,status,evidence_ref from programacion.engineering_work_checkpoints where work_item_id=479 and checkpoint_code in (''EXPIRY_DECISION'',''GATE_READBACK'') order by sequence_no',
        'select unit_metadata#>>''{recovery_policy_v2,operational_recovery_mode}'' recovery_mode, unit_metadata#>>''{recovery_policy_v2,operational_rollback_to_m9_0}'' rollback_to_m9, unit_metadata#>>''{recovery_policy_v2,archived_m9_0_role}'' archive_role, unit_metadata#>>''{recovery_policy_v2,production_authorized}'' production_authorized from programacion.engineering_plan_units where plan_code=''IG_CURATOR_VALIDATOR_REFACTOR_V2'' and unit_code=''M10.8'''
      ),
      'required_contract',jsonb_build_object(
        'prior_checkpoint','EXPIRY_DECISION=DONE',
        'operational_recovery_mode','FIX_FORWARD',
        'operational_rollback_to_m9_0','FORBIDDEN',
        'archived_m9_0_role','EVIDENCE_HISTORY_ONLY',
        'production_authorized',false
      ),
      'source_pack_missing_typed','[]'::jsonb,
      'requires_material_execution',false
    ),
    true
  )
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND unit_code='M10.8'
    AND disposition='ASSIGNED';

  UPDATE programacion.engineering_work_checkpoints
  SET title='Decisión de estrategia de recuperación: FIX_FORWARD',
      updated_at=now(),
      updated_by_execution_id='IG_M108_FIX_FORWARD_DECISION_V1'
  WHERE work_item_id=479 AND checkpoint_code='EXPIRY_DECISION';

  UPDATE programacion.engineering_work_checkpoints
  SET title='Readback terminal de estrategia FIX_FORWARD',
      updated_at=now(),
      updated_by_execution_id='IG_M108_FIX_FORWARD_DECISION_V1'
  WHERE work_item_id=479 AND checkpoint_code='GATE_READBACK';

  v_spec := programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.8','EXPIRY_DECISION'
  );

  IF v_spec->>'status' IS DISTINCT FROM 'READY'
     OR v_spec->>'contract_family' IS DISTINCT FROM 'FIX_FORWARD_RECOVERY_DECISION'
     OR v_spec->>'logical_checkpoint_code' IS DISTINCT FROM 'RECOVERY_STRATEGY_DECISION'
     OR v_spec->>'mutation_policy' IS DISTINCT FROM 'NO_DOMAIN_MUTATION'
  THEN
    RAISE EXCEPTION 'M108_FIX_FORWARD_ACTION_SPEC_FAIL:%',v_spec;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM transversal.decision_log
    WHERE adr='DEC-IG-M10.8-FIX-FORWARD-20261021'
      AND upper(estado)='VIGENTE'
      AND decision LIKE 'ADOPT_FIX_FORWARD.%'
  ) THEN
    RAISE EXCEPTION 'M108_FIX_FORWARD_DECISION_READBACK_FAIL';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM programacion.engineering_plan_units
    WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      AND unit_code='M10.8'
      AND unit_metadata#>>'{recovery_policy_v2,operational_recovery_mode}'='FIX_FORWARD'
      AND unit_metadata#>>'{recovery_policy_v2,operational_rollback_to_m9_0}'='FORBIDDEN'
      AND unit_metadata#>>'{recovery_policy_v2,archived_m9_0_role}'='EVIDENCE_HISTORY_ONLY'
      AND unit_metadata#>>'{recovery_policy_v2,production_authorized}'='false'
      AND unit_metadata#>>'{operational_maturity_policy_v1,state}'='SUPERSEDED_BY_FIX_FORWARD'
  ) THEN
    RAISE EXCEPTION 'M108_FIX_FORWARD_POLICY_READBACK_FAIL';
  END IF;

  v_transition := programacion.fn_engineering_checkpoint_transition_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M10.8',
    'EXPIRY_DECISION',
    'DONE',
    'supabase://transversal.decision_log#DEC-IG-M10.8-FIX-FORWARD-20261021',
    'GPT_NATIVE:APPLY_OWNER_DECISION:M10.8',
    'Owner explicitly approved FIX_FORWARD. Operational rollback to M9.0 is removed from the recovery strategy. M9.0 remains evidence/history only. Transaction, migration, sandbox and canary reversibility controls remain intact. No production authorization.'
  );

  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
     OR v_transition#>>'{transition,new_status}' IS DISTINCT FROM 'DONE'
  THEN
    RAISE EXCEPTION 'M108_FIX_FORWARD_TRANSITION_FAIL:%',v_transition;
  END IF;

  SELECT progress_pct INTO v_progress
  FROM programacion.v_engineering_work_progress
  WHERE id=479;

  IF v_progress IS DISTINCT FROM 80.00 THEN
    RAISE EXCEPTION 'M108_FIX_FORWARD_PROGRESS_FAIL:%',v_progress;
  END IF;
END
$m108$;

INSERT INTO public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
)
VALUES(
  'IG-M108-ROLLBACK-STRATEGY-CONFLATION-052',
  'GOVERNANCE',
  'M10.8 confundía recuperación operativa con expiración de rollback a una versión peor',
  'El diseño de M10.8 asumía que la recuperación operativa debía conservar temporalmente un hot rollback hacia M9.0 y luego decidir cuándo expirarlo. El owner definió que, si la versión anterior es peor, la estrategia correcta es FIX_FORWARD.',
  'Se modeló rollback de release como requisito universal de recuperación, en vez de separar recuperación operativa de reversibilidad técnica de pruebas/transacciones.',
  'OPERATIONAL_RELEASE_ROLLBACK_CONFLATED_WITH_TECHNICAL_REVERSIBILITY',
  'Para Input Governance usar FIX_FORWARD ante fallas operativas: detectar, aislar, corregir, validar y desplegar corrección. Mantener bundles anteriores solo como evidencia histórica. Preservar rollback transaccional, Migration Train rollback, sandbox/canary reversibility y cleanup negativo.',
  'PASS si M10.8 recovery_policy_v2=FIX_FORWARD, operational_rollback_to_m9_0=FORBIDDEN, archive role=EVIDENCE_HISTORY_ONLY, production_authorized=false, decisión ADR vigente y checkpoint EXPIRY_DECISION cerrado al 80%; GATE_READBACK permanece pendiente para lectura terminal independiente.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','VERIFICADO',
  'Owner approval 2026-10-21. M10.7 DONE; archived bundle recovery already verified; no production activation performed.',
  'GOVERNANCE',
  array['INPUT_GOVERNANCE','ENGINEERING_EXECUTOR']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'M10.8 recovery strategy',
  'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.8'
)
ON CONFLICT (codigo) DO UPDATE SET
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();

COMMIT;
