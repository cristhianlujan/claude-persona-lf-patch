-- PE10 method 03 only. Source-first Merge Train for replacement RAW provenance; checkpoint NOT closed.
-- Material version of investigation has literal 13 SELECT readbacks, complete JSON, 5/5 ATMS negation/withdrawal tests.
-- No operation activation, no authority grants, no changes to other checkpoints or runtime.
DO $pe10_m03$
DECLARE v_n integer;
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM programacion.engineering_work_items
  WHERE id=1133 AND work_code='PEVO-PE10-METHODS32-P0' AND status='BACKLOG'
 ) OR NOT EXISTS (
  SELECT 1 FROM programacion.engineering_work_checkpoints
  WHERE id=1627 AND work_item_id=1133 AND checkpoint_code='PE10_M03' AND status='PENDING'
    AND evidence_ref='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M03.json#sha256=35c677ff8ba29da910a88b4c2f28fa1905a2723bd9608f60d8405f5eb6d7adea'
    AND assertion_receipt IS NULL AND completed_at IS NULL
 ) OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=1133 AND status='PENDING' AND assertion_receipt IS NULL) <>32
 OR EXISTS (
  SELECT 1 FROM programacion.engineering_work_updates
  WHERE work_item_id=1133 AND summary='PE10_M03 research v2 frozen'
 )
 THEN RAISE EXCEPTION 'PE10_M03_RESEARCH_PRESTATE_DRIFT'; END IF;

 UPDATE programacion.engineering_work_checkpoints
 SET evidence_ref='https://github.com/cristhianlujan/claude-persona-lf-patch/blob/18b4d42cb952c1d0b9f38424040198945c01c710/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M03_RAW_V2.json#git_blob_sha=c6cb821d7e6917a66c0bd657bac1e2ad1b24dab8',
     updated_by_execution_id='PE10_M03_RESEARCH_SOURCE_FIRST_TRAIN'
 WHERE id=1627 AND work_item_id=1133 AND checkpoint_code='PE10_M03'
   AND status='PENDING' AND assertion_receipt IS NULL
   AND evidence_ref='chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M03.json#sha256=35c677ff8ba29da910a88b4c2f28fa1905a2723bd9608f60d8405f5eb6d7adea';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'PE10_M03_RESEARCH_BINDING_ROW_COUNT:%',v_n; END IF;

 INSERT INTO programacion.engineering_work_updates
 (work_item_id,update_type,summary,detail,next_action,evidence_refs,reported_by,observed_at)
 VALUES (
  1133,'DELIVERY','PE10_M03 research v2 frozen',
  'Reinvestigated M03 with 13 literal read-only SQL readbacks, 9 findings and 5/5 ATMS contradiction/withdrawal tests executed; no post-cutoff data promoted to P0. Research artifact is complete as a diagnosis with material unknowns; NOT a governed checkpoint DONE receipt. Git blob c6cb821d7e6917a66c0bd657bac1e2ad1b24dab8.',
  'Closing by canonical transition is blocked while PE10_M01 and PE10_M02 remain PENDING, plan unit is absent, evidence provider absent and close operation candidate/read-only; do not bypass sequencing or activate runtime.',
  jsonb_build_array('https://github.com/cristhianlujan/claude-persona-lf-patch/blob/18b4d42cb952c1d0b9f38424040198945c01c710/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M03_RAW_V2.json','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/02b64d85756dd6a4e6b437e233f6b64f2b866341/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M03_CLOSURE_BLOCKERS_V1.json','chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M03.json#sha256=35c677ff8ba29da910a88b4c2f28fa1905a2723bd9608f60d8405f5eb6d7adea'),
  'PE10_M03_RESEARCH_SOURCE_FIRST_TRAIN',clock_timestamp()
 );
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'PE10_M03_RESEARCH_AUDIT_ROW_COUNT:%',v_n; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND status='PENDING' AND assertion_receipt IS NULL AND completed_at IS NULL)<>32
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND checkpoint_code='PE10_M03'
     AND evidence_ref LIKE '%PE10_M03_RAW_V2.json#git_blob_sha=%')<>1
 OR (SELECT count(*) FROM programacion.engineering_work_updates
     WHERE work_item_id=1133 AND summary='PE10_M03 research v2 frozen')<>1
 THEN RAISE EXCEPTION 'PE10_M03_RESEARCH_POSTSTATE_MISMATCH'; END IF;
END $pe10_m03$;
