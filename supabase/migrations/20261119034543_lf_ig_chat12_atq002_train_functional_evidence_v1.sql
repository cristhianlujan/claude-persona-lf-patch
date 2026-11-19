-- IG Chat12 | ATQ002 FUNCTIONAL Train evidence sourced from real PG17
-- PR4162 Train run 44453107449, event22021 + artifact 14496053343.
-- Artifact readback: real PG17 17.12 10/10 PASS, BEGIN/ROLLBACK,
-- separate SELECT after rollback, negative source drift/missing config,
-- backend E2E NOT_TESTED, owner_decide NOT_CALLED.
-- Hashes: report bytes sha256; normalized readback and manifest hashes
-- are SHA256 of actual artifact's JSON canonicalized sort_keys/separators.
-- Only evidence insert; no profile step or rule mutation.
BEGIN;
DO $chat12_train_proof$
DECLARE
 v_parent constant text:='EXEC-PROFILE-GATE2-5F8B40E1F29B23126EB8B797';
 v_rule constant text:='REG_ATQ_002';
 v_src constant text:='cc10104d94ad195f133998934d8af2efeb3f03a59a837777a6bef7f007182765';
 v_proposal constant text:='293ae9e3847b7ba9b3253f09289c27f2d62dadeae2f8f02ff80e430553e80488';
 v_candidate constant text:='813f429c1aa339c651715975d551c338cfa0edd3dd568142567fd835954847e4';
 v_train constant text:='EXEC-DB-TRAIN-PR4162-20261119034114-R44453107449';
 v_train_run constant text:='44453107449';
 v_head constant text:='e0009fe5d99b0c5b555b6a7e9e96642698abcf0a';
 v_event_id constant bigint:=22021;
 v_sha text; v_auto jsonb;
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_ig_functional_train_evidence_v1
            WHERE rule_code=v_rule AND proposal_sha256=v_proposal)
    OR public.lf_asset_snapshot_sha_v1('REGLA',v_rule) IS DISTINCT FROM v_src
    OR NOT EXISTS (
     SELECT 1 FROM public.lf_operation_execution e
     JOIN public.lf_operation_execution_steps s ON s.execution_id=e.execution_id
     WHERE e.execution_id=v_parent AND e.operation_code='EJECUCION_PERFIL_LF'
       AND e.status='IN_PROGRESS' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
       AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE'
       AND s.evidence_payload->>'output_contract_result'='PASS')
 THEN RAISE EXCEPTION 'CHAT12_ATQ002_EVIDENCE_PARENT_OR_SOURCE_DRIFT'; END IF;
 SELECT encode(extensions.digest(convert_to((
  s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}')::text,'UTF8'),'sha256'),'hex')
 INTO v_sha FROM public.lf_operation_execution_steps s
 WHERE s.execution_id=v_parent AND s.step_id='execute_profile'
   AND s.status='STEP_PASS_WITH_EVIDENCE';
 IF v_sha IS DISTINCT FROM v_proposal THEN
  RAISE EXCEPTION 'CHAT12_ATQ002_PROPOSAL_SHA_DRIFT'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.lf_operation_execution te
   JOIN public.lf_eventos evt ON evt.entidad_codigo=te.execution_id
      AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
      AND evt.origen='lf-migration-merge-train'
   WHERE te.execution_id=v_train AND te.operation_code='ACTUALIZACION_DB_LF'
     AND te.status='COMPLETED'
     AND te.manifest->>'train_run_id'=v_train_run
     AND te.manifest->>'head_sha'=v_head
     AND te.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-'||v_train_run
     AND evt.id=v_event_id
     AND evt.payload#>>'{receipt,train_run_id}'=v_train_run
     AND evt.payload#>>'{receipt,heads,final_head}'=v_head
     AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
     AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
     AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
     AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
     AND evt.payload->>'receipt_sha256'=
       '228ba5501b975a8f5273fcaf29dd6f4b3ba22980cffc12677a72b1c1a774b200'
     AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')=evt.payload->>'receipt_sha256'
 ) THEN RAISE EXCEPTION 'CHAT12_ATQ002_REAL_TRAIN_RECEIPT_UNVERIFIED'; END IF;
 INSERT INTO public.lf_ig_functional_train_evidence_v1 (
  rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
  train_execution_id,train_run_id,train_event_id,train_head_sha,
  pg_rollback_status,independent_readback_status,functional_checks_status,negative_checks_status,
  pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref)
 VALUES (
  v_rule,v_src,v_proposal,v_candidate,v_train,v_train_run,v_event_id,v_head,
  'PASS','PASS','PASS','PASS',
  '7cac2f8b3c3ca92bed84afaaf34a23ea294245831283329c12d32c5eeca33786',
  '994252426a3ff3d2b4b9df41720c707575b1096079b508c703a19ccfa91d2795',
  '77160ad643d1c223f15addd68258e9388202f98776a7e55ea94c6cddfdcad043',
  'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44452921378/artifacts/14496053343#RULE_CONTRACT_LEVEL');
 v_auto:=public.lf_ig_step70_functional_train_auto_v1(v_parent);
 IF v_auto->>'status' IS DISTINCT FROM 'PASS'
    OR v_auto->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
    OR v_auto#>>'{train_evidence,rule_code}' IS DISTINCT FROM v_rule
    OR v_auto#>>'{train_evidence,source_snapshot_sha256}' IS DISTINCT FROM v_src
    OR v_auto#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM v_proposal
    OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM v_candidate
 THEN RAISE EXCEPTION 'CHAT12_ATQ002_STEP70_AUTO_INVALID:%',v_auto->>'blocking_code'; END IF;
 IF (SELECT count(*) FROM public.lf_ig_functional_train_evidence_v1
     WHERE rule_code=v_rule AND source_snapshot_sha256=v_src
       AND proposal_sha256=v_proposal AND candidate_snapshot_sha256=v_candidate
       AND train_run_id=v_train_run AND pg_rollback_status='PASS'
       AND independent_readback_status='PASS'
       AND functional_checks_status='PASS' AND negative_checks_status='PASS')<>1
 THEN RAISE EXCEPTION 'CHAT12_ATQ002_EVIDENCE_INSERT_READBACK_MISSING'; END IF;
 RAISE NOTICE 'CHAT12_ATQ002_REAL_TRAIN_SOURCE_BOUND_READY_FOR_STEP70; RULE_UNTOUCHED';
END $chat12_train_proof$;
COMMIT;
