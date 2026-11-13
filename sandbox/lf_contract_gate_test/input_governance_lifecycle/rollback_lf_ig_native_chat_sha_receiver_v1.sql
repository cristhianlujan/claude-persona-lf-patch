-- Manual inverse for governed B09 receiver migration only.
-- NOT a forward migration. Fail closed: never erase real evidence or RUNs.
BEGIN;
DO $guard$
BEGIN
 IF to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL
 OR to_regprocedure('public.lf_ig_native_chat_receipt_immutable_guard_v1()') IS NULL
 OR to_regclass('public.lf_ig_native_chat_receipt_v1') IS NULL
 THEN RAISE EXCEPTION 'B09_ROLLBACK_PREIMAGE_MISSING'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_ig_native_chat_receipt_v1)
 THEN RAISE EXCEPTION 'B09_ROLLBACK_NONEMPTY_NO_DATA_LOSS'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger
    WHERE tgrelid='public.lf_ig_native_chat_receipt_v1'::regclass
      AND tgname='lf_ig_native_chat_receipt_no_mutation_v1'
      AND NOT tgisinternal)
 THEN RAISE EXCEPTION 'B09_ROLLBACK_TRIGGER_DRIFT'; END IF;
END $guard$;
DROP FUNCTION public.lf_ig_verified_native_provider_receipt_v1(text);
DROP TABLE public.lf_ig_native_chat_receipt_v1;
DROP FUNCTION public.lf_ig_native_chat_receipt_immutable_guard_v1();
-- Preserve pgcrypto, all existing RUN, Step70, G15 and owner sources.
COMMIT;
