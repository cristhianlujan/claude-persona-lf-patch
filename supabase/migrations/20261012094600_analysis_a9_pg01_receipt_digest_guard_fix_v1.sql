-- Analysis A9 -> PG-01: correct existing exact-receipt guard, no new engine.
-- Replaces only programacion.fn_analysis_pg01_exact_receipt_guard_v1.
-- Expected receipt identity/hash/schema MUST originate from governed A9 handoff,
-- independently of the resolved context. Does not activate PG-01 runtime.
-- Regression: 8/8 positive/negative cases PASS in BEGIN/ROLLBACK against live A9.
CREATE OR REPLACE FUNCTION programacion.fn_analysis_pg01_exact_receipt_guard_v1(p_receipt jsonb, p_expected jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_snapshot jsonb;
  v_digest text;
BEGIN
  v_snapshot := p_receipt->'snapshot';
  IF v_snapshot IS NULL OR jsonb_typeof(v_snapshot) <> 'object' THEN
    RETURN jsonb_build_object('status','BLOCKED','reason','MISSING_SNAPSHOT');
  END IF;
  IF p_expected IS NULL OR jsonb_typeof(p_expected) <> 'object' THEN
    RETURN jsonb_build_object('status','BLOCKED','reason','MISSING_EXPECTED_HANDOFF');
  END IF;
  IF v_snapshot->>'schema_version' IS DISTINCT FROM p_expected->>'schema_version' THEN
    RETURN jsonb_build_object('status','BLOCKED','reason','SCHEMA_MISMATCH');
  END IF;
  v_digest := encode(digest(convert_to(v_snapshot::text,'UTF8'),'sha256'),'hex');
  IF v_digest IS DISTINCT FROM p_receipt->>'snapshot_sha256'
     OR v_digest IS DISTINCT FROM p_expected->>'snapshot_sha256' THEN
    RETURN jsonb_build_object('status','BLOCKED','reason','DIGEST_MISMATCH');
  END IF;
  IF p_receipt->>'receipt_id' IS DISTINCT FROM p_expected->>'receipt_id' THEN
    RETURN jsonb_build_object('status','BLOCKED','reason','RECEIPT_MISMATCH');
  END IF;
  RETURN jsonb_build_object('status','PASS','reason','EXACT_RECEIPT');
END;
$$;