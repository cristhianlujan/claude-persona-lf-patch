-- IG M10.0 ONLY: engineering sandbox admission is not an operational cutover.
-- New independently governed changeset: do NOT replay the historical, unapplied
-- 20261012223000_ig_m100_sandbox_technical_vs_operational_authority_v1.sql
-- Git blob dbe466b827f10c257dba6449d65d6750f2328057.
-- Historical source remains in Git as tracked technical debt, issue #2357.
-- Its clean-up is NOT a prerequisite for new scoped migration admission.
-- Train executes only the new SQL with exact source/version/ledger readback.
-- This migration changes only programacion engineering unit 283 / work item 472,
-- its checkpoint wording and its action_spec/source_pack; no human approvals,
-- promotion actions, registry, production pointers, or new validation engines.

DO $m100$
DECLARE
  v_unit_id bigint;
  v_work_id bigint;
  v_meta jsonb;
  v_specs jsonb;
  v_src jsonb;
  v_old_criterion text;
  v_old_work record;
  v_bundle_id bigint;
  v_ready_id bigint;
  v_bundle programacion.provenance_receipts%ROWTYPE;
  v_ready programacion.provenance_receipts%ROWTYPE;
  v_components_ok boolean;
  v_positive boolean;
  v_wrong_head boolean := false;
  v_wrong_bundle boolean := false;
  v_missing_ready boolean := false;
  v_forged_authority boolean := false;
  v_wrong_ready_subject boolean := false;
  v_constraints_ok boolean;
  v_triggers_ok boolean;
  v_literal_check boolean;
  v_no_approval boolean;
  v_no_promotion boolean;
  v_checks jsonb;
  v_router_refs jsonb;
  v_escalation_manifest jsonb;
  v_route_count integer;
  v_sql text;
  v_spec jsonb;
  v_cp text;
BEGIN
  SELECT u.id,u.work_item_id,u.unit_metadata,u.exit_criterion
  INTO v_unit_id,v_work_id,v_meta,v_old_criterion
  FROM programacion.engineering_plan_units u
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND u.unit_code='M10.0'
  FOR UPDATE;

  -- Do not execute the previously merged source or disguise it as applied.
  -- This new changeset is admitted independently. Old Git source is debt only.
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations
             WHERE version='20261012223000'
                OR name='ig_m100_sandbox_technical_vs_operational_authority_v1')
  THEN
    RAISE EXCEPTION 'IG_M100_V2_LEGACY_MIGRATION_NOT_UNAPPLIED';
  END IF;

  IF v_unit_id IS DISTINCT FROM 283
    OR v_work_id IS DISTINCT FROM 472
    OR v_meta#>>'{action_specs_v1,HUMAN_DECISION_RECORD,status}'
       IS DISTINCT FROM 'BLOCK_OWNER_DECISION_REQUIRED'
    OR v_meta#>>'{m10_0_contract_governance_v3,schema}'
       IS DISTINCT FROM 'M100_M912_SIGNED_READINESS_GATE_V2'
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=v_work_id AND sequence_no<=4 AND status='DONE')<>4
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=v_work_id AND sequence_no BETWEEN 5 AND 7
          AND status='PENDING')<>3
  THEN
    RAISE EXCEPTION 'IG_M100_V2_PRESTATE_DRIFT';
  END IF;

  SELECT w.title,w.objective,w.expected_result,w.acceptance_criteria,w.status
  INTO v_old_work
  FROM programacion.engineering_work_items w
  WHERE w.id=v_work_id AND w.work_code='PAULO-159' FOR UPDATE;
  IF NOT FOUND OR v_old_work.status<>'IN_PROGRESS'
     OR v_old_work.expected_result <> 'CUTOVER_AUTHORIZED ligado al SHA'
  THEN
    RAISE EXCEPTION 'IG_M100_V2_WORK_CONTRACT_DRIFT';
  END IF;

  SELECT substring(c.evidence_ref FROM 'provenance_receipts/([0-9]+)')::bigint
  INTO v_bundle_id
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND u.unit_code='M9.0'
    AND c.checkpoint_code='BUNDLE_READBACK' AND c.status='DONE';

  SELECT substring(c.evidence_ref FROM 'provenance_receipts/([0-9]+)')::bigint
  INTO v_ready_id
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND u.unit_code='M9.12'
    AND c.checkpoint_code='CUTOVER_READY_READBACK' AND c.status='DONE';

  IF v_bundle_id IS DISTINCT FROM 187 OR v_ready_id IS DISTINCT FROM 1667 THEN
    RAISE EXCEPTION 'IG_M100_V2_PINNED_RECEIPTS_CHANGED:%,%',v_bundle_id,v_ready_id;
  END IF;
  SELECT * INTO v_bundle FROM programacion.provenance_receipts WHERE id=v_bundle_id;
  SELECT * INTO v_ready FROM programacion.provenance_receipts WHERE id=v_ready_id;
  IF v_bundle.id IS NULL OR v_ready.id IS NULL THEN
    RAISE EXCEPTION 'IG_M100_V2_PINNED_RECEIPTS_ABSENT';
  END IF;

  -- Actual positive: the existing canonical verifier, not a synthetic flag.
  PERFORM programacion.fn_assert_provenance_receipt(
    v_bundle.id,v_bundle.receipt_kind,v_bundle.execution_id,v_bundle.head_sha,
    v_bundle.subject_type,v_bundle.subject_ref,v_bundle.subject_sha256);
  PERFORM programacion.fn_assert_provenance_receipt(
    v_ready.id,v_ready.receipt_kind,v_ready.execution_id,v_ready.head_sha,
    v_ready.subject_type,v_ready.subject_ref,v_ready.subject_sha256);

  v_positive := v_bundle.receipt_kind='EVIDENCE_VERIFICATION'
    AND v_ready.receipt_kind='EVIDENCE_VERIFICATION'
    AND v_bundle.issuer_channel='EVIDENCE_VERIFIER_V1'
    AND v_ready.issuer_channel='EVIDENCE_VERIFIER_V1'
    AND v_bundle.payload->>'verification_status'='VERIFIED'
    AND v_ready.payload->>'verification_status'='VERIFIED'
    AND v_ready.payload->>'readiness_status'='CUTOVER_READY'
    AND v_bundle.head_sha=v_ready.head_sha
    AND v_bundle.head_sha ~ '^[0-9a-f]{40}$'
    AND v_bundle.subject_sha256=v_ready.payload->>'bundle_sha256'
    AND v_bundle.subject_sha256 ~ '^[0-9a-f]{64}$'
    AND v_bundle.payload#>>'{manifest,bundle_sha256}'=v_bundle.subject_sha256
    AND encode(extensions.digest(convert_to(
         programacion.fn_v09_canonical_jsonb_text(
           v_bundle.payload#>'{manifest,identities}'),'UTF8'),'sha256'),'hex')
      = v_bundle.subject_sha256;
  SELECT count(*)=7 AND bool_and(
    encode(extensions.digest(convert_to(
       programacion.fn_v09_canonical_jsonb_text(
          v_bundle.payload#>array['manifest','components',t.k]),
       'UTF8'),'sha256'),'hex')
      = v_bundle.payload#>>array['manifest','identities',t.k||'_sha256'])
  INTO v_components_ok
  FROM (VALUES ('contracts'),('registry'),('core'),('semantics'),
               ('curator'),('validator'),('edge')) AS t(k);

  -- Five observed fail-closed cases, with no INSERT, UPDATE or simulated decision.
  BEGIN
    PERFORM programacion.fn_assert_provenance_receipt(
      v_bundle.id,v_bundle.receipt_kind,v_bundle.execution_id,
      repeat('0',40),v_bundle.subject_type,v_bundle.subject_ref,v_bundle.subject_sha256);
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    v_wrong_head := SQLERRM LIKE 'verified provenance receipt does not bind exact subject%';
  END;
  BEGIN
    PERFORM programacion.fn_assert_provenance_receipt(
      v_bundle.id,v_bundle.receipt_kind,v_bundle.execution_id,v_bundle.head_sha,
      v_bundle.subject_type,v_bundle.subject_ref,repeat('0',64));
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    v_wrong_bundle := SQLERRM LIKE 'verified provenance receipt does not bind exact subject%';
  END;
  BEGIN
    PERFORM programacion.fn_assert_provenance_receipt(
      0,v_ready.receipt_kind,v_ready.execution_id,v_ready.head_sha,
      v_ready.subject_type,v_ready.subject_ref,v_ready.subject_sha256);
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    v_missing_ready := SQLERRM LIKE 'verified provenance receipt 0 not found%';
  END;
  BEGIN
    PERFORM programacion.fn_assert_provenance_receipt(
      v_bundle.id,'HUMAN_DECISION',v_bundle.execution_id,v_bundle.head_sha,
      'human_decision','FORGED',v_bundle.subject_sha256);
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    v_forged_authority := SQLERRM LIKE 'verified provenance receipt does not bind exact subject%';
  END;
  BEGIN
    PERFORM programacion.fn_assert_provenance_receipt(
      v_ready.id,v_ready.receipt_kind,v_ready.execution_id,v_ready.head_sha,
      'IG_CUTOVER_READINESS','WRONG_COHORT',v_ready.subject_sha256);
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    v_wrong_ready_subject := SQLERRM LIKE 'verified provenance receipt does not bind exact subject%';
  END;

  SELECT count(*)=1 INTO v_constraints_ok
  FROM pg_constraint
  WHERE conrelid='programacion.human_decisions'::regclass
    AND conname='human_decisions_head_sha_check'
    AND pg_get_constraintdef(oid) LIKE '%{40}%';
  SELECT count(*)=1 INTO v_literal_check
  FROM pg_constraint
  WHERE conrelid='programacion.human_decisions'::regclass
    AND conname='human_decisions_decision_check'
    AND pg_get_constraintdef(oid) LIKE '%APPROVE%'
    AND pg_get_constraintdef(oid) LIKE '%REJECT%'
    AND pg_get_constraintdef(oid) NOT LIKE '%CUTOVER_AUTHORIZED%';
  SELECT count(*)=3 INTO v_triggers_ok
  FROM pg_trigger
  WHERE NOT tgisinternal AND tgenabled='O' AND (
    (tgrelid='programacion.human_decisions'::regclass
      AND tgname IN ('trg_human_decisions_insert_guard',
                     'trg_human_decisions_authority_receipt'))
    OR (tgrelid='programacion.promotions'::regclass
      AND tgname='trg_promotions_verified_authority'));
  SELECT NOT EXISTS (SELECT 1 FROM programacion.human_decisions
    WHERE decision='APPROVE'
      AND head_sha=v_bundle.head_sha
      AND metadata->>'decision_class'='CUTOVER_AUTHORIZED') INTO v_no_approval;
  SELECT NOT EXISTS (SELECT 1 FROM programacion.promotions
    WHERE head_sha=v_bundle.head_sha) INTO v_no_promotion;

  IF NOT (
    coalesce(v_positive,false)
    AND coalesce(v_components_ok,false)
    AND coalesce(v_wrong_head,false)
    AND coalesce(v_wrong_bundle,false)
    AND coalesce(v_missing_ready,false)
    AND coalesce(v_forged_authority,false)
    AND coalesce(v_wrong_ready_subject,false)
    AND coalesce(v_constraints_ok,false)
    AND coalesce(v_literal_check,false)
    AND coalesce(v_triggers_ok,false)
    AND coalesce(v_no_approval,false)
    AND coalesce(v_no_promotion,false)
  ) THEN
    RAISE EXCEPTION 'IG_M100_V2_GUARD_MATRIX_FAILED';
  END IF;

  -- Bind current cross-cutting judges. No new judge or authority.
  SELECT count(*),jsonb_object_agg(c.capability_code,
      jsonb_build_object('version',c.version,'manifest_sha256',c.manifest_sha256))
  INTO v_route_count,v_router_refs
  FROM public.lf_capability_current c
  JOIN public.lf_capability_version_registry vr
    ON vr.capability_code=c.capability_code AND vr.version=c.version
    AND vr.manifest_sha256=c.manifest_sha256 AND vr.release_state='RELEASED'
  WHERE c.capability_code IN ('SAFE_CHANGE_ADMISSION',
      'HUMAN_ESCALATION_ADMISSION','TARGETED_EVIDENCE_ACQUISITION');

  SELECT vr.manifest INTO v_escalation_manifest
  FROM public.lf_capability_current c
  JOIN public.lf_capability_version_registry vr
    ON vr.capability_code=c.capability_code AND vr.version=c.version
    AND vr.manifest_sha256=c.manifest_sha256
  WHERE c.capability_code='HUMAN_ESCALATION_ADMISSION'
    AND vr.release_state='RELEASED';
  IF v_route_count IS DISTINCT FROM 3
     OR v_escalation_manifest#>>'{dependencies,SAFE_CHANGE_ADMISSION,version}'
        IS DISTINCT FROM v_router_refs#>>'{SAFE_CHANGE_ADMISSION,version}'
     OR v_escalation_manifest#>>'{dependencies,SAFE_CHANGE_ADMISSION,manifest_sha256}'
        IS DISTINCT FROM v_router_refs#>>'{SAFE_CHANGE_ADMISSION,manifest_sha256}'
     OR v_escalation_manifest#>>'{dependencies,TARGETED_EVIDENCE_ACQUISITION,version}'
        IS DISTINCT FROM v_router_refs#>>'{TARGETED_EVIDENCE_ACQUISITION,version}'
     OR v_escalation_manifest#>>'{dependencies,TARGETED_EVIDENCE_ACQUISITION,manifest_sha256}'
        IS DISTINCT FROM v_router_refs#>>'{TARGETED_EVIDENCE_ACQUISITION,manifest_sha256}'
     OR v_escalation_manifest#>>'{contract,human_queue_allowed_only_on}'
        IS DISTINCT FROM 'HUMAN_ELIGIBLE'
  THEN
    RAISE EXCEPTION 'IG_M100_V2_PREHUMAN_CAPABILITY_DRIFT';
  END IF;
  IF (SELECT count(*) FROM private.lf_human_escalation_policies_v1
      WHERE status='ACTIVE' AND producer_code='INPUT_GOVERNANCE'
      AND subject_type='INPUT_GAP_PROPOSAL'
      AND mode='EVIDENCE_THEN_HUMAN' AND targeted_evidence_required
      AND human_after_exhaustion) < 1 THEN
    RAISE EXCEPTION 'IG_M100_V2_IG_ESCALATION_POLICY_NOT_ACTIVE';
  END IF;

  v_checks:=jsonb_build_object(
    'result','PASS','schema','IG_M100_ENGINEERING_PRECHECK_V2',
    'verified_by','CANONICAL_PROVENANCE_VERIFIER_AND_DB_CATALOG',
    'bundle_receipt_id',v_bundle.id,
    'readiness_receipt_id',v_ready.id,
    'bundle_sha256',v_bundle.subject_sha256,
    'frozen_git_head_sha40',v_bundle.head_sha,
    'signed_snapshot_components',7,
    'positive_receipts_verified',v_positive,
    'negative_wrong_head_rejected',v_wrong_head,
    'negative_wrong_bundle_rejected',v_wrong_bundle,
    'negative_missing_receipt_rejected',v_missing_ready,
    'negative_forged_authority_rejected',v_forged_authority,
    'negative_wrong_readiness_subject_rejected',v_wrong_ready_subject,
    'negative_test_count',5,
    'existing_decision_classifiers_current',v_router_refs,
    'pre_human_escalation_policy_verified',true,
    'decision_check_enforced',v_literal_check,
    'head_check_enforced',v_constraints_ok,
    'authority_triggers_enabled',v_triggers_ok,
    'no_human_cutover_approval',v_no_approval,
    'no_operational_promotion',v_no_promotion,
    'domain_writes',0,'production_activated',false
  );

  -- Readback SQL is role-limited by existing SELECT ACL only. It invokes no
  -- private hash function, no new SECURITY DEFINER function and no approval API.
  v_sql:='SELECT '
    ||'(u.unit_metadata#>>''{m10_0_engineering_admission_v2,verification,result}''=''PASS'') AS preflight_pass,'
    ||'(u.unit_metadata#>>''{m10_0_engineering_admission_v2,verification,negative_test_count}''=''5'') AS five_negative_cases,'
    ||'(u.unit_metadata#>>''{m10_0_operational_admission_v2,status}''=''BLOCKED_PENDING_GOVERNED_HUMAN_AUTHORITY'') AS operational_blocked,'
    ||'(u.unit_metadata#>>''{m10_0_decision_routing_v1,pre_human_gate}''=''HUMAN_ESCALATION_ADMISSION'') AS prehuman_gate_bound,'
    ||'(u.unit_metadata#>>''{m10_0_decision_routing_v1,route_policy,only_human_eligible_routes_to_queue}''=''true'') AS only_eligible_human,'
    ||'(SELECT count(*)=0 FROM programacion.human_decisions hd WHERE hd.decision=''APPROVE'' AND hd.head_sha='''
      ||v_bundle.head_sha||''' AND hd.metadata->>''decision_class''=''CUTOVER_AUTHORIZED'') AS no_cutover_approval,'
    ||'(SELECT count(*)=0 FROM programacion.promotions p WHERE p.head_sha='''
      ||v_bundle.head_sha||''') AS no_promotion '
    ||'FROM programacion.engineering_plan_units u '
    ||'WHERE u.plan_code=''IG_CURATOR_VALIDATOR_REFACTOR_V2'' AND u.unit_code=''M10.0''';

  v_specs:=v_meta->'action_specs_v1';
  v_src:=v_meta->'source_pack_v1';
  IF jsonb_typeof(v_specs)<>'object' OR jsonb_typeof(v_src)<>'object' THEN
    RAISE EXCEPTION 'IG_M100_V2_SPEC_OR_SOURCEPACK_MISSING';
  END IF;

  v_meta:=jsonb_set(v_meta,'{m10_0_original_unit_exit_criterion_v2}',to_jsonb(v_old_criterion),true);
  v_meta:=jsonb_set(v_meta,'{m10_0_original_exit_criterion_v2}',
    coalesce(v_meta->'exit_criterion_v2','null'::jsonb),true);
  v_meta:=jsonb_set(v_meta,'{exit_criterion_v2}',
    jsonb_build_object(
      'phase','SANDBOX_ENGINEERING_QUALIFICATION',
      'human_approval_required_for_CP5',false,
      'operational_cutover_authority_separate',true,
      'decision_routing_policy','m10_0_decision_routing_v1',
      'technical_readback_required',true),true);
  v_meta:=jsonb_set(v_meta,'{m10_0_original_work_contract_v1}',
    jsonb_build_object('title',v_old_work.title,'objective',v_old_work.objective,
      'expected_result',v_old_work.expected_result,
      'acceptance_criteria',v_old_work.acceptance_criteria),true);
  v_meta:=jsonb_set(v_meta,'{m10_0_original_governance_v3}',
    v_meta->'m10_0_contract_governance_v3',true);
  v_meta:=jsonb_set(v_meta,'{m10_0_historical_migration_debt_v1}',
    jsonb_build_object(
      'status','DEBT_RECONCILIATION_SEPARATE',
      'ledger_state_at_admission','UNAPPLIED_AT_ORIGINAL_VERSION',
      'source_path','supabase/migrations/20261012223000_ig_m100_sandbox_technical_vs_operational_authority_v1.sql',
      'source_git_blob','dbe466b827f10c257dba6449d65d6750f2328057',
      'tracking_issue','github://cristhianlujan/claude-persona-lf-patch/issues/2357',
      'not_engineering_checkpoint_dependency',true,
      'never_auto_stamp_ledger',true,
      'never_replay_old_migration',true),true);
  v_meta:=jsonb_set(v_meta,'{m10_0_operational_admission_v2}',
    jsonb_build_object(
      'status','BLOCKED_PENDING_GOVERNED_HUMAN_AUTHORITY',
      'gate','INDEPENDENT_OPERATIONAL_RELEASE_ADMISSION',
      'real_human_decision_required',true,'decision','APPROVE',
      'decision_class','CUTOVER_AUTHORIZED',
      'required_receipt_kind','HUMAN_DECISION',
      'required_approval_ref',true,
      'm9_signed_receipt_id',v_bundle.id,'m912_readiness_receipt_id',v_ready.id,
      'git_head_sha40',v_bundle.head_sha,'bundle_sha256',v_bundle.subject_sha256,
      'original_unit_exit_criterion',v_old_criterion,
      'original_work_acceptance_criteria',v_old_work.acceptance_criteria,
      'operational_admission_granted',false,
      'production_activation',false),true);
  v_meta:=jsonb_set(v_meta,'{m10_0_contract_governance_v3}',
    (v_meta->'m10_0_contract_governance_v3')
      ||jsonb_build_object('status','SUPERSEDED_FOR_ENGINEERING',
         'human_approval_required_at_CP5',false,
         'operational_human_approval_still_required',true,
         'superseded_by','M100_SANDBOX_ENGINEERING_GOVERNANCE_V4'),true);
  v_meta:=jsonb_set(v_meta,'{m10_0_contract_governance_v4}',
    jsonb_build_object('schema','M100_SANDBOX_ENGINEERING_GOVERNANCE_V4',
      'phase','SANDBOX_ENGINEERING_QUALIFICATION',
      'owner_human_approval_as_checkpoint_prerequisite',false,
      'm90_frozen_anchor',v_bundle.id,'m912_readiness_anchor',v_ready.id,
      'verifier','EXISTING_PROVENANCE_VERIFIER',
      'independent_operational_gate','m10_0_operational_admission_v2',
      'pre_human_decision_routing','m10_0_decision_routing_v1',
      'no_new_shared_validator',true,
      'production_activation',false),true);
  -- Pre-human judgment is for IG diagnostic proposals; it must not
  -- override real cutover human authorization for an operational release.
  -- The existing IG adapter resolves live canonical currentness first.
  v_meta:=jsonb_set(v_meta,'{m10_0_decision_routing_v1}',
    jsonb_build_object(
      'schema','IG_M100_EXISTING_PREHUMAN_JUDGE_BINDING_V1',
      'pre_human_gate','HUMAN_ESCALATION_ADMISSION',
      'safe_change_gate','SAFE_CHANGE_ADMISSION',
      'evidence_gate','TARGETED_EVIDENCE_ACQUISITION',
      'current_capabilities',v_router_refs,
      'source_currentness','IG_LIVE_CANONICAL_CLASSIFIER_REQUIRED',
      'ig_live_disposition','private.fn_lf_ig_human_decision_live_disposition_v1',
      'ig_eligibility_adapter','private.fn_lf_human_decision_open_ig_v3',
      'policy_authority','private.lf_human_escalation_policies_v1',
      'route_policy',jsonb_build_object(
        'no_human_for',jsonb_build_array('NO_HUMAN_REQUIRED',
          'AUTO_RESOLVE_FIRST','AUTO_EXECUTION_ELIGIBLE',
          'ACQUIRE_EVIDENCE','EVIDENCE_REQUIRED'),
        'blocked_and_unknown_not_approval',true,
        'recommended_is_not_permission',true,
        'only_human_eligible_routes_to_queue',true,
        'evidence_exhaustion_requires_proof',true,
        'policy_governs_human_eligibility',true),
      'technical_checkpoint_CP5_human_approval_required',false,
      'operational_cutover_authority_gate','m10_0_operational_admission_v2',
      'cutover_human_receipt_not_replaced_by_safe_change',true,
      'classification_executes_effects',false,
      'qualification_automatically_promotes',false),true);
  v_meta:=jsonb_set(v_meta,'{m10_0_engineering_admission_v2}',
    jsonb_build_object('status','QUALIFIED_IN_MIGRATION_PREFLIGHT',
      'phase','SANDBOX_ENGINEERING_ONLY',
      'verification',v_checks,
      'eligible_for_checkpoint_readback',true,
      'does_not_close_checkpoints',true,
      'operational_release_authorized',false),true);
  v_meta:=jsonb_set(v_meta,'{exit_criterion_v3}',
    jsonb_build_object('phase','SANDBOX_ENGINEERING_QUALIFICATION',
      'criterion','CP5 verify guarded human authority with no approval; CP6 replay-readback authenticated positive and five actual negative verifier cases; CP7 terminal readback tied to M9.0 and M9.12, operational gate BLOCKED',
      'requires_human_decision',false,
      'operational_admission_ref','m10_0_operational_admission_v2'),true);

  -- jsonb_set(create_missing=true) does not create a missing parent.
  -- Create parent explicitly, per IG-M99-JSONB-PARENT-NULL-ASSERTION-001.
  v_meta:=jsonb_set(v_meta,'{m10_0_original_specs_v1}','{}'::jsonb,true);
  FOREACH v_cp IN ARRAY ARRAY['HUMAN_DECISION_RECORD','NEG_SHA_MISMATCH','AUTHORITY_READBACK'] LOOP
    v_spec:=v_specs->v_cp;
    -- Canonical CP7 source/checkpoint exists, but the original action_spec
    -- was absent. Preserve this absence and build only a read-only contract.
    v_meta:=jsonb_set(v_meta,ARRAY['m10_0_original_specs_v1',v_cp],
      coalesce(v_spec,'null'::jsonb),true);
    IF v_spec IS NULL AND v_cp='AUTHORITY_READBACK' THEN
      PERFORM 1 FROM programacion.engineering_work_checkpoints c
        WHERE c.work_item_id=v_work_id AND c.checkpoint_code=v_cp
          AND c.sequence_no=7 AND c.status='PENDING'
          AND coalesce(length(btrim(c.title)),0)>0;
      IF NOT FOUND
        OR jsonb_typeof(v_src#>ARRAY['checkpoint_inputs',v_cp,'inputs'])
           IS DISTINCT FROM 'object'
      THEN
        RAISE EXCEPTION 'IG_M100_V2_CP7_CANONICAL_SOURCE_ABSENT';
      END IF;
      v_spec:=jsonb_build_object(
        'schema_version','ENGINEERING_ACTION_SPEC_V3',
        'checkpoint_code',v_cp,
        'contract_source','EXPLICIT_ACTION_SPEC',
        'forbidden',jsonb_build_array(
          'INFER_EXECUTION_SEMANTICS_FROM_TITLE',
          'SYNTHETIC_PASS_WITHOUT_MACHINE_ASSERTION'),
        'source_pack_missing_typed','[]'::jsonb
      );
    END IF;
    IF v_spec IS NULL THEN RAISE EXCEPTION 'IG_M100_V2_CHECKPOINT_SPEC_MISSING:%',v_cp; END IF;
    v_spec:=v_spec-'decision_authority_contract'
                  -'test_execution_contract'-'negative_contract_v1';
    v_spec:=v_spec || jsonb_build_object(
      'status','READY','action_kind','READBACK_ONCE',
      'recipe_mode','READBACK_EXACT','contract_family','CANONICAL_LEDGER_READBACK',
      'precision','IG_M100_SANDBOX_ENGINEERING_V2',
      'expected','Read actual Train preflight proof from unit metadata; verify pinned M9 signed receipt, five actual negative assertions and operational gate BLOCKED; never create human approval.',
      'mutation_policy','NO_DOMAIN_MUTATION',
      'requires_material_execution',false,
      'verification_queries',jsonb_build_array(v_sql),
      'assertion_contract',jsonb_build_object(
         'mode','EXPLICIT_PASS_WHEN_SUBSET',
         'pass_when',jsonb_build_object('preflight_pass',true,
           'five_negative_cases',true,'operational_blocked',true,
           'prehuman_gate_bound',true,'only_eligible_human',true,
           'no_cutover_approval',true,'no_promotion',true)),
      'target',jsonb_build_object(
        'declared_objects',jsonb_build_array(
          'programacion.engineering_plan_units',
          'programacion.engineering_work_checkpoints',
          'programacion.provenance_receipts',
          'programacion.human_decisions','programacion.promotions'),
        'declared_artifacts','[]'::jsonb,'mutation_artifacts','[]'::jsonb,
        'declared_assets','[]'::jsonb,'declared_events','[]'::jsonb));
    v_specs:=jsonb_set(v_specs,ARRAY[v_cp],v_spec,true);
    v_src:=jsonb_set(v_src,
      ARRAY['checkpoint_inputs',v_cp,'inputs','queries'],jsonb_build_array(v_sql),true);
    v_src:=jsonb_set(v_src,
      ARRAY['checkpoint_inputs',v_cp,'inputs','db_objects'],
        jsonb_build_array('programacion.engineering_plan_units',
          'programacion.engineering_work_checkpoints',
          'programacion.provenance_receipts','programacion.human_decisions',
          'programacion.promotions'),true);
    v_src:=jsonb_set(v_src,ARRAY['checkpoint_inputs',v_cp,'missing'],
      '[]'::jsonb,true);
    v_src:=jsonb_set(v_src,ARRAY['checkpoint_inputs',v_cp,'missing_typed'],
      '[]'::jsonb,true);
  END LOOP;
  v_meta:=jsonb_set(v_meta,'{action_specs_v1}',v_specs,true);
  v_meta:=jsonb_set(v_meta,'{source_pack_v1}',v_src,true);

  -- Contract + governance + all 3 validators and original owner objective
  -- change in the same atomic Train transaction.
  UPDATE programacion.engineering_plan_units
  SET unit_metadata=v_meta,
    exit_criterion='SANDBOX ENGINEERING: CP5 readback real human-decision guard with no approval; CP6 one canonical positive and five negative verifier cases captured by exact Train apply; CP7 final M9.0/M9.12 verified readback with operational gate BLOCKED. No operational CUTOVER_AUTHORIZED is produced or required for engineering DONE. Original operational criterion preserved as a separate authority gate.'
  WHERE id=v_unit_id AND work_item_id=v_work_id;

  UPDATE programacion.engineering_work_items
  SET title='M10.0 — ingeniería de autoridad de promoción: prueba sandbox y gate operativo separado',
      objective='Calificar los controles de autoridad de promoción contra bundle firmado M9.0 y readiness M9.12; mantener cutover real bajo decisión humana independiente',
      expected_result='Ingeniería sandbox calificada con 1 caso positivo, 5 negativos y operación bloqueada sin aprobación humana',
      acceptance_criteria=jsonb_build_array(
        'CP5–CP7 prueban controles reales en sandbox y ledger',
        'M9.0/M9.12 pinned, 7/7 componentes, sin reproducción de bundle',
        'Escalamiento previo por SAFE_CHANGE_ADMISSION y HUMAN_ESCALATION_ADMISSION: no escalar recomendaciones sin agotar opciones automáticas',
        'Cutover humano independiente: APPROVE real, authority_receipt HUMAN_DECISION; no activación automática'
      )
  WHERE id=v_work_id AND work_code='PAULO-159' AND status='IN_PROGRESS';

  UPDATE programacion.engineering_work_checkpoints
  SET title=CASE checkpoint_code
     WHEN 'HUMAN_DECISION_RECORD' THEN 'Sandbox CP5: guard de autorización humana y ausencia de aprobaciones'
     WHEN 'NEG_SHA_MISMATCH' THEN 'Sandbox CP6: verificador canónico positivo y cinco rechazos reales'
     WHEN 'AUTHORITY_READBACK' THEN 'Sandbox CP7: readback terminal; cutover operativo independiente bloqueado'
     END
  WHERE work_item_id=v_work_id AND sequence_no BETWEEN 5 AND 7 AND status='PENDING';

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_id AND sequence_no BETWEEN 5 AND 7
        AND status='PENDING')<>3
    OR (SELECT unit_metadata#>>'{m10_0_engineering_admission_v2,verification,result}'
        FROM programacion.engineering_plan_units WHERE id=v_unit_id)<>'PASS'
    OR (SELECT unit_metadata#>>'{m10_0_decision_routing_v1,pre_human_gate}'
        FROM programacion.engineering_plan_units WHERE id=v_unit_id)
       IS DISTINCT FROM 'HUMAN_ESCALATION_ADMISSION'
    OR (SELECT unit_metadata#>>'{exit_criterion_v2,phase}'
        FROM programacion.engineering_plan_units WHERE id=v_unit_id)
       IS DISTINCT FROM 'SANDBOX_ENGINEERING_QUALIFICATION'
    OR (SELECT expected_result FROM programacion.engineering_work_items
        WHERE id=v_work_id) NOT LIKE 'Ingeniería sandbox%'
  THEN
    RAISE EXCEPTION 'IG_M100_V2_ATOMIC_POSTSTATE_FAILED';
  END IF;
END;
$m100$;