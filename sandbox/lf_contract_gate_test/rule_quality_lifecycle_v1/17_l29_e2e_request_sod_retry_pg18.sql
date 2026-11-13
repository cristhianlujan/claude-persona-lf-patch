-- LOTE 29: PG18 DISPOSABLE ONLY. NOT a migration, not a native IG adapter.
-- Additive intake / SoD / replay guards. L7/L8/L11B/L14/L17/L23/L24/L26 unchanged.
SET search_path=rule_quality_l13,pg_temp;

CREATE TABLE l29_request_evidence (
 request_id text PRIMARY KEY,
 project_code text NOT NULL REFERENCES projects(project_code),
 rule_code text NOT NULL,
 request_kind text NOT NULL CHECK(request_kind IN ('NEW','MODIFY_CANDIDATE','CORRECT_VIGENTE')),
 creator_actor text NOT NULL,
 creator_sub text NOT NULL,
 creator_role text NOT NULL,
 evidence jsonb NOT NULL CHECK(jsonb_typeof(evidence)='object'),
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[0-9a-f]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(project_code,rule_code),
 FOREIGN KEY(project_code,creator_actor) REFERENCES actors(project_code,actor_code)
);
CREATE FUNCTION l29_no_direct_request_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=rule_quality_l13,pg_temp AS $f$
BEGIN
 RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L29_REQUEST_APPEND_ONLY';
END $f$;
CREATE TRIGGER trg_l29_request_immutable BEFORE UPDATE OR DELETE
 ON l29_request_evidence FOR EACH ROW EXECUTE FUNCTION l29_no_direct_request_mutation_v1();

-- Read only HMAC fixture JWT independently from L17's owner-only gate:
-- a non-owner creator must be able to request, but NEVER to approve.
CREATE FUNCTION l29_creator_identity_v1(p_project text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE raw text; cl jsonb; unsigned jsonb;secret text;expected text;
        v_role text;v_sub text;v_actor actors%ROWTYPE; v_now bigint;
BEGIN
 v_role:=nullif(current_setting('role',true),'none');
 IF session_user<>'l17_authenticator' OR v_role IS DISTINCT FROM 'lf_reader_role' THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_CREATOR_ROLE_NOT_ALLOWED';
 END IF;
 raw:=nullif(current_setting('request.jwt.claims',true),'');
 IF raw IS NULL THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_CREATOR_JWT_MISSING';
 END IF;
 BEGIN cl:=raw::jsonb;
 EXCEPTION WHEN others THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_CREATOR_JWT_BAD';
 END;
 unsigned:=cl-'test_signature';
 SELECT key_hex INTO secret FROM l17_hmac_private WHERE key_id='sandbox-only';
 expected:=encode(extensions.hmac(convert_to(unsigned::text,'UTF8'),
    decode(secret,'hex'),'sha256'),'hex');
 IF coalesce(cl->>'test_signature','') IS DISTINCT FROM expected
   OR unsigned->>'iss' IS DISTINCT FROM 'L17_TEST_ISSUER_NOT_SUPABASE'
   OR unsigned->>'aud' IS DISTINCT FROM 'L17_TEST_AUDIENCE'
   OR unsigned->>'role' IS DISTINCT FROM v_role
   OR unsigned->>'project_code' IS DISTINCT FROM p_project THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_CREATOR_SIGNED_CLAIM_INVALID';
 END IF;
 IF coalesce(unsigned->>'iat','') !~ '^[0-9]{10,12}$' OR
    coalesce(unsigned->>'nbf','') !~ '^[0-9]{10,12}$' OR
    coalesce(unsigned->>'exp','') !~ '^[0-9]{10,12}$' THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_CREATOR_CLAIM_TIME_INVALID';
 END IF;
 v_now:=floor(extract(epoch from clock_timestamp()))::bigint;
 IF (unsigned->>'exp')::bigint<=v_now OR (unsigned->>'nbf')::bigint>v_now
   OR (unsigned->>'iat')::bigint>v_now+60 THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_CREATOR_CLAIM_EXPIRED';
 END IF;
 v_sub:=nullif(unsigned->>'sub','');
 SELECT a.* INTO v_actor FROM l17_actor_subjects m
 JOIN actors a ON a.project_code=m.project_code AND a.actor_code=m.actor_code
 WHERE m.project_code=p_project AND m.subject_sub=v_sub AND m.app_role=v_role;
 IF NOT FOUND OR v_actor.can_approve OR v_actor.profile_code IS DISTINCT FROM 'READER'
  OR upper(v_actor.profile_code)='SUPER_ADMIN' THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_CREATOR_NOT_NONOWNER';
 END IF;
 RETURN jsonb_build_object('actor',v_actor.actor_code,'sub',v_sub,
  'role',v_role,'project',p_project,'identity_mode','HMAC_SANDBOX_NOT_SUPABASE');
END $f$;

CREATE FUNCTION l29_submit_request_v1(
 p_request text,p_project text,p_rule text,p_kind text,p_evidence jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE who jsonb;v_src jsonb;v_hash text;r l29_request_evidence%ROWTYPE;
BEGIN
 who:=l29_creator_identity_v1(p_project);
 IF p_project<>'lf' OR p_kind NOT IN ('NEW','MODIFY_CANDIDATE','CORRECT_VIGENTE') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L29_REQUEST_SCOPE';
 END IF;
 IF coalesce(p_request,'')='' OR p_evidence IS NULL OR jsonb_typeof(p_evidence)<>'object'
  OR nullif(btrim(p_evidence->>'source_ref'),'') IS NULL
  OR nullif(btrim(p_evidence->>'rationale'),'') IS NULL THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L29_EVIDENCE_REQUIRED';
 END IF;
 SELECT to_jsonb(s) INTO v_src FROM lf_ops.reglas s
 WHERE s.codigo=p_rule AND s.estado='CANDIDATO';
 IF v_src IS NULL THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L29_CANDIDATE_REQUIRED';
 END IF;
 v_hash:=encode(extensions.digest(convert_to(v_src::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO r FROM l29_request_evidence WHERE request_id=p_request;
 IF FOUND THEN
   IF r.project_code<>p_project OR r.rule_code<>p_rule OR r.request_kind<>p_kind
    OR r.evidence<>p_evidence OR r.source_sha256<>v_hash
    OR r.creator_actor<>who->>'actor' OR r.creator_sub<>who->>'sub' THEN
     RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L29_IDEMPOTENCY_KEY_CONFLICT';
   END IF;
   RETURN jsonb_build_object('status','ALREADY_REQUESTED_NOOP','request_id',p_request,
     'sha256',v_hash,'creator',r.creator_actor,'production_attested',false);
 END IF;
 INSERT INTO l29_request_evidence(request_id,project_code,rule_code,request_kind,
 creator_actor,creator_sub,creator_role,evidence,source_sha256)
 VALUES(p_request,p_project,p_rule,p_kind,who->>'actor',who->>'sub',who->>'role',
 p_evidence,v_hash);
 RETURN jsonb_build_object('status','REQUEST_RECEIVED_PG18','request_id',p_request,
  'sha256',v_hash,'creator',who->>'actor','production_attested',false);
END $f$;

-- BEFORE owner receipt, not after promotion. An owner cannot approve their own request.
CREATE FUNCTION l29_owner_intent_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE r l29_request_evidence%ROWTYPE;v_src jsonb;v_hash text;
BEGIN
 IF NEW.project_code<>'lf' THEN RETURN NEW; END IF;
 SELECT * INTO r FROM l29_request_evidence
 WHERE project_code=NEW.project_code AND rule_code=NEW.rule_code FOR SHARE;
 IF NOT FOUND THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_REQUEST_REQUIRED';
 END IF;
 IF r.creator_actor=NEW.owner_actor OR r.creator_sub=NEW.owner_sub THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_SAME_ACTOR_CREATOR_APPROVER';
 END IF;
 IF r.evidence IS NULL OR nullif(r.evidence->>'source_ref','') IS NULL
  OR nullif(r.evidence->>'rationale','') IS NULL THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_EVIDENCE_REQUIRED';
 END IF;
 SELECT to_jsonb(s) INTO v_src FROM lf_ops.reglas s WHERE s.codigo=NEW.rule_code;
 v_hash:=encode(extensions.digest(convert_to(v_src::text,'UTF8'),'sha256'),'hex');
 IF v_hash IS DISTINCT FROM r.source_sha256 THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_REQUEST_SNAPSHOT_STALE';
 END IF;
 IF r.request_kind='CORRECT_VIGENTE' AND NOT EXISTS(
   SELECT 1 FROM correction_requests c WHERE c.project_code=NEW.project_code
    AND c.successor_rule_code=NEW.rule_code AND c.owner_role=NEW.owner_actor) THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_CORRECTION_LINK_REQUIRED';
 END IF;
 IF r.request_kind='MODIFY_CANDIDATE'
  AND v_src->'valor_config'->>'l29_revision' IS DISTINCT FROM '2' THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_MODIFIED_CANDIDATE_EVIDENCE';
 END IF;
 RETURN NEW;
END $f$;
CREATE TRIGGER trg_l29_before_owner_intent
 BEFORE INSERT ON l18_owner_intents
 FOR EACH ROW EXECUTE FUNCTION l29_owner_intent_guard_v1();

-- Idempotent retry facade: repeat requests never duplicate promotion/closure.
-- Does NOT claim that native production RUN replay is idempotent.
CREATE FUNCTION l29_promotion_once_v1(p_project text,p_rule text,p_promotion text,p_run text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE who jsonb;r l26_promotion_receipts%ROWTYPE;v jsonb;
BEGIN
 who:=l17_verify_signed_claim_v2(p_project);
 SELECT * INTO r FROM l26_promotion_receipts
 WHERE project_code=p_project AND rule_code=p_rule AND promotion_id=p_promotion FOR SHARE;
 IF FOUND THEN
  v:=l26_check_promotion_internal_v1(p_project,p_rule,p_promotion,p_run,
         who->>'actor_code',who->>'sub',NULL);
  IF r.owner_run IS DISTINCT FROM p_run OR v->>'status' IS DISTINCT FROM 'PROMOTION_RECEIPT_VERIFIED' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_PROMOTION_REPLAY_MISMATCH';
  END IF;
  RETURN jsonb_build_object('status','ALREADY_PROMOTED_VERIFIED_NOOP',
     'receipt_sha256',r.receipt_sha256,'production_attested',false);
 END IF;
 RETURN l26_record_promotion_v1(p_project,p_rule,p_promotion,p_run);
END $f$;
CREATE FUNCTION l29_close_once_v1(p_project text,p_rule text,p_promotion text,p_run text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE who jsonb;r l24_closure_receipts%ROWTYPE;v jsonb;
BEGIN
 who:=l17_verify_signed_claim_v2(p_project);
 SELECT * INTO r FROM l24_closure_receipts
 WHERE project_code=p_project AND rule_code=p_rule AND promotion_id=p_promotion FOR SHARE;
 IF FOUND THEN
  IF r.owner_run IS DISTINCT FROM p_run OR r.actor_code IS DISTINCT FROM who->>'actor_code'
    OR r.actor_sub IS DISTINCT FROM who->>'sub' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_CLOSURE_REPLAY_OWNER';
  END IF;
  v:=l26_check_promotion_internal_v1(p_project,p_rule,p_promotion,p_run,
         who->>'actor_code',who->>'sub',r.readback_payload);
  IF v->>'status' IS DISTINCT FROM 'PROMOTION_RECEIPT_VERIFIED' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L29_CLOSURE_PROMOTION_INVALID';
  END IF;
  v:=l24_verify_closure_v1(p_project,p_rule,p_promotion);
  IF v->>'status' IS DISTINCT FROM 'VERIFIED_CLOSURE_HASH' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L29_CLOSURE_RECEIPT_INVALID';
  END IF;
  RETURN jsonb_build_object('status','ALREADY_CLOSED_VERIFIED_NOOP',
   'closure_verification',v,'production_attested',false);
 END IF;
 RETURN l26_close_integrated_v1(p_project,p_rule,p_promotion,p_run);
END $f$;

REVOKE ALL ON l29_request_evidence FROM PUBLIC,l17_authenticator,
 lf_owner_role,lf_super_role,lf_reader_role,lf_no_grant_role,
 saly_owner_role,saly_super_role;
ALTER TABLE l29_request_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE l29_request_evidence FORCE ROW LEVEL SECURITY;
REVOKE ALL ON FUNCTION l29_creator_identity_v1(text),l29_submit_request_v1(text,text,text,text,jsonb),
 l29_owner_intent_guard_v1(),l29_promotion_once_v1(text,text,text,text),
 l29_close_once_v1(text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION l29_submit_request_v1(text,text,text,text,jsonb) TO lf_reader_role;
GRANT EXECUTE ON FUNCTION l29_promotion_once_v1(text,text,text,text),
 l29_close_once_v1(text,text,text,text) TO lf_owner_role;
