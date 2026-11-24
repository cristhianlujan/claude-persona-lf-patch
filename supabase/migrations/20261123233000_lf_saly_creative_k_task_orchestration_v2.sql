-- SALY K01-K06: task-aware selector successor, one persisted selection,
-- one result per K per object, independent plan QA.
-- CANDIDATE; never deploy before owner review. No writes to existing SALY records.
BEGIN;

CREATE TABLE saly.creative_task_selection_v2 (
 item_id bigint PRIMARY KEY REFERENCES saly.creative_order_items(id) ON DELETE RESTRICT,
 task text NOT NULL,
 spatial_change boolean NOT NULL,
 selection_json jsonb NOT NULL,
 selection_sha256 text NOT NULL CHECK(selection_sha256 ~ '^[0-9a-f]{64}$'),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX creative_task_selection_item_sha256_uk_v2 ON saly.creative_task_selection_v2(item_id,selection_sha256);
CREATE TABLE saly.creative_k_results_v2 (
 item_id bigint NOT NULL REFERENCES saly.creative_order_items(id) ON DELETE RESTRICT,
 object_kind text NOT NULL CHECK(object_kind IN ('PLAN','IMAGE')),
 object_sha256 text NOT NULL CHECK(object_sha256 ~ '^[0-9a-f]{64}$'),
 module_code text NOT NULL CHECK(module_code IN ('K01','K02','K03','K04','K05','K06')),
 decision text NOT NULL CHECK(decision IN ('EJECUTADO','OMITIDO')),
 step text NOT NULL,
 reason text,
 evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
 output jsonb NOT NULL DEFAULT '{}'::jsonb,
 selection_sha256 text NOT NULL,
 FOREIGN KEY(item_id,selection_sha256) REFERENCES saly.creative_task_selection_v2(item_id,selection_sha256) DEFERRABLE INITIALLY IMMEDIATE,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(item_id,object_kind,object_sha256,module_code)
);
CREATE TABLE saly.creative_plan_pre_qa_v2 (
 item_id bigint NOT NULL REFERENCES saly.creative_order_items(id) ON DELETE RESTRICT,
 plan_sha256 text NOT NULL CHECK(plan_sha256 ~ '^[0-9a-f]{64}$'),
 plan_json jsonb NOT NULL,
 author_uid uuid NOT NULL,
 verdict text NOT NULL DEFAULT 'PENDING' CHECK(verdict IN ('PENDING','PASS','FAIL','NO_EVALUADO')),
 reviewer_uid uuid,
 review_json jsonb,
 created_at timestamptz NOT NULL DEFAULT now(),
 reviewed_at timestamptz,
 PRIMARY KEY(item_id,plan_sha256),
 CHECK((verdict='PENDING' AND reviewer_uid IS NULL AND review_json IS NULL AND reviewed_at IS NULL)
    OR (verdict<>'PENDING' AND reviewer_uid IS NOT NULL AND review_json IS NOT NULL AND reviewed_at IS NOT NULL))
);
REVOKE ALL ON saly.creative_task_selection_v2,saly.creative_k_results_v2,saly.creative_plan_pre_qa_v2
FROM PUBLIC,anon,authenticated,service_role;

-- The sole K selection intelligence reuses original live document validation.
-- NEW_SCREEN/EXPLORE map to existing NEW_DESIGN dense=true, thus all K.
-- Local spatial correction maps to existing AUDIT related=[K04,K05].
-- Numeric/local chat/nonspatial corrections map to existing LOCAL_CORRECTION.
CREATE FUNCTION visual.knowledge_select_task_v2(
 p_business text,p_task text,p_spatial_change boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','visual','saly','extensions','pg_temp'
AS $f$
DECLARE
 v_legacy_task text;
 v_dense boolean:=false;
 v_related jsonb:='[]'::jsonb;
 v_required text[];
 v_pins jsonb;
 v_review jsonb;
 v_decisions jsonb;
 v_module text;
BEGIN
 IF p_business IS DISTINCT FROM 'SALY' OR p_task IS NULL
   OR p_spatial_change IS NULL THEN RAISE EXCEPTION 'SALY_K_TASK_INVALID'; END IF;
 CASE p_task
 WHEN 'NEW_SCREEN','EXPLORE_CREATIVE' THEN
   v_legacy_task:='NEW_DESIGN';v_dense:=true;
   v_required:=ARRAY['K01','K02','K03','K04','K05','K06'];
 WHEN 'LOCAL_CORRECTION' THEN
   IF p_spatial_change THEN
     v_legacy_task:='AUDIT';v_related:='["K04","K05"]'::jsonb;
     v_required:=ARRAY['K04','K05','K06'];
   ELSE
     v_legacy_task:='LOCAL_CORRECTION';
     v_required:=ARRAY['K05','K06'];
   END IF;
 WHEN 'LOCAL_CHAT','NUMERIC_ADJUST' THEN
   IF p_spatial_change THEN RAISE EXCEPTION 'SALY_K_SPATIAL_SCOPE_INVALID'; END IF;
   v_legacy_task:='LOCAL_CORRECTION';
   v_required:=ARRAY['K05','K06'];
 ELSE RAISE EXCEPTION 'SALY_K_TASK_UNSUPPORTED: %',p_task;
 END CASE;
 SELECT jsonb_agg(jsonb_build_object('module_code',v.module_code,
   'version',v.version,'sha256',v.document_sha256) ORDER BY v.module_code)
 INTO v_pins
 FROM visual.knowledge_module_versions v
 WHERE v.business_code='SALY' AND v.state='CANDIDATE'
 AND v.module_code=ANY(v_required);
 IF jsonb_array_length(COALESCE(v_pins,'[]'::jsonb))<>cardinality(v_required)
 THEN RAISE EXCEPTION 'SALY_K_MODULE_SOURCE_INCOMPLETE'; END IF;
 -- Existing selector verifies document bytes, hashes and evidence pins.
 v_review:=visual.knowledge_select_review_v1('SALY','REVIEW_ONLY',
   jsonb_build_object('task',v_legacy_task,'dense',v_dense,'related_modules',v_related),
   v_pins);
 IF v_review->>'status' IS DISTINCT FROM 'CANDIDATE_REVIEW_ONLY'
 OR jsonb_array_length(v_review->'modules')<>cardinality(v_required)
 THEN RAISE EXCEPTION 'SALY_K_LEGACY_SELECTION_DRIFT'; END IF;
 SELECT jsonb_agg(jsonb_build_object(
   'module_code',k,
   'decision',CASE WHEN k=ANY(v_required) THEN 'EJECUTAR' ELSE 'OMITIDO' END,
   'reason',CASE WHEN k=ANY(v_required) THEN NULL
     ELSE CASE WHEN k IN ('K01','K02') THEN 'TAREA_LOCAL_SIN_REDISENO'
               WHEN k IN ('K03','K04') THEN 'TAREA_NO_REQUIERE_RECOMPOSICION'
               ELSE 'NO_APLICA_AL_TIPO_DE_TAREA' END END,
   'owner_step',CASE WHEN k IN ('K01','K02') THEN '5'
                     WHEN k IN ('K03','K04') THEN '6'
                     WHEN k='K05' THEN '7' ELSE '8_PLAN_11_IMAGE' END)
   ORDER BY k) INTO v_decisions
 FROM unnest(ARRAY['K01','K02','K03','K04','K05','K06']) AS m(k);
 RETURN jsonb_build_object(
   'schema_version','SALY_K_TASK_SELECTION_V2',
   'source','visual.knowledge_select_review_v1',
   'task',p_task,'spatial_change',p_spatial_change,
   'decisions',v_decisions,'modules',v_review->'modules',
   'pins',v_pins,'mode','CANDIDATE_REVIEW_ONLY',
   'render_authorized',false);
END $f$;

-- Once per item: subsequent steps read the saved selector output.
CREATE FUNCTION saly.creative_task_select_once_v2(
 p_item_id bigint,p_task text,p_spatial_change boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','saly','visual','extensions','pg_temp'
AS $f$
DECLARE v_row saly.creative_task_selection_v2%ROWTYPE;v_j jsonb;
BEGIN
 IF p_item_id IS NULL OR p_item_id<1 OR
 NOT EXISTS(SELECT 1 FROM saly.creative_order_items WHERE id=p_item_id)
 THEN RAISE EXCEPTION 'SALY_K_ITEM_INVALID'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:k:select:'||p_item_id::text,0));
 SELECT * INTO v_row FROM saly.creative_task_selection_v2 WHERE item_id=p_item_id;
 IF FOUND THEN
   IF v_row.task IS DISTINCT FROM p_task
     OR v_row.spatial_change IS DISTINCT FROM p_spatial_change
   THEN RAISE EXCEPTION 'SALY_K_SELECTION_ALREADY_FIXED'; END IF;
   RETURN v_row.selection_json;
 END IF;
 v_j:=visual.knowledge_select_task_v2('SALY',p_task,p_spatial_change);
 INSERT INTO saly.creative_task_selection_v2(
    item_id,task,spatial_change,selection_json,selection_sha256)
 VALUES(p_item_id,p_task,p_spatial_change,v_j,
    encode(extensions.digest(v_j::text,'sha256'),'hex'));
 RETURN v_j;
END $f$;

-- Store real K results once; omitted K gets explicit typed reason.
-- A second evaluation on the same object is rejected (including concurrent retries).
CREATE FUNCTION saly.creative_k_record_once_v2(
 p_item_id bigint,p_object_kind text,p_object_sha256 text,p_module_code text,
 p_decision text,p_step text,p_evidence jsonb,p_output jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','saly','visual','extensions','pg_temp'
AS $f$
DECLARE v_selection saly.creative_task_selection_v2%ROWTYPE;
 v_decision jsonb;v_expected text;v_reason text;v_owner text;
BEGIN
 SELECT * INTO STRICT v_selection FROM saly.creative_task_selection_v2
 WHERE item_id=p_item_id;
 SELECT x INTO v_decision FROM jsonb_array_elements(v_selection.selection_json->'decisions') x
 WHERE x->>'module_code'=p_module_code;
 IF v_decision IS NULL OR p_object_sha256 !~ '^[0-9a-f]{64}$'
 OR p_object_kind NOT IN ('PLAN','IMAGE')
 OR jsonb_typeof(p_evidence) IS DISTINCT FROM 'object'
 OR jsonb_typeof(p_output) IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'SALY_K_RECORD_INVALID'; END IF;
 v_expected:=v_decision->>'decision';v_reason:=v_decision->>'reason';
 v_owner:=v_decision->>'owner_step';
 IF p_object_kind='IMAGE' THEN
   IF p_module_code<>'K06' OR p_decision<>'EJECUTADO' OR p_step<>'11'
   THEN RAISE EXCEPTION 'SALY_K_WRONG_OBJECT_OWNER'; END IF;
 ELSIF v_expected='OMITIDO' THEN
   IF p_decision<>'OMITIDO' OR p_step<>'2'
   THEN RAISE EXCEPTION 'SALY_K_SKIP_MISMATCH'; END IF;
 ELSE
   IF p_decision<>'EJECUTADO'
   OR p_step IS DISTINCT FROM CASE p_module_code WHEN 'K06' THEN '8' ELSE v_owner END
   OR p_evidence='{}'::jsonb OR p_output='{}'::jsonb
   THEN RAISE EXCEPTION 'SALY_K_OWNER_OR_EVIDENCE_MISMATCH'; END IF;
 END IF;
 IF p_object_kind='PLAN' AND v_expected='OMITIDO' AND p_decision='OMITIDO'
 THEN
   IF p_output<>'{}'::jsonb THEN RAISE EXCEPTION 'SALY_K_SKIPPED_HAS_OUTPUT'; END IF;
 ELSE
   IF p_evidence='{}'::jsonb OR p_output='{}'::jsonb
   THEN RAISE EXCEPTION 'SALY_K_EXECUTION_EVIDENCE_MISSING'; END IF;
 END IF;
 IF EXISTS(SELECT 1 FROM saly.creative_k_results_v2 r
     WHERE r.item_id=p_item_id AND r.object_kind=p_object_kind
       AND r.object_sha256=p_object_sha256 AND r.module_code=p_module_code)
 THEN RAISE EXCEPTION 'SALY_K_DUPLICATE_OBJECT_EXECUTION'; END IF;
 INSERT INTO saly.creative_k_results_v2(
 item_id,object_kind,object_sha256,module_code,decision,step,reason,evidence,output,selection_sha256)
 VALUES (p_item_id,p_object_kind,p_object_sha256,p_module_code,p_decision,p_step,
  CASE WHEN p_decision='OMITIDO' THEN v_reason ELSE NULL END,
  p_evidence,p_output,v_selection.selection_sha256);
 RETURN jsonb_build_object('module_code',p_module_code,'decision',p_decision,
     'object_kind',p_object_kind,'step',p_step,'reason',v_reason,
     'output',p_output,'already_executed',false);
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'SALY_K_DUPLICATE_OBJECT_EXECUTION';
END $f$;

CREATE FUNCTION saly.creative_k_consume_v2(p_item_id bigint,p_object_kind text,
 p_object_sha256 text,p_module_code text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','saly','pg_temp'
AS $f$
 SELECT jsonb_build_object('module_code',r.module_code,'decision',r.decision,
  'step',r.step,'reason',r.reason,'output',r.output,'evidence',r.evidence)
 FROM saly.creative_k_results_v2 r
 WHERE r.item_id=p_item_id AND r.object_kind=p_object_kind
 AND r.object_sha256=p_object_sha256 AND r.module_code=p_module_code;
$f$;

-- Step 4: reference is optional; no fabricated asset, no new blocker.
CREATE FUNCTION saly.creative_reference_step_v2(p_reference jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'pg_catalog','pg_temp'
AS $f$
BEGIN
 IF p_reference IS NULL OR p_reference='null'::jsonb
 THEN RETURN jsonb_build_object('step','4','status','SIN_REFERENCIA',
       'execute',false,'blocking',false,'reference_observations','[]'::jsonb); END IF;
 IF jsonb_typeof(p_reference) IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'SALY_REFERENCE_INVALID'; END IF;
 RETURN jsonb_build_object('step','4','status','CON_REFERENCIA',
     'execute',true,'blocking',false,'reference',p_reference,
     'k03_k04_mode','LENTE_SIN_REEJECUCION');
END $f$;

-- Separate human/authenticated principal submits plan. No automatic PASS.
CREATE FUNCTION saly.creative_plan_submit_v2(
 p_item_id bigint,p_plan_json jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','saly','auth','extensions','pg_temp'
AS $f$
DECLARE v_author uuid;v_sha text;
BEGIN
 v_author:=auth.uid();
 IF v_author IS NULL OR jsonb_typeof(p_plan_json) IS DISTINCT FROM 'object'
 OR NOT EXISTS(SELECT 1 FROM saly.creative_order_items WHERE id=p_item_id)
 THEN RAISE EXCEPTION 'SALY_PREQA_AUTHOR_OR_PLAN_MISSING'; END IF;
 v_sha:=encode(extensions.digest(p_plan_json::text,'sha256'),'hex');
 INSERT INTO saly.creative_plan_pre_qa_v2(item_id,plan_sha256,plan_json,author_uid)
 VALUES(p_item_id,v_sha,p_plan_json,v_author);
 RETURN jsonb_build_object('status','PENDING','plan_sha256',v_sha,
       'author_uid',v_author,'independent_pass',false);
END $f$;

-- Authenticated reviewer identity is determined by auth.uid(), NEVER by caller.
CREATE FUNCTION saly.creative_plan_review_v2(
 p_item_id bigint,p_plan_sha256 text,p_verdict text,p_evidence jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','saly','auth','extensions','pg_temp'
AS $f$
DECLARE v_reviewer uuid;v_row saly.creative_plan_pre_qa_v2%ROWTYPE;
BEGIN
 v_reviewer:=auth.uid();
 SELECT * INTO STRICT v_row FROM saly.creative_plan_pre_qa_v2
 WHERE item_id=p_item_id AND plan_sha256=p_plan_sha256 FOR UPDATE;
 IF v_reviewer IS NULL OR v_reviewer=v_row.author_uid
 THEN RAISE EXCEPTION 'SALY_PREQA_INDEPENDENT_REVIEWER_REQUIRED'; END IF;
 IF v_row.verdict<>'PENDING' OR
 encode(extensions.digest(v_row.plan_json::text,'sha256'),'hex')<>v_row.plan_sha256
 THEN RAISE EXCEPTION 'SALY_PREQA_PLAN_IMMUTABLE_OR_ALREADY_REVIEWED'; END IF;
 IF p_verdict NOT IN ('PASS','FAIL','NO_EVALUADO')
 OR jsonb_typeof(p_evidence) IS DISTINCT FROM 'object'
 OR p_evidence='{}'::jsonb OR
 (p_verdict='PASS' AND (
  jsonb_typeof(p_evidence->'checks') IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_evidence->'checks')=0
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_evidence->'checks') c
            WHERE c->>'verdict' IS DISTINCT FROM 'PASS'
                OR nullif(btrim(c->>'evidence'),'') IS NULL)))
 THEN RAISE EXCEPTION 'SALY_PREQA_REVIEW_EVIDENCE_INVALID'; END IF;
 UPDATE saly.creative_plan_pre_qa_v2
 SET verdict=p_verdict,reviewer_uid=v_reviewer,review_json=p_evidence,reviewed_at=now()
 WHERE item_id=p_item_id AND plan_sha256=p_plan_sha256;
 RETURN jsonb_build_object('status',p_verdict,'plan_sha256',p_plan_sha256,
  'reviewer_uid',v_reviewer,'independent_pass',p_verdict='PASS');
END $f$;

REVOKE ALL ON FUNCTION visual.knowledge_select_task_v2(text,text,boolean),
 saly.creative_task_select_once_v2(bigint,text,boolean),
 saly.creative_k_record_once_v2(bigint,text,text,text,text,text,jsonb,jsonb),
 saly.creative_k_consume_v2(bigint,text,text,text),
 saly.creative_plan_submit_v2(bigint,jsonb),
 saly.creative_plan_review_v2(bigint,text,text,jsonb),
 saly.creative_reference_step_v2(jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION visual.knowledge_select_task_v2(text,text,boolean),
 saly.creative_task_select_once_v2(bigint,text,boolean),
 saly.creative_k_record_once_v2(bigint,text,text,text,text,text,jsonb,jsonb),
 saly.creative_k_consume_v2(bigint,text,text,text),
 saly.creative_reference_step_v2(jsonb)
 TO service_role;
GRANT EXECUTE ON FUNCTION saly.creative_plan_submit_v2(bigint,jsonb),
 saly.creative_plan_review_v2(bigint,text,text,jsonb)
 TO authenticated;
COMMIT;
