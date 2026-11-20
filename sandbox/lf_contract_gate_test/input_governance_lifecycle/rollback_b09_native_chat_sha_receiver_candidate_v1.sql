-- CANDIDATE_ONLY / disposable PG only. Fail closed if data remains.
BEGIN;
DO $guard$
BEGIN
 IF to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL
 OR to_regclass('public.lf_ig_native_chat_e2e_receipt_candidate_v1') IS NULL
 THEN RAISE EXCEPTION 'B09_CANDIDATE_ROLLBACK_PREIMAGE_MISSING'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_ig_native_chat_e2e_receipt_candidate_v1)
 THEN RAISE EXCEPTION 'B09_CANDIDATE_ROLLBACK_NONEMPTY_DATA'; END IF;
END $guard$;
DROP FUNCTION public.lf_ig_verified_native_provider_receipt_v1(text);
DROP TABLE public.lf_ig_native_chat_e2e_receipt_candidate_v1;
-- pgcrypto is retained as shared infrastructure; never DROP EXTENSION.
COMMIT;
