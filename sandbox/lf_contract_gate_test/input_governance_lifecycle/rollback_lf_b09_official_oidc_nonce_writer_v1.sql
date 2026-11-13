-- Governed reverse of 20261113235500 B09 official writer/nonce DRAFT.
-- BLOCK rollback if any nonce/event exists; never erase live evidence.
BEGIN;
DO $check$
BEGIN
 IF to_regclass('public.lf_ig_native_chat_nonce_v1') IS NULL
   OR to_regprocedure('public.lf_ig_native_chat_official_writer_binding_receipt_v1(text)') IS NULL
 THEN RAISE EXCEPTION 'B09_NONCE_ROLLBACK_SOURCE_NOT_PRESENT'; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_ig_native_chat_nonce_v1)
    OR EXISTS (SELECT 1 FROM public.lf_ig_native_chat_receipt_v1) THEN
   RAISE EXCEPTION 'B09_NONCE_ROLLBACK_DURABLE_RECEIPTS_PRESENT_NEEDS_SEPARATE_GOVERNED_PROCEDURE';
 END IF;
END $check$;
DROP FUNCTION public.lf_ig_native_chat_official_writer_binding_receipt_v1(text);
DROP TABLE public.lf_ig_native_chat_nonce_v1;
-- Restore the original canonical normal-step writer exactly; SECURITY INVOKER.
CREATE OR REPLACE FUNCTION public.lf_record_profile_execution_step_v1(
 p_execution_id text,p_step_id text,p_evidence_ref text,
 p_evidence_payload jsonb,p_actor_execution_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog','public'
AS $function$
declare
  v_trust jsonb;
begin
  v_trust:=public.lf_profile_execution_trust_validation_v2(
    p_execution_id,p_step_id,p_evidence_payload
  );

  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'EJECUCION_PERFIL_LF','PERFIL',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    v_trust,true,'lf_record_profile_execution_step_v1'
  );
end
$function$;
REVOKE ALL ON FUNCTION public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)
 TO service_role;
DO $readback$
BEGIN
 IF md5(pg_get_functiondef('public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)'::regprocedure))
    IS DISTINCT FROM '7cf717887006e278356a716f3fd80182'
    OR EXISTS (SELECT 1 FROM pg_proc
      WHERE oid='public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)'::regprocedure
      AND prosecdef)
 THEN RAISE EXCEPTION 'B09_NONCE_ROLLBACK_CANONICAL_PREIMAGE_MD5_DRIFT'; END IF;
END $readback$;
COMMIT;
