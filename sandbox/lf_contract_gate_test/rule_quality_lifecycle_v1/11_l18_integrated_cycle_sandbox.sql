-- L18 integrated PG18 fixture ONLY. No Supabase migration or frozen gate edits.
-- Lifecycle transitions reuse L13; auth reuses L17 JWT/HMAC actor; wrappers reuse L14.
SET search_path=rule_quality_l13,public;

CREATE TABLE l18_owner_intents (
 project_code text NOT NULL REFERENCES projects(project_code),
 rule_code text NOT NULL,
 promotion_id text NOT NULL,
 owner_actor text NOT NULL,
 owner_sub text NOT NULL,
 auth_mode text NOT NULL DEFAULT 'SIGNED_HMAC_SANDBOX_NOT_SUPABASE',
 decision text NOT NULL CHECK (decision='APPROVE_SANDBOX_PROPOSAL'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(project_code,rule_code,promotion_id),
 FOREIGN KEY(project_code,rule_code) REFERENCES rules(project_code,rule_code),
 FOREIGN KEY(project_code,owner_actor) REFERENCES actors(project_code,actor_code)
);
CREATE TABLE l18_closure_receipts (
 project_code text NOT NULL REFERENCES projects(project_code),
 rule_code text NOT NULL,
 promotion_id text NOT NULL,
 closed_by text NOT NULL,
 status text NOT NULL CHECK (status='CLOSED_SANDBOX_SIMULATION'),
 external_closure_attested boolean NOT NULL DEFAULT false CHECK(external_closure_attested=false),
 completed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(project_code,rule_code,promotion_id),
 FOREIGN KEY(project_code,rule_code) REFERENCES rules(project_code,rule_code)
);

-- Only explicitly proposed successor can be prepared for an independent revision.
-- Fixes L14's intentional design gap where correction creates EN_REVISION without dates.
CREATE FUNCTION l18_prepare_explicit_successor_v1(p_project text,p_original text,p_successor text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE v_actor text;v_row rules%ROWTYPE;v_adapter project_source_adapters%ROWTYPE;
 v_cat text;v_def text;v_state text;v_interval int;v_now timestamptz;
BEGIN
 v_actor:=trusted_actor_role_v2(p_project);
 SELECT * INTO v_row FROM rules WHERE project_code=p_project AND rule_code=p_successor FOR UPDATE;
 IF NOT FOUND OR v_row.state<>'EN_REVISION' OR NOT EXISTS (
   SELECT 1 FROM correction_requests
   WHERE project_code=p_project AND original_rule_code=p_original
     AND successor_rule_code=p_successor AND owner_role=v_actor) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L18_NO_EXPLICIT_SUCCESSOR';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM rules WHERE project_code=p_project
      AND rule_code=p_original AND state='VIGENTE') THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L18_ORIGINAL_NOT_VIGENTE';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM category_family_map WHERE project_code=p_project
  AND category_raw=v_row.category_raw AND family_code=v_row.family_code
  AND mapping_status='APPROVED') THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L18_SUCCESSOR_FAMILY_NOT_APPROVED';
 END IF;
 SELECT * INTO v_adapter FROM project_source_adapters WHERE project_code=p_project;
 EXECUTE format('SELECT %I::text,%I::text,%I::text FROM %s WHERE %I=$1',
   v_adapter.category_col,v_adapter.description_col,v_adapter.state_col,
   v_adapter.source_table,v_adapter.code_col)
 INTO v_cat,v_def,v_state USING p_successor;
 IF v_cat IS DISTINCT FROM v_row.category_raw OR v_def IS DISTINCT FROM v_row.definition_text
  OR v_state IS DISTINCT FROM 'CANDIDATO' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L18_SUCCESSOR_SOURCE_MISMATCH';
 END IF;
 SELECT review_interval_days INTO v_interval FROM projects WHERE project_code=p_project;
 v_now:=clock_timestamp();
 UPDATE rules SET reviewed_at=v_now,next_review_at=v_now+make_interval(days=>v_interval),
                  effective_from=v_now
  WHERE project_code=p_project AND rule_code=p_successor;
 RETURN jsonb_build_object('status','SUCCESSOR_PREPARED','actor',v_actor,
   'original',p_original,'successor',p_successor,'family',v_row.family_code,
   'reviewed_at',v_now,'next_review_at',v_now+make_interval(days=>v_interval));
END $f$;

-- Explicit HMAC-backed owner intent; NOT an official Step70 signature.
CREATE FUNCTION l18_owner_intent_v1(p_project text,p_rule text,p_promotion text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE v_actor text;v_identity jsonb;v_state text;
BEGIN
 v_identity:=l17_verify_signed_claim_v2(p_project);
 v_actor:=v_identity->>'actor_code';
 SELECT state INTO v_state FROM rules WHERE project_code=p_project AND rule_code=p_rule;
 IF v_state IS DISTINCT FROM 'EN_REVISION' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L18_OWNER_INTENT_RULE_NOT_IN_REVIEW';
 END IF;
 IF p_project='lf' AND NOT EXISTS (SELECT 1 FROM public.lf_rule_promotion_v1
    WHERE promotion_id=p_promotion AND rule_code=p_rule) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L18_OWNER_INTENT_PROMOTION_MISMATCH';
 END IF;
 INSERT INTO l18_owner_intents(project_code,rule_code,promotion_id,owner_actor,owner_sub,decision)
 VALUES(p_project,p_rule,p_promotion,v_actor,v_identity->>'sub','APPROVE_SANDBOX_PROPOSAL');
 RETURN jsonb_build_object('status','OWNER_JWT_SANDBOX_APPROVED',
   'owner_actor',v_actor,'owner_sub',v_identity->>'sub','project',p_project,
   'rule',p_rule,'promotion_id',p_promotion,
   'official_step70_attested',false,'supabase_auth_attested',false);
END $f$;

-- Only verified-owner can close sandbox cycle. Native profile close is NOT emulated.
CREATE FUNCTION l18_close_sandbox_cycle_v1(
 p_project text,p_rule text,p_promotion text,p_owner_run text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE v_actor text;v_state text;v_ticket text;v_return jsonb;
BEGIN
 v_actor:=trusted_actor_role_v2(p_project);
 IF NOT EXISTS(SELECT 1 FROM l18_owner_intents WHERE project_code=p_project
   AND rule_code=p_rule AND promotion_id=p_promotion AND owner_actor=v_actor) THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L18_OWNER_JWT_INTENT_MISSING';
 END IF;
 SELECT state INTO v_state FROM rules WHERE project_code=p_project AND rule_code=p_rule;
 SELECT status INTO v_ticket FROM activation_tickets WHERE project_code=p_project AND rule_code=p_rule;
 IF v_state IS DISTINCT FROM 'VIGENTE' OR v_ticket IS DISTINCT FROM 'CONSUMED' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L18_CLOSURE_READBACK_NOT_READY';
 END IF;
 IF p_project='lf' THEN
  v_return:=public.lf_rule_promotion_profile_return_readback_v1(p_promotion,p_owner_run);
  IF v_return->>'status' IS DISTINCT FROM 'READY' OR
     (v_return->>'readback_verified')::boolean IS DISTINCT FROM true THEN
     RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L18_PROFILE_RETURN_NOT_READY';
  END IF;
 ELSE
  v_return:=jsonb_build_object('status','SINTETICO','native_return_attested',false);
 END IF;
 INSERT INTO l18_closure_receipts(project_code,rule_code,promotion_id,closed_by,status)
 VALUES(p_project,p_rule,p_promotion,v_actor,'CLOSED_SANDBOX_SIMULATION');
 RETURN jsonb_build_object('status','CLOSED_SANDBOX_SIMULATION','project',p_project,
  'rule_code',p_rule,'actor',v_actor,'native_profile_closed',false,
  'real_step70_attested',false,'profile_return',v_return);
END $f$;

-- Simulated date p_as_of is intentionally test-only (not a trusted wall clock).
-- Uses L13 state machine, with v2 JWT authentication and no p_actor freedom.
CREATE FUNCTION l18_owner_review_decide_v1(
 p_project text,p_rule text,p_decision text,p_as_of timestamptz,
 p_evidence jsonb,p_successor text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE v_actor text;v_id bigint;v_state text;v_next timestamptz;v_link text;
BEGIN
 v_actor:=trusted_actor_role_v2(p_project);
 IF p_decision='SUPERSEDE' AND NOT EXISTS (SELECT 1 FROM correction_requests
  WHERE project_code=p_project AND original_rule_code=p_rule
    AND successor_rule_code=p_successor AND owner_role=v_actor) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L18_UNAPPROVED_SUCCESSOR_LINK';
 END IF;
 v_id:=decide_rule_review(p_project,p_rule,v_actor,p_decision,p_evidence,p_as_of,p_successor);
 SELECT state,next_review_at,successor_rule_code INTO v_state,v_next,v_link
 FROM rules WHERE project_code=p_project AND rule_code=p_rule;
 RETURN jsonb_build_object('status','OWNER_REVIEW_DECISION_SANDBOX',
    'decision',p_decision,'decision_id',v_id,'actor',v_actor,
    'rule_code',p_rule,'state',v_state,'next_review_at',v_next,
    'successor_rule_code',v_link,'as_of_simulated',p_as_of);
END $f$;

REVOKE ALL ON l18_owner_intents,l18_closure_receipts FROM PUBLIC;
REVOKE ALL ON FUNCTION l18_prepare_explicit_successor_v1(text,text,text),
 l18_owner_intent_v1(text,text,text),
 l18_close_sandbox_cycle_v1(text,text,text,text),
 l18_owner_review_decide_v1(text,text,text,timestamptz,jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION l18_prepare_explicit_successor_v1(text,text,text),
 l18_owner_intent_v1(text,text,text),
 l18_close_sandbox_cycle_v1(text,text,text,text),
 l18_owner_review_decide_v1(text,text,text,timestamptz,jsonb,text)
 TO lf_owner_role,lf_super_role,lf_reader_role,saly_owner_role,saly_super_role;


-- Read-only overdue detector via verified actor; never grants table SELECT.
-- as_of is next_review_at + one second, a declared simulated clock.
CREATE FUNCTION l18_due_snapshot_v1(p_project text,p_rule text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE v_actor text;v_date timestamptz;v_state text;v_due_count integer;
BEGIN
 v_actor:=trusted_actor_role_v2(p_project);
 SELECT next_review_at,state INTO v_date,v_state FROM rules
 WHERE project_code=p_project AND rule_code=p_rule;
 IF v_date IS NULL THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L18_DUE_DATE_NOT_SET';
 END IF;
 SELECT count(*) INTO v_due_count FROM list_review_due(p_project,v_date+interval '1 second')
 WHERE rule_code=p_rule;
 RETURN jsonb_build_object('as_of_simulated',v_date+interval '1 second',
  'next_review_at',v_date,'state',v_state,'due',v_due_count,
  'proposal_only',true,'caller',v_actor);
END $f$;

-- A separate authenticated, owner-only decision: no caller-supplied identity or wall-clock.
CREATE FUNCTION l18_owner_due_decide_v1(p_project text,p_rule text,
 p_decision text,p_evidence jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE v_actor text;v_date timestamptz;v_result jsonb;
BEGIN
 v_actor:=trusted_actor_role_v2(p_project);
 IF p_decision NOT IN ('KEEP_VIGENTE','EXPIRE') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L18_ONLY_RENEW_OR_EXPIRE';
 END IF;
 SELECT next_review_at INTO v_date FROM rules
 WHERE project_code=p_project AND rule_code=p_rule;
 IF v_date IS NULL THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L18_DUE_DATE_NOT_SET';
 END IF;
 v_result:=l18_owner_review_decide_v1(p_project,p_rule,p_decision,
   v_date+interval '1 second',p_evidence);
 RETURN v_result || jsonb_build_object('clock_mode','SIMULATED_AS_OF_NEXT_REVIEW_PLUS_1_SECOND');
END $f$;

CREATE FUNCTION l18_readback_rule_state_v1(p_project text,p_rule text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $f$
DECLARE v_actor text;v_state text;v_date timestamptz;v_count integer;
BEGIN
 v_actor:=trusted_actor_role_v2(p_project);
 SELECT state,next_review_at INTO v_state,v_date FROM rules
 WHERE project_code=p_project AND rule_code=p_rule;
 SELECT count(*) INTO v_count FROM review_decisions
 WHERE project_code=p_project AND rule_code=p_rule;
 RETURN jsonb_build_object('state',v_state,'next_review_at',v_date,
  'decision_rows',v_count,'owner_actor',v_actor);
END $f$;

REVOKE ALL ON FUNCTION l18_due_snapshot_v1(text,text),
 l18_owner_due_decide_v1(text,text,text,jsonb),
 l18_readback_rule_state_v1(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION l18_due_snapshot_v1(text,text),
 l18_owner_due_decide_v1(text,text,text,jsonb),
 l18_readback_rule_state_v1(text,text) TO
 lf_owner_role,lf_super_role,lf_reader_role,saly_owner_role,saly_super_role;
