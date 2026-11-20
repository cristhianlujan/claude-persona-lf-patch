-- SALY visual sources: first small batch of SIX original PNGs from Drive.
-- Files remain intact in Google Drive; only references + independently computed SHA256.
-- CANDIDATE despite location in Pantallas_Aprobadas: approval receipt not validated per asset.
-- No standards, activation, output generation, UI/Router changes.
-- PR -> PASE -> ready-to-merge -> LF Migration Merge Train only.
BEGIN;

DO $preflight$
BEGIN
 IF to_regclass('visual.source_assets') IS NULL OR
    (SELECT COUNT(*) FROM saly.proyecto WHERE codigo='SALY-001' AND estado='ACTIVO')<>1 OR
    (SELECT COUNT(*) FROM supabase_migrations.schema_migrations WHERE name='lf_saly_visual_catalog_empty_v1')<>1
 THEN RAISE EXCEPTION 'SALY_SCREEN_SOURCES_VISUAL_CATALOG_MISSING'; END IF;
 IF (SELECT COUNT(*) FROM visual.source_assets)<>0
 THEN RAISE EXCEPTION 'SALY_SCREEN_SOURCES_BASELINE_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM visual.standard_activations)
 THEN RAISE EXCEPTION 'SALY_SCREEN_SOURCES_UNEXPECTED_ACTIVE_STANDARDS'; END IF;
END $preflight$;

INSERT INTO visual.source_assets
 (asset_code,version_number,source_kind,provider,file_ref,source_sha256,
  independent_sha_verified,approval_status,metadata)
VALUES
  ('SALY_HOME_IPHONE16PRO',1,'SCREEN','GOOGLE_DRIVE','1YXWAS8McVi0Y91FEtMbCW6M57-6D9em9','3d80592dc94938ea6e4d34727a99a0aec242b43838e2815820b72e87d649d33e',true,'CANDIDATE','{"source_filename":"SALY_HOME_IPHONE16PRO_v1.1.png","mime_type":"image/png","byte_size":1343036,"width_px":1086,"height_px":1448,"folder_id":"1qhQwIhuJJ-EvKFRDxEVf-R265_gGh-65","source_url":"https://drive.google.com/file/d/1YXWAS8McVi0Y91FEtMbCW6M57-6D9em9/view?usp=drivesdk","byte_verification_method":"GOOGLE_DRIVE_AUTHENTICATED_RAW_DOWNLOAD_PYTHON_SHA256","verified_date":"2026-11-20","status_note":"CANDIDATE_ONLY_REQUIRES_APPROVAL_RECEIPT"}'::jsonb),
  ('SALY_SOLICITAR_ADELANTO',1,'SCREEN','GOOGLE_DRIVE','1n9nNgKow7jcMJuX1tI6JXXAeye5rXJhJ','65d537d740b9dd19fbf953cbc0574ad55206c00a67f0a10c2035d5e1d21842fc',true,'CANDIDATE','{"source_filename":"SALY_SOLICITAR_ADELANTO_INTELIGENTE_v1.0.png","mime_type":"image/png","byte_size":1639029,"width_px":1024,"height_px":1536,"folder_id":"1qhQwIhuJJ-EvKFRDxEVf-R265_gGh-65","source_url":"https://drive.google.com/file/d/1n9nNgKow7jcMJuX1tI6JXXAeye5rXJhJ/view?usp=drivesdk","byte_verification_method":"GOOGLE_DRIVE_AUTHENTICATED_RAW_DOWNLOAD_PYTHON_SHA256","verified_date":"2026-11-20","status_note":"CANDIDATE_ONLY_REQUIRES_APPROVAL_RECEIPT"}'::jsonb),
  ('SALY_MI_DISPONIBLE_DIARIO',1,'SCREEN','GOOGLE_DRIVE','1HkgD-u2jfqBfyewEkDPepB_f6pKnaXni','5bf71b4e9ec9a752c27c3ac7d3aeb97e0a443a484a75e550cef47c3a5b8b6c58',true,'CANDIDATE','{"source_filename":"SALY_MI_DISPONIBLE_ASIGNACION_DIARIA_v1.0.png","mime_type":"image/png","byte_size":1308404,"width_px":1024,"height_px":1536,"folder_id":"1qhQwIhuJJ-EvKFRDxEVf-R265_gGh-65","source_url":"https://drive.google.com/file/d/1HkgD-u2jfqBfyewEkDPepB_f6pKnaXni/view?usp=drivesdk","byte_verification_method":"GOOGLE_DRIVE_AUTHENTICATED_RAW_DOWNLOAD_PYTHON_SHA256","verified_date":"2026-11-20","status_note":"CANDIDATE_ONLY_REQUIRES_APPROVAL_RECEIPT"}'::jsonb),
  ('SALY_SOPORTE_AI_PROACTIVO',1,'SCREEN','GOOGLE_DRIVE','1UqFaIv0MsBC7f9IVeM9MHr4ckG6i3CM5','b67ab3b4fd04aec3d3bee6ae1dd99a0fe40239c0d0ee1728d815e2bb2abd7567',true,'CANDIDATE','{"source_filename":"SALY_SOPORTE_AI_v1.1_INICIO_PROACTIVO_APROBADA.png","mime_type":"image/png","byte_size":553278,"width_px":560,"height_px":1086,"folder_id":"1qhQwIhuJJ-EvKFRDxEVf-R265_gGh-65","source_url":"https://drive.google.com/file/d/1UqFaIv0MsBC7f9IVeM9MHr4ckG6i3CM5/view?usp=drivesdk","byte_verification_method":"GOOGLE_DRIVE_AUTHENTICATED_RAW_DOWNLOAD_PYTHON_SHA256","verified_date":"2026-11-20","status_note":"CANDIDATE_ONLY_REQUIRES_APPROVAL_RECEIPT"}'::jsonb),
  ('SALY_SEGUIMIENTO_MINIMAL',1,'SCREEN','GOOGLE_DRIVE','177828miKHoOkhQQwYP7XfMbaWo0Asvbf','91fd15fea8830e7dd9323b55feed114caa824ce57cb007ffe967f8b5946cd7c7',true,'CANDIDATE','{"source_filename":"SALY_SEGUIMIENTO_MINIMAL_v1.5.png","mime_type":"image/png","byte_size":595055,"width_px":596,"height_px":1312,"folder_id":"1qhQwIhuJJ-EvKFRDxEVf-R265_gGh-65","source_url":"https://drive.google.com/file/d/177828miKHoOkhQQwYP7XfMbaWo0Asvbf/view?usp=drivesdk","byte_verification_method":"GOOGLE_DRIVE_AUTHENTICATED_RAW_DOWNLOAD_PYTHON_SHA256","verified_date":"2026-11-20","status_note":"CANDIDATE_ONLY_REQUIRES_APPROVAL_RECEIPT"}'::jsonb),
  ('SALY_REWARDS_HOME_SORTEOS',1,'SCREEN','GOOGLE_DRIVE','1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ','d8dd1a4da97f3ac180e060a4fb23ba4f91d7e37668fe905135c769fd3aa68850',true,'CANDIDATE','{"source_filename":"SALY_HOME_IPHONE16PRO_REWARDS_SORTEOS_V3_APROBADA.png","mime_type":"image/png","byte_size":1623170,"width_px":1086,"height_px":1448,"folder_id":"1qhQwIhuJJ-EvKFRDxEVf-R265_gGh-65","source_url":"https://drive.google.com/file/d/1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ/view?usp=drivesdk","byte_verification_method":"GOOGLE_DRIVE_AUTHENTICATED_RAW_DOWNLOAD_PYTHON_SHA256","verified_date":"2026-11-20","status_note":"CANDIDATE_ONLY_REQUIRES_APPROVAL_RECEIPT"}'::jsonb);

DO $postflight$
DECLARE
 v_count bigint;
BEGIN
 SELECT COUNT(*) INTO v_count FROM visual.source_assets
 WHERE brand_code='SALY' AND source_kind='SCREEN'
 AND provider='GOOGLE_DRIVE' AND approval_status='CANDIDATE'
 AND approval_ref IS NULL AND independent_sha_verified
 AND source_sha256 ~ '^[a-f0-9]{64}$'
 AND metadata->>'folder_id'='1qhQwIhuJJ-EvKFRDxEVf-R265_gGh-65'
 AND (metadata->>'byte_size')::bigint > 0
 AND (metadata->>'width_px')::integer > 0
 AND (metadata->>'height_px')::integer > 0;
 IF v_count<>6 OR (SELECT COUNT(*) FROM visual.source_assets)<>6
 THEN RAISE EXCEPTION 'SALY_SCREEN_SOURCES_EXPECTED_SIX_VERIFIED_CANDIDATES'; END IF;
 IF (SELECT COUNT(*) FROM visual.source_assets WHERE approval_status='APPROVED')<>0
    OR (SELECT COUNT(*) FROM visual.standard_activations)<>0
    OR (SELECT COUNT(*) FROM visual.standard_versions)<>0
    OR (SELECT COUNT(*) FROM visual.generation_receipts)<>0
 THEN RAISE EXCEPTION 'SALY_SCREEN_SOURCES_MUST_NOT_AUTHORIZE_RENDER'; END IF;
END $postflight$;

COMMIT;
