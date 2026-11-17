-- Source-only DRAFT; mandatory application via existing LF Migration Merge Train.
-- Policy: owner approval is the literal USER turn in the orchestration CHAT.
-- No Ed25519, signing provider, GitHub click, email, SMS or external service.
-- The trusted orchestrator transports original user-turn metadata; never accept
-- a model/proposer assertion as proof of the human speaker.
BEGIN;

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
  source_kind text NOT NULL CHECK (source_kind='CHAT_ORCHESTRATOR_USER_TURN'),
  actor_subject text NOT NULL CHECK (length(actor_subject)>=8),
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
  CHECK (proposer_subject<>registrar_subject AND actor_subject<>registrar_subject),
  CHECK (expires_at > sent_at AND expires_at <= sent_at + interval '15 minutes'),
  CHECK (consumed_at IS NULL OR consumed_by IS NOT NULL)
);
CREATE TABLE IF NOT EXISTS private.lf_owner_chat_revocations_v1 (
  order_id uuid PRIMARY KEY REFERENCES private.lf_owner_chat_orders_v1(order_id),
  revocation_message_id text NOT NULL UNIQUE CHECK (length(revocation_message_id)>=12),
  revoked_by_owner text NOT NULL,
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
  p_actor_subject text,p_proposer_subject text,p_registrar_subject text,
  p_sent_at timestamptz,p_literal_text text,p_scope jsonb
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_action text; v_catalog private.lf_owner_chat_action_catalog_v1%ROWTYPE;
  v_sha text;v_text text;v_order uuid;v_keys text[];v_count int;v_unique int;
BEGIN
 IF p_source_kind IS DISTINCT FROM 'CHAT_ORCHESTRATOR_USER_TURN' OR
    p_source_chat_id IS NULL OR length(p_source_chat_id)<12 OR
    p_source_message_id IS NULL OR length(p_source_message_id)<12 OR
    p_actor_subject IS NULL OR length(p_actor_subject)<8 OR
    p_proposer_subject IS NULL OR length(p_proposer_subject)<8 OR
    p_registrar_subject IS NULL OR length(p_registrar_subject)<8 OR
    p_proposer_subject=p_registrar_subject OR p_actor_subject=p_registrar_subject THEN
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
 IF coalesce(p_scope->>'repository','') !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' THEN
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
   SELECT count(*),count(DISTINCT s) INTO v_count,v_unique
     FROM jsonb_array_elements_text(p_scope->'rule_codes') AS s;
   IF v_count<>v_unique OR EXISTS(
     SELECT 1 FROM jsonb_array_elements_text(p_scope->'rule_codes') AS s
     WHERE s !~ '^[A-Z0-9_-]{3,128}$') OR
     (SELECT jsonb_agg(s ORDER BY s)
      FROM jsonb_array_elements_text(p_scope->'rule_codes') AS s)
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
   source_chat_id,source_message_id,source_kind,actor_subject,
   proposer_subject,registrar_subject,action_code,scope,scope_sha256,
   literal_text,literal_sha256,sent_at,expires_at)
 VALUES(p_source_chat_id,p_source_message_id,p_source_kind,p_actor_subject,
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
 p_expected_owner_subject text,p_consumer_ref text
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
 IF v.actor_subject IS DISTINCT FROM p_expected_owner_subject OR
    v.action_code IS DISTINCT FROM p_action_code OR
    v.scope IS DISTINCT FROM p_expected_scope OR
    v.proposer_subject=v.registrar_subject OR
    v.actor_subject=v.registrar_subject OR
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
 p_order_id uuid,p_revocation_message_id text,p_owner_subject text,p_reason text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v private.lf_owner_chat_orders_v1%ROWTYPE;
BEGIN
 SELECT * INTO v FROM private.lf_owner_chat_orders_v1 WHERE order_id=p_order_id FOR UPDATE;
 IF NOT FOUND OR v.actor_subject IS DISTINCT FROM p_owner_subject OR
    v.consumed_at IS NOT NULL OR length(coalesce(p_revocation_message_id,''))<12
    OR nullif(btrim(p_reason),'') IS NULL OR
    p_revocation_message_id=v.source_message_id THEN
   RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_REVOKE_INVALID');
 END IF;
 INSERT INTO private.lf_owner_chat_revocations_v1(order_id,revocation_message_id,revoked_by_owner,reason)
 VALUES(p_order_id,p_revocation_message_id,p_owner_subject,p_reason)
 ON CONFLICT DO NOTHING;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','code','CHAT_ORDER_ALREADY_REVOKED'); END IF;
 RETURN jsonb_build_object('status','REVOKED','order_id',p_order_id);
END;
$fn$;
REVOKE ALL ON FUNCTION private.fn_lf_owner_chat_register_v1(text,text,text,text,text,text,timestamptz,text,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fn_lf_owner_chat_consume_v1(uuid,text,jsonb,text,text)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fn_lf_owner_chat_revoke_v1(uuid,text,text,text)
 FROM PUBLIC,anon,authenticated,service_role;
-- No GRANT. Cutover to existing HUMAN decide and LF Merge Train is separate
-- and requires readback of the actual orquestador USER event boundary.
COMMIT;
