-- Source-only DRAFT; mandatory application via existing LF Migration Merge Train.
-- Policy: owner approval is the literal USER turn in the orchestration CHAT.
-- No Ed25519, signing provider, GitHub click, email, SMS or external service.
-- The trusted orchestrator transports original user-turn metadata; never accept
-- a model/proposer assertion as proof of the human speaker.
BEGIN;

-- Canonical human authority: ONE config row, UUID from LF project owner.
-- Name is read from the public source by JOIN; never compared as text.
CREATE TABLE IF NOT EXISTS private.lf_owner_chat_identity_v1(
  config_key text PRIMARY KEY CHECK (config_key='LF_OWNER'),
  project_code text NOT NULL,
  owner_sub uuid NOT NULL,
  repository_full_name text NOT NULL CHECK
    (repository_full_name ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  channel_code text NOT NULL CHECK (length(channel_code)>=8),
  authority_role_code text NOT NULL CHECK (length(authority_role_code)>=8),
  fixed boolean NOT NULL DEFAULT true CHECK (fixed)
);
INSERT INTO private.lf_owner_chat_identity_v1
 (config_key,project_code,owner_sub,repository_full_name,channel_code,authority_role_code)
SELECT 'LF_OWNER',p.project_code,p.owner_sub,
  'cristhianlujan/claude-persona-lf-patch',
  'CHAT_ORCHESTRATOR_USER_TURN','SUPER_ADMIN'
FROM public.lf_ig_project_owner_v2 p WHERE p.project_code='LF'
ON CONFLICT(config_key) DO NOTHING;
DO $fixed_owner$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM private.lf_owner_chat_identity_v1 c
   JOIN public.lf_ig_project_owner_v2 p
     ON p.project_code=c.project_code AND p.owner_sub=c.owner_sub
   WHERE c.config_key='LF_OWNER' AND c.fixed
     AND c.repository_full_name IS NOT NULL AND c.channel_code IS NOT NULL
     AND c.authority_role_code IS NOT NULL)
 THEN RAISE EXCEPTION 'CHAT_OWNER_FIXED_IDENTITY_CONTRACT_DRIFT'; END IF;
END $fixed_owner$;
REVOKE ALL ON private.lf_owner_chat_identity_v1
 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.fn_lf_owner_chat_owner_sub_v1()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
 SELECT c.owner_sub FROM private.lf_owner_chat_identity_v1 c
 JOIN public.lf_ig_project_owner_v2 p
   ON p.project_code=c.project_code AND p.owner_sub=c.owner_sub
 WHERE c.config_key='LF_OWNER' AND c.fixed
$fn$;
REVOKE ALL ON FUNCTION private.fn_lf_owner_chat_owner_sub_v1()
 FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS private.lf_owner_chat_action_catalog_v1 (
  action_code text PRIMARY KEY,
  required_scope_keys text[] NOT NULL,
  max_ttl_seconds integer NOT NULL DEFAULT 900 CHECK (max_ttl_seconds BETWEEN 1 AND 900),
  enabled boolean NOT NULL DEFAULT false,
  policy_version text NOT NULL,
  CHECK (cardinality(required_scope_keys)>0)
);
INSERT INTO private.lf_owner_chat_action_catalog_v1
(action_code,required_scope_keys,enabled,policy_version) VALUES
('MERGE_GOVERNANCE_PR',ARRAY['action','repository','pr_number','head_sha']::text[],true,'LF_CHAT_OWNER_ORDER_V2'),
('PROMOTE_RULE_BATCH',ARRAY['action','repository','execution_id','rule_codes','rule_snapshots_sha256']::text[],true,'LF_CHAT_OWNER_ORDER_V2')
ON CONFLICT(action_code) DO NOTHING;

CREATE TABLE IF NOT EXISTS private.lf_owner_chat_orders_v1 (
  order_id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  source_chat_id text NOT NULL CHECK (length(source_chat_id)>=12),
  source_message_id text NOT NULL UNIQUE CHECK (length(source_message_id)>=12),
  source_kind text NOT NULL CHECK (length(source_kind)>=8),
  actor_sub uuid NOT NULL,
  proposer_subject text NOT NULL CHECK (length(proposer_subject)>=8),
  registrar_subject text NOT NULL CHECK (length(registrar_subject)>=8),
  action_code text NOT NULL REFERENCES private.lf_owner_chat_action_catalog_v1(action_code),
  scope jsonb NOT NULL CHECK (jsonb_typeof(scope)='object'),
  scope_sha256 text NOT NULL CHECK (scope_sha256 ~ '^[a-f0-9]{64}$'),
  literal_text text NOT NULL,
  literal_sha256 text NOT NULL CHECK (literal_sha256 ~ '^[a-f0-9]{64}$'),
  sent_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  consumed_by text,
  CHECK (proposer_subject<>registrar_subject AND actor_sub::text<>registrar_subject),
  CHECK (expires_at > sent_at AND expires_at <= sent_at + interval '15 minutes'),
  CHECK (consumed_at IS NULL OR consumed_by IS NOT NULL)
);
CREATE TABLE IF NOT EXISTS private.lf_owner_chat_revocations_v1 (
  order_id uuid PRIMARY KEY REFERENCES private.lf_owner_chat_orders_v1(order_id),
  revocation_message_id text NOT NULL UNIQUE CHECK (length(revocation_message_id)>=12),
  revoked_by_owner_sub uuid NOT NULL,
  revoked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  reason text NOT NULL CHECK (length(btrim(reason))>0)
);
REVOKE ALL ON private.lf_owner_chat_action_catalog_v1,
  private.lf_owner_chat_orders_v1,private.lf_owner_chat_revocations_v1
  FROM PUBLIC,anon,authenticated,service_role;

-- Called ONLY by a trusted, already-authorized orchestrator writer.
-- Function arguments are not human-authentication evidence by themselves.
CREATE OR REPLACE FUNCTION private.fn_lf_owner_chat_register_v1(
  p_source_chat_id text,p_source_message_id text,p_source_kind text,
  p_actor_sub uuid,p_proposer_subject text,p_registrar_subject text,
  p_sent_at timestamptz,p_literal_text text,p_scope jsonb
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_action text; v_catalog private.lf_owner_chat_action_catalog_v1%ROWTYPE;
  v_sha text;v_text text;v_order uuid;v_keys text[];v_count int;v_unique int;
BEGIN
 IF p_source_kind IS DISTINCT FROM
      (SELECT channel_code FROM private.lf_owner_chat_identity_v1 WHERE config_key='LF_OWNER') OR
    p_source_chat_id IS NULL OR length(p_source_chat_id)<12 OR
    p_source_message_id IS NULL OR length(p_source_message_id)<12 OR
    p_actor_sub IS NULL OR
    p_proposer_subject IS NULL OR length(p_proposer_subject)<8 OR
    p_registrar_subject IS NULL OR length(p_registrar_subject)<8 OR
    p_proposer_subject=p_registrar_subject OR
    p_actor_sub::text=p_registrar_subject OR
    p_actor_sub IS DISTINCT FROM private.fn_lf_owner_chat_owner_sub_v1() THEN
   RAISE EXCEPTION 'CHAT_OWNER_ORCHESTRATOR_EVENT_OR_SEPARATION_INVALID';
 END IF;
 IF p_sent_at IS NULL OR p_sent_at > clock_timestamp()+interval '30 seconds'
    OR p_sent_at+interval '15 minutes' <= clock_timestamp() THEN
   RAISE EXCEPTION 'CHAT_OWNER_ORDER_EXPIRED_OR_FUTURE';
 END IF;
 IF p_scope IS NULL OR jsonb_typeof(p_scope)<>'object' THEN
   RAISE EXCEPTION 'CHAT_OWNER_SCOPE_INVALID';
 END IF;
 v_action:=p_scope->>'action';
 SELECT * INTO v_catalog FROM private.lf_owner_chat_action_catalog_v1
   WHERE action_code=v_action AND enabled=true;
 IF NOT FOUND THEN RAISE EXCEPTION 'CHAT_OWNER_ACTION_NOT_CATALOGUED'; END IF;
 SELECT pg_catalog.array_agg(k ORDER BY k) INTO v_keys
   FROM jsonb_object_keys(p_scope) AS k;
 IF v_keys IS DISTINCT FROM (SELECT pg_catalog.array_agg(k ORDER BY k)
    FROM unnest(v_catalog.required_scope_keys) AS k) THEN
   RAISE EXCEPTION 'CHAT_OWNER_SCOPE_FIELDS_NOT_CLOSED';
 END IF;
 IF coalesce(p_scope->>'repository','') IS DISTINCT FROM
   (SELECT repository_full_name FROM private.lf_owner_chat_identity_v1 WHERE config_key='LF_OWNER') THEN
   RAISE EXCEPTION 'CHAT_OWNER_REPOSITORY_INVALID';
 END IF;
 IF v_action='MERGE_GOVERNANCE_PR' THEN
   IF jsonb_typeof(p_scope->'pr_number') <> 'number' OR
      (p_scope->>'pr_number') !~ '^[1-9][0-9]*$' OR
      coalesce(p_scope->>'head_sha','') !~ '^[a-f0-9]{40}$' THEN
     RAISE EXCEPTION 'CHAT_OWNER_PR_HEAD_INVALID';
   END IF;
 ELSIF v_action='PROMOTE_RULE_BATCH' THEN
   IF coalesce(p_scope->>'execution_id','') !~ '^EXEC-[A-Z0-9_-]{10,128}$' OR
      coalesce(p_scope->>'rule_snapshots_sha256','') !~ '^[a-f0-9]{64}$' OR
      jsonb_typeof(p_scope->'rule_codes') IS DISTINCT FROM 'array' OR
      jsonb_array_length(p_scope->'rule_codes')=0 THEN
     RAISE EXCEPTION 'CHAT_OWNER_RULE_BATCH_INVALID';
   END IF;
   SELECT count(*),count(DISTINCT x.code) INTO v_count,v_unique
     FROM jsonb_array_elements_text(p_scope->'rule_codes') AS x(code);
   IF v_count<>v_unique OR EXISTS(
     SELECT 1 FROM jsonb_array_elements_text(p_scope->'rule_codes') AS x(code)
     WHERE x.code !~ '^[A-Z0-9_-]{3,128}$') OR
     (SELECT jsonb_agg(x.code ORDER BY x.code)
      FROM jsonb_array_elements_text(p_scope->'rule_codes') AS x(code))
        IS DISTINCT FROM p_scope->'rule_codes' THEN
      RAISE EXCEPTION 'CHAT_OWNER_RULE_COHORT_NOT_CLOSED';
   END IF;
 END IF;
 v_text:=programacion.fn_v09_canonical_jsonb_text(p_scope);
 v_sha:=programacion.fn_v09_sha256_jsonb(p_scope);
 IF p_literal_text IS DISTINCT FROM 'APRUEBO '||left(v_sha,12)||' '||v_text THEN
   RAISE EXCEPTION 'CHAT_OWNER_LITERAL_OR_SHORT_HASH_MISMATCH';
 END IF;
 INSERT INTO private.lf_owner_chat_orders_v1(
   source_chat_id,source_message_id,source_kind,actor_sub,
   proposer_subject,registrar_subject,action_code,scope,scope_sha256,
   literal_text,literal_sha256,sent_at,expires_at)
 VALUES(p_source_chat_id,p_source_message_id,p_source_kind,p_actor_sub,
   p_proposer_subject,p_registrar_subject,v_action,p_scope,v_sha,
   p_literal_text,encode(extensions.digest(convert_to(p_literal_text,'UTF8'),'sha256'),'hex'),
   p_sent_at,p_sent_at + make_interval(secs=>v_catalog.max_ttl_seconds))
 RETURNING order_id INTO v_order;
 RETURN jsonb_build_object('status','RECORDED_USER_CHAT_ORDER','order_id',v_order,
   'source_message_id',p_source_message_id,'action',v_action,
   'scope_sha256',v_sha,'literal_sha256',
   encode(extensions.digest(convert_to(p_literal_text,'UTF8'),'sha256'),'hex'),
   'sent_at_lima',to_char(p_sent_at AT TIME ZONE 'America/Lima','YYYY-MM-DD"T"HH24:MI:SS')||'-05:00',
   'expires_at',p_sent_at+make_interval(secs=>v_catalog.max_ttl_seconds));
END;
$fn$;

CREATE OR REPLACE FUNCTION private.fn_lf_owner_chat_consume_v1(
 p_order_id uuid,p_action_code text,p_expected_scope jsonb,
 p_consumer_ref text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v private.lf_owner_chat_orders_v1%ROWTYPE;
  v_sha text;v_text text;v_catalog private.lf_owner_chat_action_catalog_v1%ROWTYPE;
BEGIN
 SELECT * INTO v FROM private.lf_owner_chat_orders_v1
 WHERE order_id=p_order_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','code','NO_OWNER_CHAT_ORDER'); END IF;
 IF v.consumed_at IS NOT NULL THEN
   RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_REUSED');
 END IF;
 IF EXISTS(SELECT 1 FROM private.lf_owner_chat_revocations_v1 WHERE order_id=p_order_id) THEN
   RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_REVOKED');
 END IF;
 IF clock_timestamp()>=v.expires_at THEN
   RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_EXPIRED');
 END IF;
 IF v.actor_sub IS DISTINCT FROM private.fn_lf_owner_chat_owner_sub_v1() OR
    v.source_kind IS DISTINCT FROM
      (SELECT channel_code FROM private.lf_owner_chat_identity_v1 WHERE config_key='LF_OWNER') OR
    v.scope->>'repository' IS DISTINCT FROM
      (SELECT repository_full_name FROM private.lf_owner_chat_identity_v1 WHERE config_key='LF_OWNER') OR
    v.action_code IS DISTINCT FROM p_action_code OR
    v.scope IS DISTINCT FROM p_expected_scope OR
    v.proposer_subject=v.registrar_subject OR
    v.actor_sub::text=v.registrar_subject OR
    nullif(btrim(p_consumer_ref),'') IS NULL THEN
   RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_SCOPE_OR_ACTORS_MISMATCH');
 END IF;
 SELECT * INTO v_catalog FROM private.lf_owner_chat_action_catalog_v1
   WHERE action_code=v.action_code AND enabled=true;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_ACTION_DISABLED'); END IF;
 v_sha:=programacion.fn_v09_sha256_jsonb(p_expected_scope);
 v_text:=programacion.fn_v09_canonical_jsonb_text(p_expected_scope);
 IF v.scope_sha256 IS DISTINCT FROM v_sha OR
    v.literal_text IS DISTINCT FROM 'APRUEBO '||left(v_sha,12)||' '||v_text OR
    v.literal_sha256 IS DISTINCT FROM
      encode(extensions.digest(convert_to(v.literal_text,'UTF8'),'sha256'),'hex') THEN
   RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_HASH_MISMATCH');
 END IF;
 UPDATE private.lf_owner_chat_orders_v1
 SET consumed_at=clock_timestamp(),consumed_by=p_consumer_ref
 WHERE order_id=p_order_id AND consumed_at IS NULL;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_REUSED'); END IF;
 RETURN jsonb_build_object('status','CONSUMED','order_id',p_order_id,
  'scope_sha256',v_sha,'source_message_id',v.source_message_id,
  'consumer_ref',p_consumer_ref);
END;
$fn$;

-- Revocation is a separate owner USER event, registered by trusted transport.
CREATE OR REPLACE FUNCTION private.fn_lf_owner_chat_revoke_v1(
 p_order_id uuid,p_revocation_message_id text,p_owner_sub uuid,p_reason text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v private.lf_owner_chat_orders_v1%ROWTYPE;
BEGIN
 SELECT * INTO v FROM private.lf_owner_chat_orders_v1 WHERE order_id=p_order_id FOR UPDATE;
 IF NOT FOUND OR v.actor_sub IS DISTINCT FROM private.fn_lf_owner_chat_owner_sub_v1()
    OR p_owner_sub IS DISTINCT FROM private.fn_lf_owner_chat_owner_sub_v1() OR
    v.consumed_at IS NOT NULL OR length(coalesce(p_revocation_message_id,''))<12
    OR nullif(btrim(p_reason),'') IS NULL OR
    p_revocation_message_id=v.source_message_id THEN
   RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_REVOKE_INVALID');
 END IF;
 INSERT INTO private.lf_owner_chat_revocations_v1(order_id,revocation_message_id,revoked_by_owner_sub,reason)
 VALUES(p_order_id,p_revocation_message_id,p_owner_sub,p_reason)
 ON CONFLICT DO NOTHING;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_ALREADY_REVOKED'); END IF;
 RETURN jsonb_build_object('status','REVOKED','order_id',p_order_id);
END;
$fn$;
REVOKE ALL ON FUNCTION private.fn_lf_owner_chat_register_v1(text,text,text,uuid,text,text,timestamptz,text,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fn_lf_owner_chat_consume_v1(uuid,text,jsonb,text)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fn_lf_owner_chat_revoke_v1(uuid,text,uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;

-- HUMAN consumer: one immutable order -> one complete closed rule batch -> one
-- transaction. A direct HUMAN:* call to decide_v1 has no per-rule tx lease.
CREATE TABLE private.lf_owner_chat_promotion_leases_v1(
  promotion_id text PRIMARY KEY REFERENCES public.lf_rule_promotion_v1(promotion_id),
  order_id uuid NOT NULL REFERENCES private.lf_owner_chat_orders_v1(order_id),
  rule_code text NOT NULL,
  parent_run text NOT NULL,
  tx_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(order_id,rule_code)
);
REVOKE ALL ON private.lf_owner_chat_promotion_leases_v1
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.fn_lf_owner_chat_promote_batch_v1(
 p_order_id uuid,p_promotion_ids text[],p_note text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
  v_run text;v_codes text[];v_snap text;v_scope jsonb;v_receipt jsonb;
  v_count integer;v_bad integer;v_ids_count integer;
  v_promotion_id text;v_r record;v_dec jsonb;v_apply jsonb;v_done integer:=0;
  v_xid text:=pg_current_xact_id()::text;
BEGIN
  IF coalesce(array_length(p_promotion_ids,1),0)=0
    OR array_position(p_promotion_ids,NULL) IS NOT NULL
    OR (SELECT count(*) <> count(DISTINCT i) FROM unnest(p_promotion_ids) AS i)
    OR nullif(btrim(coalesce(p_note,'')),'') IS NULL
  THEN RAISE EXCEPTION 'CHAT_OWNER_PROMOTION_BATCH_INPUT_INVALID'; END IF;

  -- Stable lock order and complete cohort: no partial approval after drift.
  PERFORM 1 FROM public.lf_rule_promotion_v1
   WHERE promotion_id=ANY(p_promotion_ids) ORDER BY promotion_id FOR UPDATE;
  v_ids_count:=cardinality(p_promotion_ids);
  SELECT count(*),count(*) FILTER(WHERE status<>'PENDING'),
    min(request_execution_id),array_agg(rule_code ORDER BY rule_code),
    programacion.fn_v09_sha256_jsonb(
      jsonb_agg(jsonb_build_object('rule_code',rule_code,
                      'snapshot_sha256',request_snapshot_sha256) ORDER BY rule_code))
  INTO v_count,v_bad,v_run,v_codes,v_snap
  FROM public.lf_rule_promotion_v1 WHERE promotion_id=ANY(p_promotion_ids);
  IF v_count<>v_ids_count OR v_bad<>0 OR
     (SELECT count(DISTINCT request_execution_id) FROM public.lf_rule_promotion_v1
       WHERE promotion_id=ANY(p_promotion_ids))<>1 OR
     (SELECT count(DISTINCT rule_code) FROM public.lf_rule_promotion_v1
       WHERE promotion_id=ANY(p_promotion_ids))<>v_count OR
     EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1
       WHERE promotion_id=ANY(p_promotion_ids) AND
         (public.lf_asset_snapshot_sha_v1('REGLA',rule_code)
                 IS DISTINCT FROM request_snapshot_sha256)) THEN
    RAISE EXCEPTION 'CHAT_OWNER_PROMOTION_COHORT_OR_SNAPSHOT_STALE';
  END IF;
  v_scope:=jsonb_build_object('action','PROMOTE_RULE_BATCH',
    'repository',(SELECT repository_full_name FROM private.lf_owner_chat_identity_v1 WHERE config_key='LF_OWNER'),
    'execution_id',v_run,'rule_codes',to_jsonb(v_codes),
    'rule_snapshots_sha256',v_snap);
  v_receipt:=private.fn_lf_owner_chat_consume_v1(
    p_order_id,'PROMOTE_RULE_BATCH',v_scope,
    'PROMOTION_BATCH_TX:'||v_xid);
  IF v_receipt->>'status' IS DISTINCT FROM 'CONSUMED' THEN
    RAISE EXCEPTION 'CHAT_OWNER_PROMOTION_NO_VALID_ORDER:%',v_receipt;
  END IF;

  INSERT INTO private.lf_owner_chat_promotion_leases_v1
    (promotion_id,order_id,rule_code,parent_run,tx_id)
  SELECT promotion_id,p_order_id,rule_code,request_execution_id,v_xid
  FROM public.lf_rule_promotion_v1 WHERE promotion_id=ANY(p_promotion_ids);

  FOR v_promotion_id IN
    SELECT promotion_id FROM public.lf_rule_promotion_v1
    WHERE promotion_id=ANY(p_promotion_ids) ORDER BY rule_code
  LOOP
    v_dec:=public.lf_rule_promotion_decide_v1(v_promotion_id,'APPROVE',
      'HUMAN:'||private.fn_lf_owner_chat_owner_sub_v1()::text,
      'ORQUESTACION_CHAT_ORDER:'||p_order_id::text||' '||p_note);
    IF v_dec->>'status' IS DISTINCT FROM 'APPROVED' THEN
      RAISE EXCEPTION 'CHAT_OWNER_PROMOTION_DECIDE_DENIED:%',v_dec;
    END IF;
    v_apply:=public.lf_rule_promotion_apply_v1(v_promotion_id);
    IF v_apply->>'status' IS DISTINCT FROM 'APPLIED' THEN
      RAISE EXCEPTION 'CHAT_OWNER_PROMOTION_APPLY_DENIED:%',v_apply;
    END IF;
    v_done:=v_done+1;
  END LOOP;

  IF (SELECT count(*) FROM public.lf_rule_promotion_v1
      WHERE promotion_id=ANY(p_promotion_ids) AND status='APPLIED')<>v_done THEN
    RAISE EXCEPTION 'CHAT_OWNER_PROMOTION_READBACK_MISMATCH';
  END IF;
  RETURN jsonb_build_object('status','APPLIED','count',v_done,
    'order_id',p_order_id,'parent_run',v_run,
    'snapshot_cohort_sha256',v_snap);
END;
$fn$;
REVOKE ALL ON FUNCTION private.fn_lf_owner_chat_promote_batch_v1(uuid,text[],text)
 FROM PUBLIC,anon,authenticated,service_role;

-- Guard the exact live HUMAN consumer; preserve AUTO_SCORE_V1 logic.
DO $guard$
DECLARE d text;target text;addition text;
BEGIN
 d:=pg_get_functiondef('public.lf_rule_promotion_decide_v1(text,text,text,text)'::regprocedure);
 IF md5(d)<>'98f1be74469c91d577e5eca66b81cba5' THEN
   RAISE EXCEPTION 'CHAT_OWNER_DECIDE_V1_BASE_DRIFT';
 END IF;
 target:=$t$ if p_decision='APPROVE' and public.lf_asset_snapshot_sha_v1$t$;
 addition:=$a$
 IF p_decided_by LIKE 'HUMAN:%' AND p_decision='APPROVE' AND NOT EXISTS(
   SELECT 1
   FROM private.lf_owner_chat_promotion_leases_v1 l
   JOIN private.lf_owner_chat_orders_v1 o ON o.order_id=l.order_id
   WHERE l.promotion_id=p_promotion_id AND l.rule_code=p.rule_code
     AND l.parent_run=p.request_execution_id
     AND l.tx_id=pg_current_xact_id()::text
     AND o.action_code='PROMOTE_RULE_BATCH'
     AND o.actor_sub=private.fn_lf_owner_chat_owner_sub_v1()
     AND p_decided_by='HUMAN:'||o.actor_sub::text
     AND o.consumed_by='PROMOTION_BATCH_TX:'||pg_current_xact_id()::text
     AND o.consumed_at IS NOT NULL
     AND o.expires_at>clock_timestamp()
     AND NOT EXISTS(SELECT 1 FROM private.lf_owner_chat_revocations_v1 r
       WHERE r.order_id=o.order_id)
 ) THEN
   RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','CHAT_OWNER_HUMAN_BATCH_RECEIPT_REQUIRED');
 END IF;
 $a$;
 IF position(target in d)=0 THEN RAISE EXCEPTION 'CHAT_OWNER_DECIDE_V1_PATCH_TARGET_NOT_FOUND'; END IF;
 d:=replace(d,target,addition||target);
 EXECUTE d;
END;
$guard$;

-- Train consumer; invoked only at trusted-main exact-HEAD pre-apply stage.
-- This is one-use and does NOT merge, publish a check or bypass Train.
CREATE OR REPLACE FUNCTION private.fn_lf_owner_chat_train_merge_gate_v1(
 p_order_id uuid,p_repository text,p_pr_number integer,p_final_head_sha text,
 p_train_run_ref text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_scope jsonb;v jsonb;
BEGIN
 IF p_repository IS DISTINCT FROM
   (SELECT repository_full_name FROM private.lf_owner_chat_identity_v1 WHERE config_key='LF_OWNER')
   OR p_pr_number IS NULL OR p_pr_number<=0 OR
   coalesce(p_final_head_sha,'') !~ '^[a-f0-9]{40}$' OR
   coalesce(p_repository,'') !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
   OR coalesce(p_train_run_ref,'') !~ '^TRAIN-[A-Z0-9_-]{8,128}$' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','TRAIN_CHAT_OWNER_SCOPE_INVALID');
 END IF;
 v_scope:=jsonb_build_object('action','MERGE_GOVERNANCE_PR',
   'repository',p_repository,'pr_number',p_pr_number,'head_sha',p_final_head_sha);
 v:=private.fn_lf_owner_chat_consume_v1(
   p_order_id,'MERGE_GOVERNANCE_PR',v_scope,
   'MERGE_TRAIN:'||p_train_run_ref);
 IF v->>'status' IS DISTINCT FROM 'CONSUMED' THEN
   RETURN jsonb_build_object('status','BLOCKED',
      'code','TRAIN_CHAT_OWNER_ORDER_NOT_AUTHORIZED','gate_receipt',v);
 END IF;
 RETURN jsonb_build_object('status','AUTHORIZED_FOR_TRAIN_ONLY',
   'pr_number',p_pr_number,'head_sha',p_final_head_sha,
   'order_id',p_order_id,'consumed_receipt',v);
END;
$fn$;
REVOKE ALL ON FUNCTION private.fn_lf_owner_chat_train_merge_gate_v1(uuid,text,integer,text)
 FROM PUBLIC,anon,authenticated,service_role;

-- No new EXECUTE grants. Train must explicitly wire this guarded function
-- through the already-authorized trusted-main transport before activation.
COMMIT;
