-- Retire the legacy direct-mutation independent review RPC.
-- EKB: INDEPENDENT-REVIEW-LEGACY-RPC-BYPASS-001
-- The canonical path is ACT-0001 -> REVISION_INDEPENDIENTE_ESTRATEGIA_LF
-- -> lf_finalize_qualification_independent_review_v1.

DO $pre$
DECLARE
  legacy_def text;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_registry
    WHERE operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      AND lifecycle_state_code='OP_OPERATIONAL'
  ) THEN
    RAISE EXCEPTION 'LF_LEGACY_INDEPENDENT_REVIEW_RETIRE_CANONICAL_OPERATION_NOT_OPERATIONAL';
  END IF;

  IF to_regprocedure('public.lf_independent_strategy_review_begin_v1(text,uuid,uuid,bigint,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('public.lf_independent_strategy_review_finalize_v1(text)') IS NULL
     OR to_regprocedure('public.lf_finalize_qualification_independent_review_v1(uuid,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'LF_LEGACY_INDEPENDENT_REVIEW_RETIRE_CANONICAL_SURFACE_MISSING';
  END IF;

  SELECT pg_get_functiondef(
    'public.lf_apply_independent_strategy_review_v1(uuid,uuid,uuid,bigint,text,jsonb,text)'::regprocedure
  ) INTO legacy_def;

  IF position('INDEPENDENT_CHAT_CONTEXT' in legacy_def)=0
     OR position('update public.lf_test_runs' in lower(legacy_def))=0
     OR position('update public.lf_qualification_receipts' in lower(legacy_def))=0 THEN
    RAISE EXCEPTION 'LF_LEGACY_INDEPENDENT_REVIEW_RETIRE_EXPECTED_LEGACY_SHAPE_MISSING';
  END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.lf_apply_independent_strategy_review_v1(
  p_qualification_id uuid,
  p_suite_run_id uuid,
  p_test_run_id uuid,
  p_snapshot_id bigint,
  p_expected_revision_sha256 text,
  p_review_receipt jsonb,
  p_actor_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  RAISE EXCEPTION 'LF_INDEPENDENT_REVIEW_LEGACY_RPC_RETIRED: use ACT-0001 -> REVISION_INDEPENDIENTE_ESTRATEGIA_LF';
END
$function$;

REVOKE EXECUTE ON FUNCTION public.lf_apply_independent_strategy_review_v1(uuid,uuid,uuid,bigint,text,jsonb,text)
FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.lf_apply_independent_strategy_review_v1(uuid,uuid,uuid,bigint,text,jsonb,text) IS
'RETIRED fail-closed compatibility tombstone. Direct independent-review mutation is forbidden. Use ACT-0001 -> REVISION_INDEPENDIENTE_ESTRATEGIA_LF; qualification materialization remains owned by lf_finalize_qualification_independent_review_v1.';
