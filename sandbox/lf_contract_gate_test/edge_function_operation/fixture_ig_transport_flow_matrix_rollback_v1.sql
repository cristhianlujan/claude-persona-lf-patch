-- ONLY DISPOSABLE PG17.6/PG18.7 rollback matrix; NOT a deployed application function.
-- Replicates exact JSONB boundary semantics of source-controlled Deno/Python guard.
-- SQL writes are transactional fixture records, never live LF product/IG tables.
BEGIN;
CREATE TEMP TABLE lf_ig_transport_test_receipt
 (case_name text PRIMARY KEY, result jsonb NOT NULL) ON COMMIT DROP;

CREATE OR REPLACE FUNCTION pg_temp.ig_raw_forbidden(node jsonb, path text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE k text; v jsonb; idx integer := 0; hit text;
BEGIN
 IF jsonb_typeof(node)='object' THEN
   FOR k,v IN SELECT key,value FROM jsonb_each(node) LOOP
     IF k IN ('semantic_receipt_sha256','catalog_sha256','request_sha256') THEN
       RETURN path||'.'||k;
     END IF;
     hit:=pg_temp.ig_raw_forbidden(v,path||'.'||k);
     IF hit IS NOT NULL THEN RETURN hit; END IF;
   END LOOP;
 ELSIF jsonb_typeof(node)='array' THEN
   FOR v IN SELECT value FROM jsonb_array_elements(node) LOOP
     hit:=pg_temp.ig_raw_forbidden(v,path||'['||idx||']');
     IF hit IS NOT NULL THEN RETURN hit; END IF;
     idx:=idx+1;
   END LOOP;
 END IF;
 RETURN NULL;
END $fn$;

CREATE OR REPLACE FUNCTION pg_temp.ig_payload_forbidden(node jsonb,path text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE k text;v jsonb;hit text;idx integer:=0;nextpath text;
BEGIN
 IF jsonb_typeof(node)='object' THEN
   FOR k,v IN SELECT key,value FROM jsonb_each(node) LOOP
     nextpath:=CASE WHEN path='' THEN k ELSE path||'.'||k END;
     IF k IN ('raw','RAW','raw_input','raw_output','raw_payload','profile_output') THEN
       IF v='null'::jsonb OR v='{}'::jsonb OR v='[]'::jsonb OR v='""'::jsonb OR v='"{}"'::jsonb THEN
         RETURN nextpath;
       END IF;
       hit:=pg_temp.ig_raw_forbidden(v,nextpath);
     ELSE
       hit:=pg_temp.ig_payload_forbidden(v,nextpath);
     END IF;
     IF hit IS NOT NULL THEN RETURN hit; END IF;
   END LOOP;
 ELSIF jsonb_typeof(node)='array' THEN
   FOR v IN SELECT value FROM jsonb_array_elements(node) LOOP
     hit:=pg_temp.ig_payload_forbidden(v,path||'['||idx||']');
     IF hit IS NOT NULL THEN RETURN hit; END IF;
     idx:=idx+1;
   END LOOP;
 END IF;
 RETURN NULL;
END $fn$;

CREATE OR REPLACE FUNCTION pg_temp.ig_guard(payload jsonb,required text[])
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE k text;v jsonb; bad text;
BEGIN
 IF payload IS NULL OR payload='null'::jsonb OR jsonb_typeof(payload)<>'object'
    OR payload='{}'::jsonb THEN
   RETURN jsonb_build_object('code','FLOW_TRANSPORT_INVALID','field','$','dispatch_allowed',false);
 END IF;
 FOREACH k IN ARRAY required LOOP
   v:=payload->k;
   IF NOT (payload ? k) OR v IS NULL OR v='null'::jsonb
      OR v='{}'::jsonb OR v='[]'::jsonb
      OR (jsonb_typeof(v)='string' AND btrim(v#>>'{}') IN ('','{}')) THEN
     RETURN jsonb_build_object('code','FLOW_TRANSPORT_INVALID','field',k,'dispatch_allowed',false);
   END IF;
 END LOOP;
 bad:=pg_temp.ig_payload_forbidden(payload,'');
 IF bad IS NOT NULL THEN
   RETURN jsonb_build_object('code','FLOW_TRANSPORT_INVALID','field',bad,'dispatch_allowed',false);
 END IF;
 RETURN jsonb_build_object('code','TRANSPORT_PASS','field',null,'dispatch_allowed',true);
END $fn$;

CREATE OR REPLACE FUNCTION pg_temp.ig_flow_or_finding(cause text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
BEGIN
 IF cause IN ('FLOW_CONTRACT_INVALID','FLOW_TRANSPORT_INVALID',
              'FLOW_SOURCE_UNREADABLE','FLOW_AUTHORITY_INVALID') THEN
    RETURN jsonb_build_object('class','BLOCK_FLOW','cause',cause,
      'continuation_allowed',false,'production_authorized',false);
 ELSIF cause IN ('RULE_INCOMPLETE','SKILL_FAILED','IG_CURATOR_PENDING',
                 'VALIDATOR_NOT_READY','HUMAN_DECISION_REQUIRED','CONTENT_TIMEOUT_90S') THEN
    RETURN jsonb_build_object('class','FINDING_CONTENT','cause',cause,
      'continuation_allowed',true,'production_authorized',false);
 END IF;
 RETURN jsonb_build_object('class','BLOCK_FLOW','cause','FLOW_CONTRACT_INVALID',
   'continuation_allowed',false,'production_authorized',false);
END $fn$;

DO $test$
DECLARE field_name text; invalid jsonb; k text; result jsonb; expected text; count_verified integer;
BEGIN
 FOREACH field_name IN ARRAY ARRAY['execution_id','run_id','ticket','consumer','pantalla_id'] LOOP
   FOREACH invalid IN ARRAY ARRAY['null'::jsonb,'""'::jsonb,'"   "'::jsonb,'"{}"'::jsonb,'{}'::jsonb] LOOP
     result:=pg_temp.ig_guard(jsonb_build_object(
       'execution_id','EXEC-VALID','run_id',954,'ticket','valid','consumer','CONTEXT_PACK',
       'pantalla_id',44)::jsonb || jsonb_build_object(field_name,invalid),
       ARRAY['execution_id','run_id','ticket','consumer','pantalla_id']);
     IF result->>'code'<>'FLOW_TRANSPORT_INVALID' OR result->>'field'<>field_name OR
        result->>'dispatch_allowed'<>'false' THEN
       RAISE EXCEPTION 'REQUIRED_NEGATIVE_FAIL:%,%,%',field_name,invalid,result;
     END IF;
     INSERT INTO lf_ig_transport_test_receipt VALUES
       ('required_'||field_name||'_'||md5(invalid::text),result);
   END LOOP;
 END LOOP;
 FOREACH k IN ARRAY ARRAY['semantic_receipt_sha256','catalog_sha256','request_sha256'] LOOP
   FOREACH field_name IN ARRAY ARRAY['raw','RAW','raw_input','raw_output','raw_payload','profile_output'] LOOP
     result:=pg_temp.ig_guard(
       jsonb_build_object('ticket','valid',field_name,jsonb_build_object('nested',jsonb_build_object(k,'forged'))),
       ARRAY['ticket']);
     expected:=field_name||'.nested.'||k;
     IF result->>'code'<>'FLOW_TRANSPORT_INVALID' OR result->>'field'<>expected OR
        result->>'dispatch_allowed'<>'false' THEN
       RAISE EXCEPTION 'RAW_FORBIDDEN_NEGATIVE_FAIL:%,%',expected,result;
     END IF;
     INSERT INTO lf_ig_transport_test_receipt VALUES ('raw_'||field_name||'_'||k,result);
   END LOOP;
   result:=pg_temp.ig_guard(jsonb_build_object('ticket','valid',k,'outer_metadata','raw',jsonb_build_object('literal','source')),ARRAY['ticket']);
   IF result->>'code'<>'TRANSPORT_PASS' OR result->>'dispatch_allowed'<>'true' THEN
     RAISE EXCEPTION 'OUTER_METADATA_FALSE_POSITIVE:%',result;
   END IF;
 END LOOP;
 FOREACH k IN ARRAY ARRAY['FLOW_CONTRACT_INVALID','FLOW_TRANSPORT_INVALID','FLOW_SOURCE_UNREADABLE','FLOW_AUTHORITY_INVALID'] LOOP
   result:=pg_temp.ig_flow_or_finding(k);
   IF result->>'class'<>'BLOCK_FLOW' OR result->>'continuation_allowed'<>'false' OR
      result->>'production_authorized'<>'false' THEN
     RAISE EXCEPTION 'FLOW_CLASSIFICATION_FAIL:%,%',k,result;
   END IF;
   INSERT INTO lf_ig_transport_test_receipt VALUES ('flow_'||k,result);
 END LOOP;
 FOREACH k IN ARRAY ARRAY['RULE_INCOMPLETE','SKILL_FAILED','IG_CURATOR_PENDING','VALIDATOR_NOT_READY','HUMAN_DECISION_REQUIRED','CONTENT_TIMEOUT_90S'] LOOP
   result:=pg_temp.ig_flow_or_finding(k);
   IF result->>'class'<>'FINDING_CONTENT' OR result->>'continuation_allowed'<>'true' OR
      result->>'production_authorized'<>'false' THEN
     RAISE EXCEPTION 'CONTENT_CLASSIFICATION_FAIL:%,%',k,result;
   END IF;
   INSERT INTO lf_ig_transport_test_receipt VALUES ('finding_'||k,result);
 END LOOP;
 SELECT count(*) INTO count_verified FROM lf_ig_transport_test_receipt;
 IF count_verified<>53 THEN RAISE EXCEPTION 'PG_MATRIX_COUNT_WRONG:%',count_verified; END IF;
END $test$;
SELECT 'PASS_PG_IG_GUARD_53_CASES' AS marker,
 count(*) AS cases, count(*) FILTER (WHERE (result->>'dispatch_allowed')='false') AS negative_rejected
FROM lf_ig_transport_test_receipt;
ROLLBACK;
SELECT CASE WHEN to_regclass('pg_temp.lf_ig_transport_test_receipt') IS NULL
 THEN 'PASS_PG_IG_MATRIX_ROLLBACK_CLEAN' ELSE 'FAIL_PG_ROLLBACK_LEAK' END AS rollback_marker;
