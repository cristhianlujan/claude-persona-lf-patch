-- IG M9.9: EVIDENCE_VERIFIER_V1 real channel issuance NEGATIVE CONTROL.
-- Issuer token resolved ONLY on server; never returned. Receipt is REJECTED,
-- sandbox-only and always rolled back. Never qualifies live canary.
BEGIN;
CREATE TEMP TABLE ig_m99_negative_channel_test_v1(
 issued boolean,issuer text,gate_rejects boolean,rollback_executed boolean,
 durable_receipt_created boolean) ON COMMIT DROP;
DO $sig$
DECLARE v_token text;v_id bigint;v_digest text;v_subject jsonb;v_subject_sha text;
 v_payload jsonb;v_gate jsonb;v_before bigint;v_head text:='3b603c36e3bab6412b95fa833b0ef4151649295b';
BEGIN
 SELECT count(*) INTO v_before FROM programacion.provenance_receipts
 WHERE subject_type='IG_CANARY_OBSERVATION';
 SELECT decrypted_secret INTO v_token FROM vault.decrypted_secrets
 WHERE name='EVIDENCE_VERIFIER_V1_TOKEN' ORDER BY created_at DESC LIMIT 1;
 IF length(coalesce(v_token,''))<32 THEN
  RAISE EXCEPTION 'M99_SIGNED_RECEIPT_CHANNEL_UNAVAILABLE'; END IF;
 v_subject:=jsonb_build_object('schema_version','IG_M99_SANDBOX_REJECTED_TEST_V1',
  'proof_level','NEGATIVE_CONTROL_ONLY','cohort_type_code','AUTH',
  'case_code','FALSE_PASS','acceptance',false);
 v_subject_sha:=programacion.fn_v09_sha256_jsonb(v_subject);
 v_payload:=jsonb_build_object(
  'schema_version','IG_CANARY_OBSERVATION_V1',
  'head_sha',v_head,'subject_sha256',v_subject_sha,
  'verification_status','REJECTED','verifier_identity','SUPABASE:IG_M99_NEGATIVE_TEST',
  'subject_type','IG_CANARY_OBSERVATION','subject_ref','IG_CANARY:AUTH',
  'cohort_type_code','AUTH','stage','OBSERVATION','run_ref','TEST-ROLLBACK-ONLY',
  'proof_level','SANDBOX_NEGATIVE_CONTROL_NEVER_ACCEPTED',
  'observation',jsonb_build_object('false_pass_detected',true,
     'divergence_level','D0','elapsed_ms',100000,'execution_error',false,
     'receipt_present',true,'receipt_verified',false));
 SELECT r.id,r.receipt_sha256 INTO STRICT v_id,v_digest
 FROM programacion.issue_provenance_receipt(
  'EVIDENCE_VERIFIER_V1',v_token,'EVIDENCE_VERIFICATION',null,
  v_head,'IG_CANARY_OBSERVATION','IG_CANARY:AUTH',v_subject_sha,
  'SUPABASE:IG_M99_NEGATIVE_TEST','sandbox://M9.9/negative-issuer-test',
  v_payload) r;
 v_token:=null;
 IF v_digest !~ '^[0-9a-f]{64}$'
  OR NOT EXISTS(SELECT 1 FROM programacion.provenance_receipts p
    WHERE p.id=v_id AND p.issuer_channel='EVIDENCE_VERIFIER_V1'
      AND p.payload->>'verification_status'='REJECTED')
 THEN RAISE EXCEPTION 'M99_PROVENANCE_CHANNEL_ISSUE_NOT_VERIFIED'; END IF;
 v_gate:=programacion.fn_ig_m99_canary_receipt_gate_v1(v_id,v_subject_sha,'AUTH');
 IF v_gate->>'action' IS DISTINCT FROM 'ROLLBACK_REQUIRED'
  OR v_gate->>'rollback_executed' IS DISTINCT FROM 'false'
  OR NOT(v_gate->'reason_codes' ? 'RECEIPT_MISSING_STALE_OR_UNATTESTED')
 THEN RAISE EXCEPTION 'M99_REJECTED_VERIFIER_RECEIPT_WRONGLY_ACCEPTED:%',v_gate; END IF;
 INSERT INTO pg_temp.ig_m99_negative_channel_test_v1
 VALUES(true,'EVIDENCE_VERIFIER_V1',true,false,false);
END $sig$;
SELECT * FROM pg_temp.ig_m99_negative_channel_test_v1;
ROLLBACK;
