\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned
\pset fieldsep ' | '
SELECT 'PRETEST_INPUT|55 real token versions; contexts 3/4; orders 7/8/9; items 10/11/13';
SELECT 'PRETEST_OUTPUT|' || jsonb_build_object(
  'total_tokens',(SELECT count(*) FROM saly.identity_versions),
  'ctx3',(SELECT count(*) FROM saly.creative_context_tokens WHERE context_set_id=3),
  'ctx4',(SELECT count(*) FROM saly.creative_context_tokens WHERE context_set_id=4),
  'order9_ctx',(SELECT context_set_id FROM saly.creative_orders WHERE id=9),
  'item10_status',(SELECT status FROM saly.creative_order_items WHERE id=10),
  'item11_status',(SELECT status FROM saly.creative_order_items WHERE id=11),
  'item13_status',(SELECT status FROM saly.creative_order_items WHERE id=13)
)::text;
BEGIN;
SELECT 'STEP01_INPUT|UPDATE identity_versions.metadata for alias ids 21..33 only; 58..61 unchanged';
UPDATE saly.identity_versions v
SET metadata=v.metadata||jsonb_build_object(
 'kind','ALIAS',
 'alias_target_code','candidate.saly_ds_v1.' ||
     trim(both '{}' from v.value_json->>'value'))
WHERE v.id BETWEEN 21 AND 33 AND v.metadata->>'kind' IS DISTINCT FROM 'ALIAS';
SELECT 'STEP01_OUTPUT|' || jsonb_build_object(
 'aliases_21_33_fixed',(SELECT count(*) FROM saly.identity_versions v WHERE v.id BETWEEN 21 AND 33 AND v.metadata->>'kind'='ALIAS'),
 'aliases_58_61_existing',(SELECT count(*) FROM saly.identity_versions v WHERE v.id BETWEEN 58 AND 61 AND v.metadata->>'kind'='ALIAS'),
 'unresolved_targets',(SELECT count(*) FROM saly.identity_versions v WHERE v.metadata->>'kind'='ALIAS' AND NOT EXISTS(
  SELECT 1 FROM saly.identity_elements e WHERE e.code=v.metadata->>'alias_target_code'))
)::text;

SELECT 'STEP02_INPUT|INSERT new context DRAFT + all 55 tokens; SEAL context; retain approval statuses';
INSERT INTO saly.creative_context_sets(
 id,project_id,code,version_label,mode,state,provenance)
SELECT max(id)+1,2,'SALY_HOME_55TOKENS_ROLLBACK_20261123','simulation','EXPLORE',
 'DRAFT','OWNER_SIMULATION_ONLY_ROLLBACK'
FROM saly.creative_context_sets;
INSERT INTO saly.creative_context_tokens(context_set_id,identity_version_id,role,value_sha256)
SELECT (SELECT id FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123'),
  v.id,
  CASE WHEN e.code IN('color.action.primary.bg','color.brand.primary')
          AND v.approval_status='APPROVED' THEN 'OFFICIAL'
       WHEN e.code LIKE 'candidate.saly_home_v3.%' THEN 'HOME'
       ELSE 'EXISTING' END,
  repeat('0',64)
FROM saly.identity_versions v JOIN saly.identity_elements e ON e.id=v.element_id
WHERE e.project_id=2 ORDER BY v.id;
UPDATE saly.creative_context_sets
SET state='SEALED'
WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123';
SELECT 'STEP02_OUTPUT|' || jsonb_build_object(
 'context_id',(SELECT id FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123'),
 'context_state',(SELECT state FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123'),
 'token_count',(SELECT count(*) FROM saly.creative_context_tokens WHERE context_set_id=(SELECT id FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123')),
 'official',(SELECT count(*) FROM saly.creative_context_tokens WHERE role='OFFICIAL' AND context_set_id=(SELECT id FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123')),
 'candidate',(SELECT count(*) FROM saly.creative_context_tokens WHERE role<>'OFFICIAL' AND context_set_id=(SELECT id FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123')),
 'sha_mismatches',(SELECT count(*) FROM saly.creative_context_tokens t JOIN saly.identity_versions v ON v.id=t.identity_version_id
   WHERE t.context_set_id=(SELECT id FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123')
     AND t.value_sha256<>encode(extensions.digest(v.value_json::text,'sha256'),'hex'))
)::text;

SELECT 'STEP03_INPUT|UPDATE order 9 context_set_id + identity_snapshot from selected 55 token versions';
UPDATE saly.creative_orders o
SET context_set_id=c.id,
identity_snapshot=jsonb_build_object('context_set_id',c.id,'selected_versions',
 (SELECT jsonb_agg(jsonb_build_object('version_id',t.identity_version_id,
  'sha256',t.value_sha256,'role',t.role) ORDER BY t.identity_version_id)
 FROM saly.creative_context_tokens t WHERE t.context_set_id=c.id))
FROM saly.creative_context_sets c
WHERE o.id=9 AND o.status='BORRADOR'
AND c.code='SALY_HOME_55TOKENS_ROLLBACK_20261123';
SELECT 'STEP03_OUTPUT|' || jsonb_build_object(
 'order9_ctx',(SELECT context_set_id FROM saly.creative_orders WHERE id=9),
 'snapshot_versions',(SELECT jsonb_array_length(identity_snapshot->'selected_versions') FROM saly.creative_orders WHERE id=9),
 'matches_context',(SELECT
 o.identity_snapshot IS NOT DISTINCT FROM jsonb_build_object(
 'context_set_id',o.context_set_id,'selected_versions',
 (SELECT jsonb_agg(jsonb_build_object('version_id',t.identity_version_id,'sha256',t.value_sha256,'role',t.role)
 ORDER BY t.identity_version_id) FROM saly.creative_context_tokens t WHERE t.context_set_id=o.context_set_id))
 FROM saly.creative_orders o WHERE o.id=9)
)::text;

SELECT 'STEP04_INPUT|Set candidate token_codes for items 10,11,13; preserve terminal guard';
DO $attempt$
DECLARE err text;
BEGIN
 BEGIN
  UPDATE saly.creative_order_items
  SET context_json=jsonb_set(context_json,'{token_codes}',
      (SELECT jsonb_agg(e.code ORDER BY e.code) FROM saly.identity_versions v
       JOIN saly.identity_elements e ON e.id=v.element_id
       WHERE e.code LIKE 'candidate.%'),true)
  WHERE id=10 AND order_id=7;
  RAISE NOTICE 'STEP04_ITEM10_OUTPUT: UPDATED';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  RAISE NOTICE 'STEP04_ITEM10_OUTPUT: %',err;
 END;
END $attempt$;
UPDATE saly.creative_order_items i
SET context_json=jsonb_set(i.context_json,'{token_codes}',
 (SELECT jsonb_agg(e.code ORDER BY e.code)
 FROM saly.identity_versions v JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE e.code LIKE 'candidate.%'),true)
WHERE i.id IN (11,13);
SELECT 'STEP04_OUTPUT|' || jsonb_build_object(
 'item10_token_codes',(SELECT context_json->'token_codes' FROM saly.creative_order_items WHERE id=10),
 'item11_token_count',(SELECT jsonb_array_length(context_json->'token_codes') FROM saly.creative_order_items WHERE id=11),
 'item13_token_count',(SELECT jsonb_array_length(context_json->'token_codes') FROM saly.creative_order_items WHERE id=13),
 'item11_ctx',(SELECT o.context_set_id FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id WHERE i.id=11)
)::text;

SELECT 'STEP05_INPUT|Add visual_rules to items 10,11,13; no new blocking rules';
DO $attempt$
DECLARE err text;
BEGIN
 BEGIN
  UPDATE saly.creative_order_items i
  SET acceptance_json=jsonb_set(acceptance_json,'{visual_rules}',
      jsonb_build_object('scope',o.code,'no_decorative_rays',true,
      'spacing','OBSERVE','typography','OBSERVE','radii','OBSERVE','elevation','OBSERVE'),true)
  FROM saly.creative_orders o WHERE i.order_id=o.id AND i.id=10;
  RAISE NOTICE 'STEP05_ITEM10_OUTPUT: UPDATED';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  RAISE NOTICE 'STEP05_ITEM10_OUTPUT: %',err;
 END;
END $attempt$;
UPDATE saly.creative_order_items i
SET acceptance_json=jsonb_set(acceptance_json,'{visual_rules}',
  jsonb_build_object('scope',o.code,'no_decorative_rays',true,
    'spacing','OBSERVE','typography','OBSERVE','radii','OBSERVE','elevation','OBSERVE'),true)
FROM saly.creative_orders o
WHERE i.order_id=o.id AND i.id IN(11,13);
SELECT 'STEP05_OUTPUT|' || jsonb_build_object(
 'item10_has_visual_rules',(SELECT acceptance_json?'visual_rules' FROM saly.creative_order_items WHERE id=10),
 'item11_visual_rules',(SELECT acceptance_json->'visual_rules' FROM saly.creative_order_items WHERE id=11),
 'item13_visual_rules',(SELECT acceptance_json->'visual_rules' FROM saly.creative_order_items WHERE id=13)
)::text;

SELECT 'STEP06_INPUT|Compile modified L3B with 23 nonblocking checks (SQL source: proposed_l3b_observe_only.sql)';
\i sandbox/creative_factory/rollback55_v1/proposed_l3b_observe_only.sql
SELECT 'STEP06_OUTPUT|' || jsonb_build_object(
 'l3b_proposed_function_compiled',to_regprocedure('saly.creative_item_visual_contract_l3b(bigint)') IS NOT NULL,
 'existing_checks',5,
 'added_observation_checks',(SELECT count(*) FROM saly.creative_context_tokens t JOIN saly.identity_versions v ON v.id=t.identity_version_id
    JOIN saly.identity_elements e ON e.id=v.element_id
    WHERE t.context_set_id=(SELECT context_set_id FROM saly.creative_orders WHERE id=9)
     AND e.family IN('SPACING','TYPOGRAPHY','LAYOUT','RULE')),
 'families',(SELECT jsonb_object_agg(family,qty) FROM
    (SELECT e.family,count(*) qty FROM saly.creative_context_tokens t JOIN saly.identity_versions v ON v.id=t.identity_version_id
     JOIN saly.identity_elements e ON e.id=v.element_id WHERE t.context_set_id=(SELECT context_set_id FROM saly.creative_orders WHERE id=9)
     GROUP BY e.family) grouped)
)::text;

SELECT 'STEP06B_INPUT|Try real L2A context binding for 11 and 13 without granting runtime authority';
DO $attempt$
DECLARE err text; obj jsonb;
BEGIN
 BEGIN
  obj:=saly.creative_item_context_l2a(11);
  RAISE NOTICE 'STEP06B_ITEM11_OUTPUT: CONTEXT_OK, token_count=%',jsonb_array_length(obj->'tokens');
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  RAISE NOTICE 'STEP06B_ITEM11_OUTPUT: %',err;
 END;
 BEGIN
  obj:=saly.creative_item_context_l2a(13);
  RAISE NOTICE 'STEP06B_ITEM13_OUTPUT: CONTEXT_OK, token_count=%',jsonb_array_length(obj->'tokens');
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  RAISE NOTICE 'STEP06B_ITEM13_OUTPUT: %',err;
 END;
END $attempt$;

SELECT 'STEP07_INPUT|Build exact prompt with original value_json and alias resolutions; attach official logo ref+sha; store BEFORE dispatch';
CREATE TEMP TABLE saly_handoff_simulation AS
WITH resolved AS (
 SELECT e.code,e.family,v.approval_status,v.id,
   CASE WHEN v.metadata->>'kind'='ALIAS'
      THEN (SELECT v2.value_json->'value'
            FROM saly.identity_versions v2 JOIN saly.identity_elements e2 ON e2.id=v2.element_id
            WHERE e2.code=v.metadata->>'alias_target_code')
      ELSE v.value_json->'value' END AS real_value
 FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE t.context_set_id=(SELECT context_set_id FROM saly.creative_orders WHERE id=9)
),
msg AS (
 SELECT jsonb_agg(jsonb_build_object('token_code',code,'family',family,'status',approval_status,
         'version_id',id,'real_value',real_value) ORDER BY code) AS tokens,
    string_agg(format('%s = %s [%s]',code,real_value::text,approval_status),E'\n' ORDER BY code) AS token_lines,
    count(*) AS token_count, count(*) FILTER(WHERE real_value IS NULL) AS unresolved
 FROM resolved
)
SELECT 9::bigint AS order_id,13::bigint AS item_id,
 'HOME SALY, iPhone 16 Pro. Cambio solicitado: Mi disponible -> Cómo se calcula; sin monto. '||
 'Conservar las demás regiones y copys. TOKEN_VALUES:'||E'\n'||token_lines||E'\n'||
 'LOGO_FILE: 01_SALY_PRINCIPAL_TRANSPARENTE.png'||E'\n'||
 'LOGO_SOURCE: https://drive.google.com/file/d/1xQyhrhrqgjHvkPVSg1vYCgDjlFV7ox78/view'
 AS prompt_utf8,
 tokens AS token_payload,
 jsonb_build_array(jsonb_build_object('name','01_SALY_PRINCIPAL_TRANSPARENTE.png',
   'url','https://drive.google.com/file/d/1xQyhrhrqgjHvkPVSg1vYCgDjlFV7ox78/view',
   'sha256','5573f0503ddb3dd1029221a9ee336d0e28155c392598286628dbf294da146995',
   'file_attached_to_renderer',false)) AS attachments,
 token_count,unresolved,false::boolean AS transmitted
FROM msg;
SELECT 'STEP07_OUTPUT|' || jsonb_build_object(
 'order_id',order_id,'item_id',item_id,'token_count',token_count,
 'unresolved_alias_values',unresolved,
 'attachment_count',jsonb_array_length(attachments),
 'prompt_sha256',encode(extensions.digest(convert_to(prompt_utf8,'UTF8'),'sha256'),'hex'),
 'prompt_bytes',octet_length(prompt_utf8),
 'transmitted',transmitted,'handoff_saved_before_send',true
)::text FROM saly_handoff_simulation;
SELECT 'STEP07_EXACT_INPUT_PAYLOAD|' || jsonb_build_object(
 'order_id',order_id,'item_id',item_id,'prompt_utf8',prompt_utf8,
 'attachments',attachments,'token_values',token_payload,
 'prompt_sha256',encode(extensions.digest(convert_to(prompt_utf8,'UTF8'),'sha256'),'hex'),
 'transmitted',transmitted)::text FROM saly_handoff_simulation;

SELECT 'STEP08_INPUT|ROLLBACK entire simulation; no database modifications persist';
ROLLBACK;
SELECT 'STEP08_OUTPUT_AFTER_ROLLBACK|' || jsonb_build_object(
 'version21_alias_kind',(SELECT metadata->>'kind' FROM saly.identity_versions WHERE id=21),
 'simulated_context_rows',(SELECT count(*) FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123'),
 'order9_context_set_id',(SELECT context_set_id FROM saly.creative_orders WHERE id=9),
 'item11_token_codes',(SELECT context_json->'token_codes' FROM saly.creative_order_items WHERE id=11),
 'item13_token_codes',(SELECT context_json->'token_codes' FROM saly.creative_order_items WHERE id=13),
 'item13_visual_rules',(SELECT acceptance_json->'visual_rules' FROM saly.creative_order_items WHERE id=13),
 'proposed_l3b_function_exists',to_regprocedure('saly.creative_item_visual_contract_l3b(bigint)') IS NOT NULL,
 'handoff_temp_table_exists',to_regclass('saly_handoff_simulation') IS NOT NULL
)::text;
