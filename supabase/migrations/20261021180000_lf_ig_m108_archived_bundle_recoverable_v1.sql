-- IG M10.8 ARCHIVED_BUNDLE_RECOVERABLE
-- Repair incorrect mutation-oriented contract into exact read-only Git recoverability
-- and close from verified M9.0 receipt + exact Git SHA readback.
-- No rebuild. No production activation.

BEGIN;

DO $repair_and_close$
DECLARE
  v_spec jsonb;
  v_packet jsonb;
  v_cp record;
  v_transition jsonb;
  v_progress numeric;
  v_m90_status text;
  v_receipt record;
  v_capture_ref constant text :=
    'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/input_governance/M10_8_ARCHIVED_BUNDLE_RECOVERABLE_CAPTURE_V1.json#blob:5be6d1469a0529e5bbc93efade3ec12fcb2c8704';
BEGIN
  SELECT w.status
    INTO v_m90_status
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND u.unit_code='M9.0';

  IF v_m90_status IS DISTINCT FROM 'DONE' THEN
    RAISE EXCEPTION 'M108_ARCHIVED_BUNDLE_M90_NOT_DONE:%',v_m90_status;
  END IF;

  SELECT status,evidence_ref,assertion_receipt_sha256
    INTO v_cp
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=479
    AND checkpoint_code='ARCHIVED_BUNDLE_RECOVERABLE'
  FOR UPDATE;

  IF v_cp.status IS DISTINCT FROM 'PENDING'
     OR v_cp.evidence_ref IS NOT NULL
     OR v_cp.assertion_receipt_sha256 IS NOT NULL
  THEN
    RAISE EXCEPTION 'M108_ARCHIVED_BUNDLE_CP_DRIFT:%',row_to_json(v_cp);
  END IF;

  SELECT id,receipt_kind,subject_type,subject_ref,payload,receipt_sha256
    INTO v_receipt
  FROM programacion.provenance_receipts
  WHERE id=187;

  IF v_receipt.id IS NULL
     OR v_receipt.receipt_kind IS DISTINCT FROM 'EVIDENCE_VERIFICATION'
     OR v_receipt.subject_type IS DISTINCT FROM 'input_governance_release_bundle'
     OR v_receipt.receipt_sha256 IS DISTINCT FROM 'fafd3ac20510d7a802cea9dead8106abf9c11157823c85845f04e8639912c292'
     OR v_receipt.payload->>'verification_status' IS DISTINCT FROM 'VERIFIED'
     OR v_receipt.payload->>'head_sha' IS DISTINCT FROM '5a8ff982539bc5f9f102c16c1c5d4661c66e26a0'
     OR v_receipt.payload#>>'{manifest,bundle_sha256}' IS DISTINCT FROM 'db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f'
  THEN
    RAISE EXCEPTION 'M108_ARCHIVED_BUNDLE_RECEIPT_FAIL:%',row_to_json(v_receipt);
  END IF;

  UPDATE programacion.engineering_plan_units
  SET unit_metadata = jsonb_set(
    unit_metadata,
    '{action_specs_v1,ARCHIVED_BUNDLE_RECOVERABLE}',
    jsonb_build_object(
      'status','READY',
      'target',jsonb_build_object(
        'declared_assets','[]'::jsonb,
        'declared_events','[]'::jsonb,
        'declared_objects',jsonb_build_array('programacion.provenance_receipts'),
        'declared_artifacts',jsonb_build_array(
          jsonb_build_object(
            'path','cristhianlujan/claude-persona-lf-patch:supabase/functions/input-governance-agent-v1/index.ts',
            'role','EVIDENCE_ONLY','ref','5a8ff982539bc5f9f102c16c1c5d4661c66e26a0',
            'git_blob_sha1','326a5c492c84cceccb45ea8d6a0f39a1d5305637'
          ),
          jsonb_build_object(
            'path','cristhianlujan/claude-persona-lf-patch:supabase/functions/input-governance-curator-v1/index.ts',
            'role','EVIDENCE_ONLY','ref','5a8ff982539bc5f9f102c16c1c5d4661c66e26a0',
            'git_blob_sha1','bd43f469d5d508f64dbee21eea7be611e7d2e780'
          ),
          jsonb_build_object(
            'path','cristhianlujan/claude-persona-lf-patch:supabase/functions/input-governance-validator-v1/index.ts',
            'role','EVIDENCE_ONLY','ref','5a8ff982539bc5f9f102c16c1c5d4661c66e26a0',
            'git_blob_sha1','31a77e43c02f714479e5ed2f1fdb615fbe38eead'
          )
        ),
        'mutation_artifacts','[]'::jsonb
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'expected','M9.0 archived release bundle remains recoverable from exact Git SHA and its verified canonical receipt remains intact.',
      'forbidden',jsonb_build_array(
        'REBUILD_ARCHIVED_BUNDLE',
        'INFER_CURRENT_RUNTIME_PARITY_FROM_ARCHIVE',
        'PRODUCTION_ACTIVATION',
        'TREAT_EVIDENCE_ARTIFACT_AS_MUTATION_TARGET'
      ),
      'precision','EXPLICIT_ARCHIVED_BUNDLE_READBACK_V2',
      'action_kind','READBACK_ONCE',
      'recipe_mode','GIT_EXACT_SHA_RECOVERABILITY_READBACK_V1',
      'action_steps',jsonb_build_array(
        'READ_DECLARED_AUTHORITY_ONCE',
        'ASSERT_EXACT_GIT_SHA_RECOVERABLE',
        'PERSIST_CHECKPOINT_ONLY',
        'USE_RETURNED_BOOTSTRAP'
      ),
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'checkpoint_code','ARCHIVED_BUNDLE_RECOVERABLE',
      'contract_family','READ_ONLY_EVIDENCE',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'mutation_policy','NO_DOMAIN_MUTATION',
      'verification_queries',jsonb_build_array(
        'select id,receipt_kind,subject_type,subject_ref,payload,receipt_sha256 from programacion.provenance_receipts where id=187'
      ),
      'required_contract',jsonb_build_object(
        'query_source','M9_0_RECEIPT_187_PLUS_GIT_EXACT_SHA_READBACK',
        'semantic_pass_predicate','receipt VERIFIED and exact archived Git commit/files retrievable'
      ),
      'upstream_contract',jsonb_build_object(
        'producer_unit','M9.0',
        'rebuild','FORBIDDEN',
        'readback','GIT_EXACT_SHA_RECOVERABLE',
        'git_head','5a8ff982539bc5f9f102c16c1c5d4661c66e26a0',
        'bundle_sha256','db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',
        'receipt_id',187
      ),
      'git_recoverability_evidence',jsonb_build_object(
        'capture_ref',v_capture_ref,
        'commit_retrievable',true,
        'commit_signature_verified',true,
        'required_file_count',3,
        'retrievable_file_count',3,
        'claim_boundary','RECOVERABILITY_ONLY_NOT_CURRENT_RUNTIME_PARITY'
      ),
      'source_pack_missing_typed','[]'::jsonb,
      'requires_material_execution',false
    ),
    true
  )
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND unit_code='M10.8'
    AND disposition='ASSIGNED';

  v_spec := programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.8','ARCHIVED_BUNDLE_RECOVERABLE'
  );

  IF v_spec->>'status' IS DISTINCT FROM 'READY'
     OR v_spec->>'mutation_policy' IS DISTINCT FROM 'NO_DOMAIN_MUTATION'
     OR v_spec#>>'{upstream_contract,git_head}' IS DISTINCT FROM '5a8ff982539bc5f9f102c16c1c5d4661c66e26a0'
     OR v_spec#>>'{git_recoverability_evidence,retrievable_file_count}' IS DISTINCT FROM '3'
  THEN
    RAISE EXCEPTION 'M108_ARCHIVED_BUNDLE_SPEC_FAIL:%',v_spec;
  END IF;

  v_packet := programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M10.8',
    'ARCHIVED_BUNDLE_RECOVERABLE',
    v_spec,
    '{}'::jsonb
  );

  IF v_packet->>'status' IS DISTINCT FROM 'READY'
     OR v_packet->>'execution_capability' IS DISTINCT FROM 'READ'
  THEN
    RAISE EXCEPTION 'M108_ARCHIVED_BUNDLE_PACKET_FAIL:%',v_packet;
  END IF;

  v_transition := programacion.fn_engineering_checkpoint_transition_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M10.8',
    'ARCHIVED_BUNDLE_RECOVERABLE',
    'DONE',
    v_capture_ref,
    'GPT_NATIVE:M10.8:ARCHIVED_BUNDLE_RECOVERABLE',
    'PASS: M9.0 receipt 187 remains VERIFIED (bundle_sha256=db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f; git_head=5a8ff982539bc5f9f102c16c1c5d4661c66e26a0). Exact Git commit is retrievable and Agent/Curator/Validator index.ts are readable at that ref with blobs 326a5c492c84cceccb45ea8d6a0f39a1d5305637 / bd43f469d5d508f64dbee21eea7be611e7d2e780 / 31a77e43c02f714479e5ed2f1fdb615fbe38eead. Recoverability only; no claim of current runtime parity, no rebuild, no production authorization.'
  );

  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
     OR v_transition#>>'{transition,new_status}' IS DISTINCT FROM 'DONE'
  THEN
    RAISE EXCEPTION 'M108_ARCHIVED_BUNDLE_TRANSITION_FAIL:%',v_transition;
  END IF;

  SELECT progress_pct INTO v_progress
  FROM programacion.v_engineering_work_progress
  WHERE id=479;

  IF v_progress IS DISTINCT FROM 60.00 THEN
    RAISE EXCEPTION 'M108_ARCHIVED_BUNDLE_PROGRESS_FAIL:%',v_progress;
  END IF;
END
$repair_and_close$;

INSERT INTO public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
)
VALUES(
  'IG-M108-ARCHIVED-BUNDLE-READBACK-CONTRACT-050',
  'GOVERNANCE',
  'M10.8 ARCHIVED_BUNDLE_RECOVERABLE heredó contrato de mutación para un readback',
  'El checkpoint de recuperabilidad exigía implementation_ref, mutation_target y assertion_contract aunque su upstream_contract define rebuild=FORBIDDEN y readback=GIT_EXACT_SHA_RECOVERABLE.',
  'Plantilla de contrato BOUNDED/UPSTREAM dejó requisitos de mutación incompatibles con una comprobación read-only de material archivado.',
  'READBACK_CHECKPOINT_MISCLASSIFIED_AS_MUTATION_REQUIRED',
  'Para recoverabilidad archivada usar receipt canónico + Git exact ref/blob readback; no reconstruir bundle ni convertir evidencia en mutation target.',
  'PASS si action spec compila READY/READ/NO_DOMAIN_MUTATION, receipt 187 sigue VERIFIED, el commit y 3 archivos son recuperables, checkpoint queda DONE y M10.8=60%.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','VERIFICADO',
  'M9.0 receipt 187 SHA fafd3ac20510d7a802cea9dead8106abf9c11157823c85845f04e8639912c292; bundle db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f; git 5a8ff982539bc5f9f102c16c1c5d4661c66e26a0; capture blob 5be6d1469a0529e5bbc93efade3ec12fcb2c8704.',
  'EXECUTION',
  array['INPUT_GOVERNANCE','ENGINEERING_EXECUTOR']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'M10.8 archived bundle recoverability',
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
