-- IG M10.8: hot rollback expiry must require real operational maturity.
-- Owner correction 2026-10-21: the system is practically new; technical soak alone
-- must not make expiry eligible.
-- This migration does NOT expire rollback and does NOT authorize production.

BEGIN;

DO $m108$
DECLARE
  v_old_exit constant text :=
    'Gate registrado (evento + decisión humana) que fija la expiración del hot rollback tras soak M10.7 aprobado; desde ese punto el único rollback es redeploy del bundle archivado, probado por readback de que el bundle está recuperable';
  v_new_exit constant text :=
    'Gate de expiración del hot rollback: M10.7 técnico y la recuperabilidad del bundle archivado son precondiciones necesarias pero no suficientes. La decisión humana de expiración solo es elegible después de activación/uso real y de un receipt VERIFIED de madurez operativa posterior al go-live, con ventana observada bajo una política explícita aprobada, evidencia de operación real y 0 incidentes materiales no resueltos / 0 disparadores de rollback durante esa ventana. Hasta entonces se mantiene el hot rollback. No implica autorización de producción.';
  v_spec jsonb;
  v_progress numeric;
  v_cp_status text;
  v_decisions bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM programacion.engineering_plan_units
    WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      AND unit_code='M10.8'
      AND disposition='ASSIGNED'
      AND exit_criterion=v_old_exit
      AND unit_metadata#>>'{action_specs_v1,EXPIRY_DECISION,status}'='BLOCK_OWNER_DECISION_REQUIRED'
  ) THEN
    RAISE EXCEPTION 'M108_OPERATIONAL_MATURITY_PREIMAGE_DRIFT';
  END IF;

  SELECT count(*) INTO v_decisions
  FROM programacion.human_decisions;

  IF v_decisions <> 0 THEN
    RAISE EXCEPTION 'M108_OPERATIONAL_MATURITY_UNEXPECTED_PRIOR_DECISION:%',v_decisions;
  END IF;

  UPDATE programacion.engineering_plan_units
  SET exit_criterion = v_new_exit,
      unit_metadata = jsonb_set(
        jsonb_set(
          unit_metadata,
          '{action_specs_v1,EXPIRY_DECISION}',
          jsonb_build_object(
            'status','BLOCK_OPERATIONAL_MATURITY_REQUIRED',
            'target',jsonb_build_object(
              'declared_assets','[]'::jsonb,
              'declared_events','[]'::jsonb,
              'declared_objects',jsonb_build_array(
                'programacion.provenance_receipts',
                'programacion.human_decisions'
              ),
              'declared_artifacts','[]'::jsonb,
              'mutation_artifacts','[]'::jsonb
            ),
            'expected','Hot rollback expiry is not decision-eligible until a VERIFIED operational-maturity receipt exists after real production activation/use. M10.7 technical soak alone is insufficient.',
            'forbidden',jsonb_build_array(
              'AUTO_EXPIRE_HOT_ROLLBACK',
              'TREAT_TECHNICAL_SOAK_AS_OPERATIONAL_MATURITY',
              'START_EXPIRY_CLOCK_BEFORE_REAL_PRODUCTION_ACTIVATION',
              'INFER_OPERATIONAL_MATURITY_FROM_HISTORICAL_TEST_RUNS',
              'PRODUCTION_ACTIVATION_BY_THIS_CHECKPOINT'
            ),
            'precision','EXPLICIT_OPERATIONAL_MATURITY_BEFORE_OWNER_EXPIRY_V1',
            'action_kind','DECISION_GATE',
            'recipe_mode','OPERATIONAL_MATURITY_THEN_OWNER_DECISION_V1',
            'schema_version','ENGINEERING_ACTION_SPEC_V3',
            'checkpoint_code','EXPIRY_DECISION',
            'contract_family','OPERATIONAL_MATURITY_PENDING',
            'contract_source','OWNER_CORRECTION_2026_10_21',
            'mutation_policy','NO_DOMAIN_MUTATION',
            'verification_queries',jsonb_build_array(
              'select id,receipt_kind,subject_type,subject_ref,payload,receipt_sha256,created_at from programacion.provenance_receipts where subject_type=''input_governance_operational_maturity'' order by id desc limit 5'
            ),
            'operational_maturity_contract',jsonb_build_object(
              'receipt_table','programacion.provenance_receipts',
              'subject_type','input_governance_operational_maturity',
              'verification_status_required','VERIFIED',
              'clock_start','FIRST_REAL_PRODUCTION_ACTIVATION_ONLY',
              'technical_soak_sufficient',false,
              'historical_test_runs_sufficient',false,
              'window_duration_policy','EXPLICIT_OWNER_APPROVED_AT_OR_BEFORE_GO_LIVE',
              'required_payload_fields',jsonb_build_array(
                'production_activation_ref',
                'operational_window_started_at',
                'operational_window_ended_at',
                'window_policy_ref',
                'real_operation_observed',
                'unresolved_material_incidents',
                'rollback_trigger_count'
              ),
              'pass_conditions',jsonb_build_object(
                'real_operation_observed',true,
                'unresolved_material_incidents',0,
                'rollback_trigger_count',0
              )
            ),
            'decision_authority_contract',jsonb_build_object(
              'owner','SUPER_ADMIN',
              'record_table','programacion.human_decisions',
              'automatic_decision','FORBIDDEN',
              'decision_semantics','EXPIRE_HOT_ROLLBACK_AFTER_VERIFIED_OPERATIONAL_MATURITY',
              'preconditions',jsonb_build_array(
                'M10.7_DONE',
                'ARCHIVED_BUNDLE_RECOVERABLE_DONE',
                'VERIFIED_OPERATIONAL_MATURITY_RECEIPT'
              ),
              'required_fields',jsonb_build_array(
                'decision','actor_identity','approval_ref'
              )
            ),
            'source_pack_missing_typed','[]'::jsonb,
            'requires_material_execution',false
          ),
          true
        ),
        '{operational_maturity_policy_v1}',
        jsonb_build_object(
          'schema_version','M10_8_OPERATIONAL_MATURITY_POLICY_V1',
          'state','WAIT_REAL_OPERATION',
          'clock_start','FIRST_REAL_PRODUCTION_ACTIVATION_ONLY',
          'technical_soak_sufficient',false,
          'expiry_decision_eligible',false,
          'production_authorized',false
        ),
        true
      ),
      updated_at=now()
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND unit_code='M10.8'
    AND disposition='ASSIGNED';

  v_spec := programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.8','EXPIRY_DECISION'
  );

  IF v_spec->>'status' IS DISTINCT FROM 'BLOCK_OPERATIONAL_MATURITY_REQUIRED'
     OR v_spec#>>'{operational_maturity_contract,clock_start}' IS DISTINCT FROM 'FIRST_REAL_PRODUCTION_ACTIVATION_ONLY'
     OR v_spec#>>'{operational_maturity_contract,technical_soak_sufficient}' IS DISTINCT FROM 'false'
     OR v_spec#>>'{decision_authority_contract,automatic_decision}' IS DISTINCT FROM 'FORBIDDEN'
  THEN
    RAISE EXCEPTION 'M108_OPERATIONAL_MATURITY_SPEC_FAIL:%',v_spec;
  END IF;

  SELECT status INTO v_cp_status
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=479
    AND checkpoint_code='EXPIRY_DECISION';

  SELECT progress_pct INTO v_progress
  FROM programacion.v_engineering_work_progress
  WHERE id=479;

  IF v_cp_status IS DISTINCT FROM 'PENDING'
     OR v_progress IS DISTINCT FROM 60.00
  THEN
    RAISE EXCEPTION 'M108_OPERATIONAL_MATURITY_LEDGER_FAIL:cp=% progress=%',
      v_cp_status,v_progress;
  END IF;
END
$m108$;

INSERT INTO public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
)
VALUES(
  'IG-M108-TECHNICAL-SOAK-NOT-OPERATIONAL-MATURITY-051',
  'GOVERNANCE',
  'M10.8 no debe expirar hot rollback de un sistema prácticamente nuevo',
  'El gate de expiración quedaba elegible inmediatamente después de M10.7, aunque M10.7 prueba suficiencia técnica/histórica y no madurez bajo uso real.',
  'Se confundió soak técnico con madurez operativa posterior al go-live.',
  'TECHNICAL_SOAK_MISUSED_AS_OPERATIONAL_MATURITY',
  'El reloj de expiración comienza solo con la primera activación/uso real. Antes de decisión humana exigir receipt VERIFIED de madurez operativa con ventana aprobada, operación real observada, 0 incidentes materiales no resueltos y 0 disparadores de rollback. No fijar una duración arbitraria antes del go-live.',
  'PASS si M10.8 permanece 60%, EXPIRY_DECISION=PENDING, action spec=BLOCK_OPERATIONAL_MATURITY_REQUIRED, technical_soak_sufficient=false y no se crea decisión humana ni autorización de producción.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','VERIFICADO',
  'Owner correction 2026-10-21: sistema prácticamente nuevo; no retirar hot rollback por M10.7 técnico. M10.8 estaba 60% con 0 human_decisions.',
  'GOVERNANCE',
  array['INPUT_GOVERNANCE','ENGINEERING_EXECUTOR']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'M10.8 expiry gate',
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
