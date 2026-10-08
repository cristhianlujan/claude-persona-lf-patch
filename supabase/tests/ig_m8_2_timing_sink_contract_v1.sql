-- Contract-only temporary regression: no real receipt is forged, no channel token bypass.
-- Execute against sandbox after the M8.2 merged migration.
do $ig_m82_test$
declare
  v_payload jsonb;
  v_rejected integer := 0;
  v_n integer;
begin
  create temporary table ig_m82_timing_probe
    (like programacion.provenance_receipts including constraints)
    on commit drop;

  v_payload := jsonb_build_object(
    'schema_version','IG_PERFORMANCE_TIMING_RECEIPT_V1',
    'verification_status','VERIFIED',
    'verifier_identity','TEST_ONLY_NO_ISSUER_CREDENTIAL',
    'subject_type','IG_PERFORMANCE_TIMING',
    'subject_ref','input-readiness-run:525',
    'subject_sha256',repeat('b',64),
    'head_sha',repeat('a',40),
    'run_id','525',
    'source_snapshot_sha256',repeat('c',64),
    'measurement_method','CLOCK_TIMESTAMP_OBSERVED',
    'phase','CURATOR',
    'elapsed_ms',120,
    'measurement_ref','test://rollback-only/measured-duration',
    'measured_at','2026-10-08T19:00:00Z',
    'semantic_sha_excluded',true);

  insert into pg_temp.ig_m82_timing_probe(
    id,receipt_kind,execution_id,head_sha,subject_type,subject_ref,
    subject_sha256,issuer_channel,issuer_identity,verification_ref,payload,
    receipt_sha256,created_at
  ) values (
    1,'EVIDENCE_VERIFICATION',null,repeat('a',40),
    'IG_PERFORMANCE_TIMING','input-readiness-run:525',repeat('b',64),
    'EVIDENCE_VERIFIER_V1','TEST_ONLY','test://contract-only',v_payload,
    repeat('d',64),clock_timestamp());

  select count(*) into v_n from pg_temp.ig_m82_timing_probe;
  if v_n <> 1 then raise exception 'FAIL_IG_M82_VALID_SHAPE_NOT_ACCEPTED'; end if;

  begin
    insert into pg_temp.ig_m82_timing_probe(
      id,receipt_kind,head_sha,subject_type,subject_ref,
      subject_sha256,issuer_channel,issuer_identity,verification_ref,payload,
      receipt_sha256,created_at
    ) values (
      2,'EVIDENCE_VERIFICATION',repeat('a',40),'IG_PERFORMANCE_TIMING',
      'input-readiness-run:525',repeat('b',64),'EVIDENCE_VERIFIER_V1',
      'TEST_ONLY','test://negative-time',
      v_payload||jsonb_build_object('elapsed_ms',-9),
      repeat('e',64),clock_timestamp());
    raise exception 'FAIL_NEGATIVE_DURATION_ACCEPTED';
  exception when check_violation then
    v_rejected := v_rejected+1;
  end;

  begin
    insert into pg_temp.ig_m82_timing_probe(
      id,receipt_kind,head_sha,subject_type,subject_ref,
      subject_sha256,issuer_channel,issuer_identity,verification_ref,payload,
      receipt_sha256,created_at
    ) values (
      3,'EVIDENCE_VERIFICATION',repeat('a',40),'IG_PERFORMANCE_TIMING',
      'input-readiness-run:525',repeat('b',64),'EVIDENCE_VERIFIER_V1',
      'TEST_ONLY','test://missing-source-sha',
      v_payload - 'source_snapshot_sha256',
      repeat('f',64),clock_timestamp());
    raise exception 'FAIL_MISSING_SHA_ACCEPTED';
  exception when check_violation then
    v_rejected := v_rejected+1;
  end;

  begin
    insert into pg_temp.ig_m82_timing_probe(
      id,receipt_kind,head_sha,subject_type,subject_ref,
      subject_sha256,issuer_channel,issuer_identity,verification_ref,payload,
      receipt_sha256,created_at
    ) values (
      4,'EVIDENCE_VERIFICATION',repeat('a',40),'IG_PERFORMANCE_TIMING',
      'input-readiness-run:525',repeat('b',64),'CI_VERIFIER_V1',
      'TEST_ONLY','test://wrong-channel',
      v_payload,repeat('1',64),clock_timestamp());
    raise exception 'FAIL_WRONG_CHANNEL_ACCEPTED';
  exception when check_violation then
    v_rejected := v_rejected+1;
  end;

  if v_rejected <> 3 then
    raise exception 'FAIL_IG_M82_NEGATIVES:%',v_rejected;
  end if;

  if exists (select 1 from programacion.provenance_receipts where subject_type='IG_PERFORMANCE_TIMING') then
    raise exception 'FAIL_TEST_CREATED_REAL_TIMING_RECEIPT';
  end if;

  raise notice 'PASS IG M8.2 shape: positive 1/1, negative 3/3; no real receipt created';
end;
$ig_m82_test$;
