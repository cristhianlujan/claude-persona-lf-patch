-- LOTE 26: INTEGRATION-ONLY SQL FOR DISPOSABLE POSTGRESQL 18. NEVER DEPLOY.
-- L23 and L24 sources are imported bit-for-bit unchanged. No frozen gates edited.
-- L23 enforces ACEPTAR at L14 ticket arming. This bridge preserves that pre-apply
-- decision and requires a separate promotion receipt before L24 can emit closure.
SET search_path=rule_quality_l13,pg_temp;

CREATE TABLE l26_promotion_receipts (
 project_code text NOT NULL REFERENCES projects(project_code),
 rule_code text NOT NULL,
 promotion_id text NOT NULL,
 owner_run text,
 actor_code text NOT NULL,
 actor_sub text NOT NULL,
 curator_fingerprint_sha256 text NOT NULL CHECK(curator_fingerprint_sha256 ~ '^[0-9a-f]{64}$'),
 curator_seal_hmac_sha256 text NOT NULL CHECK(curator_seal_hmac_sha256 ~ '^[0-9a-f]{64}$'),
 readback_payload jsonb NOT NULL CHECK(jsonb_typeof(readback_payload)='object'),
 readback_sha256 text NOT NULL CHECK(readback_sha256 ~ '^[0-9a-f]{64}$'),
 readback_core_sha256 text NOT NULL CHECK(readback_core_sha256 ~ '^[0-9a-f]{64}$'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 receipt_sha256 text NOT NULL CHECK(receipt_sha256 ~ '^[0-9a-f]{64}$'),
 PRIMARY KEY(project_code,rule_code,promotion_id),
 FOREIGN KEY(project_code,rule_code) REFERENCES rules(project_code,rule_code),
 FOREIGN KEY(project_code,actor_code) REFERENCES actors(project_code,actor_code)
);
CREATE FUNCTION l26_no_promotion_receipt_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=rule_quality_l13,pg_temp AS $f$
BEGIN
 RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L26_PROMOTION_RECEIPT_APPEND_ONLY';
END $f$;
CREATE TRIGGER trg_l26_promotion_receipt_append_only
 BEFORE UPDATE OR DELETE ON l26_promotion_receipts
 FOR EACH ROW EXECUTE FUNCTION l26_no_promotion_receipt_mutation_v1();

-- Normalizes only invariant, authoritative fields. Full L24 readback remains
-- stored independently; time-varying metadata must not produce false mismatch.
CREATE FUNCTION l26_readback_core_v1(p_payload jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
 SELECT jsonb_build_object(
  'project',p_payload->>'project','rule_code',p_payload->>'rule_code',
  'status',p_payload->>'status','ticket',p_payload->>'activation_ticket',
  'registry',p_payload->'quality_source_snapshot'->>'registry',
  'source',p_payload->'quality_source_snapshot'->>'source',
  'target_divergence',p_payload->>'target_divergence',
  'profile_return_status',p_payload->'profile_return'->>'status',
  'profile_return_verified',p_payload->'profile_return'->>'readback_verified',
  'lf_owner_binding',p_payload->'profile_return'->>'owner_approval_binding_sha256',
  'lf_ig_binding',p_payload->'profile_return'->>'ig_external_receipt_sha256',
  'lf_citation_binding',p_payload->'profile_return'->>'blind_case_binding_sha256'
 )
$f$;

-- Post-apply recomputation of pre-apply *fingerprint* would always fail because
-- the source became VIGENTE. Instead re-check HMAC of the L23 decision and bind
-- the exact fingerprint/seal that the L23 BEFORE ticket trigger already verified.
CREATE FUNCTION l26_validate_curator_seal_v1(p_project text,p_rule text,p_actor text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE v l23_curator_verdicts%ROWTYPE; signed jsonb; expected text;
        intent l18_owner_intents%ROWTYPE;
BEGIN
 SELECT * INTO v FROM l23_curator_verdicts
 WHERE project_code=p_project AND rule_code=p_rule;
 IF NOT FOUND OR v.verdict IS DISTINCT FROM 'ACEPTAR' THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L26_CURATOR_ACCEPT_REQUIRED';
 END IF;
 IF v.actor_code IS DISTINCT FROM p_actor THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L26_CURATOR_ACTOR_MISMATCH';
 END IF;
 signed:=jsonb_build_object('project',v.project_code,'rule',v.rule_code,
  'verdict',v.verdict,'reason',v.reason_code,'reason_text',v.reason_text,
  'evidence',v.evidence,'fingerprint',v.candidate_fingerprint_sha256,
  'actor',v.actor_code,'owner_profile',v.owner_profile_code);
 expected:=l23_curator_seal_v1(signed);
 IF expected IS DISTINCT FROM v.seal_hmac_sha256 THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L26_CURATOR_SEAL_TAMPERED';
 END IF;
 IF v.evidence->>'candidate_fingerprint_sha256' IS DISTINCT FROM v.candidate_fingerprint_sha256
    OR v.evidence->>'candidate_rule' IS DISTINCT FROM p_rule
    OR v.evidence->>'project' IS DISTINCT FROM p_project THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L26_CURATOR_FINGERPRINT_BINDING';
 END IF;
 RETURN jsonb_build_object('status','CURATOR_SEAL_VERIFIED_POST_APPLY',
  'actor',v.actor_code,'verdict',v.verdict,'fingerprint',v.candidate_fingerprint_sha256,
  'seal',v.seal_hmac_sha256,'rule_code',p_rule);
END $f$;

CREATE FUNCTION l26_promotion_receipt_body_v1(p l26_promotion_receipts)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp AS $f$
 SELECT jsonb_build_object('project',p.project_code,'rule_code',p.rule_code,
  'promotion_id',p.promotion_id,'owner_run',p.owner_run,
  'actor_code',p.actor_code,'actor_sub',p.actor_sub,
  'curator_fingerprint_sha256',p.curator_fingerprint_sha256,
  'curator_seal_hmac_sha256',p.curator_seal_hmac_sha256,
  'readback_sha256',p.readback_sha256,
  'readback_core_sha256',p.readback_core_sha256,'recorded_at',p.recorded_at)
$f$;

CREATE FUNCTION l26_check_promotion_internal_v1(
 p_project text,p_rule text,p_promotion text,p_owner_run text,p_actor text,p_sub text,
 p_close_readback jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE p l26_promotion_receipts%ROWTYPE;v_cur jsonb;v_hash text;
BEGIN
 SELECT * INTO p FROM l26_promotion_receipts
 WHERE project_code=p_project AND rule_code=p_rule AND promotion_id=p_promotion FOR SHARE;
 IF NOT FOUND THEN
  RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='BLOCK_L26_PROMOTION_RECEIPT_REQUIRED';
 END IF;
 IF p.actor_code IS DISTINCT FROM p_actor OR p.actor_sub IS DISTINCT FROM p_sub
    OR p.owner_run IS DISTINCT FROM p_owner_run THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L26_PROMOTION_OWNER_OR_RUN_MISMATCH';
 END IF;
 v_cur:=l26_validate_curator_seal_v1(p_project,p_rule,p_actor);
 IF v_cur->>'seal' IS DISTINCT FROM p.curator_seal_hmac_sha256 OR
    v_cur->>'fingerprint' IS DISTINCT FROM p.curator_fingerprint_sha256 THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L26_PROMOTION_CURATOR_BINDING';
 END IF;
 IF l24_digest_json_v1(p.readback_payload) IS DISTINCT FROM p.readback_sha256
    OR l24_digest_json_v1(l26_readback_core_v1(p.readback_payload))
          IS DISTINCT FROM p.readback_core_sha256
    OR l24_digest_json_v1(l26_promotion_receipt_body_v1(p))
          IS DISTINCT FROM p.receipt_sha256 THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L26_PROMOTION_RECEIPT_HASH';
 END IF;
 IF p_close_readback IS NOT NULL AND
   l24_digest_json_v1(l26_readback_core_v1(p_close_readback)) IS DISTINCT FROM p.readback_core_sha256 THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L26_PROMOTION_CLOSURE_READBACK_DRIFT';
 END IF;
 RETURN jsonb_build_object('status','PROMOTION_RECEIPT_VERIFIED',
   'project',p_project,'rule_code',p_rule,'promotion_id',p_promotion,
   'curator_seal_hmac_sha256',p.curator_seal_hmac_sha256,
   'readback_core_sha256',p.readback_core_sha256,
   'receipt_sha256',p.receipt_sha256);
END $f$;

-- The owner can record promotion only AFTER L14 has actually applied and the
-- readback is READY. This is the distinct receipt missing in L24.
CREATE FUNCTION l26_record_promotion_v1(
 p_project text,p_rule text,p_promotion text,p_owner_run text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE id jsonb;v_cur jsonb;v_ready jsonb;v_hash text;
        v_core text;v_stamp timestamptz;v_body jsonb;v_rhash text;
        intent l18_owner_intents%ROWTYPE;v_n int;
BEGIN
 id:=l17_verify_signed_claim_v2(p_project);
 SELECT * INTO intent FROM l18_owner_intents
 WHERE project_code=p_project AND rule_code=p_rule AND promotion_id=p_promotion;
 IF NOT FOUND OR intent.owner_actor IS DISTINCT FROM id->>'actor_code'
    OR intent.owner_sub IS DISTINCT FROM id->>'sub' THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L26_PROMOTION_OWNER_INTENT_REQUIRED';
 END IF;
 v_cur:=l26_validate_curator_seal_v1(p_project,p_rule,id->>'actor_code');
 v_ready:=l24_ready_payload_v1(p_project,p_rule,p_promotion,p_owner_run);
 IF v_ready->>'status' IS DISTINCT FROM 'READY' THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L26_PROMOTION_NOT_READY';
 END IF;
 v_hash:=l24_digest_json_v1(v_ready);
 v_core:=l24_digest_json_v1(l26_readback_core_v1(v_ready));
 v_stamp:=clock_timestamp();
 v_body:=jsonb_build_object('project',p_project,'rule_code',p_rule,
  'promotion_id',p_promotion,'owner_run',p_owner_run,
  'actor_code',id->>'actor_code','actor_sub',id->>'sub',
  'curator_fingerprint_sha256',v_cur->>'fingerprint',
  'curator_seal_hmac_sha256',v_cur->>'seal',
  'readback_sha256',v_hash,'readback_core_sha256',v_core,
  'recorded_at',v_stamp);
 v_rhash:=l24_digest_json_v1(v_body);
 INSERT INTO l26_promotion_receipts(project_code,rule_code,promotion_id,owner_run,
  actor_code,actor_sub,curator_fingerprint_sha256,curator_seal_hmac_sha256,
  readback_payload,readback_sha256,readback_core_sha256,recorded_at,receipt_sha256)
 VALUES(p_project,p_rule,p_promotion,p_owner_run,id->>'actor_code',id->>'sub',
  v_cur->>'fingerprint',v_cur->>'seal',v_ready,v_hash,v_core,v_stamp,v_rhash);
 RETURN jsonb_build_object('status','PROMOTION_RECEIPT_RECORDED',
  'rule_code',p_rule,'project',p_project,'promotion_id',p_promotion,
  'actor_code',id->>'actor_code','readback_status','READY',
  'readback_sha256',v_hash,'readback_core_sha256',v_core,
  'curator_seal_hmac_sha256',v_cur->>'seal',
  'receipt_sha256',v_rhash,'native_receiver_attested',false);
END $f$;

-- Defense in depth. Even calling L24 directly cannot write a closure without
-- L26 promotion + an intact HMAC Curator result and a matching READY readback.
CREATE FUNCTION l26_guard_l24_closure_insert_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE v jsonb;
BEGIN
 v:=l26_check_promotion_internal_v1(NEW.project_code,NEW.rule_code,
  NEW.promotion_id,NEW.owner_run,NEW.actor_code,NEW.actor_sub,
  NEW.readback_payload);
 IF v->>'status' IS DISTINCT FROM 'PROMOTION_RECEIPT_VERIFIED' THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L26_CLOSURE_WITHOUT_VERIFIED_PROMOTION';
 END IF;
 RETURN NEW;
END $f$;
CREATE TRIGGER trg_l26_guard_l24_closure_insert
 BEFORE INSERT ON l24_closure_receipts
 FOR EACH ROW EXECUTE FUNCTION l26_guard_l24_closure_insert_v1();

CREATE FUNCTION l26_close_integrated_v1(
 p_project text,p_rule text,p_promotion text,p_owner_run text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE id jsonb;v_cur jsonb;v_ready jsonb;v_before jsonb;
        v_close jsonb;v_verify jsonb;
BEGIN
 id:=l17_verify_signed_claim_v2(p_project);
 v_cur:=l26_validate_curator_seal_v1(p_project,p_rule,id->>'actor_code');
 v_ready:=l24_ready_payload_v1(p_project,p_rule,p_promotion,p_owner_run);
 v_before:=l26_check_promotion_internal_v1(p_project,p_rule,p_promotion,p_owner_run,
  id->>'actor_code',id->>'sub',v_ready);
 v_close:=l24_emit_closure_v1(p_project,p_rule,p_promotion,p_owner_run,false);
 IF v_close->>'status' IS DISTINCT FROM 'CLOSED_VERIFIABLE_SANDBOX' THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L26_CLOSURE_NOT_NEW_RECEIPT';
 END IF;
 v_verify:=l24_verify_closure_v1(p_project,p_rule,p_promotion);
 IF v_verify->>'status' IS DISTINCT FROM 'VERIFIED_CLOSURE_HASH' THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L26_CLOSURE_HASH_NOT_VERIFIED';
 END IF;
 RETURN v_close||jsonb_build_object(
  'status','INTEGRATED_CLOSED_VERIFIED_PG18',
  'promotion_receipt_sha256',v_before->>'receipt_sha256',
  'curator_seal_hmac_sha256',v_cur->>'seal',
  'closure_verification',v_verify,'production_attested',false);
END $f$;

-- Test only: throws after SQL apply/receipt in the SAME transaction.
CREATE FUNCTION l26_injected_fail_between_promotion_and_closure_v1()
RETURNS void LANGUAGE plpgsql SET search_path=rule_quality_l13,pg_temp AS $f$
BEGIN
 RAISE EXCEPTION USING ERRCODE='23514',
 MESSAGE='L26_INJECTED_AFTER_PROMOTION_BEFORE_CLOSURE';
END $f$;

REVOKE ALL ON l26_promotion_receipts FROM PUBLIC,l17_authenticator,lf_owner_role,
 lf_super_role,lf_reader_role,lf_no_grant_role,saly_owner_role,saly_super_role;
ALTER TABLE l26_promotion_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE l26_promotion_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON FUNCTION l26_record_promotion_v1(text,text,text,text),
 l26_close_integrated_v1(text,text,text,text),
 l26_readback_core_v1(jsonb),l26_validate_curator_seal_v1(text,text,text),
 l26_promotion_receipt_body_v1(l26_promotion_receipts),
 l26_check_promotion_internal_v1(text,text,text,text,text,text,jsonb),
 l26_guard_l24_closure_insert_v1(),l26_injected_fail_between_promotion_and_closure_v1()
 FROM PUBLIC;
GRANT EXECUTE ON FUNCTION l26_record_promotion_v1(text,text,text,text),
 l26_close_integrated_v1(text,text,text,text)
 TO lf_owner_role,lf_super_role,lf_reader_role,saly_owner_role,saly_super_role;
