-- IG Chat9 L2: two source-bound FUNCTIONAL evidence records from a real
-- completed Merge Train and real ephemeral PostgreSQL17 rollback report.
-- No update to lf_ops.reglas; no Step70 promotion; no fabricated receipt.
BEGIN;
DO $ig_chat9_proof$
DECLARE
  v_event_id bigint;
  v_auto jsonb;
  r record;
  v_actual text;
  v_proposal text;
BEGIN
  IF to_regclass('public.lf_ig_functional_train_evidence_v1') IS NULL
     OR (SELECT count(*) FROM public.lf_global_config WHERE scope='CLIENT'
         AND value_status='REAL' AND value_type='INTEGER')<>6
     OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo IN ('REG_SES_003','REG_ATQ_016')
         AND estado='VIGENTE')<>2
     OR EXISTS (SELECT 1 FROM public.lf_ig_functional_train_evidence_v1
                WHERE rule_code IN ('REG_SES_003','REG_ATQ_016'))
  THEN RAISE EXCEPTION 'CHAT9_L2_EVIDENCE_SOURCE_PREIMAGE_DRIFT'; END IF;

  SELECT evt.id INTO v_event_id
  FROM public.lf_operation_execution te
  JOIN public.lf_eventos evt
    ON evt.entidad_codigo=te.execution_id
   AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
   AND evt.origen='lf-migration-merge-train'
  WHERE te.execution_id='EXEC-DB-TRAIN-PR4133-20261118233636-R44422905263'
    AND te.operation_code='ACTUALIZACION_DB_LF'
    AND te.status='COMPLETED'
    AND te.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-44422905263'
    AND te.manifest->>'train_run_id'='44422905263'
    AND te.manifest->>'head_sha'='065efed55f1a6308d8e168db93c10ca4f36c6124'
    AND evt.id=21986
    AND evt.payload#>>'{receipt,train_run_id}'='44422905263'
    AND evt.payload#>>'{receipt,heads,final_head}'='065efed55f1a6308d8e168db93c10ca4f36c6124'
    AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
    AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
    AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
    AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
    AND evt.payload->>'receipt_sha256'='deed1ac765d501214f47b8fadab6a54b78fc987ffc19cfbbdcf1cf6b6cd00188'
    AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')=evt.payload->>'receipt_sha256';
  IF v_event_id IS NULL
  THEN RAISE EXCEPTION 'CHAT9_L2_REAL_TRAIN_COMPLETION_NOT_VERIFIED'; END IF;

  FOR r IN SELECT * FROM (VALUES
    ('REG_ATQ_016','EXEC-PROFILE-GATE2-20142FEB637CF8230EFB86E5',
     'c16436927a07128022e33b932ea8ee6f8e3dc550264b059b8130e56e4ce143c7',
     'b7b4f96167366592d1da5b7ea167f32525d9a7bb91b02d04eadbe1908e422293',
     '37c1394198971e65902d444205dc0cf48a8c839958df53f14fb2db7914b58bae'),
    ('REG_SES_003','EXEC-PROFILE-GATE2-CE703F89151A142D1B6630D8',
     'cd4ddc5dbf5e4dfbf93023bf08df60b870330a29bb79c4fb731b4904c0da7321',
     '93865ab6d1e4c541136cac3f5d2a58b52687cfe2a9aa47290b96ec704a951117',
     '4e03594096ae2eb2f5d986a19e941408f9b0f028ef0207a38788b977dbe8ed66')
   ) AS e(rule_code,parent_run,source_sha,proposal_sha,candidate_sha)
  LOOP
    v_actual:=public.lf_asset_snapshot_sha_v1('REGLA',r.rule_code);
    SELECT encode(extensions.digest(convert_to((s.evidence_payload#>
      '{profile_output,deliverable_created,governed_rule_patch}')::text,'UTF8'),'sha256'),'hex')
    INTO v_proposal
    FROM public.lf_operation_execution_steps s
    WHERE s.execution_id=r.parent_run AND s.step_id='execute_profile'
      AND s.status='STEP_PASS_WITH_EVIDENCE';
    IF v_actual IS DISTINCT FROM r.source_sha
       OR v_proposal IS DISTINCT FROM r.proposal_sha
       OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s
         WHERE s.execution_id=r.parent_run AND s.step_id='output_validate'
           AND s.status='STEP_PASS_WITH_EVIDENCE'
           AND s.evidence_payload->>'output_contract_result'='PASS')
    THEN RAISE EXCEPTION 'CHAT9_L2_EVIDENCE_PARENT_PATCH_SOURCE_DRIFT:%',r.rule_code; END IF;
    INSERT INTO public.lf_ig_functional_train_evidence_v1(
      rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
      train_execution_id,train_run_id,train_event_id,train_head_sha,
      pg_rollback_status,independent_readback_status,functional_checks_status,negative_checks_status,
      pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref
    ) VALUES(
      r.rule_code,r.source_sha,r.proposal_sha,r.candidate_sha,
      'EXEC-DB-TRAIN-PR4133-20261118233636-R44422905263',
      '44422905263',v_event_id,'065efed55f1a6308d8e168db93c10ca4f36c6124',
      'PASS','PASS','PASS','PASS',
      'c2a99e303cc3bbcba548ac6f21d4cf1f219944a30b5bae3b91d44dd610545975',
      '466302b9484f4cb36bf0c785bbf8bf3b29bcccc594daceffb46b689d6ae74045',
      '2f74dc9630cbf4ee6163bab4ea746e4afd774d76bf290cb140975193d4b9eef3',
      'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44422766609/artifacts/14481988842#FUNCTIONAL_RULE_CONTRACT_ONLY'
    );
    v_auto:=public.lf_ig_step70_functional_train_auto_v1(r.parent_run);
    IF v_auto->>'status' IS DISTINCT FROM 'PASS'
       OR v_auto->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
       OR v_auto#>>'{train_evidence,rule_code}' IS DISTINCT FROM r.rule_code
       OR v_auto#>>'{train_evidence,source_snapshot_sha256}' IS DISTINCT FROM r.source_sha
       OR v_auto#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM r.proposal_sha
       OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM r.candidate_sha
    THEN RAISE EXCEPTION 'CHAT9_L2_STEP70_AUTO_NOT_SOURCE_BOUND:%:%',r.rule_code,v_auto->>'blocking_code'; END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.lf_ig_functional_train_evidence_v1
      WHERE rule_code IN ('REG_SES_003','REG_ATQ_016')
        AND pg_rollback_status='PASS' AND independent_readback_status='PASS'
        AND functional_checks_status='PASS' AND negative_checks_status='PASS')<>2
  THEN RAISE EXCEPTION 'CHAT9_L2_EVIDENCE_READBACK_INCOMPLETE'; END IF;
  RAISE NOTICE 'CHAT9_L2_TRAIN_PROOF_BOUND_2_PASS; production_not_authorized; rules_unchanged';
END $ig_chat9_proof$;
COMMIT;
