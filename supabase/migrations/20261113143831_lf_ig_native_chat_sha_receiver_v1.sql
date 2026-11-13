-- B09 G12: native-chat SHA receipt reader, NOT an Ed25519/provider attester.
-- CANDIDATE FOR LF MIGRATION MERGE TRAIN ONLY; not approved for application.
-- No existing RUN, rule, Step70, G15 or production contract is modified.
-- Source preflight must be read back on actual deployment. No automatic GO.
BEGIN;
DO $preflight$
BEGIN
 IF to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NOT NULL
 OR to_regclass('public.lf_ig_native_chat_receipt_v1') IS NOT NULL
 OR to_regprocedure('public.lf_ig_native_chat_receipt_immutable_guard_v1()') IS NOT NULL
 OR to_regclass('public.lf_operation_execution') IS NULL
 OR to_regprocedure('public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)') IS NULL
 OR to_regprocedure('extensions.digest(bytea,text)') IS NULL
 OR to_regprocedure('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)') IS NULL
 OR to_regprocedure('public.lf_ig_g15_motor_temporary_v1(jsonb)') IS NULL
 THEN RAISE EXCEPTION 'B09_SHA_RECEIVER_PREIMAGE_OR_DEPENDENCY_MISSING'; END IF;
 -- Freeze unchanged deployed semantic and G15 sources; this migration
 -- DOES NOT reinterpret CRYPTOGRAPHICALLY_VERIFIED or G15 GO.
 IF md5(pg_get_functiondef(
   'public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure))
    IS DISTINCT FROM '78cb1b8fab6975f4539a79baa2ab11fd'
 OR md5(pg_get_functiondef(
   'public.lf_ig_g15_motor_temporary_v1(jsonb)'::regprocedure))
    IS DISTINCT FROM 'eb1779e3d958d26d56a20f22ed717235'
 THEN RAISE EXCEPTION 'B09_SHA_RECEIVER_STEP70_OR_G15_SOURCE_DRIFT'; END IF;
END $preflight$;

CREATE TABLE public.lf_ig_native_chat_receipt_v1 (
 execution_id text NOT NULL CHECK(execution_id ~ '^EXEC-[A-Za-z0-9_-]{8,}$'),
 seq integer NOT NULL CHECK(seq BETWEEN 1 AND 3),
 kind text NOT NULL CHECK(kind IN ('REQUEST','EXECUTOR','JUDGE')),
 raw_text text NOT NULL,
 raw_sha256 text NOT NULL CHECK(raw_sha256 ~ '^[0-9a-f]{64}$'),
 prev_sha256 text NOT NULL CHECK(prev_sha256 ~ '^[0-9a-f]{64}$'),
 chain_sha256 text NOT NULL CHECK(chain_sha256 ~ '^[0-9a-f]{64}$'),
 writer_receipt_ref text NOT NULL CHECK(length(writer_receipt_ref)>0),
 writer_receipt_sha256 text NOT NULL CHECK(writer_receipt_sha256 ~ '^[0-9a-f]{64}$'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(execution_id, seq),
 UNIQUE(execution_id, chain_sha256)
);
-- REQUEST nonce cannot be replayed across RUNs. Server issuance remains a
-- separate official-writer requirement: the nonce is NOT authenticated here.
CREATE UNIQUE INDEX lf_ig_native_chat_request_nonce_uq
 ON public.lf_ig_native_chat_receipt_v1
 (((raw_text::jsonb)->>'nonce')) WHERE seq=1;
ALTER TABLE public.lf_ig_native_chat_receipt_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lf_ig_native_chat_receipt_v1
 FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.lf_ig_native_chat_receipt_immutable_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $guard$
BEGIN
 RAISE EXCEPTION 'B09_RECEIPT_IMMUTABLE' USING ERRCODE='23514';
END $guard$;
CREATE TRIGGER lf_ig_native_chat_receipt_no_mutation_v1
 BEFORE UPDATE OR DELETE ON public.lf_ig_native_chat_receipt_v1
 FOR EACH ROW EXECUTE FUNCTION public.lf_ig_native_chat_receipt_immutable_guard_v1();
REVOKE ALL ON FUNCTION public.lf_ig_native_chat_receipt_immutable_guard_v1()
 FROM PUBLIC,anon,authenticated,service_role;

-- Reads existing evidence; no writer is created or bypassed by this migration.
-- Only the already-governed native profile RUN in progress is eligible.
-- Successful SHA integrity is deliberately NOT provider authenticity.
CREATE FUNCTION public.lf_ig_verified_native_provider_receipt_v1(p_execution_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $reader$
DECLARE
 e public.lf_operation_execution%ROWTYPE;
 r record;
 j jsonb;
 n integer:=0;
 tip text:=repeat('0',64);
 calc text;
 nonce text;
 candidate text;
 scope_hash text;
 producer_prompt text;
 judge_prompt text;
 producer_chat text;
 judge_chat text;
 provider_ref text;
 kind_expected text;
BEGIN
 IF coalesce(p_execution_id,'') !~ '^EXEC-[A-Za-z0-9_-]{8,}$' THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_RUN_ID_INVALID'); END IF;
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
 IF NOT FOUND OR e.operation_code<>'EJECUCION_PERFIL_LF'
 OR e.target_type<>'PERFIL' OR e.target_code<>'PERFIL-PRODUCT-DIRECTOR-LF'
 OR e.status<>'IN_PROGRESS' OR e.manifest->>'executor_mode'<>'GPT_NATIVE'
 OR e.manifest->>'executor_provider'<>'OPENAI_CHATGPT_NATIVE'
 OR e.manifest ? 'queue_request_id'
 OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_RUN_NOT_ELIGIBLE'); END IF;
 FOR r IN SELECT * FROM public.lf_ig_native_chat_receipt_v1
    WHERE execution_id=p_execution_id ORDER BY seq LOOP
   n:=n+1;
   kind_expected:=CASE n WHEN 1 THEN 'REQUEST' WHEN 2 THEN 'EXECUTOR'
     WHEN 3 THEN 'JUDGE' ELSE 'EXTRA' END;
   IF n>3 OR r.seq<>n OR r.kind<>kind_expected THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_CHAIN_SEQUENCE_INVALID'); END IF;
   IF encode(extensions.digest(convert_to(r.raw_text,'UTF8'),'sha256'),'hex')<>r.raw_sha256
      OR r.prev_sha256<>tip THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_CHAIN_RAW_OR_PREV_HASH_INVALID'); END IF;
   calc:=encode(extensions.digest(convert_to(
     'LF_NATIVE_CHAT_EVENT_V1|'||r.execution_id||'|'||r.seq::text||'|'||
     r.kind||'|'||r.raw_sha256||'|'||r.prev_sha256||'|'||
     r.writer_receipt_sha256,'UTF8'),'sha256'),'hex');
   IF calc<>r.chain_sha256 THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_CHAIN_LINK_HASH_INVALID'); END IF;
   j:=r.raw_text::jsonb;
   IF jsonb_typeof(j)<>'object' OR j->>'stage' IS DISTINCT FROM r.kind
     OR j->>'execution_id' IS DISTINCT FROM p_execution_id
     OR nullif(j->>'nonce','') IS NULL
     OR coalesce(j->>'candidate_sha256','') !~ '^[0-9a-f]{64}$'
     OR coalesce(j->>'scope_packet_sha256','') !~ '^[0-9a-f]{64}$'
     OR coalesce(j->>'producer_prompt_sha256','') !~ '^[0-9a-f]{64}$'
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_CHAIN_RAW_SCOPE_INVALID'); END IF;
   IF n=1 THEN
     nonce:=j->>'nonce';candidate:=j->>'candidate_sha256';
     scope_hash:=j->>'scope_packet_sha256';producer_prompt:=j->>'producer_prompt_sha256';
   ELSIF j->>'nonce' IS DISTINCT FROM nonce
     OR j->>'candidate_sha256' IS DISTINCT FROM candidate
     OR j->>'scope_packet_sha256' IS DISTINCT FROM scope_hash
     OR j->>'producer_prompt_sha256' IS DISTINCT FROM producer_prompt THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_CHAIN_RUN_BINDING_INVALID'); END IF;
   IF n=2 THEN
     producer_chat:=nullif(j->>'executor_chat_ref','');
     provider_ref:=nullif(j->>'provider_receipt_ref','');
     IF producer_chat IS NULL OR provider_ref IS NULL THEN
       RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_PRODUCER_REF_MISSING'); END IF;
   ELSIF n=3 THEN
     judge_chat:=nullif(j->>'judge_chat_ref','');
     judge_prompt:=nullif(j->>'reviewer_prompt_sha256','');
     IF judge_chat IS NULL OR judge_chat=producer_chat
       OR j->>'executor_chat_ref' IS DISTINCT FROM producer_chat
       OR coalesce(judge_prompt,'') !~ '^[0-9a-f]{64}$'
       OR judge_prompt=producer_prompt
       OR j->>'review_mode' IS DISTINCT FROM 'SAME_LLM_SEPARATE_CHAT'
     THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_JUDGE_LOGICAL_SEPARATION_INVALID'); END IF;
   END IF;
   tip:=r.chain_sha256;
 END LOOP;
 IF n<>3 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_CHAIN_INCOMPLETE'); END IF;
 RETURN jsonb_build_object(
  'status','SHA256_CHAIN_VERIFIED_DOCUMENTAL_PROVENANCE_UNATTESTED',
  'execution_id',p_execution_id,
  'candidate_sha256',candidate,'scope_packet_sha256',scope_hash,
  'producer_prompt_sha256',producer_prompt,'reviewer_prompt_sha256',judge_prompt,
  'provider_receipt_ref',provider_ref,'chain_tip_sha256',tip,
  'event_count',n,'integrity_verified',true,'producer_chat_ref',producer_chat,
  'judge_chat_ref',judge_chat,'writer_identity_verified',false,
  'vendor_model_provenance_verified',false,'reviewer_model_independence_proven',false,
  'effect_authority',false,'downstream_execution_allowed',false);
EXCEPTION WHEN invalid_text_representation THEN
 RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_RAW_JSON_INVALID');
END $reader$;
REVOKE ALL ON FUNCTION public.lf_ig_verified_native_provider_receipt_v1(text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lf_ig_verified_native_provider_receipt_v1(text)
 TO service_role;
-- No GRANT INSERT/UPDATE/DELETE to service_role; future registration must bind
-- to the SINGLE official profile step writer under a separately approved contract.
COMMIT;
