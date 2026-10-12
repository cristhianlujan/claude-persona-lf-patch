-- M10.0 CP3: M9.12 is DONE and pins CUTOVER_READY receipt #1667.
-- Use checkpoint anchored upstream receipt, never latest; same M9.0 signed bundle.
-- Engineering gate only. Human decision is independent and must not be synthesized.
DO $m100$
DECLARE m jsonb;s jsonb;specs jsonb;src jsonb;q text;
BEGIN
 SELECT unit_metadata INTO m FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.0'
 FOR UPDATE;
 IF m IS NULL
 OR m#>>'{action_specs_v1,CUTOVER_READY_PRECONDITION,status}' IS DISTINCT FROM 'BLOCK_UPSTREAM_RECEIPT_PENDING'
 OR m#>>'{m10_0_contract_governance_v2,schema}' IS DISTINCT FROM 'M100_PINNED_SIGNED_SNAPSHOT_V2'
 THEN RAISE EXCEPTION 'M100_M912_GATE_PRESTATE_DRIFT'; END IF;
 q:=$check$
WITH a AS (
 SELECT
 (SELECT substring(c.evidence_ref FROM 'provenance_receipts/([0-9]+)')::bigint
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND u.unit_code='M9.0' AND c.checkpoint_code='BUNDLE_READBACK' AND c.status='DONE') AS frozen_id,
 (SELECT substring(c.evidence_ref FROM 'provenance_receipts/([0-9]+)')::bigint
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND u.unit_code='M9.12' AND c.checkpoint_code='CUTOVER_READY_READBACK' AND c.status='DONE') AS readiness_id
),
r AS (
 SELECT a.frozen_id,a.readiness_id,f.head_sha AS frozen_head,
        f.subject_sha256 AS frozen_bundle,z.head_sha AS readiness_head,
        z.payload->>'bundle_sha256' AS readiness_bundle,
        z.issuer_channel,z.payload,z.receipt_kind,z.subject_type
 FROM a
 JOIN programacion.provenance_receipts f ON f.id=a.frozen_id
 JOIN programacion.provenance_receipts z ON z.id=a.readiness_id
)
SELECT
 (issuer_channel='EVIDENCE_VERIFIER_V1'
  AND receipt_kind='EVIDENCE_VERIFICATION'
  AND subject_type='IG_CUTOVER_READINESS'
  AND payload->>'verification_status'='VERIFIED'
  AND payload->>'readiness_status'='CUTOVER_READY') AS receipt_verified,
 (readiness_head=frozen_head AND readiness_bundle=frozen_bundle) AS exact_bundle_bound,
 (readiness_id IS NOT NULL AND frozen_id IS NOT NULL) AS both_provenance_pinned,
 readiness_id AS m912_receipt_id, frozen_id AS m90_receipt_id
FROM r
$check$;
 specs:=m->'action_specs_v1';s:=specs->'CUTOVER_READY_PRECONDITION';
 s:=s||jsonb_build_object(
  'status','READY','action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT',
  'contract_family','CANONICAL_LEDGER_READBACK',
  'precision','M100_M912_ANCHORED_READY_RECEIPT_V2',
  'expected','Read M9.12 CUTOVER_READY_READBACK anchored verified signed receipt and compare head+bundle with M9.0 anchored signed receipt. No latest selection and no human decision or production cutover.',
  'verification_queries',jsonb_build_array(q),
  'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET',
     'pass_when',jsonb_build_object('receipt_verified',true,'exact_bundle_bound',true,'both_provenance_pinned',true)),
  'upstream_receipt_contract',coalesce(s->'upstream_receipt_contract','{}'::jsonb)
      ||jsonb_build_object('selector','CHECKPOINT_ANCHORED_ID_ONLY',
        'checkpoint_code','CUTOVER_READY_READBACK','producer_unit','M9.12',
        'must_be_current',true,'no_latest_receipt_selection',true,
        'human_approval_separate',true,'no_production_activation',true));
 specs:=jsonb_set(specs,'{CUTOVER_READY_PRECONDITION}',s,true);
 m:=jsonb_set(m,'{action_specs_v1}',specs,true);
 src:=m->'source_pack_v1';
 src:=jsonb_set(src,'{checkpoint_inputs,CUTOVER_READY_PRECONDITION,inputs,queries}',jsonb_build_array(q),true);
 src:=jsonb_set(src,'{checkpoint_inputs,CUTOVER_READY_PRECONDITION,inputs,db_objects}',
 '["programacion.provenance_receipts","programacion.engineering_work_checkpoints","programacion.engineering_plan_units"]'::jsonb,true);
 m:=jsonb_set(m,'{source_pack_v1}',src,true);
 m:=jsonb_set(m,'{m10_0_contract_governance_v3}',jsonb_build_object(
   'schema','M100_M912_SIGNED_READINESS_GATE_V2',
   'gate','ENGINEERING_READINESS_ONLY',
   'upstream_selector','M9.12_CUTOVER_READY_READBACK_RECEIPT_ID',
   'same_frozen_head_and_bundle',true,
   'human_approval_required_at_CP5',true,
   'live_promotion_activation','BLOCKED_WITHOUT_HUMAN_DECISION',
   'no_production_activation',true,'no_latest_receipt',true),true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=m
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.0';
END $m100$;