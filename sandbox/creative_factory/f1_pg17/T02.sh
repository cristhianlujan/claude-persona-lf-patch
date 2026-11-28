#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T02|FAIL unsafe'; exit 2; }
psql -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
BEGIN;
INSERT INTO saly.creative_context_sets(id,project_id,code,version_label,mode,state,sealed_at,provenance)
OVERRIDING SYSTEM VALUE VALUES (9202,3,'LF_F1_T02_CTX','CI','EXPLORE','SEALED',clock_timestamp(),'{"assets":[]}');
INSERT INTO saly.creative_context_tokens(context_set_id,identity_version_id,role,value_sha256)
VALUES(9202,125,'OFFICIAL','afc1a69dc102317aeb0a51f5cff57bf4e54930d67b00e384f552c4b3ed8b240c');
INSERT INTO saly.creative_orders(id,project_id,code,request_key,title,request_kind,design_mode,requested_by,scope_json,identity_snapshot,status,context_set_id)
OVERRIDING SYSTEM VALUE VALUES(9202,3,'LF_F1_T02_ORDER','lf-f1-t02','T02','APP_SCREEN_SINGLE','EXPLORE','CI',
 jsonb_build_object('queue_mode','SERIAL_V1','review_only',false,'render_authorized',true,'rendering_authority',true,'original_literal_request','CI LF F1 synthetic request'),'{}','PLANIFICADO',9202);
INSERT INTO saly.creative_order_items(id,order_id,code,ordinal,kind,title,required,acceptance_json,context_json,status)
OVERRIDING SYSTEM VALUE
SELECT 92021,9202,'LF_F1_T02_SCREEN',1,'SCREEN','T02',true,acceptance_json,
 jsonb_set(context_json,'{asset_codes}','["LF_BRAND_LOGO_1L_LIGHT_TRANSPARENT"]'::jsonb,true),'PENDIENTE'
FROM saly.creative_order_items WHERE id=2501;
DO $$
BEGIN
 BEGIN
  PERFORM saly.creative_item_context_l2a(92021);
  RAISE EXCEPTION 'T02_DID_NOT_BLOCK';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM 'LF_ITEM_ASSET_NOT_VERIFIED' THEN RAISE EXCEPTION 'T02_WRONG_ERROR:%',SQLERRM; END IF;
 END;
END $$;
ROLLBACK;
SQL
echo 'T02|PASS'
