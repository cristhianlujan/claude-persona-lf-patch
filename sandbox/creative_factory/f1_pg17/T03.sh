#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T03|FAIL unsafe'; exit 2; }
psql -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
BEGIN;
INSERT INTO saly.creative_context_sets(id,project_id,code,version_label,mode,state,sealed_at,provenance)
OVERRIDING SYSTEM VALUE VALUES (9203,3,'LF_F1_T03_CTX','CI','EXPLORE','SEALED',clock_timestamp(),
 '{"assets":[{"asset_code":"SALY_HOME_IPHONE16PRO","brand_asset_id":1,"checksum_sha256":"3d80592dc94938ea6e4d34727a99a0aec242b43838e2815820b72e87d649d33e","filename":"SALY_HOME_IPHONE16PRO_v1.1.png","mime_type":"image/png","storage_provider":"GOOGLE_DRIVE","storage_object_path":"1YXWAS8McVi0Y91FEtMbCW6M57-6D9em9"}]}');
INSERT INTO saly.creative_context_tokens(context_set_id,identity_version_id,role,value_sha256)
VALUES(9203,125,'OFFICIAL','afc1a69dc102317aeb0a51f5cff57bf4e54930d67b00e384f552c4b3ed8b240c');
INSERT INTO saly.creative_orders(id,project_id,code,request_key,title,request_kind,design_mode,requested_by,scope_json,identity_snapshot,status,context_set_id)
OVERRIDING SYSTEM VALUE VALUES(9203,3,'LF_F1_T03_ORDER','lf-f1-t03','T03','APP_SCREEN_SINGLE','EXPLORE','CI',
 jsonb_build_object('queue_mode','SERIAL_V1','review_only',false,'render_authorized',true,'rendering_authority',true,'original_literal_request','CI LF F1 synthetic request'),'{}','PLANIFICADO',9203);
INSERT INTO saly.creative_order_items(id,order_id,code,ordinal,kind,title,required,acceptance_json,context_json,status)
OVERRIDING SYSTEM VALUE
SELECT 92031,9203,'LF_F1_T03_SCREEN',1,'SCREEN','T03',true,acceptance_json,
 jsonb_set(context_json,'{asset_codes}','["SALY_HOME_IPHONE16PRO"]'::jsonb,true),'PENDIENTE'
FROM saly.creative_order_items WHERE id=2501;
DO $$
BEGIN
 BEGIN
  PERFORM saly.creative_item_context_l2a(92031);
  RAISE EXCEPTION 'T03_DID_NOT_BLOCK';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM 'LF_ITEM_ASSET_NOT_VERIFIED' THEN RAISE EXCEPTION 'T03_WRONG_ERROR:%',SQLERRM; END IF;
 END;
END $$;
ROLLBACK;
SQL
echo 'T03|PASS'
