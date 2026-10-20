-- RW1-01_C3 V3 supplemental evidence reconciliation.
-- Preserves the historical V2 assertion receipt and DONE lifecycle unchanged.
BEGIN;
DO $rw101_c3_v3_evidence$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-01';
  v_work_item constant bigint := 1127;
  v_cp constant text := 'RW1-01_C3';
  v_actor constant text := 'LF_ROUTER_RW101_C3_V3_EVIDENCE_RECONCILIATION_20261020';
  v_ev jsonb := $evidence$
  {
    "schema_version":"RW101_C3_V3_SUPPLEMENTAL_FUNCTIONAL_EVIDENCE_V1",
    "source_freeze_main_sha":"59e611a2b27edd35006c4bfe24bcb4cbb04537e3",
    "github_run_id":"39487232512",
    "github_job_id":"118850694844",
    "functional_verdict":"PASS",
    "public_v2_self_test":"PASS",
    "v3_self_test":"PASS",
    "holdout_good_total":12,
    "holdout_good_accepted":12,
    "holdout_bad_total":26,
    "holdout_bad_rejected":26,
    "novel_falsifiers_total":2,
    "novel_falsifiers_rejected":2,
    "holdout_commitment_sha256":"56a033eca65e0e5766a4bbfc0589ad0d87602780205ecedceb166c942837745a",
    "holdout_manifest_sha256":"e439f1c87d3b284c401b44d6add822d290b1bb546d1b321f9639c3186a2d4057",
    "raw1_sha256":"38f3d0bc8b8739153b3969b569c2d3b5e8f794bb4b8d1103cf90ae13e21d0144",
    "artifact_id":"12294310938",
    "artifact_zip_sha256":"4d87b5e16d0465a9d92eb2b28c57bd4fdd268b5f5d9337dde125e0baccb77a9c",
    "scope":"LOCAL_ACCEPTANCE_CONTRACT_FUNCTIONAL_EVIDENCE_ONLY_NOT_ROUTER_RUNTIME",
    "independent_judge_attested":false,
    "no_router_runtime_claim":true,
    "no_production_mutation":true,
    "recorded_by":"LF_ROUTER_RW101_C3_V3_EVIDENCE_RECONCILIATION_20261020"
  }
  $evidence$::jsonb;
  v_old jsonb;
  v_new jsonb;
  v_supp jsonb;
  v_count integer;
BEGIN
  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit
    AND work_item_id=v_work_item AND disposition='ASSIGNED'
  FOR UPDATE;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE id=1609 AND work_item_id=v_work_item AND checkpoint_code=v_cp
        AND status='DONE'
        AND evidence_ref='github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_01_C3_INDEPENDENT_VERDICT_V2.json'
        AND assertion_receipt_sha256='b396d871a13c5a72caf02f9b2e2084c6e483fe75013ffa079dec93e72880c6d5'
        AND assertion_receipt->>'passed'='true')<>1
  THEN RAISE EXCEPTION 'RW101_C3_V3_HISTORICAL_ASSERTION_DRIFT'; END IF;

  IF v_old#>'{supplemental_evidence_v1,RW1-01_C3_V3}' IS NOT NULL
  THEN RAISE EXCEPTION 'RW101_C3_V3_EVIDENCE_ALREADY_RECORDED'; END IF;

  v_supp:=coalesce(v_old->'supplemental_evidence_v1','{}'::jsonb)
          || jsonb_build_object('RW1-01_C3_V3',v_ev);
  v_new:=jsonb_set(v_old,ARRAY['supplemental_evidence_v1'],v_supp,true);

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit
     AND work_item_id=v_work_item AND unit_metadata=v_old;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW101_C3_V3_EVIDENCE_UPDATE_COUNT:%',v_count; END IF;

  IF (SELECT unit_metadata#>'{supplemental_evidence_v1,RW1-01_C3_V3}'
      FROM programacion.engineering_plan_units
      WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_work_item)
      IS DISTINCT FROM v_ev
  THEN RAISE EXCEPTION 'RW101_C3_V3_EVIDENCE_READBACK_FAILED'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE id=1609 AND status='DONE'
        AND assertion_receipt_sha256='b396d871a13c5a72caf02f9b2e2084c6e483fe75013ffa079dec93e72880c6d5')<>1
  THEN RAISE EXCEPTION 'RW101_C3_V3_HISTORICAL_RECEIPT_CHANGED'; END IF;
END
$rw101_c3_v3_evidence$;
COMMIT;
