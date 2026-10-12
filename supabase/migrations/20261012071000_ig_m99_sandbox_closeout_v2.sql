-- IG M9.9 sandbox-only closeout; NOT a canary runtime activation.
-- Must follow Git source-first migration/ledger policy.
-- Relies on previously executed exact-source six-case transaction
-- in sandbox: CLEAN CONTINUE, 5 negative cases ROLLBACK_REQUIRED,
-- source blob 9d72abfa435bbc094d60645f77ec9e1a7868abdf.
-- Independent live signed canary gate remains BLOCKED.
DO $m99$
DECLARE u record; c record; evidence text; result jsonb; receipt jsonb;
        outcome jsonb; b jsonb; cp4 jsonb; cp5 jsonb;
BEGIN
 SELECT id,work_item_id,unit_metadata INTO STRICT u
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9'
 FOR UPDATE;
 cp4:=programacion.fn_engineering_checkpoint_action_spec_v3(
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.9','ROLLBACK_TRIGGER_NEGATIVE');
 cp5:=programacion.fn_engineering_checkpoint_action_spec_v3(
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.9','CANARY_READBACK');
 IF u.unit_metadata#>>'{m99_two_level_qualification_governance_v2,unit_acceptance_scope}'
       IS DISTINCT FROM 'SANDBOX_ENGINEERING_ONLY'
 OR u.unit_metadata#>>'{m99_two_level_qualification_governance_v2,operational_gate,status}'
       IS DISTINCT FROM 'BLOCKED_UNTIL_SEPARATE_AUTHORIZATION_AND_VERIFIED_PROVENANCE'
 OR cp4#>>'{acceptance_profile}' IS DISTINCT FROM 'SANDBOX_REVERSIBLE_QUALIFICATION_V2'
 OR cp4#>>'{assertion_contract,pass_when,evidence_origin}' IS DISTINCT FROM 'SOURCE_BOUND_SANDBOX_DB_RUN'
 OR cp5#>>'{sandbox_readback_acceptance_v2,source_bound_case_count}' IS DISTINCT FROM '6'
 OR cp5#>>'{operational_readback_acceptance_v1,signed_live_receipts_required}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'M99_NEW_GOVERNANCE_NOT_CURRENT'; END IF;
 IF NOT EXISTS (
  SELECT 1 FROM transversal.error_knowledge
  WHERE codigo='IG-M99-ROLLBACK-FIVE-TRIGGERS-VALIDATION-GAP-001'
    AND position('M99_SCOPE_SPLIT_V2_20261012' in coalesce(evidencia,''))>0
 ) OR NOT EXISTS (
  SELECT 1 FROM transversal.error_knowledge
  WHERE codigo='IG-M99-RUNTIME-EXECUTOR-RECEIPT-DISCONNECTED-001'
    AND position('M99_INTEGRATED_SIX_CASE_20261012' in coalesce(evidencia,''))>0
 ) THEN RAISE EXCEPTION 'M99_SOURCE_BOUND_EKB_EVIDENCE_MISSING'; END IF;
 SELECT version,manifest_sha256,previous_version INTO STRICT c
 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE';
 IF c.version IS DISTINCT FROM '1.0.0'
 OR c.manifest_sha256 IS DISTINCT FROM
 'd1f5947613ef7e6d74d8763e39da534f79d70d61a2eab65e4765579fa4028e44'
 OR c.previous_version IS NOT NULL
 OR EXISTS (SELECT 1 FROM public.lf_capability_version_registry
            WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1')
 THEN RAISE EXCEPTION 'M99_BASELINE_POSTSTATE_RESIDUE'; END IF;
 IF EXISTS(SELECT 1 FROM programacion.provenance_receipts
  WHERE subject_type='IG_CANARY_OBSERVATION'
    AND payload->>'verification_status'='VERIFIED')
 THEN RAISE EXCEPTION 'M99_LIVE_CANARY_REQUIRES_SEPARATE_RELEASE_ADMISSION'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=u.work_item_id AND checkpoint_code='ROLLBACK_TRIGGER_NEGATIVE')
    IS DISTINCT FROM 'PENDING'
 OR (SELECT status FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=u.work_item_id AND checkpoint_code='CANARY_READBACK')
    IS DISTINCT FROM 'PENDING'
 THEN RAISE EXCEPTION 'M99_CHECKPOINT_LIFECYCLE_CHANGED'; END IF;

 evidence:='github://cristhianlujan/claude-persona-lf-patch@761db989a64da36c339c20e57e661b9be4a2f7c9/sandbox/lf_contract_gate_test/engineering_checkpoints/m9_9/cases/integrated_six_case_canary_v1.sql#blob=9d72abfa435bbc094d60645f77ec9e1a7868abdf';
 result:=jsonb_build_object(
  'status','PASS','evidence_ref',evidence,
  'observed',jsonb_build_object(
   'test_passed',true,'test_exit_code',0,'zero_residue',true,
   'rollback_exact',true,'evidence_origin','SOURCE_BOUND_SANDBOX_DB_RUN',
   'sandbox_six_case_matrix_verified',true,'positive_control_verified',true,
   'negative_case_count',5,'baseline_currentness_verified',true,
   'operational_canary_activated',false,
   'test_scope','SANDBOX_TRANSACTIONAL_ONLY',
   'source_blob_sha1','9d72abfa435bbc094d60645f77ec9e1a7868abdf',
   'timeout_source','HISTORICAL_ELAPSED_NOT_LIVE_CANARY'));
 receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(
   'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.9','ROLLBACK_TRIGGER_NEGATIVE',
   result,'IG_M99_SANDBOX_V2');
 IF receipt->>'passed' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'M99_SANDBOX_ASSERTION_NOT_RECORDED'; END IF;
 outcome:=programacion.fn_engineering_checkpoint_transition_v1(
   'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.9','ROLLBACK_TRIGGER_NEGATIVE',
   'DONE',evidence,'IG_M99_SANDBOX_V2',
   'Sandbox six-case qualification only: 5 negative transactional rollbacks; no operational canary certification.');
 IF outcome#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
 THEN RAISE EXCEPTION 'M99_CP4_TRANSITION_FAILED'; END IF;
 IF NOT EXISTS (
  SELECT 1 FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=u.work_item_id AND checkpoint_code='ROLLBACK_TRIGGER_NEGATIVE'
    AND status='DONE' AND assertion_receipt->>'passed'='true'
 ) THEN RAISE EXCEPTION 'M99_CP4_ASSERTION_READBACK_FAILED'; END IF;
 outcome:=programacion.fn_engineering_checkpoint_transition_v1(
   'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.9','CANARY_READBACK',
   'DONE','supabase://public.lf_capability_current/INPUT_GOVERNANCE@1.0.0',
   'IG_M99_SANDBOX_V2',
   'Sandbox readback: base version 1.0.0, unchanged manifest, previous_version null, no candidate or receipt residue. Operational gate remains blocked.');
 IF outcome#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
 THEN RAISE EXCEPTION 'M99_CP5_TRANSITION_FAILED'; END IF;
 b:=programacion.fn_engineering_unit_bootstrap_v3(
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.9');
 IF (b->'state'->>'done_checkpoint_count')::integer<>5
 OR (b->'state'->>'checkpoint_count')::integer<>5
 THEN RAISE EXCEPTION 'M99_SANDBOX_UNIT_NOT_TERMINAL:%',b; END IF;
 UPDATE programacion.engineering_plan_units SET
   title='Canary reversible comprobado en sandbox; admision operativa independiente',
   unit_metadata=jsonb_set(unit_metadata,'{m99_two_level_qualification_governance_v2,sandbox_gate,qualification_state}',
      '"QUALIFIED_SANDBOX_ONLY"'::jsonb,true)
 WHERE id=u.id;
END $m99$;

UPDATE transversal.error_knowledge SET
 evidencia=CASE WHEN position('M99_SANDBOX_DONE_SCOPE_V2_20261012' in coalesce(evidencia,''))>0
 THEN evidencia ELSE concat_ws(E'\n',evidencia,
 'M99_SANDBOX_DONE_SCOPE_V2_20261012: M9.9 qualifies only the bounded sandbox reversible matrix (six cases, five condition-triggered aborts, exact INPUT_GOVERNANCE 1.0.0 restore, zero residue). This is not evidence of a live signed operational canary. Independent live admission remains blocked and is not closed by this unit.') END,
 updated_at=clock_timestamp()
WHERE codigo IN ('IG-M99-RUNTIME-EXECUTOR-RECEIPT-DISCONNECTED-001',
                 'IG-M99-ROLLBACK-FIVE-TRIGGERS-VALIDATION-GAP-001');
