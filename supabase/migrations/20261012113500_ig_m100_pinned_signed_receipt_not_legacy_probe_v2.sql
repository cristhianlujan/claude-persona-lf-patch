-- M10.0: reconcile authority without declaring legacy M9.0 probe hash equal.
-- Construction/readback only; no human decision, promotion or production activation.
-- The earlier BUNDLE_MANIFEST_SHA evidence is a pre-freeze judge result.
-- Final M9.0 BUNDLE_READBACK pins receipt by ID, not latest. The receipt contains
-- the frozen component snapshot. A different historical digest remains visible.
DO $m100$
DECLARE
 m jsonb; s jsonb; specs jsonb; src jsonb; q text;
BEGIN
 SELECT unit_metadata INTO m
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.0'
 FOR UPDATE;
 IF m IS NULL
    OR m#>>'{action_specs_v1,BUNDLE_M9_BINDING,precision}' IS DISTINCT FROM 'FROZEN_BUNDLE_TYPED_IDENTITY_CONTRACT_V1'
    OR m#>>'{m10_0_contract_governance_v1,freeze_bundle_to_m90_signed_receipt}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'M100_PINNED_RECEIPT_PRESTATE_DRIFT'; END IF;

 q:=$verify$
WITH anchor AS (
 SELECT m.evidence_ref AS legacy_evidence,
        c.evidence_ref AS frozen_evidence,
        c.status AS checkpoint_status,
        substring(c.evidence_ref FROM 'provenance_receipts/([0-9]+)')::bigint AS frozen_id
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_checkpoints c
   ON c.work_item_id=u.work_item_id AND c.checkpoint_code='BUNDLE_READBACK'
 JOIN programacion.engineering_work_checkpoints m
   ON m.work_item_id=u.work_item_id AND m.checkpoint_code='BUNDLE_MANIFEST_SHA'
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M9.0'
),
r AS (
 SELECT a.*,p.id,p.head_sha,p.subject_sha256,p.issuer_channel,p.payload
 FROM anchor a JOIN programacion.provenance_receipts p ON p.id=a.frozen_id
)
SELECT
 (payload->>'verification_status'='VERIFIED'
  AND issuer_channel='EVIDENCE_VERIFIER_V1'
  AND checkpoint_status='DONE') AS receipt_verified,
 (payload#>>'{manifest,bundle_sha256}'=subject_sha256
  AND programacion.fn_v09_sha256_jsonb(payload#>'{manifest,identities}')=subject_sha256) AS manifest_sha_parity,
 (payload#>>'{manifest,identities,git_head}'=head_sha
  AND head_sha ~ '^[0-9a-f]{40}$'
  AND subject_sha256 ~ '^[0-9a-f]{64}$') AS head_bound,
 (frozen_evidence LIKE 'supabase://programacion.provenance_receipts/'||id::text||' %') AS provenance_pinned,
 (SELECT count(*)=7
         AND bool_and(programacion.fn_v09_sha256_jsonb(payload#>ARRAY['manifest','components',k])
                      =payload#>>ARRAY['manifest','identities',k||'_sha256'])
  FROM (VALUES ('core'),('edge'),('curator'),('validator'),('semantics'),('contracts'),('registry')) AS v(k)
 ) AS components_verified,
 (legacy_evidence LIKE '%'||subject_sha256||'%') AS historical_probe_equals_release,
 id AS frozen_receipt_id, head_sha AS frozen_head_sha,
 subject_sha256 AS frozen_bundle_sha256
FROM r
$verify$;

 specs:=m->'action_specs_v1';
 s:=specs->'BUNDLE_M9_BINDING';
 s:=s||jsonb_build_object(
  'precision','M100_PINNED_SIGNED_SNAPSHOT_V2',
  'expected','For engineering binding consume ONLY the M9.0 BUNDLE_READBACK-pinned signed receipt, self-verify 7 components, its manifest identity and head. Record BUNDLE_MANIFEST_SHA mismatch as an earlier, distinct test observation; never call the two hashes equivalent. Keep operational cutover/human approval gated.',
  'verification_queries',jsonb_build_array(q),
  'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET',
   'pass_when',jsonb_build_object('receipt_verified',true,'manifest_sha_parity',true,
      'head_bound',true,'provenance_pinned',true,'components_verified',true)),
  'binding_contract',(coalesce(s->'binding_contract','{}'::jsonb)||
    jsonb_build_object('release_manifest_source','PINNED_SIGNED_RECEIPT_PAYLOAD',
    'legacy_probe_is_authority',false,'legacy_probe_digest_equal_is_not_required_for_engineering',true,
    'legacy_probe_difference_is_preserved',true,'operational_currentness_required',true,
    'no_latest_receipt_selection',true,'no_bundle_rebuild',true,
    'no_promotion_execution',true)));
 specs:=jsonb_set(specs,'{BUNDLE_M9_BINDING}',s,true);
 m:=jsonb_set(m,'{action_specs_v1}',specs,true);

 src:=m->'source_pack_v1';
 src:=jsonb_set(src,'{checkpoint_inputs,BUNDLE_M9_BINDING,inputs,queries}',jsonb_build_array(q),true);
 src:=jsonb_set(src,'{checkpoint_inputs,BUNDLE_M9_BINDING,inputs,db_objects}',
    '["programacion.engineering_plan_units","programacion.engineering_work_checkpoints","programacion.provenance_receipts"]'::jsonb,true);
 m:=jsonb_set(m,'{source_pack_v1}',src,true);

 m:=jsonb_set(m,'{m10_0_contract_governance_v2}',
  jsonb_build_object(
   'schema','M100_PINNED_SIGNED_SNAPSHOT_V2',
   'phase','ENGINEERING_BINDING_ONLY',
   'release_authority','M9.0_BUNDLE_READBACK_SIGNED_RECEIPT_ANCHOR',
   'frozen_manifest_is_receipt_payload',true,
   'historical_probe_may_differ',true,
   'historical_probe_equivalence_claim','FORBIDDEN',
   'frozen_components_self_digest_required',7,
   'm912_cutover_receipt_required_separately',true,
   'human_decision_required_separately',true,
   'live_operational_currentness_required',true,
   'no_auto_authorization',true,'no_production_activation',true,
   'no_manifest_rebuild',true,'preserve_legacy_evidence',true),true);

 UPDATE programacion.engineering_plan_units SET unit_metadata=m
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.0';
END $m100$;
