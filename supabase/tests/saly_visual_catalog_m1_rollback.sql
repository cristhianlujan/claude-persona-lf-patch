-- Manual/PG17 test AFTER the M1 schema migration, never as an activation.
-- Execute as migration tester/privileged role. Every data write is ROLLED BACK.
BEGIN;
DO $tests$
DECLARE
  v_standard bigint;
  v_ver bigint;
  v_ok boolean;
BEGIN
  INSERT INTO visual.standards(standard_code,kind)
  VALUES ('SALY_SCREEN_TEST_ONLY','APP_SCREEN') RETURNING id INTO v_standard;
  INSERT INTO visual.standard_versions(standard_id,kind,version,manifest_json,state)
  VALUES (v_standard,'APP_SCREEN','0.1-test','{"test_only":true}'::jsonb,'CANDIDATE')
  RETURNING id INTO v_ver;
  IF NOT EXISTS(
    SELECT 1 FROM visual.standard_versions v
    WHERE v.id=v_ver AND v.manifest_sha256 ~ '^[a-f0-9]{64}$'
  ) THEN RAISE EXCEPTION 'TEST_HASH_NOT_GENERATED'; END IF;

  -- Activation must reject CANDIDATE, even with a valid approval_ref field.
  v_ok:=false;
  BEGIN
    INSERT INTO visual.standard_activations(
      kind,channel_code,audience_code,device_class,output_target,
      standard_version_id,valid_from,approval_ref)
    VALUES ('APP_SCREEN','PRODUCTO','ALL','ANDROID','IMAGE',v_ver,
            now(),'TEST_REF_MUST_ROLLBACK');
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='VISUAL_STANDARD_ACTIVATION_UNAPPROVED_VERSION' THEN
      v_ok:=true;
    ELSE RAISE; END IF;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TEST_CANDIDATE_ACTIVATION_ACCEPTED'; END IF;

  -- No cross-brand contamination.
  v_ok:=false;
  BEGIN
    INSERT INTO visual.standards(brand_code,standard_code,kind)
    VALUES ('LF','LF_NOT_ALLOWED_TEST','APP_SCREEN');
  EXCEPTION WHEN check_violation THEN v_ok:=true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TEST_LF_BRAND_ALLOWED'; END IF;

  -- Approved sources require independent SHA.
  v_ok:=false;
  BEGIN
    INSERT INTO visual.source_assets(
      asset_code,version_number,source_kind,provider,file_ref,
      approval_status,approval_ref)
    VALUES ('SALY_TEST_SCREEN',1,'SCREEN','GOOGLE_DRIVE',
            'FIXTURE_NOT_A_REAL_DRIVE_FILE','APPROVED','TEST_ONLY');
  EXCEPTION WHEN check_violation THEN v_ok:=true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TEST_UNVERIFIED_SCREEN_APPROVED'; END IF;

  -- Histories cannot silently mutate or be deleted.
  v_ok:=false;
  BEGIN
    UPDATE visual.standard_versions SET manifest_json='{"different":true}'::jsonb
    WHERE id=v_ver;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='VISUAL_STANDARD_VERSION_MANIFEST_IMMUTABLE' THEN v_ok:=true;
    ELSE RAISE; END IF;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TEST_VERSION_HISTORY_MUTABLE'; END IF;

  -- Independent active release needs CANDIDATE→APPROVED with evidence.
  UPDATE visual.standard_versions
    SET state='APPROVED',approval_ref='TEST_REF_MUST_ROLLBACK'
  WHERE id=v_ver;
  INSERT INTO visual.standard_activations(
    kind,channel_code,audience_code,device_class,output_target,
    standard_version_id,valid_from,valid_to,approval_ref)
  VALUES ('APP_SCREEN','PRODUCTO','ALL','ANDROID','IMAGE',v_ver,
          now(),now()+interval '1 hour','TEST_REF_MUST_ROLLBACK');

  v_ok:=false;
  BEGIN
    INSERT INTO visual.standard_activations(
      kind,channel_code,audience_code,device_class,output_target,
      standard_version_id,valid_from,valid_to,approval_ref)
    VALUES ('APP_SCREEN','PRODUCTO','ALL','ANDROID','IMAGE',v_ver,
            now()+interval '1 minute',now()+interval '2 hours','TEST_REF_MUST_ROLLBACK');
  EXCEPTION WHEN exclusion_violation THEN v_ok:=true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TEST_OVERLAPPING_ACTIVATIONS_ALLOWED'; END IF;

  -- Completed receipts must carry QA, output digest and approval.
  v_ok:=false;
  BEGIN
    INSERT INTO visual.generation_receipts(request_ref,mode,state,qa_status)
    VALUES ('FIXTURE_NO_REAL_RUN','OFFICIAL','APPROVED','PASS');
  EXCEPTION WHEN check_violation THEN v_ok:=true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TEST_UNVERIFIED_RENDER_APPROVED'; END IF;

  RAISE NOTICE 'SALY_VISUAL_M1_NEGATIVE_TESTS_PASS_ROLLBACK_REQUIRED';
END
$tests$;
ROLLBACK;
-- Independent verification after rollback: all five tables must have 0 rows
-- on initial deployment; run the real SELECT readback separately.
