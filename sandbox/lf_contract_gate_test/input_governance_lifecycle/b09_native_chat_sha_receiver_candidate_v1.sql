-- CANDIDATE_ONLY / NOT_DEPLOYABLE: disposable PG17.6 / PG18.7 test.
-- Not a replacement for the deployed Step70 crypto verifier contract.
-- No production migration, RUN creation or operational writer.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
CREATE TABLE public.lf_ig_native_chat_e2e_receipt_candidate_v1 (
  execution_id text NOT NULL CHECK (length(execution_id)>10),
  seq integer NOT NULL CHECK (seq BETWEEN 1 AND 3),
  kind text NOT NULL CHECK (kind IN ('REQUEST','EXECUTOR','JUDGE')),
  raw_text text NOT NULL,
  raw_sha256 text NOT NULL CHECK (raw_sha256 ~ '^[0-9a-f]{64}$'),
  prev_sha256 text NOT NULL CHECK (prev_sha256 ~ '^[0-9a-f]{64}$'),
  chain_sha256 text NOT NULL CHECK (chain_sha256 ~ '^[0-9a-f]{64}$'),
  writer_receipt_ref text NOT NULL CHECK (length(writer_receipt_ref)>0),
  writer_receipt_sha256 text NOT NULL CHECK (writer_receipt_sha256 ~ '^[0-9a-f]{64}$'),
  PRIMARY KEY(execution_id,seq),
  UNIQUE(execution_id,chain_sha256)
);
-- Replay of a REQUEST nonce across distinct RUNs is rejected by a unique index.
-- This is insufficient without authoritative server-side nonce issuance.
CREATE UNIQUE INDEX lf_ig_native_chat_e2e_request_nonce_candidate_uq
 ON public.lf_ig_native_chat_e2e_receipt_candidate_v1
 (((raw_text::jsonb)->>'nonce')) WHERE seq=1;
REVOKE ALL ON TABLE public.lf_ig_native_chat_e2e_receipt_candidate_v1
 FROM PUBLIC,anon,authenticated,service_role;

-- Reader only. Candidate DOES NOT authenticate GPT, the judge, or the writer.
-- Successful digest validation must NEVER emit CRYPTOGRAPHICALLY_VERIFIED.
CREATE FUNCTION public.lf_ig_verified_native_provider_receipt_v1(p_execution_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  r record;
  raw jsonb;
  seq_now integer:=0;
  tip text:=repeat('0',64);
  calc text;
  nonce text;
  candidate text;
  scope text;
  executor_chat text;
  judge_chat text;
  reviewer_prompt text;
  receipt_ref text;
  expected_kind text;
BEGIN
  IF coalesce(p_execution_id,'') !~ '^EXEC-[A-Za-z0-9_-]{8,}$' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','RUN_ID_INVALID');
  END IF;
  FOR r IN SELECT * FROM public.lf_ig_native_chat_e2e_receipt_candidate_v1
   WHERE execution_id=p_execution_id ORDER BY seq LOOP
    seq_now:=seq_now+1;
    expected_kind:=CASE seq_now WHEN 1 THEN 'REQUEST'
      WHEN 2 THEN 'EXECUTOR' WHEN 3 THEN 'JUDGE' ELSE 'UNEXPECTED' END;
    IF r.seq<>seq_now OR r.kind<>expected_kind OR seq_now>3 THEN
      RETURN jsonb_build_object('status','BLOCKED','blocking_code','CHAIN_SEQUENCE_INVALID');
    END IF;
    IF encode(public.digest(convert_to(r.raw_text,'UTF8'),'sha256'),'hex')<>r.raw_sha256
       OR r.prev_sha256<>tip THEN
      RETURN jsonb_build_object('status','BLOCKED','blocking_code','CHAIN_RAW_OR_PREV_HASH_INVALID');
    END IF;
    calc:=encode(public.digest(convert_to(
      'LF_NATIVE_CHAT_EVENT_V1|'||r.execution_id||'|'||r.seq::text||'|'||
      r.kind||'|'||r.raw_sha256||'|'||r.prev_sha256||'|'||
      r.writer_receipt_sha256,'UTF8'),'sha256'),'hex');
    IF calc<>r.chain_sha256 THEN
      RETURN jsonb_build_object('status','BLOCKED','blocking_code','CHAIN_LINK_HASH_INVALID');
    END IF;
    raw:=r.raw_text::jsonb;
    IF jsonb_typeof(raw)<>'object'
      OR raw->>'execution_id' IS DISTINCT FROM p_execution_id
      OR raw->>'stage' IS DISTINCT FROM r.kind
      OR nullif(raw->>'nonce','') IS NULL
      OR coalesce(raw->>'candidate_sha256','') !~ '^[0-9a-f]{64}$'
      OR coalesce(raw->>'scope_packet_sha256','') !~ '^[0-9a-f]{64}$'
    THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','CHAIN_SCOPE_OR_PAYLOAD_INVALID');
    END IF;
    IF seq_now=1 THEN
      nonce:=raw->>'nonce'; candidate:=raw->>'candidate_sha256';
      scope:=raw->>'scope_packet_sha256';
    ELSIF raw->>'nonce' IS DISTINCT FROM nonce
      OR raw->>'candidate_sha256' IS DISTINCT FROM candidate
      OR raw->>'scope_packet_sha256' IS DISTINCT FROM scope
    THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','CHAIN_RUN_BINDING_INVALID');
    END IF;
    IF seq_now=2 THEN
      executor_chat:=nullif(raw->>'executor_chat_ref','');
      receipt_ref:=nullif(raw->>'provider_receipt_ref','');
      IF executor_chat IS NULL OR receipt_ref IS NULL THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','EXECUTOR_PROVENANCE_FIELDS_MISSING');
      END IF;
    ELSIF seq_now=3 THEN
      judge_chat:=nullif(raw->>'judge_chat_ref','');
      reviewer_prompt:=nullif(raw->>'reviewer_prompt_sha256','');
      IF judge_chat IS NULL OR judge_chat=executor_chat
         OR coalesce(reviewer_prompt,'') !~ '^[0-9a-f]{64}$'
         OR raw->>'executor_chat_ref' IS DISTINCT FROM executor_chat
         OR raw->>'review_mode' IS DISTINCT FROM 'SAME_LLM_SEPARATE_CHAT'
      THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','JUDGE_LOGICAL_SEPARATION_INVALID');
      END IF;
    END IF;
    tip:=r.chain_sha256;
  END LOOP;
  IF seq_now<>3 THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','CHAIN_INCOMPLETE');
  END IF;
  RETURN jsonb_build_object(
     'status','SHA_CHAIN_INTACT_NATIVE_PROVENANCE_UNATTESTED',
     'execution_id',p_execution_id,'chain_tip_sha256',tip,
     'candidate_sha256',candidate,'scope_packet_sha256',scope,
     'provider_receipt_ref',receipt_ref,'reviewer_prompt_sha256',reviewer_prompt,
     'event_count',seq_now,'integrity_verified',true,
     'writer_identity_verified',false,'vendor_model_provenance_verified',false,
     'reviewer_independence_proven',false,
     'effect_authority',false,'downstream_execution_allowed',false);
EXCEPTION WHEN invalid_text_representation THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','RAW_JSON_INVALID');
END $fn$;
REVOKE ALL ON FUNCTION public.lf_ig_verified_native_provider_receipt_v1(text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lf_ig_verified_native_provider_receipt_v1(text)
 TO service_role;
COMMIT;
