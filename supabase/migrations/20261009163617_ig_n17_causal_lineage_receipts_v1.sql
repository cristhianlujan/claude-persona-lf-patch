-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / N-17 / TYPED_CAUSAL_IDENTITY
-- The Curator -> Validator hop is an ASYNC_JOB boundary. This emits the explicit causal edge for a COMPLETED run:
--   PRODUCER receipt        : typed parent (curator handoff receipt) + correlation (run), bound to the handoff receipt sha.
--   RECEIVER_EFFECT receipt : same identities, cross-linked to the producer receipt sha, effect_ref = the Validator completion.
-- and returns the CAUSAL_EFFECT_LINEAGE request (receiver readback re-read from the persisted receipt and the run).
-- Names / timestamps / same-object are never used as causal proof. Idempotent per (run, handoff receipt, completion).
CREATE OR REPLACE FUNCTION programacion.fn_ig_causal_lineage_receipts_emit_v1(p_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'public'
AS $fn$
declare
  v_head constant text := '42cc13e35a11b9fe7ab711ad2ee666778c765f91';
  v_issuer constant text := 'SUPABASE:INPUT_GOVERNANCE_CAUSAL_LINEAGE_V1';
  v_ref text := 'input-readiness-run:'||p_run_id::text;
  v_run programacion.input_readiness_runs%rowtype;
  v_h programacion.provenance_receipts%rowtype;
  v_p programacion.provenance_receipts%rowtype;
  v_r programacion.provenance_receipts%rowtype;
  v_token text; v_parent jsonb; v_corr jsonb; v_effect text; v_cur text;
  v_subj jsonb; v_sha text; v_id bigint; v_payload jsonb; v_rb programacion.provenance_receipts%rowtype;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found or v_run.status is distinct from 'COMPLETED' or v_run.validator_completed_at is null then
    raise exception 'IG_CAUSAL_LINEAGE_RUN_NOT_COMPLETED:%',p_run_id;
  end if;
  select * into v_h from programacion.provenance_receipts
   where subject_type='input_governance_curator_handoff' and subject_ref=v_ref and payload->>'verification_status'='VERIFIED'
   order by id desc limit 1;
  if not found then raise exception 'IG_CAUSAL_LINEAGE_HANDOFF_RECEIPT_MISSING:%',p_run_id; end if;
  select decrypted_secret into v_token from vault.decrypted_secrets where name='EVIDENCE_VERIFIER_V1_TOKEN' order by created_at desc limit 1;
  if length(coalesce(v_token,''))<32 then raise exception 'IG_CAUSAL_LINEAGE_EVIDENCE_VERIFIER_TOKEN_MISSING'; end if;

  v_parent:=jsonb_build_object('scope','lf:ig-curator-handoff','opaque_id','receipt-'||v_h.id::text);
  v_corr:=jsonb_build_object('scope','lf:ig-run','opaque_id','run-'||p_run_id::text);
  v_effect:='validator-completed.run-'||p_run_id::text||'.'||floor(extract(epoch from v_run.validator_completed_at))::bigint::text;
  v_cur:=case when v_run.invalidated_at is null then 'CURRENT' else 'STALE' end;

  -- producer
  v_subj:=jsonb_build_object('schema_version','IG_CAUSAL_PRODUCER_SUBJECT_V1','run_id',p_run_id,'handoff_receipt_sha256',v_h.receipt_sha256);
  v_sha:=programacion.fn_v09_sha256_jsonb(v_subj);
  select * into v_p from programacion.provenance_receipts where subject_type='IG_CAUSAL_PRODUCER' and subject_ref=v_ref and subject_sha256=v_sha and head_sha=v_head order by id desc limit 1;
  if not found then
    v_payload:=jsonb_build_object('schema_version','LF_EVIDENCE_LEDGER_RECEIPT_V1','causal_role','PRODUCER','head_sha',v_head,
      'subject_type','IG_CAUSAL_PRODUCER','subject_ref',v_ref,'subject_sha256',v_sha,'verification_status','VERIFIED','verifier_identity',v_issuer,
      'parent_identity',v_parent,'correlation_identity',v_corr,'currentness','CURRENT','handoff_receipt_sha256',v_h.receipt_sha256);
    select r.id into v_id from programacion.issue_provenance_receipt('EVIDENCE_VERIFIER_V1',v_token,'EVIDENCE_VERIFICATION',null,v_head,
      'IG_CAUSAL_PRODUCER',v_ref,v_sha,v_issuer,'supabase://programacion.provenance_receipts/'||v_h.id::text,v_payload) r;
    select * into v_p from programacion.provenance_receipts where id=v_id;
  end if;

  -- receiver effect
  v_subj:=jsonb_build_object('schema_version','IG_CAUSAL_RECEIVER_SUBJECT_V1','run_id',p_run_id,'producer_receipt_sha256',v_p.receipt_sha256,'effect_ref',v_effect);
  v_sha:=programacion.fn_v09_sha256_jsonb(v_subj);
  select * into v_r from programacion.provenance_receipts where subject_type='IG_CAUSAL_RECEIVER_EFFECT' and subject_ref=v_ref and subject_sha256=v_sha and head_sha=v_head order by id desc limit 1;
  if not found then
    v_payload:=jsonb_build_object('schema_version','LF_EVIDENCE_LEDGER_RECEIPT_V1','causal_role','RECEIVER_EFFECT','head_sha',v_head,
      'subject_type','IG_CAUSAL_RECEIVER_EFFECT','subject_ref',v_ref,'subject_sha256',v_sha,'verification_status','VERIFIED','verifier_identity',v_issuer,
      'parent_identity',v_parent,'correlation_identity',v_corr,'currentness',v_cur,'producer_receipt_sha256',v_p.receipt_sha256,'effect_ref',v_effect);
    select r.id into v_id from programacion.issue_provenance_receipt('EVIDENCE_VERIFIER_V1',v_token,'EVIDENCE_VERIFICATION',null,v_head,
      'IG_CAUSAL_RECEIVER_EFFECT',v_ref,v_sha,v_issuer,'supabase://programacion.input_readiness_runs/'||p_run_id::text||'#validator-completion',v_payload) r;
    select * into v_r from programacion.provenance_receipts where id=v_id;
  end if;

  -- receiver readback: re-read the persisted receiver receipt and the run state
  select * into v_rb from programacion.provenance_receipts where id=v_r.id;
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  return jsonb_build_object(
    'parent_identity',v_parent,'correlation_identity',v_corr,
    'provenance',jsonb_build_object('producer','ig-curator','receiver','ig-validator','authority_ref','evidence-ledger','boundary','ASYNC_JOB'),
    'currentness',jsonb_build_object('producer','CURRENT','receiver',v_cur,'correlation',v_cur),
    'producer_receipt',jsonb_build_object('receipt_id','receipt-'||v_p.id::text,'receipt_sha256',v_p.receipt_sha256,'verification_state','VERIFIED','receipt_payload',v_p.payload),
    'receiver_effect_receipt',jsonb_build_object('receipt_id','receipt-'||v_r.id::text,'receipt_sha256',v_r.receipt_sha256,'verification_state','VERIFIED','receipt_payload',v_r.payload),
    'receiver_readback',jsonb_build_object(
       'observed',(v_run.status='COMPLETED' and v_run.validator_completed_at is not null and v_rb.id is not null),
       'currentness',case when v_run.invalidated_at is null then 'CURRENT' else 'STALE' end,
       'effect_ref',v_rb.payload->>'effect_ref','receiver_receipt_sha256',v_rb.receipt_sha256));
end;
$fn$;
