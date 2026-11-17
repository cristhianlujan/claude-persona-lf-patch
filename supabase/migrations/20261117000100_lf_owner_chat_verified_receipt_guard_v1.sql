-- LF owner chat approval -- DRAFT ONLY. NO EXECUTION AGAINST LF DATABASE.
-- Authority-specific verifier consumer, NOT a parallel human-decision router.
-- Trusted signed-message ingress is NOT available to this PR. Missing active
-- issuer policy/provenance denies ALL calls. No grant to any new role.
BEGIN;

CREATE TABLE IF NOT EXISTS private.lf_owner_chat_receipt_consumptions_v1 (
  request_id uuid PRIMARY KEY REFERENCES private.lf_human_decision_requests_v1(request_id),
  authority_receipt_sha256 text NOT NULL UNIQUE CHECK (authority_receipt_sha256 ~ '^[a-f0-9]{64}$'),
  source_message_id text NOT NULL UNIQUE CHECK (length(source_message_id) >= 12),
  scope_sha256 text NOT NULL CHECK (scope_sha256 ~ '^[a-f0-9]{64}$'),
  expected_subject jsonb NOT NULL,
  action_code text NOT NULL CHECK (action_code IN ('PROMOTE_RULE_BATCH','MERGE_GOVERNANCE_PR')),
  consumer_ref text NOT NULL CHECK (length(btrim(consumer_ref)) > 0),
  consumed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (jsonb_typeof(expected_subject) = 'object')
);
REVOKE ALL ON private.lf_owner_chat_receipt_consumptions_v1
  FROM PUBLIC, anon, authenticated, service_role;

-- A revoked event is never accepted, even if originally valid.
-- Revocation creation is reserved to the same authenticated ingress.
CREATE TABLE IF NOT EXISTS private.lf_owner_chat_revocations_v1 (
  authority_receipt_sha256 text PRIMARY KEY CHECK (authority_receipt_sha256 ~ '^[a-f0-9]{64}$'),
  revocation_receipt_sha256 text NOT NULL UNIQUE CHECK (revocation_receipt_sha256 ~ '^[a-f0-9]{64}$'),
  revoked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  reason text NOT NULL CHECK (length(btrim(reason)) > 0)
);
REVOKE ALL ON private.lf_owner_chat_revocations_v1
  FROM PUBLIC, anon, authenticated, service_role;

-- Existing HUMAN_DECISION_ROUTING remains canonical for request/receipt.
-- Service-role/LLM JSON, screenshots and HUMAN:<name> do NOT confer authority.
-- A future independent ChatGPT-provider gateway must validate Ed25519 + actor
-- and populate signed provenance through the existing governed writer.
CREATE OR REPLACE FUNCTION private.fn_lf_owner_chat_consume_v1(
  p_request_id uuid,
  p_action_code text,
  p_expected_subject jsonb,
  p_currentness_sha256 text,
  p_consumer_ref text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_req private.lf_human_decision_requests_v1%ROWTYPE;
  v_dec private.lf_human_decision_receipts_v1%ROWTYPE;
  v_prov programacion.provenance_receipts%ROWTYPE;
  v_prov_id bigint;
  v_n integer;
BEGIN
  IF p_action_code NOT IN ('PROMOTE_RULE_BATCH','MERGE_GOVERNANCE_PR')
      OR p_expected_subject IS NULL OR jsonb_typeof(p_expected_subject) <> 'object'
      OR coalesce(p_currentness_sha256,'') !~ '^[a-f0-9]{64}$'
      OR nullif(btrim(p_consumer_ref),'') IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','code','INVALID_EXPECTED_SCOPE');
  END IF;
  SELECT * INTO v_req FROM private.lf_human_decision_requests_v1
    WHERE request_id=p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status','BLOCKED','code','NO_OWNER_ORDER');
  END IF;
  IF v_req.status <> 'DECIDED' OR v_req.expires_at IS NULL
      OR v_req.expires_at <= clock_timestamp() THEN
    RETURN jsonb_build_object('status','BLOCKED','code','UNDECIDED_OR_EXPIRED');
  END IF;
  IF v_req.subject_type IS DISTINCT FROM
      CASE p_action_code WHEN 'PROMOTE_RULE_BATCH' THEN 'RULE_PROMOTION_BATCH'
                         WHEN 'MERGE_GOVERNANCE_PR' THEN 'GOVERNANCE_PR' END
      OR v_req.subject_ref IS DISTINCT FROM p_expected_subject
      OR v_req.currentness_sha256 IS DISTINCT FROM p_currentness_sha256 THEN
    RETURN jsonb_build_object('status','BLOCKED','code','EXACT_SCOPE_MISMATCH');
  END IF;
  SELECT * INTO v_dec FROM private.lf_human_decision_receipts_v1
    WHERE request_id=p_request_id;
  IF NOT FOUND OR v_dec.decision_code <> 'APPROVE'
      OR v_dec.observed_currentness_sha256 IS DISTINCT FROM p_currentness_sha256 THEN
    RETURN jsonb_build_object('status','BLOCKED','code','DECISION_NOT_AUTHENTICATED');
  END IF;
  IF coalesce(v_dec.authority_receipt_ref,'') !~
      '^supabase://programacion/provenance_receipts/[0-9]+$' THEN
    RETURN jsonb_build_object('status','BLOCKED','code','AUTHORITY_RECEIPT_INVALID');
  END IF;
  v_prov_id := split_part(v_dec.authority_receipt_ref,'/',5)::bigint;
  SELECT * INTO v_prov FROM programacion.provenance_receipts WHERE id=v_prov_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status','BLOCKED','code','MISSING_SIGNED_PROVENANCE');
  END IF;

  -- Canonical verifier checks receipt SHA, active authority policy, reviewer
  -- role and exact request binding. NO replacement verifier or bypass.
  PERFORM private.fn_lf_human_decision_assert_authority_receipt_v1(
    p_request_id, v_dec.decision_code, v_dec.reviewer_role,
    v_dec.authority_ref, v_dec.authority_receipt_ref,
    v_dec.authority_receipt_sha256, v_dec.observed_currentness_sha256);

  IF v_prov.issuer_channel <> 'CHATGPT_SIGNED_USER_MESSAGE_V1'
      OR v_prov.payload->>'signature_verification' <> 'TRUSTED_INGRESS_ED25519_PASS'
      OR v_prov.payload->>'event_type' <> 'USER_MESSAGE'
      OR v_prov.payload->>'scope_sha256' IS DISTINCT FROM p_currentness_sha256
      OR v_prov.payload->>'action_code' IS DISTINCT FROM 'APPROVE'
      OR coalesce(v_prov.payload->>'source_message_id','') = ''
      OR coalesce(v_prov.payload->>'literal_text_sha256','') !~ '^[a-f0-9]{64}$'
      OR coalesce(v_prov.payload->>'signed_key_id','') = ''
      OR coalesce(v_prov.payload->>'actor_subject','') = ''
      OR coalesce(v_prov.payload->>'model_generated','') <> 'false'
      OR (v_prov.payload->>'signed_expires_at')::timestamptz <= clock_timestamp()
      OR (v_prov.payload->>'signed_sent_at')::timestamptz >
          clock_timestamp() + interval '30 seconds'
      OR (v_prov.payload->>'signed_expires_at')::timestamptz >
          (v_prov.payload->>'signed_sent_at')::timestamptz + interval '15 minutes'
      OR (v_prov.payload->>'signed_expires_at')::timestamptz IS DISTINCT FROM v_req.expires_at THEN
    RETURN jsonb_build_object('status','BLOCKED','code','NO_TRUSTED_CHAT_ATTESTATION');
  END IF;

  IF EXISTS(SELECT 1 FROM private.lf_owner_chat_revocations_v1
    WHERE authority_receipt_sha256=v_dec.authority_receipt_sha256) THEN
    RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_REVOKED');
  END IF;
  IF EXISTS(SELECT 1 FROM private.lf_owner_chat_receipt_consumptions_v1
    WHERE request_id=p_request_id OR authority_receipt_sha256=v_dec.authority_receipt_sha256
      OR source_message_id=v_prov.payload->>'source_message_id') THEN
    RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_ALREADY_CONSUMED');
  END IF;
  INSERT INTO private.lf_owner_chat_receipt_consumptions_v1(
    request_id,authority_receipt_sha256,source_message_id,scope_sha256,
    expected_subject,action_code,consumer_ref)
  VALUES(p_request_id,v_dec.authority_receipt_sha256,
    v_prov.payload->>'source_message_id',p_currentness_sha256,
    p_expected_subject,p_action_code,p_consumer_ref)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_ALREADY_CONSUMED');
  END IF;
  RETURN jsonb_build_object('status','CONSUMED','request_id',p_request_id,
    'source_message_id',v_prov.payload->>'source_message_id',
    'scope_sha256',p_currentness_sha256,
    'authority_receipt_sha256',v_dec.authority_receipt_sha256,
    'consumer_ref',p_consumer_ref);
END;
$function$;
REVOKE ALL ON FUNCTION private.fn_lf_owner_chat_consume_v1(uuid,text,jsonb,text,text)
  FROM PUBLIC, anon, authenticated, service_role;

-- Intentionally NOT CUT OVER decide_v1, Merge Train or PASE. Activation would
-- require authenticated provider ingress, exact-head checks and PG17/18 tests.
COMMIT;
