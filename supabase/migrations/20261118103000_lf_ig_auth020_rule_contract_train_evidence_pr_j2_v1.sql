-- PR-J2: insert ONE source-bound RULE_CONTRACT_LEVEL technical evidence record.
-- The producing Train #4085 is already COMPLETED; event #21937 read back independently.
-- The functional/negative PASS values apply to the SQL rule contract MODEL ONLY;
-- Spring Boot/Cognito login E2E remains NOT_TESTED, production_authorized=false.
-- No AUTH-020 rule UPDATE, no owner decision or profile RUN fabrication.
BEGIN;
DO $pr_j2$
DECLARE v_md5 text; v_source text; v_event_id bigint;
BEGIN
 SELECT md5((to_jsonb(r)-'updated_at')::text),
        public.lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-020')
 INTO v_md5,v_source FROM lf_ops.reglas r
 WHERE codigo='B2B-RULE-AUTH-020' AND estado='VIGENTE';
 IF v_md5 IS DISTINCT FROM '7588d5a7de4d94a864fca9e63cd10ebe'
 OR v_source IS DISTINCT FROM '8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8'
 THEN RAISE EXCEPTION 'PR_J2_AUTH020_SOURCE_DRIFT'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas)<>579
 OR (SELECT count(*) FROM lf_ops.perfiles_permisos WHERE permission_id=38 AND status='VIGENTE')<>0
 OR (SELECT count(*) FROM lf_ops.politicas_seguridad WHERE security_policy_id=20 AND status='CANDIDATO')<>1
 OR (SELECT count(*) FROM public.lf_ig_owner_decision_v2)<>0
 OR (SELECT count(*) FROM public.lf_ig_rule_change_v2)<>0
 THEN RAISE EXCEPTION 'PR_J2_BASELINE_SCOPE_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_ig_functional_train_evidence_v1
           WHERE rule_code='B2B-RULE-AUTH-020')
 THEN RAISE EXCEPTION 'PR_J2_AUTH020_RECEIPT_ALREADY_PRESENT'; END IF;

 SELECT evt.id INTO v_event_id
 FROM public.lf_operation_execution te
 JOIN public.lf_eventos evt
   ON evt.entidad_codigo=te.execution_id
  AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
  AND evt.origen='lf-migration-merge-train'
 WHERE te.execution_id='EXEC-DB-TRAIN-PR4085-20261118100000-R44330090597'
   AND te.operation_code='ACTUALIZACION_DB_LF'
   AND te.status='COMPLETED'
   AND te.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-44330090597'
   AND te.manifest->>'train_run_id'='44330090597'
   AND te.manifest->>'head_sha'='367f5fa03875348cfe0114e24be7e34ded72c761'
   AND evt.id=21937
   AND evt.payload#>>'{receipt,train_run_id}'='44330090597'
   AND evt.payload#>>'{receipt,heads,final_head}'='367f5fa03875348cfe0114e24be7e34ded72c761'
   AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
   AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
   AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
   AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
   AND evt.payload->>'receipt_sha256' ~ '^[0-9a-f]{64}$'
   AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')
       =evt.payload->>'receipt_sha256';
 IF v_event_id IS NULL
 THEN RAISE EXCEPTION 'PR_J2_COMPLETED_TRAIN_SOURCE_OR_RECEIPT_UNVERIFIED'; END IF;

 INSERT INTO public.lf_ig_functional_train_evidence_v1(
  rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
  train_execution_id,train_run_id,train_event_id,train_head_sha,
  pg_rollback_status,independent_readback_status,functional_checks_status,negative_checks_status,
  pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref
 ) VALUES(
  'B2B-RULE-AUTH-020',
  '8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8',
  'adaffe6a15e705fc4ec48fa809135088736915cd0d4446691ede078899704a02',
  '16729473fcfc98cb04a04d2489cfa6338cb59f1c1cace12ce9443a4c24bee061',
  'EXEC-DB-TRAIN-PR4085-20261118100000-R44330090597',
  '44330090597',v_event_id,'367f5fa03875348cfe0114e24be7e34ded72c761',
  'PASS','PASS','PASS','PASS',
  '2595d1a15fe61945ff59e0cd87a32068b1e1e80975e2dd64767b2ba249045ec5',
  'c01aae41970c82bf5dd053e38e12db702c65602b85f063bc185e7dc6e4994362',
  'fb9dc4bd53b8ff63e91edc514b3b5f9111106151976607552b681e8b595aee10',
  'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44329868870/artifacts/14439620038#RULE_CONTRACT_LEVEL'
 );
 IF (SELECT count(*) FROM public.lf_ig_functional_train_evidence_v1
    WHERE rule_code='B2B-RULE-AUTH-020'
      AND proposal_sha256='adaffe6a15e705fc4ec48fa809135088736915cd0d4446691ede078899704a02')<>1
 THEN RAISE EXCEPTION 'PR_J2_RECEIPT_INSERT_READBACK_NOT_ONE'; END IF;
 IF public.lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-020')
 IS DISTINCT FROM '8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8'
 THEN RAISE EXCEPTION 'PR_J2_UNAUTHORIZED_RULE_MUTATION'; END IF;
 RAISE NOTICE 'PR_J2_RULE_CONTRACT_LEVEL_TRAIN_EVIDENCE_INSERT_PASS producing_run=44330090597 event_id=21937 backend_e2e=NOT_TESTED';
END
$pr_j2$;
COMMIT;
