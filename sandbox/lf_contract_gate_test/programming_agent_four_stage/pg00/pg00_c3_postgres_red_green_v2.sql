-- Execute only in disposable PostgreSQL 17 after stripping BEGIN/ROLLBACK from candidate DDL.
DO $test$
DECLARE payload jsonb; digest_hex text; got jsonb; failed bool; n int:=0;
BEGIN
 payload:='{"schema_version":"LF_STANDARDS_CATALOG_V1","catalog_version":"0.6.2","status":"CANDIDATO_TEST"}'::jsonb;
 digest_hex:=encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex');
 -- Negative: unknown version
 got:=transversal.fn_lf_programming_std_catalog_readback_v2('99.9.9');
 IF got->>'reason'<>'PG00_C3_RELEASE_NOT_FOUND' THEN RAISE EXCEPTION 'UNKNOWN_VERSION_ACCEPTED'; END IF; n:=n+1;
 -- Negative: corrupt JSON digest
 failed:=false;
 BEGIN
  INSERT INTO transversal.lf_programming_std_catalog_release_v2(catalog_version,source_repo,source_commit_sha,source_path,catalog_json,source_file_sha256,catalog_jsonb_sha256,train_execution_ref)
  VALUES('0.6.2','test/repo',repeat('a',40),'standards/catalog.json',payload,repeat('b',64),repeat('0',64),'SYNTHETIC_NOT_TRAIN');
 EXCEPTION WHEN check_violation THEN failed:=true; END;
 IF NOT failed THEN RAISE EXCEPTION 'CORRUPT_DIGEST_ACCEPTED'; END IF; n:=n+1;
 -- Positive: DB-only synthetic readback
 INSERT INTO transversal.lf_programming_std_catalog_release_v2(catalog_version,source_repo,source_commit_sha,source_path,catalog_json,source_file_sha256,catalog_jsonb_sha256,train_execution_ref)
 VALUES('0.6.2','test/repo',repeat('a',40),'standards/catalog.json',payload,repeat('b',64),digest_hex,'SYNTHETIC_NOT_TRAIN');
 got:=transversal.fn_lf_programming_std_catalog_readback_v2('0.6.2');
 IF got->>'found'<>'true' OR got->>'status'<>'DB_RECORD_ONLY_UNTIL_INDEPENDENT_SOURCE_READBACK' OR got->>'recomputed_jsonb_sha256'<>digest_hex THEN RAISE EXCEPTION 'SYNTHETIC_READBACK_FAILED'; END IF; n:=n+1;
 -- Negative: replay same version
 failed:=false;
 BEGIN
  INSERT INTO transversal.lf_programming_std_catalog_release_v2(catalog_version,source_repo,source_commit_sha,source_path,catalog_json,source_file_sha256,catalog_jsonb_sha256,train_execution_ref)
  VALUES('0.6.2','test/repo',repeat('a',40),'standards/catalog.json',payload,repeat('b',64),digest_hex,'SYNTHETIC_NOT_TRAIN');
 EXCEPTION WHEN OTHERS THEN failed:=true; END;
 IF NOT failed THEN RAISE EXCEPTION 'REPLAY_ACCEPTED'; END IF; n:=n+1;
 -- Negative: downgrade to 0.6.1
 payload:=jsonb_set(payload,'{catalog_version}','"0.6.1"');
 digest_hex:=encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex');
 failed:=false;
 BEGIN
  INSERT INTO transversal.lf_programming_std_catalog_release_v2(catalog_version,source_repo,source_commit_sha,source_path,catalog_json,source_file_sha256,catalog_jsonb_sha256,train_execution_ref)
  VALUES('0.6.1','test/repo',repeat('a',40),'standards/catalog.json',payload,repeat('b',64),digest_hex,'SYNTHETIC_NOT_TRAIN');
 EXCEPTION WHEN OTHERS THEN failed:=true; END;
 IF NOT failed THEN RAISE EXCEPTION 'DOWNGRADE_ACCEPTED'; END IF; n:=n+1;
 -- Negative: post-release tampering
 failed:=false;
 BEGIN
  UPDATE transversal.lf_programming_std_catalog_release_v2 SET source_repo='tampered' WHERE catalog_version='0.6.2';
 EXCEPTION WHEN OTHERS THEN failed:=true; END;
 IF NOT failed THEN RAISE EXCEPTION 'UPDATE_ACCEPTED'; END IF; n:=n+1;
 failed:=false;
 BEGIN
  DELETE FROM transversal.lf_programming_std_catalog_release_v2 WHERE catalog_version='0.6.2';
 EXCEPTION WHEN OTHERS THEN failed:=true; END;
 IF NOT failed THEN RAISE EXCEPTION 'DELETE_ACCEPTED'; END IF; n:=n+1;
 RAISE NOTICE 'PG00_C3_POSTGRES17_RED_GREEN_PASS checks=% DB_ONLY_NOT_SOURCE_VERIFIED',n;
END $test$;
