\set ON_ERROR_STOP on
-- Disposable PG17 schema, never actual Supabase production.
ALTER TABLE saly.creative_orders ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
ALTER TABLE saly.creative_order_items ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
INSERT INTO saly.creative_orders (id,code,status,scope_json,created_at,request_kind)
OVERRIDING SYSTEM VALUE VALUES (7,'SALY_HOME_V015_SINGLE_20261123','PLANIFICADO',
 '{"render_authorized":false,"rendering_authority":false,"review_only":true,"intake_source_status":"MISSING_VERIFIED_USER_VISUAL_REQUEST"}'::jsonb,now(),'APP_SCREEN_SINGLE');
INSERT INTO saly.creative_order_items (id,order_id,code,ordinal,status,required,qa_receipt)
OVERRIDING SYSTEM VALUE VALUES (10,7,'HOME',1,'PENDIENTE',true,'{}'::jsonb);
DO $negative$
BEGIN
 BEGIN
  UPDATE saly.creative_order_items SET status='TERMINADO' WHERE id=10;
  RAISE EXCEPTION 'INVALID_TERMINAL_UPDATE_WAS_ALLOWED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM = 'INVALID_TERMINAL_UPDATE_WAS_ALLOWED' THEN RAISE; END IF;
  IF position('SALY_CHAT_TERMINAL_JUDGE_OR_DEPENDENCY_MISSING' in SQLERRM)=0
  THEN RAISE; END IF;
 END;
 BEGIN
  UPDATE saly.creative_orders SET status='TERMINADO',completed_at=now() WHERE id=7;
  RAISE EXCEPTION 'INVALID_TERMINAL_ORDER_WAS_ALLOWED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM = 'INVALID_TERMINAL_ORDER_WAS_ALLOWED' THEN RAISE; END IF;
  IF position('SALY_CHAT_TERMINAL_ORDER_DETAILS_INCOMPLETE' in SQLERRM)=0
  THEN RAISE; END IF;
 END;
 IF (SELECT status FROM saly.creative_order_items WHERE id=10) <> 'PENDIENTE'
 OR (SELECT status FROM saly.creative_orders WHERE id=7) <> 'PLANIFICADO'
 THEN RAISE EXCEPTION 'PRESTATE_MUTATED_AFTER_REJECTED_UPDATE'; END IF;
END $negative$;
SELECT 'PASS_PRE_MIGRATION_FALSE_TERMINAL_REJECTED';
