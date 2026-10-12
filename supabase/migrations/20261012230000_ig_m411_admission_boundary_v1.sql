-- IG M4.11: separar readback de prerequisitos de admision del oracle decisional.
-- EKB: IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001,
-- IG-EKB-READ-WITHOUT-SEMANTIC-PREFLIGHT-001,
-- IG-M412-ORACLE-VERSION-PIN-AND-INDEPENDENCE-DRIFT-001,
-- IG-M100-GIT-HEAD-DOES-NOT-FREEZE-DB-COMPONENTS-001.
--
-- Alcance: SOLO el contrato de la unidad M4.11 y su gobernanza de admision.
-- No modifica funciones productoras, punteros, registry, roles ni checkpoints.
-- CP2: verificar M4.10/M9.8/M9.12 y recibo historico exacto de M9.12.
-- CP3: independencia T-INDEP y cutover real continúan fail-closed.
-- CP4/CP5/CP6: sin cambios; NO activar runtime/produccion.
DO $m411$
DECLARE
  v_id bigint;
  v_meta jsonb;
  v_cp2 jsonb;
  v_cp3 jsonb;
  v_query text;
  v_new_meta jsonb;
  v_receipt programacion.provenance_receipts%rowtype;
  v_upstream integer;
  v_after jsonb;
BEGIN
  SELECT id, unit_metadata INTO v_id, v_meta
    FROM programacion.engineering_plan_units
   WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
     AND unit_code='M4.11'
     AND disposition='ASSIGNED'
   FOR UPDATE;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'M411_CANONICAL_UNIT_NOT_FOUND';
  END IF;

  SELECT count(*) INTO v_upstream
    FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
   WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
     AND u.unit_code IN ('M4.10','M9.8','M9.12')
     AND w.status='DONE';
  IF v_upstream <> 3 THEN
    RAISE EXCEPTION 'M411_UPSTREAM_ENGINEERING_NOT_DONE:%/3',v_upstream;
  END IF;

  SELECT * INTO v_receipt
    FROM programacion.provenance_receipts
   WHERE id=1667
     AND receipt_kind='EVIDENCE_VERIFICATION'
     AND subject_type='IG_CUTOVER_READINESS'
     AND subject_ref='plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.12/CUTOVER_READY'
     AND receipt_sha256='b4b8174360d8478c122340ca25973ba54cdcd7785d2d168ae8271840fc0c7fc5'
     AND issuer_identity='SUPABASE:IG_M912_READINESS_VERIFIER_V1'
     AND payload->>'verification_status'='VERIFIED'
     AND payload->>'readiness_status'='CUTOVER_READY'
     AND payload->>'bundle_sha256'='db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f'
     AND payload#>>'{manifest,bundle_sha256}'=payload->>'bundle_sha256'
     AND payload#>>'{manifest,production_activation}'='false';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'M411_M912_EXACT_HISTORIC_CUTOVER_RECEIPT_MISSING_OR_DRIFTED';
  END IF;

  v_cp2:=v_meta#>'{action_specs_v1,PREREQ_GATES_PASS}';
  v_cp3:=v_meta#>'{action_specs_v1,DECISIONAL_BINDING_VIA_RELEASE}';
  IF jsonb_typeof(v_cp2) <> 'object' OR jsonb_typeof(v_cp3) <> 'object' THEN
    RAISE EXCEPTION 'M411_ACTION_SPECS_NOT_FOUND';
  END IF;
  IF (v_meta#>>'{m411_admission_boundary_v1,version}')='1.0.0' THEN
    RAISE EXCEPTION 'M411_BOUNDARY_ALREADY_APPLIED_REVIEW_BEFORE_REAPPLY';
  END IF;

  v_query := $q$
    WITH upstream AS (
      SELECT u.unit_code,w.status
        FROM programacion.engineering_plan_units u
        JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
       WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
         AND u.unit_code IN ('M4.10','M9.8','M9.12')
    ), receipt AS (
      SELECT id,receipt_sha256,payload->>'bundle_sha256' bundle_sha,
             payload->>'verification_status' verification_status
        FROM programacion.provenance_receipts
       WHERE id=1667
         AND receipt_kind='EVIDENCE_VERIFICATION'
         AND subject_type='IG_CUTOVER_READINESS'
         AND subject_ref='plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.12/CUTOVER_READY'
         AND receipt_sha256='b4b8174360d8478c122340ca25973ba54cdcd7785d2d168ae8271840fc0c7fc5'
         AND issuer_identity='SUPABASE:IG_M912_READINESS_VERIFIER_V1'
         AND payload->>'verification_status'='VERIFIED'
         AND payload->>'readiness_status'='CUTOVER_READY'
         AND payload->>'bundle_sha256'='db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f'
         AND payload#>>'{manifest,bundle_sha256}'=payload->>'bundle_sha256'
         AND payload#>>'{manifest,production_activation}'='false'
    )
    SELECT jsonb_build_object(
      'contract','IG_M411_UPSTREAM_READBACK_V1',
      'status',CASE WHEN (SELECT count(*) FROM upstream WHERE status='DONE')=3
                    AND (SELECT count(*) FROM receipt)=1
                    THEN 'PASS' ELSE 'BLOCKED' END,
      'upstream_done',(SELECT count(*) FROM upstream WHERE status='DONE'),
      'upstream_expected',3,
      'cutover_receipt_id',(SELECT id FROM receipt),
      'cutover_receipt_sha256',(SELECT receipt_sha256 FROM receipt),
      'pinned_bundle_sha256',(SELECT bundle_sha FROM receipt),
      'decisional_oracle_authorized',false,
      'independence_proven',false,
      'next_independence_gate','DECISIONAL_BINDING_VIA_RELEASE'
    ) AS m411_prereq_readback
  $q$;

  v_cp2 := v_cp2 || jsonb_build_object(
    'status','READY',
    'precision','M411_UPSTREAM_READBACK_ONLY_V1',
    'contract_family','ENGINEERING_UPSTREAM_SIGNED_RECEIPT_READBACK',
    'action_kind','READBACK_ONCE',
    'recipe_mode','READBACK_EXACT',
    'requires_material_execution',false,
    'mutation_policy','NO_DOMAIN_MUTATION',
    'checkpoint_title','Verificar M4.10/M9.8 y CUTOVER_READY firmado de M9.12; independencia decisional sigue en CP3',
    'expected','3/3 unidades DONE y recibo M9.12 id=1667 SHA exacto VERIFIED; CP2 NO acredita independencia ni habilita oracle',
    'required_evidence_contract',jsonb_build_object(
      'phase','ENGINEERING_UPSTREAM_READBACK',
      'signed_cutover_receipt_id',1667,
      'signed_cutover_receipt_sha256','b4b8174360d8478c122340ca25973ba54cdcd7785d2d168ae8271840fc0c7fc5',
      'bundle_sha256','db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',
      'independence_claim','NOT_MADE',
      'independence_required_at','DECISIONAL_BINDING_VIA_RELEASE',
      'production_authorized',false
    ),
    'verification_queries',jsonb_build_array(v_query),
    'action_steps',jsonb_build_array('READ_EXACT_UPSTREAM_RECEIPT','ASSERT_POSITIVE_AND_NEGATIVE','TRANSITION_WITH_NONEMPTY_READBACK_EVIDENCE'),
    'forbidden',jsonb_build_array('CP2_DONE_IMPLIES_T_INDEP','CP2_DONE_AUTHORIZES_CUTOVER','REBUILD_HISTORICAL_BUNDLE_FROM_LIVE_REGISTRY','CLOSE_WITH_EMPTY_EVIDENCE')
  );

  v_cp3 := v_cp3 || jsonb_build_object(
    'status',v_cp3->>'status',
    'expected','Decisional release REQUIRES independently verified T-INDEP receipt of exact candidate, DEPENDENCIES/DATA/AUTHOR INDEPENDENT, signed subject bound to M9.12 immutable bundle, currentness and fail-closed negative; never infer from CP2',
    'required_evidence_contract',jsonb_build_object(
      'phase','DECISIONAL_ORACLE_ADMISSION',
      'bundle_sha256','db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',
      't_indep_receipt_required',true,
      'producer_root','fn_input_governance_bootstrap_classify_v2',
      'oracle_root','fn_input_governance_shadow_priority_oracle_v2',
      'capability_code','INDEPENDENT_ASSURANCE',
      'required_overall_state','INDEPENDENT',
      'required_dimensions',jsonb_build_array('DEPENDENCIES','DATA','AUTHOR'),
      'reviewer_identity_provenance_required',true,
      'runtime_activation_authorized',false,
      'production_activation_authorized',false
    ),
    'forbidden',coalesce(v_cp3->'forbidden','[]'::jsonb)
      || jsonb_build_array('PROMOTE_COMPARISON_ONLY_ORACLE','AUTOPASS_FROM_M4_10_M9_8_M9_12','SELF_CLAIMED_REVIEWER_IDENTITY','LATEST_BUNDLE_INSTEAD_OF_SIGNED_EXACT_SHA')
  );

  v_new_meta := jsonb_set(
    coalesce(v_meta,'{}'::jsonb),
    '{action_specs_v1}',
    coalesce(v_meta->'action_specs_v1','{}'::jsonb)
      || jsonb_build_object('PREREQ_GATES_PASS',v_cp2,'DECISIONAL_BINDING_VIA_RELEASE',v_cp3),
    true
  );
  v_new_meta := jsonb_set(v_new_meta,'{m411_admission_boundary_v1}',
    jsonb_build_object(
      'version','1.0.0',
      'engineering_cp2','UPSTREAM_SIGNED_READBACK_ONLY',
      'decisional_cp3','T_INDEP_AND_RELEASE_BINDING_REQUIRED',
      'family_coverage_cp5','47_OF_47_WITH_TRUE_ORACLE',
      'negative_cp4','NO_PASS_WITHOUT_ORACLE',
      'operational_cutover','NOT_AUTHORIZED',
      'source','EKB_M99_M910_M411',
      'historical_m912_receipt_id',1667,
      'historical_m912_receipt_sha256','b4b8174360d8478c122340ca25973ba54cdcd7785d2d168ae8271840fc0c7fc5'
    ),true);

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new_meta
   WHERE id=v_id;

  v_after:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','PREREQ_GATES_PASS');
  IF v_after->>'status'<>'READY' THEN
    RAISE EXCEPTION 'M411_CP2_ACTION_SPEC_POSTCHECK_BLOCKED:%',v_after->>'status';
  END IF;
  v_after:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','DECISIONAL_BINDING_VIA_RELEASE');
  IF v_after->>'status'='READY' THEN
    RAISE EXCEPTION 'M411_CP3_MUST_REMAIN_FAIL_CLOSED';
  END IF;
END;
$m411$;
