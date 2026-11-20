-- LF OWNER 2026-11-17: forward-only teardown of #4063 owner-chat approvals.
-- NO changes to VIGENTE rules, score, AUTO authority, or historical migration ledger.
-- Pre-#4063 profile transition is already unchanged; assert exact live source hash.
-- APPLY ONLY via governed LF Migration Merge Train; DO NOT run in production manually.
BEGIN;

DO $preflight$
DECLARE d text;
BEGIN
  IF to_regclass('private.lf_owner_chat_identity_v1') IS NULL
     OR to_regclass('private.lf_owner_chat_orders_v1') IS NULL
     OR to_regclass('private.lf_ig_parameters_v1') IS NULL
     OR to_regclass('private.lf_ig_parameter_change_audit_v1') IS NULL
  THEN RAISE EXCEPTION 'OWNER_CHAT_TEARDOWN_PREIMAGE_OBJECTS_MISSING'; END IF;
  d:=pg_get_functiondef('public.lf_rule_promotion_decide_v1(text,text,text,text)'::regprocedure);
  IF md5(d)<>'9be3f4837047c51faf8d5df308e6c846'
  THEN RAISE EXCEPTION 'OWNER_CHAT_TEARDOWN_DECIDE_PREIMAGE_DRIFT'; END IF;
  IF md5(pg_get_functiondef('public.lf_profile_runtime_transition_v1(jsonb)'::regprocedure))
      <>'121fe8be9a5464695547dd889b8b7c9d'
  THEN RAISE EXCEPTION 'OWNER_CHAT_TEARDOWN_TRANSITION_PREIMAGE_DRIFT'; END IF;
  IF (SELECT count(*) FROM private.lf_owner_chat_orders_v1)<>0
     OR (SELECT count(*) FROM private.lf_owner_chat_revocations_v1)<>0
     OR (SELECT count(*) FROM private.lf_owner_chat_promotion_leases_v1)<>0
     OR (SELECT count(*) FROM private.lf_ig_parameter_change_audit_v1)<>0
  THEN RAISE EXCEPTION 'OWNER_CHAT_TEARDOWN_NONEMPTY_RECEIPTS_REQUIRES_REVIEW'; END IF;
  IF (SELECT count(*) FROM private.lf_ig_parameters_v1
      WHERE parameter_namespace='OWNER_CHAT')<>2
    OR EXISTS(SELECT 1 FROM private.lf_ig_parameters_v1
       WHERE parameter_namespace<>'OWNER_CHAT' AND last_approved_order_id IS NOT NULL)
  THEN RAISE EXCEPTION 'OWNER_CHAT_TEARDOWN_PARAMETER_ROWS_DRIFT'; END IF;
END;
$preflight$;

-- Reverse precisely the one #4063 HUMAN/APPROVE injected block.
-- SQL source equality and MD5 are backed by live PG17.6 read-only checks.
DO $restore_decide$
DECLARE
  d text;
  inserted text:=$owner_guard$
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
 $owner_guard$;
BEGIN
  d:=pg_get_functiondef('public.lf_rule_promotion_decide_v1(text,text,text,text)'::regprocedure);
  IF md5(d)<>'9be3f4837047c51faf8d5df308e6c846'
     OR strpos(d,inserted)=0
  THEN RAISE EXCEPTION 'OWNER_CHAT_TEARDOWN_GUARD_NOT_UNIQUE_OR_SOURCE_DRIFT'; END IF;
  d:=replace(d,inserted,'');
  IF md5(d)<>'98f1be74469c91d577e5eca66b81cba5'
  THEN RAISE EXCEPTION 'OWNER_CHAT_TEARDOWN_RESTORED_SOURCE_MISMATCH'; END IF;
  EXECUTE d;
  IF md5(pg_get_functiondef('public.lf_rule_promotion_decide_v1(text,text,text,text)'::regprocedure))
       <>'98f1be74469c91d577e5eca66b81cba5'
  THEN RAISE EXCEPTION 'OWNER_CHAT_TEARDOWN_DECIDE_READBACK_MISMATCH'; END IF;
END;
$restore_decide$;

-- Retain the general IG parameter table and all its columns.
-- Remove the chat-specific write guard and empty audit object.
DROP TRIGGER lf_ig_parameter_governed_write_v1 ON private.lf_ig_parameters_v1;
DROP FUNCTION private.fn_lf_ig_parameter_update_v1(uuid,text,text,text,integer,text,boolean);
DROP FUNCTION private.fn_lf_ig_parameter_guard_audit_v1();
DROP TABLE private.lf_ig_parameter_change_audit_v1;

-- Remove the two OWNER_CHAT seed rows; keep INPUT_GOVERNANCE and NOTIFICATIONS rows.
DELETE FROM private.lf_ig_parameters_v1 WHERE parameter_namespace='OWNER_CHAT';
ALTER TABLE private.lf_ig_parameters_v1
  DROP CONSTRAINT lf_ig_parameter_last_order_fkey,
  DROP CONSTRAINT lf_ig_parameters_v1_owner_sub_fkey,
  DROP CONSTRAINT lf_ig_parameters_v1_parameter_namespace_check,
  DROP CONSTRAINT lf_ig_parameters_v1_check;
ALTER TABLE private.lf_ig_parameters_v1
  ADD CONSTRAINT lf_ig_parameters_v1_non_chat_namespace_check
    CHECK (parameter_namespace IN ('INPUT_GOVERNANCE','NOTIFICATIONS')),
  ADD CONSTRAINT lf_ig_parameters_v1_non_chat_value_check
    CHECK (channel_code='' AND owner_sub IS NULL
      AND ((value_kind='JSONB' AND value_jsonb IS NOT NULL AND value_sha256 IS NULL)
        OR (value_kind='SHA256' AND value_sha256 IS NOT NULL AND value_jsonb IS NULL)));

DROP VIEW private.lf_owner_chat_authorized_accounts_v1;
DROP FUNCTION private.fn_lf_owner_chat_train_merge_gate_v1(uuid,text,integer,text,text);
DROP FUNCTION private.fn_lf_owner_chat_promote_batch_v1(uuid,text[],text);
DROP FUNCTION private.fn_lf_owner_chat_revoke_v1(uuid,text,uuid,text,text,text);
DROP FUNCTION private.fn_lf_owner_chat_register_v1(text,text,text,uuid,text,text,text,text,timestamptz,text,jsonb);
DROP FUNCTION private.fn_lf_owner_chat_consume_v1(uuid,text,jsonb,text);
DROP FUNCTION private.fn_lf_owner_chat_owner_sub_v1();
DROP TABLE private.lf_owner_chat_promotion_leases_v1;
DROP TABLE private.lf_owner_chat_revocations_v1;
DROP TABLE private.lf_owner_chat_orders_v1;
DROP TABLE private.lf_owner_chat_action_catalog_v1;
DROP TABLE private.lf_owner_chat_identity_v1;

DO $readback$
BEGIN
  IF to_regclass('private.lf_owner_chat_identity_v1') IS NOT NULL
     OR to_regclass('private.lf_owner_chat_orders_v1') IS NOT NULL
     OR to_regclass('private.lf_owner_chat_promotion_leases_v1') IS NOT NULL
     OR to_regclass('private.lf_ig_parameters_v1') IS NULL
     OR EXISTS(SELECT 1 FROM private.lf_ig_parameters_v1
               WHERE parameter_namespace='OWNER_CHAT')
     OR to_regprocedure('private.fn_lf_owner_chat_owner_sub_v1()') IS NOT NULL
  THEN RAISE EXCEPTION 'OWNER_CHAT_TEARDOWN_POSTCONDITION_FAILED'; END IF;
END;
$readback$;
COMMIT;
