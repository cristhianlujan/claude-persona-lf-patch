\set ON_ERROR_STOP on
-- CI-only SALY regression fixtures derived from read-only production shape.
-- Source readback 2026-11-28: historical order type 22 = SALY-001 /
-- APP_SCREEN_SINGLE / SERIAL_V1 / blueprint=yes / semantic_qa=no /
-- 55 context tokens / one source SHA 3d80592d...d33e.
-- Legacy type order 11 = same project/kind/queue, blueprint=no, semantic_qa=no.
-- IDs 9220+ are intentionally disjoint from production. No claim_token or PII.

DO $pre$
BEGIN
  IF (SELECT codigo FROM saly.proyecto WHERE id=2) IS DISTINCT FROM 'SALY-001'
  THEN RAISE EXCEPTION 'SALY_REG_PROJECT_DRIFT'; END IF;
  IF (SELECT count(*) FROM saly.identity_versions WHERE id IN (7,8) OR id BETWEEN 64 AND 116) <> 55
  THEN RAISE EXCEPTION 'SALY_REG_REAL_TOKEN_SNAPSHOT_INCOMPLETE'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM visual.source_assets
    WHERE id=1
      AND source_sha256='3d80592dc94938ea6e4d34727a99a0aec242b43838e2815820b72e87d649d33e'
      AND brand_code='SALY'
  ) THEN RAISE EXCEPTION 'SALY_REG_REAL_SOURCE_SNAPSHOT_DRIFT'; END IF;
END
$pre$;

INSERT INTO saly.creative_context_sets
(id,project_id,code,version_label,mode,state,sealed_at,provenance)
OVERRIDING SYSTEM VALUE VALUES
(9220,2,'SALY_REG_REAL_CTX','CI_V1','EXPLORE','DRAFT',NULL,
 'READ_ONLY_PROD_SHAPE_20261128_ORDER22_SANITIZED');

INSERT INTO saly.creative_context_tokens
(context_set_id,identity_version_id,role,value_sha256)
SELECT 9220,v.id,
       CASE WHEN v.id IN (7,8) THEN 'OFFICIAL'
            WHEN v.id BETWEEN 108 AND 114 THEN 'HOME'
            ELSE 'EXISTING' END,
       encode(extensions.digest(convert_to(v.value_json::text,'UTF8'),'sha256'),'hex')
FROM saly.identity_versions v
WHERE v.id IN (7,8) OR v.id BETWEEN 64 AND 116
ORDER BY v.id;

UPDATE saly.creative_context_sets SET state='SEALED' WHERE id=9220;

INSERT INTO saly.creative_orders
(id,project_id,code,request_key,title,request_kind,design_mode,requested_by,
 scope_json,identity_snapshot,status,context_set_id)
OVERRIDING SYSTEM VALUE VALUES
(9220,2,'SALY_REG_REAL_HIST','saly-reg-real-hist','SALY historical regression fixture',
 'APP_SCREEN_SINGLE','EXPLORE','CI_REGRESSION',
 jsonb_build_object('queue_mode','SERIAL_V1','review_only',false,
                    'render_authorized',true,'rendering_authority',true,
                    'literal_request','CI sanitized historical SALY request'),
 '{}'::jsonb,'PLANIFICADO',9220);

WITH bp AS (
  SELECT context_json#>'{screen_spec,visual_blueprint}' AS blueprint
  FROM saly.creative_order_items WHERE id=9101
)
INSERT INTO saly.creative_order_items
(id,order_id,code,ordinal,kind,title,required,acceptance_json,context_json,status)
OVERRIDING SYSTEM VALUE
SELECT 9226,9220,'SALY_REG_REAL_HIST_SCREEN',1,'SCREEN','SALY historical regression screen',true,
       jsonb_build_object(
         'qa_required',true,
         'visual_rules',jsonb_build_object(
           'scope','SALY_REG_REAL_HIST','no_decorative_rays',true)),
       jsonb_build_object(
         'screen_spec',jsonb_build_object(
           'device','IPHONE16PRO','screen','CI_SALY_HIST',
           'visual_blueprint',blueprint)),
       'PENDIENTE'
FROM bp;

INSERT INTO saly.creative_item_sources
(id,order_id,item_id,source_asset_id,purpose,source_sha256)
OVERRIDING SYSTEM VALUE VALUES
(9226,9220,9226,1,'VISUAL_REFERENCE',
 '3d80592dc94938ea6e4d34727a99a0aec242b43838e2815820b72e87d649d33e');

-- R2: sanitized structural clone of a real SALY legacy request (order 11 shape).
INSERT INTO saly.creative_orders
(id,project_id,code,request_key,title,request_kind,design_mode,requested_by,
 scope_json,identity_snapshot,status,context_set_id)
OVERRIDING SYSTEM VALUE VALUES
(9230,2,'SALY_REG_LEGACY','saly-reg-legacy','SALY legacy regression fixture',
 'APP_SCREEN_SINGLE','EXPLORE','CI_REGRESSION',
 jsonb_build_object('queue_mode','SERIAL_V1','review_only',false,
                    'render_authorized',true,'rendering_authority',true,
                    'literal_request','CI sanitized legacy SALY request'),
 '{}'::jsonb,'EN_PROCESO',9220);

INSERT INTO saly.creative_order_items
(id,order_id,code,ordinal,kind,title,required,acceptance_json,context_json,status)
OVERRIDING SYSTEM VALUE VALUES
(9231,9230,'SALY_REG_LEGACY_SCREEN',1,'SCREEN','SALY legacy regression screen',true,
 '{"qa_required":true}'::jsonb,
 '{"screen_spec":{"device":"IPHONE16PRO","screen":"CI_SALY_LEGACY"}}'::jsonb,
 'PRODUCIENDO');

-- R3/R4: SALY fixture with a governed 5-check semantic contract.
INSERT INTO saly.creative_orders
(id,project_id,code,request_key,title,request_kind,design_mode,requested_by,
 scope_json,identity_snapshot,status,context_set_id)
OVERRIDING SYSTEM VALUE VALUES
(9240,2,'SALY_REG_DUAL_QA','saly-reg-dual-qa','SALY dual QA regression fixture',
 'APP_SCREEN_SINGLE','EXPLORE','CI_REGRESSION',
 jsonb_build_object('queue_mode','SERIAL_V1','review_only',false,
                    'render_authorized',true,'rendering_authority',true,
                    'literal_request','CI sanitized dual QA SALY request'),
 '{}'::jsonb,'PLANIFICADO',9220);

WITH bp AS (
  SELECT context_json#>'{screen_spec,visual_blueprint}' AS blueprint
  FROM saly.creative_order_items WHERE id=9226
), msgs AS (
  SELECT jsonb_build_array(
    jsonb_build_object('speaker','USER','text','CI sanitized dual QA SALY request')
  ) AS m
), sem AS (
  SELECT jsonb_build_object(
    'schema_version','SALY_SEMANTIC_QA_L3C_V1',
    'scope','SCREEN',
    'source_type','OWNER_LITERAL',
    'require_artifact_evidence',true,
    'require_independent_interpretation',true,
    'original_messages',m,
    'original_request_sha256',
       encode(extensions.digest(convert_to(m::text,'UTF8'),'sha256'),'hex'),
    'interpretation',jsonb_build_object(
       'objective','Regression only',
       'preserve',jsonb_build_array('governed SALY contract'),
       'excluded',jsonb_build_array('production mutation'),
       'creative_freedom','none in regression',
       'interpretation_origin','ASSISTANT_INTERPRETATION_SEPARATE_FROM_OWNER_LITERAL'),
    'checks',jsonb_build_array(
       jsonb_build_object('code','SALY_SEM_01','expected','MATCH','severity','BLOCK'),
       jsonb_build_object('code','SALY_SEM_02','expected','MATCH','severity','BLOCK'),
       jsonb_build_object('code','SALY_SEM_03','expected','MATCH','severity','BLOCK'),
       jsonb_build_object('code','SALY_SEM_04','expected','MATCH','severity','BLOCK'),
       jsonb_build_object('code','SALY_SEM_05','expected','MATCH','severity','BLOCK'))
  ) AS s
  FROM msgs
)
INSERT INTO saly.creative_order_items
(id,order_id,code,ordinal,kind,title,required,acceptance_json,context_json,status)
OVERRIDING SYSTEM VALUE
SELECT 9241,9240,'SALY_REG_DUAL_QA_SCREEN',1,'SCREEN','SALY dual QA regression screen',true,
       jsonb_build_object('qa_required',true,'semantic_qa',s),
       jsonb_build_object(
         'screen_spec',jsonb_build_object(
           'device','IPHONE16PRO','screen','CI_SALY_DUAL_QA',
           'visual_blueprint',blueprint)),
       'PENDIENTE'
FROM bp,sem;

INSERT INTO saly.creative_item_sources
(id,order_id,item_id,source_asset_id,purpose,source_sha256)
OVERRIDING SYSTEM VALUE VALUES
(9241,9240,9241,1,'VISUAL_REFERENCE',
 '3d80592dc94938ea6e4d34727a99a0aec242b43838e2815820b72e87d649d33e');

DO $post$
BEGIN
 IF (SELECT count(*) FROM saly.creative_context_tokens WHERE context_set_id=9220)<>55
 THEN RAISE EXCEPTION 'SALY_REG_TOKEN_COUNT_NOT_55'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM saly.creative_order_items
   WHERE id=9226 AND context_json#>'{screen_spec,visual_blueprint}' IS NOT NULL
     AND NOT (acceptance_json ? 'semantic_qa')
 ) THEN RAISE EXCEPTION 'SALY_REG_R1_SHAPE_INVALID'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM saly.creative_order_items
   WHERE id=9231 AND context_json#>'{screen_spec,visual_blueprint}' IS NULL
     AND NOT (acceptance_json ? 'semantic_qa')
 ) THEN RAISE EXCEPTION 'SALY_REG_R2_SHAPE_INVALID'; END IF;
 RAISE NOTICE 'SALY_REG_REAL_FIXTURE|PASS|tokens=55|source_count=1|ids=9220,9226,9230,9231,9240,9241';
END
$post$;
