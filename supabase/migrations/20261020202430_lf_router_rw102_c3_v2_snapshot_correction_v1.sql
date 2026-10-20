-- Correct RW1-02_C3 V2 source snapshot to the first commit containing all declared V2 sources.
BEGIN;
DO $rw102_c3_v2_snapshot$
DECLARE
  v_count integer;
BEGIN
  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE id=1612 AND work_item_id=1128 AND checkpoint_code='RW1-02_C3'
        AND status='PENDING' AND evidence_ref IS NULL AND assertion_receipt IS NULL)<>1
  THEN RAISE EXCEPTION 'RW102_C3_V2_SNAPSHOT_LIFECYCLE_DRIFT'; END IF;

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=jsonb_set(
       unit_metadata,
       '{source_pack_v2,checkpoint_inputs,RW1-02_C3,source_snapshot_commit}',
       to_jsonb('469089b796cae8de01c9506c52c9ae9b72d97d0d'::text),
       false
     )
   WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1'
     AND unit_code='RW1-02'
     AND work_item_id=1128
     AND unit_metadata#>>'{action_specs_v1,RW1-02_C3,precision}'='EXACT_RW102_C3_INDEPENDENT_ARCHITECTURE_REVIEW_V2'
     AND unit_metadata#>>'{source_pack_v2,checkpoint_inputs,RW1-02_C3,source_snapshot_commit}'='fa6e679fc3df5ff2f9d67338aec4901a78c023c1'
     AND unit_metadata#>>'{source_pack_v2,checkpoint_inputs,RW1-02_C3,source_git_blobs,handoff}'='aa4654dc81dd156198b7a48afaa88efae8df7913';
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW102_C3_V2_SNAPSHOT_UPDATE_COUNT:%',v_count; END IF;

  IF (SELECT unit_metadata#>>'{source_pack_v2,checkpoint_inputs,RW1-02_C3,source_snapshot_commit}'
      FROM programacion.engineering_plan_units
      WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1' AND unit_code='RW1-02' AND work_item_id=1128)
     IS DISTINCT FROM '469089b796cae8de01c9506c52c9ae9b72d97d0d'
  THEN RAISE EXCEPTION 'RW102_C3_V2_SNAPSHOT_READBACK_FAILED'; END IF;
END
$rw102_c3_v2_snapshot$;
COMMIT;
