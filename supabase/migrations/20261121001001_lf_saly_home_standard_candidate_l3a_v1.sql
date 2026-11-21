-- SALY · L3A: append-only HOME screen standard CANDIDATE.
-- No brand token promotion, no activation, no generation, no receipt, no ZIP.
-- The approved pair of brand/CTA colors is inherited by exact DB refs;
-- other selected tokens remain candidates, not authoritative standards.
BEGIN;

DO $saly_l3a$
DECLARE
 v_project_id bigint;
 v_set_id bigint;
 v_order_id bigint;
 v_item_id bigint;
 v_standard_id bigint;
 v_version_id bigint;
 v_packet jsonb;
 v_manifest jsonb;
 v_manifest_hash text;
 v_rejected boolean:=false;
BEGIN
 SELECT id INTO STRICT v_project_id FROM saly.proyecto
 WHERE codigo='SALY-001' AND estado='ACTIVO';

 SELECT id INTO STRICT v_set_id FROM saly.creative_context_sets
 WHERE project_id=v_project_id AND code='SALY_HOME_FIRST'
   AND version_label='0.3' AND state='SEALED' AND mode='EXPLORE';

 SELECT o.id,i.id INTO STRICT v_order_id,v_item_id
 FROM saly.creative_orders o
 JOIN saly.creative_order_items i ON i.order_id=o.id
 WHERE o.project_id=v_project_id AND o.code='SALY_HOME_BATCH_001'
 AND o.context_set_id=v_set_id AND o.status='PLANIFICADO'
 AND i.code='HOME' AND i.status='PENDIENTE';

 IF EXISTS(SELECT 1 FROM visual.standards
   WHERE brand_code='SALY' AND standard_code='SALY_HOME_APP_EXPLORE_V03')
 THEN RAISE EXCEPTION 'SALY_L3A_STANDARD_DUPLICATE'; END IF;

 IF (SELECT count(*) FROM saly.creative_context_tokens
     WHERE context_set_id=v_set_id)<>41
 OR (SELECT count(*) FROM saly.creative_context_tokens
     WHERE context_set_id=v_set_id AND role='OFFICIAL')<>2
 THEN RAISE EXCEPTION 'SALY_L3A_CONTEXT_BASELINE_INVALID'; END IF;

 v_packet:=saly.creative_item_context_l2a(v_item_id);
 IF v_packet->>'business_code'<>'SALY'
 OR v_packet->>'item_code'<>'HOME'
 OR v_packet->>'image_generation_allowed'<>'false'
 OR jsonb_typeof(v_packet->'tokens')<>'array'
 OR jsonb_array_length(v_packet->'tokens')<4
 OR (SELECT count(*) FROM jsonb_array_elements(v_packet->'tokens') AS t(value)
     WHERE t.value->>'role'='OFFICIAL')<>2
 OR jsonb_typeof(v_packet->'source_refs')<>'array'
 OR jsonb_array_length(v_packet->'source_refs')<>1
 THEN RAISE EXCEPTION 'SALY_L3A_SCREEN_CONTEXT_INVALID'; END IF;

 -- Versioned visual design proposal: all values come from the sealed SALY
 -- context; no arbitrary colors/typography or materialized external files.
 v_manifest:=jsonb_build_object(
 'schema_version','SALY_HOME_VISUAL_STANDARD_CANDIDATE_L3A_V1',
 'business_code','SALY',
 'project_code','SALY-001',
 'kind','APP_SCREEN',
 'screen_code','HOME',
 'standard_code','SALY_HOME_APP_EXPLORE_V03',
 'design_mode','EXPLORE',
 'status','CANDIDATE_NOT_ACTIVATED',
 'context_set_id',v_set_id,
 'context_set_code','SALY_HOME_FIRST',
 'context_version','0.3',
 'order_id',v_order_id,
 'order_code','SALY_HOME_BATCH_001',
 'item_id',v_item_id,
 'token_selection',v_packet->'tokens',
 'verified_source_refs',v_packet->'source_refs',
 'screen_spec',(SELECT context_json->'screen_spec'
                FROM saly.creative_order_items WHERE id=v_item_id),
 'acceptance_criteria',(SELECT acceptance_json
                 FROM saly.creative_order_items WHERE id=v_item_id),
 'creative_packet_sha256',encode(extensions.digest(convert_to(v_packet::text,'UTF8'),'sha256'),'hex'),
 'official_token_count',2,
 'consumer_gate','REQUIRES_VALID_NATIVE_RUN_AND_INDEPENDENT_QA',
 'image_generation_allowed',false,
 'approval_ref',null,
 'activation_ref',null,
 'external_renderer_receipt',null
 );
 v_manifest_hash:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

 INSERT INTO visual.standards(brand_code,standard_code,kind)
 VALUES('SALY','SALY_HOME_APP_EXPLORE_V03','APP_SCREEN')
 RETURNING id INTO v_standard_id;

 -- manifest_sha256 is a PostgreSQL GENERATED ALWAYS column; it must
 -- be derived by the database, never supplied by the caller.
 INSERT INTO visual.standard_versions
   (standard_id,brand_code,kind,version,manifest_json,state)
 VALUES(v_standard_id,'SALY','APP_SCREEN','0.3-candidate',
        v_manifest,'CANDIDATE')
 RETURNING id INTO v_version_id;

 IF (SELECT manifest_sha256
       FROM visual.standard_versions WHERE id=v_version_id)
      IS DISTINCT FROM encode(extensions.digest(convert_to(
       (SELECT manifest_json FROM visual.standard_versions WHERE id=v_version_id)::text,
       'UTF8'),'sha256'),'hex')
 OR (SELECT state FROM visual.standard_versions WHERE id=v_version_id)<>'CANDIDATE'
 THEN RAISE EXCEPTION 'SALY_L3A_STANDARD_HASH_OR_STATE_INVALID'; END IF;

 -- Negative proof: an unapproved version cannot be made ACTIVE. The rejected
 -- insert is rolled back within the PL/pgSQL exception subtransaction.
 BEGIN
   INSERT INTO visual.standard_activations
     (brand_code,kind,channel_code,audience_code,device_class,
      output_target,standard_version_id,valid_from,approval_ref)
   VALUES('SALY','APP_SCREEN','APP','SALY_USERS','MOBILE',
      'APP_SCREEN',v_version_id,now(),'NEGATIVE_TEST_ONLY');
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM='VISUAL_STANDARD_ACTIVATION_UNAPPROVED_VERSION'
   THEN v_rejected:=true;
   ELSE RAISE; END IF;
 END;
 IF NOT v_rejected THEN RAISE EXCEPTION 'SALY_L3A_CANDIDATE_ACTIVATION_NOT_BLOCKED'; END IF;

 IF (SELECT count(*) FROM visual.standards
      WHERE brand_code='SALY' AND standard_code='SALY_HOME_APP_EXPLORE_V03')<>1
 OR (SELECT count(*) FROM visual.standard_versions
      WHERE standard_id=v_standard_id AND state='CANDIDATE')<>1
 OR EXISTS(SELECT 1 FROM visual.standard_activations WHERE brand_code='SALY')
 OR EXISTS(SELECT 1 FROM visual.generation_receipts WHERE brand_code='SALY')
 OR EXISTS(SELECT 1 FROM saly.creative_runs WHERE order_id=v_order_id)
 OR EXISTS(SELECT 1 FROM saly.creative_order_items
           WHERE order_id=v_order_id AND status<>'PENDIENTE')
 THEN RAISE EXCEPTION 'SALY_L3A_UNEXPECTED_SIDE_EFFECT'; END IF;
END $saly_l3a$;

COMMIT;