BEGIN;
-- Candidate composition source assets only. SVG text lives in Supabase;
-- no external URI, generation, official token or template activation.
DO $assets$
DECLARE
  inserted integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM visual.source_assets
    WHERE id=6 AND brand_code='SALY' AND independent_sha_verified
      AND source_sha256='d8dd1a4da97f3ac180e060a4fb23ba4f91d7e37668fe905135c769fd3aa68850') THEN
    RAISE EXCEPTION 'SALY_SOURCE_REFERENCE_MISMATCH';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
    WHERE i.id=9 AND i.code='HOME_B' AND i.status='PENDIENTE'
      AND i.context_json->>'template_version_id'='4'
      AND i.context_json->'handoff_review'->'composition'->'geometry'->'viewport'='[400,848]'::jsonb
      AND o.scope_json->'render_authorized'='false'::jsonb
      AND i.context_json->'handoff_review'->'transmitted'='false'::jsonb) THEN
    RAISE EXCEPTION 'SALY_HOME_B_REVIEW_GUARD';
  END IF;
  WITH a(code,kind,svg) AS (VALUES
('SALY_IPHONE16PRO_FRAME_VECTOR','FRAME',$svg$<svg xmlns="http://www.w3.org/2000/svg" width="432" height="928" viewBox="0 0 432 928"><title>iPhone 16 Pro inspired candidate frame</title><defs><linearGradient id="metal"><stop stop-color="#6c6764"/><stop offset=".23" stop-color="#e1dcd5"/><stop offset=".52" stop-color="#b1a9a1"/><stop offset=".78" stop-color="#f2eee9"/><stop offset="1" stop-color="#746f6b"/></linearGradient></defs><path fill="url(#metal)" fill-rule="evenodd" d="M58 0H374Q432 0 432 58V870Q432 928 374 928H58Q0 928 0 870V58Q0 0 58 0Z M16 48H416V896H16Z"/><path fill="#111214" fill-rule="evenodd" d="M58 5H374Q427 5 427 58V870Q427 923 374 923H58Q5 923 5 870V58Q5 5 58 5Z M16 48H416V896H16Z"/><path fill="#fff" d="M16 48Q16 15 58 15H374Q416 15 416 48Z M16 896H416Q407 913 374 913H58Q25 913 16 896Z"/><rect x="155" y="21" width="122" height="24" rx="12" fill="#09090b"/><rect x="150" y="905" width="132" height="4" rx="2" fill="#111214"/></svg>$svg$),
('SALY_NAV_HOME_VECTOR','ICON',$svg$<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><title>Inicio activo</title><path fill="currentColor" d="M3 10a2 2 0 0 1 .69-1.51l7-6a2 2 0 0 1 2.62 0l7 6A2 2 0 0 1 21 10v10a1 1 0 0 1-1 1h-5v-5a3 3 0 0 0-6 0v5H4a1 1 0 0 1-1-1z"/></svg>$svg$),
('SALY_NAV_HISTORY_VECTOR','ICON',$svg$<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><title>Historial</title><g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9.5"/><path d="M12 6v6l4 2"/></g></svg>$svg$),
('SALY_NAV_EXPLORE_VECTOR','ICON',$svg$<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><title>Explorar</title><g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></g></svg>$svg$),
('SALY_NAV_PROFILE_VECTOR','ICON',$svg$<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><title>Perfil</title><g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="7" r="4"/><path d="M3 21v-1a9 9 0 0 1 18 0v1z"/></g></svg>$svg$)
  ), expected(code,sha) AS (VALUES
('SALY_IPHONE16PRO_FRAME_VECTOR','1e9fc1061686da752256181b6ad62f086ff20fb4f2fcc62841e07049e4277529'),
('SALY_NAV_EXPLORE_VECTOR','9b7de5d834477202f53a6da970e44af3e5887ef6d4c1c05547100c96550489c5'),
('SALY_NAV_HISTORY_VECTOR','b62158d340d6230ca5c9db956f83c647fb137600dff4d90a461e28c092a95f8e'),
('SALY_NAV_HOME_VECTOR','a25cbdfb38990373017c919cb97b7c44dc2f6e28b39e44329381bc6799a01f88'),
('SALY_NAV_PROFILE_VECTOR','bc8ce2d35903b74e13cfbd2ecb83188c70245a67d0506fbdf5f644ae9fafaeae')
  )
  INSERT INTO visual.source_assets(brand_code,asset_code,version_number,source_kind,provider,file_ref,
    source_sha256,independent_sha_verified,approval_status,metadata)
  SELECT 'SALY',a.code,1,a.kind,'SUPABASE_INLINE_SVG',
    'visual.source_assets/SALY/'||a.code||'/1#metadata.svg',
    expected.sha,false,'CANDIDATE',
    jsonb_build_object('svg',a.svg,'mime_type','image/svg+xml','encoding','UTF-8',
      'reference_asset_id',6,'derivation','NEW_VECTOR_INTERPRETATION_NOT_EXACT_EXTRACTION',
      'usage','COMPOSITION_REVIEW_ONLY','byte_size',octet_length(a.svg),
      'geometry',CASE WHEN a.kind='FRAME' THEN
        '{"outer":[432,928],"app_opening":[16,48,400,848],"device_exactness":"ILLUSTRATIVE_ONLY"}'::jsonb
        ELSE '{"viewBox":[0,0,24,24],"color":"currentColor","stroke_or_fill":"asset_defined"}'::jsonb END)
  FROM a JOIN expected USING(code)
  WHERE xml_is_well_formed_document(a.svg)
    AND encode(extensions.digest(convert_to(a.svg,'UTF8'),'sha256'),'hex')=expected.sha;
  GET DIAGNOSTICS inserted=ROW_COUNT;
  IF inserted<>5 THEN RAISE EXCEPTION 'SALY_ASSET_INSERT_COUNT %',inserted; END IF;
  IF (SELECT count(*) FROM visual.source_assets WHERE brand_code='SALY'
    AND asset_code IN ('SALY_IPHONE16PRO_FRAME_VECTOR','SALY_NAV_HOME_VECTOR','SALY_NAV_HISTORY_VECTOR','SALY_NAV_EXPLORE_VECTOR','SALY_NAV_PROFILE_VECTOR')
    AND version_number=1 AND approval_status='CANDIDATE'
    AND NOT independent_sha_verified AND approval_ref IS NULL
    AND source_sha256=encode(extensions.digest(convert_to(metadata->>'svg','UTF8'),'sha256'),'hex')
    AND provider='SUPABASE_INLINE_SVG')<>5 THEN RAISE EXCEPTION 'SALY_ASSET_READBACK_MISMATCH'; END IF;
END $assets$;
COMMIT;
