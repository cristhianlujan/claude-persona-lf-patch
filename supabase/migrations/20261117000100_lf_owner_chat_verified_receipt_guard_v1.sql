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

-- One canonical extensible IG parameter table, usable for future notifications.
-- The owner account is an active SHA256 parameter; never persist email plaintext.
-- No editor/agent roles receive table privileges or EXECUTE.
ALTER TABLE private.lf_owner_chat_identity_v1
 ADD CONSTRAINT lf_owner_chat_identity_owner_sub_uq UNIQUE(owner_sub);
CREATE TABLE IF NOT EXISTS private.lf_ig_parameters_v1 (
 parameter_namespace text NOT NULL CHECK
   (parameter_namespace IN ('OWNER_CHAT','INPUT_GOVERNANCE','NOTIFICATIONS')),
 parameter_code text NOT NULL CHECK (parameter_code ~ '^[A-Z0-9_]{5,96}$'),
 channel_code text NOT NULL DEFAULT '',
 owner_sub uuid REFERENCES private.lf_owner_chat_identity_v1(owner_sub),
 value_kind text NOT NULL CHECK (value_kind IN ('SHA256','JSONB')),
 value_sha256 text CHECK (value_sha256 ~ '^[a-f0-9]{64}$'),
 value_jsonb jsonb,
 activo boolean NOT NULL DEFAULT false,
 revision integer NOT NULL DEFAULT 1 CHECK (revision>=1),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 last_approved_order_id uuid,
 PRIMARY KEY(parameter_namespace,parameter_code,channel_code),
 CHECK (
  (parameter_namespace='OWNER_CHAT' AND parameter_code='SESSION_EMAIL_SHA256'
   AND channel_code IN ('CHAT_GPT_SESSION','CHAT_CLAUDE_SESSION')
   AND owner_sub IS NOT NULL AND value_kind='SHA256'
   AND value_sha256 IS NOT NULL AND value_jsonb IS NULL)
  OR
  (parameter_namespace IN ('INPUT_GOVERNANCE','NOTIFICATIONS')
   AND channel_code='' AND owner_sub IS NULL
   AND ((value_kind='JSONB' AND value_jsonb IS NOT NULL AND value_sha256 IS NULL)
     OR (value_kind='SHA256' AND value_sha256 IS NOT NULL AND value_jsonb IS NULL)))
 )
);
INSERT INTO private.lf_ig_parameters_v1
 (parameter_namespace,parameter_code,channel_code,owner_sub,value_kind,value_sha256,activo)
SELECT 'OWNER_CHAT','SESSION_EMAIL_SHA256',ch.channel_code,c.owner_sub,'SHA256',
 'e9ff5f5f431ad1a7fdea5aeda30fcbad4bd48d2f0d73231e9383682098c4e258',true
FROM private.lf_owner_chat_identity_v1 c
CROSS JOIN (VALUES('CHAT_CLAUDE_SESSION'),('CHAT_GPT_SESSION')) AS ch(channel_code)
WHERE c.config_key='LF_OWNER'
ON CONFLICT DO NOTHING;
-- Read-only compatibility VIEW: one data store, no duplicate session rows.
CREATE VIEW private.lf_owner_chat_authorized_accounts_v1 AS
 SELECT owner_sub,channel_code,value_sha256 AS account_email_sha256,activo
 FROM private.lf_ig_parameters_v1
 WHERE parameter_namespace='OWNER_CHAT' AND parameter_code='SESSION_EMAIL_SHA256';
REVOKE ALL ON private.lf_ig_parameters_v1,
 private.lf_owner_chat_authorized_accounts_v1
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
('PROMOTE_RULE_BATCH',ARRAY['action','repository','execution_id','rule_codes','rule_snapshots_sha256']::text[],true,'LF_CHAT_OWNER_ORDER_V2'),
('UPDATE_IG_PARAMETER',ARRAY['action','repository','parameter_namespace','parameter_code','channel_code','expected_revision','new_value_sha256','new_activo']::text[],true,'LF_CHAT_OWNER_ORDER_V2')
ON CONFLICT(action_code) DO NOTHING;

CREATE TABLE IF NOT EXISTS private.lf_owner_chat_orders_v1 (
  order_id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  source_chat_id text NOT NULL CHECK (length(source_chat_id)>=12),
  source_message_id text NOT NULL UNIQUE CHECK (length(source_message_id)>=12),
  source_kind text NOT NULL CHECK (length(source_kind)>=8),
  actor_sub uuid NOT NULL,
  channel_code text NOT NULL,
  session_account_sha256 text NOT NULL CHECK (session_account_sha256 ~ '^[a-f0-9]{64}$'),
  identity_mode text NOT NULL CHECK (identity_mode='ACCOUNT_SESSION'),
  sent_at_lima text NOT NULL,
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

-- Called ONLY by a trusted orchestrator with a provider-verified account
-- session. Account email may be transient inbound metadata but is never
-- configured via environment or persisted in plaintext. The active SHA
-- parameter row is the sole authority; function arguments alone prove nothing.
CREATE OR REPLACE FUNCTION private.fn_lf_owner_chat_register_v1(
  p_source_chat_id text,p_source_message_id text,p_source_kind text,
  p_actor_sub uuid,p_channel_code text,p_session_account_email text,
  p_proposer_subject text,p_registrar_subject text,
  p_sent_at timestamptz,p_literal_text text,p_scope jsonb
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_action text; v_catalog private.lf_owner_chat_action_catalog_v1%ROWTYPE;
  v_sha text;v_text text;v_order uuid;v_keys text[];v_count int;v_unique int;
  v_account_sha text;
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
 -- Never log or store the raw input; derive SHA256(lower(trim(email))) here.
 -- Model cannot choose identity_mode; valid account session is mandatory.
 IF p_session_account_email IS NULL OR
    nullif(btrim(p_session_account_email),'') IS NULL
 THEN RAISE EXCEPTION 'CHAT_OWNER_ACCOUNT_SESSION_NOT_AUTHORIZED'; END IF;
 v_account_sha:=encode(extensions.digest(
     convert_to(lower(btrim(p_session_account_email)),'UTF8'),'sha256'),'hex');
 IF p_channel_code IS NULL OR NOT EXISTS(
      SELECT 1 FROM private.lf_owner_chat_authorized_accounts_v1 a
       WHERE a.owner_sub=p_actor_sub AND a.channel_code=p_channel_code
         AND a.account_email_sha256=v_account_sha AND a.activo)
 THEN RAISE EXCEPTION 'CHAT_OWNER_ACCOUNT_SESSION_NOT_AUTHORIZED'; END IF;
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
 ELSIF v_action='UPDATE_IG_PARAMETER' THEN
   IF p_scope->>'parameter_namespace' IS DISTINCT FROM 'OWNER_CHAT'
     OR p_scope->>'parameter_code' IS DISTINCT FROM 'SESSION_EMAIL_SHA256'
     OR p_scope->>'channel_code' NOT IN ('CHAT_GPT_SESSION','CHAT_CLAUDE_SESSION')
     OR coalesce(p_scope->>'new_value_sha256','') !~ '^[a-f0-9]{64}$'
     OR jsonb_typeof(p_scope->'expected_revision') IS DISTINCT FROM 'number'
     OR (p_scope->>'expected_revision') !~ '^[1-9][0-9]*$'
     OR jsonb_typeof(p_scope->'new_activo') IS DISTINCT FROM 'boolean'
   THEN RAISE EXCEPTION 'CHAT_OWNER_PARAMETER_SCOPE_INVALID'; END IF;
 END IF;
 v_text:=programacion.fn_v09_canonical_jsonb_text(p_scope);
 v_sha:=programacion.fn_v09_sha256_jsonb(p_scope);
 IF p_literal_text IS DISTINCT FROM 'APRUEBO '||left(v_sha,12)||' '||v_text THEN
   RAISE EXCEPTION 'CHAT_OWNER_LITERAL_OR_SHORT_HASH_MISMATCH';
 END IF;
 INSERT INTO private.lf_owner_chat_orders_v1(
   source_chat_id,source_message_id,source_kind,actor_sub,
   channel_code,session_account_sha256,identity_mode,sent_at_lima,
   proposer_subject,registrar_subject,action_code,scope,scope_sha256,
   literal_text,literal_sha256,sent_at,expires_at)
 VALUES(p_source_chat_id,p_source_message_id,p_source_kind,p_actor_sub,
   p_channel_code,v_account_sha,'ACCOUNT_SESSION',
   to_char(p_sent_at AT TIME ZONE 'America/Lima','YYYY-MM-DD"T"HH24:MI:SS')||'-05:00',
   p_proposer_subject,p_registrar_subject,v_action,p_scope,v_sha,
   p_literal_text,encode(extensions.digest(convert_to(p_literal_text,'UTF8'),'sha256'),'hex'),
   p_sent_at,p_sent_at + make_interval(secs=>v_catalog.max_ttl_seconds))
 RETURNING order_id INTO v_order;
 RETURN jsonb_build_object('status','RECORDED_USER_CHAT_ORDER','order_id',v_order,
   'source_message_id',p_source_message_id,'action',v_action,
   'identity_mode','ACCOUNT_SESSION','channel_code',p_channel_code,
   'session_account_sha256',v_account_sha,
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
    v.identity_mode IS DISTINCT FROM 'ACCOUNT_SESSION' OR
    NOT EXISTS(SELECT 1 FROM private.lf_owner_chat_authorized_accounts_v1 a
       WHERE a.owner_sub=v.actor_sub AND a.channel_code=v.channel_code
         AND a.account_email_sha256=v.session_account_sha256 AND a.activo) OR
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
  'identity_mode',v.identity_mode,'channel_code',v.channel_code,
  'session_account_sha256',v.session_account_sha256,'sent_at_lima',v.sent_at_lima,
  'consumer_ref',p_consumer_ref);
END;
$fn$;

-- Revocation is a separate owner USER event, registered by trusted transport.
CREATE OR REPLACE FUNCTION private.fn_lf_owner_chat_revoke_v1(
 p_order_id uuid,p_revocation_message_id text,p_owner_sub uuid,p_channel_code text,p_session_account_email text,p_reason text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v private.lf_owner_chat_orders_v1%ROWTYPE;
  v_email_sha text;
BEGIN
 IF p_session_account_email IS NULL OR nullif(btrim(p_session_account_email),'') IS NULL
 THEN RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_REVOKE_INVALID'); END IF;
 v_email_sha:=encode(extensions.digest(
      convert_to(lower(btrim(p_session_account_email)),'UTF8'),'sha256'),'hex');
 SELECT * INTO v FROM private.lf_owner_chat_orders_v1 WHERE order_id=p_order_id FOR UPDATE;
 IF NOT FOUND OR v.actor_sub IS DISTINCT FROM private.fn_lf_owner_chat_owner_sub_v1()
    OR p_owner_sub IS DISTINCT FROM private.fn_lf_owner_chat_owner_sub_v1() OR
    p_channel_code IS DISTINCT FROM v.channel_code OR
    v_email_sha IS DISTINCT FROM v.session_account_sha256 OR
    v.identity_mode IS DISTINCT FROM 'ACCOUNT_SESSION' OR
    NOT EXISTS(SELECT 1 FROM private.lf_owner_chat_authorized_accounts_v1 a
      WHERE a.owner_sub=v.actor_sub AND a.channel_code=p_channel_code
        AND a.account_email_sha256=v_email_sha AND a.activo) OR
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
REVOKE ALL ON FUNCTION private.fn_lf_owner_chat_register_v1(text,text,text,uuid,text,text,text,text,timestamptz,text,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fn_lf_owner_chat_consume_v1(uuid,text,jsonb,text)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fn_lf_owner_chat_revoke_v1(uuid,text,uuid,text,text,text)
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
     AND o.identity_mode='ACCOUNT_SESSION'
     AND EXISTS(SELECT 1 FROM private.lf_owner_chat_authorized_accounts_v1 a
       WHERE a.owner_sub=o.actor_sub AND a.channel_code=o.channel_code
         AND a.account_email_sha256=o.session_account_sha256 AND a.activo)
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
REVOKE ALL ON FUNCTION private.fn_lf_owner_chat_train_merge_gate_v1(uuid,text,integer,text,text)
 FROM PUBLIC,anon,authenticated,service_role;

-- Single canonical parameter store: immutability unless one-use approved
-- owner CHAT order is consumed by this transaction. Audit is mandatory.
ALTER TABLE private.lf_ig_parameters_v1 ADD CONSTRAINT
 lf_ig_parameter_last_order_fkey FOREIGN KEY(last_approved_order_id)
 REFERENCES private.lf_owner_chat_orders_v1(order_id);
CREATE TABLE private.lf_ig_parameter_change_audit_v1(
 change_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 parameter_namespace text NOT NULL,
 parameter_code text NOT NULL,
 channel_code text NOT NULL,
 owner_sub uuid,
 old_sha256 text,
 new_sha256 text,
 old_activo boolean NOT NULL,
 new_activo boolean NOT NULL,
 old_revision integer NOT NULL,
 new_revision integer NOT NULL,
 approval_order_id uuid NOT NULL REFERENCES private.lf_owner_chat_orders_v1(order_id),
 approval_message_id text NOT NULL,
 approval_scope_sha256 text NOT NULL,
 owner_actor_sub uuid NOT NULL,
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
REVOKE ALL ON private.lf_ig_parameter_change_audit_v1
 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.fn_lf_ig_parameter_guard_audit_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE ord private.lf_owner_chat_orders_v1%ROWTYPE;
  expected jsonb; repo text;
BEGIN
 IF TG_OP<>'UPDATE' THEN
   RAISE EXCEPTION 'IG_PARAMETER_DIRECT_INSERT_DELETE_BLOCKED';
 END IF;
 IF NEW.parameter_namespace IS DISTINCT FROM OLD.parameter_namespace OR
    NEW.parameter_code IS DISTINCT FROM OLD.parameter_code OR
    NEW.channel_code IS DISTINCT FROM OLD.channel_code OR
    NEW.owner_sub IS DISTINCT FROM OLD.owner_sub OR
    NEW.value_kind IS DISTINCT FROM OLD.value_kind OR
    NEW.value_jsonb IS DISTINCT FROM OLD.value_jsonb OR
    NEW.revision<>OLD.revision+1 OR NEW.last_approved_order_id IS NULL OR
    NEW.updated_at IS NULL THEN
   RAISE EXCEPTION 'IG_PARAMETER_UNAUTHORIZED_STRUCTURE_CHANGE';
 END IF;
 SELECT * INTO ord FROM private.lf_owner_chat_orders_v1
  WHERE order_id=NEW.last_approved_order_id FOR UPDATE;
 repo:=(SELECT repository_full_name FROM private.lf_owner_chat_identity_v1 WHERE config_key='LF_OWNER');
 expected:=jsonb_build_object('action','UPDATE_IG_PARAMETER','repository',repo,
  'parameter_namespace',OLD.parameter_namespace,'parameter_code',OLD.parameter_code,
  'channel_code',OLD.channel_code,'expected_revision',OLD.revision,
  'new_value_sha256',NEW.value_sha256,'new_activo',NEW.activo);
 IF ord.order_id IS NULL OR ord.action_code IS DISTINCT FROM 'UPDATE_IG_PARAMETER' OR
    ord.actor_sub IS DISTINCT FROM private.fn_lf_owner_chat_owner_sub_v1() OR
    ord.identity_mode IS DISTINCT FROM 'ACCOUNT_SESSION' OR
    ord.proposer_subject=ord.registrar_subject OR
    ord.scope IS DISTINCT FROM expected OR
    ord.scope_sha256 IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(expected) OR
    ord.consumed_by IS DISTINCT FROM 'PARAMETER_CHANGE_TX:'||pg_current_xact_id()::text OR
    ord.consumed_at IS NULL OR NEW.owner_sub IS DISTINCT FROM ord.actor_sub OR
    EXISTS(SELECT 1 FROM private.lf_owner_chat_revocations_v1 r WHERE r.order_id=ord.order_id)
 THEN RAISE EXCEPTION 'IG_PARAMETER_APPROVED_OWNER_CHAT_RECEIPT_REQUIRED'; END IF;
 INSERT INTO private.lf_ig_parameter_change_audit_v1(
  parameter_namespace,parameter_code,channel_code,owner_sub,
  old_sha256,new_sha256,old_activo,new_activo,old_revision,new_revision,
  approval_order_id,approval_message_id,approval_scope_sha256,owner_actor_sub)
 VALUES(OLD.parameter_namespace,OLD.parameter_code,OLD.channel_code,OLD.owner_sub,
  OLD.value_sha256,NEW.value_sha256,OLD.activo,NEW.activo,OLD.revision,NEW.revision,
  ord.order_id,ord.source_message_id,ord.scope_sha256,ord.actor_sub);
 RETURN NEW;
END;
$fn$;
REVOKE ALL ON FUNCTION private.fn_lf_ig_parameter_guard_audit_v1()
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER lf_ig_parameter_governed_write_v1
 BEFORE INSERT OR UPDATE OR DELETE ON private.lf_ig_parameters_v1
 FOR EACH ROW EXECUTE FUNCTION private.fn_lf_ig_parameter_guard_audit_v1();

CREATE OR REPLACE FUNCTION private.fn_lf_ig_parameter_update_v1(
 p_order_id uuid,p_namespace text,p_code text,p_channel_code text,
 p_expected_revision integer,p_new_sha256 text,p_new_activo boolean
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE oldrow private.lf_ig_parameters_v1%ROWTYPE; scope jsonb; receipt jsonb;
BEGIN
 IF p_namespace IS DISTINCT FROM 'OWNER_CHAT' OR
    p_code IS DISTINCT FROM 'SESSION_EMAIL_SHA256' OR
    p_channel_code NOT IN ('CHAT_CLAUDE_SESSION','CHAT_GPT_SESSION') OR
    coalesce(p_new_sha256,'') !~ '^[a-f0-9]{64}$' OR
    p_new_activo IS NULL OR coalesce(p_expected_revision,0)<1
 THEN RAISE EXCEPTION 'IG_PARAMETER_CHANGE_NOT_CATALOGUED'; END IF;
 SELECT * INTO oldrow FROM private.lf_ig_parameters_v1
  WHERE parameter_namespace=p_namespace AND parameter_code=p_code
    AND channel_code=p_channel_code FOR UPDATE;
 IF NOT FOUND OR oldrow.revision IS DISTINCT FROM p_expected_revision
 THEN RAISE EXCEPTION 'IG_PARAMETER_STALE_OR_MISSING'; END IF;
 scope:=jsonb_build_object('action','UPDATE_IG_PARAMETER',
  'repository',(SELECT repository_full_name FROM private.lf_owner_chat_identity_v1 WHERE config_key='LF_OWNER'),
  'parameter_namespace',p_namespace,'parameter_code',p_code,
  'channel_code',p_channel_code,'expected_revision',p_expected_revision,
  'new_value_sha256',p_new_sha256,'new_activo',p_new_activo);
 receipt:=private.fn_lf_owner_chat_consume_v1(p_order_id,'UPDATE_IG_PARAMETER',
  scope,'PARAMETER_CHANGE_TX:'||pg_current_xact_id()::text);
 IF receipt->>'status' IS DISTINCT FROM 'CONSUMED'
 THEN RAISE EXCEPTION 'IG_PARAMETER_OWNER_APPROVAL_REQUIRED:%',receipt; END IF;
 UPDATE private.lf_ig_parameters_v1
  SET value_sha256=p_new_sha256,activo=p_new_activo,revision=revision+1,
      last_approved_order_id=p_order_id,updated_at=clock_timestamp()
 WHERE parameter_namespace=p_namespace AND parameter_code=p_code
   AND channel_code=p_channel_code;
 RETURN jsonb_build_object('status','UPDATED_WITH_OWNER_CHAT_AUDIT',
   'parameter_namespace',p_namespace,'parameter_code',p_code,
   'channel_code',p_channel_code,'revision',p_expected_revision+1,
   'order_id',p_order_id);
END;
$fn$;
REVOKE ALL ON FUNCTION private.fn_lf_ig_parameter_update_v1(uuid,text,text,text,integer,text,boolean)
 FROM PUBLIC,anon,authenticated,service_role;

-- No new EXECUTE grants. Train must explicitly wire this guarded function
-- through the already-authorized trusted-main transport before activation.
COMMIT;
