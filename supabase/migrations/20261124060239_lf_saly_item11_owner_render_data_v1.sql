-- SALY data only. Owner authorization via Claude, 2026-11-24 00:57 Lima.
BEGIN;
DO $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM saly.creative_orders WHERE id=8 AND status='PLANIFICADO'
   AND scope_json->>'literal_origin'='USER_MESSAGE'
   AND scope_json->>'source_message_ref'='OWNER_CHAT_CLAUDE_2026-11-24T00:31-05:00'
   AND nullif(btrim(scope_json->>'content_prompt'),'') IS NOT NULL)
 OR NOT EXISTS (SELECT 1 FROM saly.creative_order_items WHERE id=11 AND order_id=8 AND status='PENDIENTE')
 THEN RAISE EXCEPTION 'SALY_ITEM11_EXPECTED_SOURCE_OR_STATE_MISSING'; END IF;
END $$;
UPDATE saly.creative_orders
SET scope_json = (scope_json - 'block_reason') || jsonb_build_object(
 'render_authorized',true,'rendering_authority',true,'review_only',false,
 'render_authorization_source','OWNER_CHAT_CLAUDE_2026-11-24T00:57-05:00',
 'native_executor','GPT_CHAT',
 'previous_intake_semantic_qa',scope_json->'intake_semantic_qa',
 'previous_block_reason',scope_json->'block_reason',
 'previous_intake_source_status',scope_json->'intake_source_status',
 'intake_source_status','VERIFIED_USER_VISUAL_REQUEST',
 'intake_semantic_qa',jsonb_build_object(
    'verdict','PASS','intent_class','VISUAL_REQUEST',
    'source_origin','USER_MESSAGE','source_message_ref',scope_json->>'source_message_ref',
    'source_sha256',encode(extensions.digest(scope_json->>'literal_request','sha256'),'hex'),
    'compiled_prompt_origin','content_prompt',
    'repair_contract','SALY_CREATIVE_INTAKE_SEMANTIC_REPAIR_V1'),
 'prompt_sha256',encode(extensions.digest(scope_json->>'compiled_prompt','sha256'),'hex')
),updated_at=now()
WHERE id=8;
UPDATE saly.creative_order_items
SET status='LISTO',updated_at=now()
WHERE id=11 AND order_id=8 AND status='PENDIENTE';
SELECT saly.creative_task_select_once_v2(11,'NEW_SCREEN',false);
COMMIT;
