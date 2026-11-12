-- LOTE 24: PG18 SANDBOX ONLY. NEVER DEPLOY. NO FROZEN GATES ALTERED.
-- L24 is an additional verifiable mechanical closure receipt in sandbox;
-- it is NOT the official RUN terminal receipt/Step80 and not real Supabase Auth.
SET search_path=rule_quality_l13,public;

CREATE TABLE l24_closure_receipts (
 receipt_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 project_code text NOT NULL REFERENCES projects(project_code),
 rule_code text NOT NULL,
 promotion_id text NOT NULL,
 owner_run text,
 version text NOT NULL,
 final_state text NOT NULL CHECK(final_state='VIGENTE'),
 proposal_payload jsonb NOT NULL CHECK(jsonb_typeof(proposal_payload)='object'),
 proposal_sha256 text NOT NULL CHECK(proposal_sha256 ~ '^[0-9a-f]{64}$'),
 readback_payload jsonb NOT NULL CHECK(jsonb_typeof(readback_payload)='object'),
 readback_sha256 text NOT NULL CHECK(readback_sha256 ~ '^[0-9a-f]{64}$'),
 owner_approval jsonb NOT NULL CHECK(jsonb_typeof(owner_approval)='object'),
 judge_evidence jsonb NOT NULL CHECK(jsonb_typeof(judge_evidence)='object'),
 actor_code text NOT NULL,
 actor_sub text NOT NULL,
 closed_at timestamptz NOT NULL,
 receipt_sha256 text NOT NULL CHECK(receipt_sha256 ~ '^[0-9a-f]{64}$'),
 provenance text NOT NULL DEFAULT 'L24_MECHANICAL_PG18_NOT_NATIVE_CLOSURE',
 native_receiver_attested boolean NOT NULL DEFAULT false CHECK(native_receiver_attested=false),
 UNIQUE(project_code,rule_code,promotion_id),
 FOREIGN KEY(project_code,rule_code) REFERENCES rules(project_code,rule_code),
 FOREIGN KEY(project_code,actor_code) REFERENCES actors(project_code,actor_code)
);

CREATE FUNCTION l24_no_modify_receipt_v1()
RETURNS trigger LANGUAGE plpgsql
SET search_path=rule_quality_l13,pg_temp AS $fn$
BEGIN
 RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L24_APPEND_ONLY_RECEIPT';
END $fn$;
CREATE TRIGGER l24_receipt_append_only
 BEFORE UPDATE OR DELETE ON l24_closure_receipts
 FOR EACH ROW EXECUTE FUNCTION l24_no_modify_receipt_v1();

-- Fixed domain only, not caller supplied SQL or DDL.
CREATE FUNCTION l24_digest_json_v1(p_doc jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $fn$
 SELECT encode(extensions.digest(convert_to(p_doc::text,'UTF8'),'sha256'),'hex')
$fn$;

-- Content-addressed "version": L13 has no canonical revision field;
-- do not pretend this SHA256 is a deployed business-version identifier.
CREATE FUNCTION l24_proposal_payload_v1(p_project text,p_rule text,p_promotion text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE r rules%ROWTYPE;v_original text;v_intent l18_owner_intents%ROWTYPE;
BEGIN
 IF p_project NOT IN ('lf','saly') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L24_PROJECT_NOT_SUPPORTED';
 END IF;
 SELECT * INTO r FROM rules WHERE project_code=p_project AND rule_code=p_rule;
 IF NOT FOUND THEN
  RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='BLOCK_L24_RULE_NOT_FOUND';
 END IF;
 SELECT * INTO v_intent FROM l18_owner_intents
  WHERE project_code=p_project AND rule_code=p_rule AND promotion_id=p_promotion;
 IF NOT FOUND THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L24_OWNER_APPROVAL_INTENT_MISSING';
 END IF;
 SELECT original_rule_code INTO v_original FROM correction_requests
  WHERE project_code=p_project AND successor_rule_code=p_rule;
 RETURN jsonb_build_object(
  'project_code',r.project_code,'rule_code',r.rule_code,
  'promotion_id',p_promotion,'family_code',r.family_code,
  'category_raw',r.category_raw,'entity_code',r.entity_code,
  'definition_text',r.definition_text,'config',r.config,
  'reviewed_at',r.reviewed_at,'effective_from',r.effective_from,
  'original_rule_code',v_original,
  'owner_intent','APPROVE_SANDBOX_PROPOSAL',
  'owner_actor',v_intent.owner_actor,
  'owner_sub',v_intent.owner_sub,
  'source_type','L13_SNAPSHOT_CONTENT_ADDRESS_NOT_OFFICIAL_PROPOSAL');
END $fn$;

-- Called ONLY by signed-owner closure; this is mechanically derived from L14
-- consumed activation ticket + L20 quality/source readback + LF frozen
-- profile-return READY. SALY has no native return: status READY is synthetic
-- evidence from the fixture adapter, labeled as such.
CREATE FUNCTION l24_ready_payload_v1(
 p_project text,p_rule text,p_promotion text,p_owner_run text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_target jsonb;v_return jsonb;v_approval jsonb;v_capture jsonb;
        v_ig jsonb;v_ticket text;v_div int;v_engine text;
BEGIN
 IF p_project NOT IN ('lf','saly') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L24_PROJECT_NOT_SUPPORTED';
 END IF;
 SELECT engine INTO v_engine FROM project_source_adapters WHERE project_code=p_project;
 IF v_engine IS NULL THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L24_ADAPTER_MISSING';
 END IF;
 v_target:=l20_target_readback_v1(p_project,p_rule);
 SELECT status INTO v_ticket FROM activation_tickets
  WHERE project_code=p_project AND rule_code=p_rule;
 IF v_target->>'registry' IS DISTINCT FROM 'VIGENTE'
    OR v_target->>'source' IS DISTINCT FROM 'VIGENTE'
    OR v_ticket IS DISTINCT FROM 'CONSUMED' THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L24_READBACK_NOT_READY';
 END IF;
 SELECT count(*) INTO v_div FROM l20_list_divergences_v1(p_project) d
  WHERE d.rule_code=p_rule;
 IF v_div<>0 OR coalesce((v_target->>'target_divergence')::int,1)<>0 THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L24_DIVERGENCE_REGISTER_SOURCE';
 END IF;
 IF p_project='lf' THEN
  IF v_engine<>'LF_FROZEN_APPLY' OR nullif(p_owner_run,'') IS NULL THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L24_LF_OWNER_RUN_REQUIRED';
  END IF;
  v_return:=public.lf_rule_promotion_profile_return_readback_v1(p_promotion,p_owner_run);
  IF v_return->>'status' IS DISTINCT FROM 'READY'
     OR (v_return->>'readback_verified')::boolean IS DISTINCT FROM true
     OR v_return->>'rule_code' IS DISTINCT FROM p_rule
     OR v_return->>'estado' IS DISTINCT FROM 'VIGENTE' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L24_READBACK_NOT_READY';
  END IF;
  v_capture:=public.lf_rule_promotion_citation_verify_v1(p_promotion);
  v_ig:=public.lf_rule_promotion_ig_semantic_verify_v1(p_promotion);
  IF v_capture->>'status' IS DISTINCT FROM 'VERIFIED_CAPTURE_BINDING'
     OR v_ig->>'status' IS DISTINCT FROM 'READY_FOR_PROFILE_APPROVAL' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L24_GATE_CITATION_OR_IG_NOT_READY';
  END IF;
  v_approval:=public.lf_rule_promotion_profile_owner_verify_v1(p_promotion);
  IF v_approval->>'status' IS DISTINCT FROM 'VERIFIED_PROFILE_OWNER' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L24_OWNER_APPROVAL_READBACK';
  END IF;
 ELSE
  IF v_engine<>'SALY_SYNTHETIC_APPLY' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L24_SALY_ADAPTER_UNTRUSTED';
  END IF;
  v_return:=jsonb_build_object('status','READY','readback_verified',true,
    'native_profile_return_attested',false,'source','L14_SALY_FIXTURE_SYNTHETIC_READY');
  v_capture:=jsonb_build_object('status','NO_PROBADO','saly_native_ig',false);
  v_ig:=jsonb_build_object('status','NO_PROBADO','saly_native_ig',false);
  v_approval:=jsonb_build_object('status','L17_SIGNED_OWNER_SANDBOX',
   'native_owner_approval_attested',false);
 END IF;
 RETURN jsonb_build_object(
  'status','READY','project',p_project,'rule_code',p_rule,
  'quality_source_snapshot',v_target,'activation_ticket','CONSUMED',
  'target_divergence',v_div,'profile_return',v_return,
  'citation_capture',v_capture,'ig_semantic',v_ig,
  'profile_owner_verification',v_approval,
  'native_receiver_attested',false);
END $fn$;

-- Content is fixed by function, NEVER by caller-supplied hashes, actor or
-- artificial READY. One INSERT atomically becomes a verified append-only receipt.
CREATE FUNCTION l24_emit_closure_v1(
 p_project text,p_rule text,p_promotion text,p_owner_run text DEFAULT NULL,
 p_test_fail_after_insert boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE identity jsonb;v_actor text;intent l18_owner_intents%ROWTYPE;
        existing l24_closure_receipts%ROWTYPE;v_prop jsonb;v_rb jsonb;
        v_prop_hash text;v_rb_hash text;v_version text;
        v_owner jsonb;v_judge jsonb;v_closed timestamptz;
        v_body jsonb;v_receipt_hash text;v_id bigint;
        v_verified jsonb;
BEGIN
 identity:=l17_verify_signed_claim_v2(p_project);
 v_actor:=identity->>'actor_code';
 SELECT * INTO intent FROM l18_owner_intents
 WHERE project_code=p_project AND rule_code=p_rule AND promotion_id=p_promotion;
 IF NOT FOUND OR intent.owner_actor IS DISTINCT FROM v_actor
    OR intent.owner_sub IS DISTINCT FROM identity->>'sub'
    OR intent.decision IS DISTINCT FROM 'APPROVE_SANDBOX_PROPOSAL' THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L24_OWNER_APPROVAL_MISSING';
 END IF;
 SELECT * INTO existing FROM l24_closure_receipts
 WHERE project_code=p_project AND rule_code=p_rule AND promotion_id=p_promotion
 FOR UPDATE;
 IF FOUND THEN
  IF existing.actor_code IS DISTINCT FROM v_actor
     OR existing.actor_sub IS DISTINCT FROM identity->>'sub'
     OR existing.owner_run IS DISTINCT FROM p_owner_run THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L24_IDEMPOTENT_ACTOR_OR_RUN_MISMATCH';
  END IF;
  v_verified:=l24_verify_closure_v1(p_project,p_rule,p_promotion);
  IF v_verified->>'status' IS DISTINCT FROM 'VERIFIED_CLOSURE_HASH' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L24_IDEMPOTENT_UNVERIFIED';
  END IF;
  RETURN jsonb_build_object('status','ALREADY_CLOSED_NOOP','receipt_id',existing.receipt_id,
   'receipt_sha256',existing.receipt_sha256,'rows_written',0,
   'project',p_project,'rule_code',p_rule,'official_receiver_attested',false);
 END IF;
 -- Computing the binding validates the L20 source/registry and LF native-gate
 -- mechanical profile-return readback. Never accept external "READY".
 v_rb:=l24_ready_payload_v1(p_project,p_rule,p_promotion,p_owner_run);
 IF v_rb->>'status' IS DISTINCT FROM 'READY' THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L24_READBACK_NOT_READY';
 END IF;
 v_prop:=l24_proposal_payload_v1(p_project,p_rule,p_promotion);
 v_prop_hash:=l24_digest_json_v1(v_prop);
 v_rb_hash:=l24_digest_json_v1(v_rb);
 v_version:='sha256:'||v_prop_hash;
 v_owner:=jsonb_build_object('intent_decision',intent.decision,
   'actor_code',v_actor,'actor_sub',identity->>'sub',
   'profile_code',identity->>'profile_code',
   'profile_owner_verification',v_rb->'profile_owner_verification',
   'native_approval',false);
 v_judge:=jsonb_build_object('model','SAME_L11B_SYNTHETIC_MECHANICAL_VERDICT',
   'independence_attested',false,'native_step70_attested',false,
   'ig_readback',v_rb->'ig_semantic','citation_verification',v_rb->'citation_capture');
 v_closed:=clock_timestamp();
 v_body:=jsonb_build_object('project',p_project,'rule_code',p_rule,
   'promotion_id',p_promotion,'owner_run',p_owner_run,'version',v_version,
   'final_state','VIGENTE','proposal_sha256',v_prop_hash,
   'readback_sha256',v_rb_hash,'owner_approval',v_owner,
   'judge_evidence',v_judge,'actor_code',v_actor,'actor_sub',identity->>'sub',
   'closed_at',v_closed,'provenance','L24_MECHANICAL_PG18_NOT_NATIVE_CLOSURE',
   'native_receiver_attested',false);
 v_receipt_hash:=l24_digest_json_v1(v_body);
 INSERT INTO l24_closure_receipts(
  project_code,rule_code,promotion_id,owner_run,version,final_state,
  proposal_payload,proposal_sha256,readback_payload,readback_sha256,
  owner_approval,judge_evidence,actor_code,actor_sub,closed_at,receipt_sha256)
 VALUES(p_project,p_rule,p_promotion,p_owner_run,v_version,'VIGENTE',
  v_prop,v_prop_hash,v_rb,v_rb_hash,v_owner,v_judge,v_actor,
  identity->>'sub',v_closed,v_receipt_hash)
 RETURNING receipt_id INTO v_id;
 IF p_test_fail_after_insert THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='L24_INJECTED_AFTER_INSERT_ROLLBACK_ALL';
 END IF;
 RETURN jsonb_build_object('status','CLOSED_VERIFIABLE_SANDBOX','receipt_id',v_id,
   'receipt_sha256',v_receipt_hash,'proposal_sha256',v_prop_hash,
   'readback_sha256',v_rb_hash,'version',v_version,
   'project',p_project,'rule_code',p_rule,'final_state','VIGENTE',
   'actor',v_actor,'actor_sub',identity->>'sub','closed_at',v_closed,
   'rows_written',1,'official_receiver_attested',false);
END $fn$;

-- Cryptographically re-derive hashes from saved payloads; does NOT claim
-- receiver attestation, native RUN, source of proposal SHA or independent judge.
CREATE FUNCTION l24_verify_closure_v1(
 p_project text,p_rule text,p_promotion text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE identity jsonb;r l24_closure_receipts%ROWTYPE;
        body jsonb;v_prop_hash text;v_rb_hash text;v_receipt_hash text;
BEGIN
 identity:=l17_verify_signed_claim_v2(p_project);
 SELECT * INTO r FROM l24_closure_receipts WHERE
 project_code=p_project AND rule_code=p_rule AND promotion_id=p_promotion;
 IF NOT FOUND THEN
  RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='BLOCK_L24_RECEIPT_NOT_FOUND';
 END IF;
 IF r.actor_code IS DISTINCT FROM identity->>'actor_code'
    OR r.actor_sub IS DISTINCT FROM identity->>'sub' THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L24_RECEIPT_ACTOR_MISMATCH';
 END IF;
 v_prop_hash:=l24_digest_json_v1(r.proposal_payload);
 v_rb_hash:=l24_digest_json_v1(r.readback_payload);
 body:=jsonb_build_object('project',r.project_code,'rule_code',r.rule_code,
   'promotion_id',r.promotion_id,'owner_run',r.owner_run,'version',r.version,
   'final_state',r.final_state,'proposal_sha256',r.proposal_sha256,
   'readback_sha256',r.readback_sha256,'owner_approval',r.owner_approval,
   'judge_evidence',r.judge_evidence,'actor_code',r.actor_code,
   'actor_sub',r.actor_sub,'closed_at',r.closed_at,
   'provenance',r.provenance,'native_receiver_attested',r.native_receiver_attested);
 v_receipt_hash:=l24_digest_json_v1(body);
 IF v_prop_hash IS DISTINCT FROM r.proposal_sha256
    OR v_rb_hash IS DISTINCT FROM r.readback_sha256
    OR r.version IS DISTINCT FROM 'sha256:'||r.proposal_sha256
    OR r.readback_payload->>'status' IS DISTINCT FROM 'READY'
    OR r.readback_payload->'quality_source_snapshot'->>'registry' IS DISTINCT FROM 'VIGENTE'
    OR r.readback_payload->'quality_source_snapshot'->>'source' IS DISTINCT FROM 'VIGENTE'
    OR r.readback_payload->>'target_divergence' IS DISTINCT FROM '0'
    OR r.owner_approval->>'intent_decision' IS DISTINCT FROM 'APPROVE_SANDBOX_PROPOSAL'
    OR r.judge_evidence->>'independence_attested' IS DISTINCT FROM 'false'
    OR v_receipt_hash IS DISTINCT FROM r.receipt_sha256 THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L24_HASH_OR_RECEIPT_TAMPER';
 END IF;
 RETURN jsonb_build_object('status','VERIFIED_CLOSURE_HASH','receipt_id',r.receipt_id,
   'rule_code',r.rule_code,'version',r.version,'state_at_closure',r.final_state,
   'proposal_sha256',r.proposal_sha256,'readback_sha256',r.readback_sha256,
   'receipt_sha256',r.receipt_sha256,
   'native_receiver_attested',false,'native_supabase_auth_attested',false,
   'independent_semantic_judge_attested',false);
END $fn$;

-- The full receipt row is not accessible by application roles. The authorized
-- owner can only invoke the checked emit/verify interface.
REVOKE ALL ON l24_closure_receipts FROM PUBLIC;
ALTER TABLE l24_closure_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE l24_closure_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON FUNCTION l24_emit_closure_v1(text,text,text,text,boolean),
 l24_verify_closure_v1(text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION l24_proposal_payload_v1(text,text,text),
 l24_ready_payload_v1(text,text,text,text),
 l24_digest_json_v1(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION l24_no_modify_receipt_v1() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION l24_emit_closure_v1(text,text,text,text,boolean),
 l24_verify_closure_v1(text,text,text)
 TO lf_owner_role,lf_super_role,lf_reader_role,saly_owner_role,saly_super_role;
