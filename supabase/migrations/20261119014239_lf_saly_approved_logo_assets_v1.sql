-- SALY-approved PNG logos / governed Git migration v1.
-- Authority: Google Drive acta 1CUetXF_XIc5DA8Rgo5XmH3iG2X4rsA3M; 8 approved PNGs (2026-11-18).
-- Hashes transcribed from approval acta, not independently recomputed from bytes.
-- No LF changes; no creative tokens, palettes, typography, tone or channel approvals.
BEGIN;
DO $pre$
BEGIN
 IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001')<>1
 THEN RAISE EXCEPTION 'SALY_LOGO_PROJECT_CARDINALITY'; END IF;
 IF (SELECT count(*) FROM saly.brand_assets)<>0
 THEN RAISE EXCEPTION 'SALY_LOGO_TARGET_ALREADY_POPULATED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='saly.brand_assets'::regclass
 AND conname='brand_assets_no_overlap')
 THEN RAISE EXCEPTION 'SALY_LOGO_TEMPORAL_GUARD_MISSING'; END IF;
END $pre$;
WITH approved(code,filename,drive_id,sha256) AS (VALUES
 ('logo.avatar.white','08_SALY_AVATAR_BLANCO.png','1sMbY-nV6O1Pcv3CvU2ik_iwHDhwv6n-Q','ce66973e631ca47c7af27b874cfb55356b695c2fb04b95a1f9877e7b6cb94a7c'),
 ('logo.icon.square.navy','06_SALY_ICONO_CUADRADO_NAVY.png','1xptyWlFnX6hBfaGS0_9MwPnJ3JVrC4HL','2a30146443d4fbcb9ad84a69f77731fb21cfe012c5f05a8046cef8464d9c608e'),
 ('logo.inverse.navy','02_SALY_INVERSO_FONDO_NAVY.png','1tHiDoVvwFK6zIuJJlWv08sFpx4hkB7R8','94c4423a20c74e6100fcef8899b5403ba6dfa16bb423e948346d3a59d3eb1cc1'),
 ('logo.monochrome.green.transparent','05_SALY_MONOCROMO_VERDE_TRANSPARENTE.png','1N9MSZ0luoZn6KcSQSUynqftyUCE-h-ID','a30cbddc4e6304ae00f3572d5807f5c45ca9427abc4fa59c646212c2901e565f'),
 ('logo.monochrome.navy.transparent','03_SALY_MONOCROMO_NAVY_TRANSPARENTE.png','1BVvtndJJFIdxbvQq4CG5U0Ix0PqMM_k7','2ffcdc9d53d57b814f7871238deffcf721d2a293600300d30ae4509585fa9c18'),
 ('logo.monochrome.white.navy','04_SALY_MONOCROMO_BLANCO_FONDO_NAVY.png','1RPkCJx_qolzi7y8frJOEHzWH35Wbkt-p','8b7b9b7b065f6453047a288b6dd31bf507c80b7244191c8311618090b2bcf3d8'),
 ('logo.primary.transparent','01_SALY_PRINCIPAL_TRANSPARENTE.png','1xQyhrhrqgjHvkPVSg1vYCgDjlFV7ox78','5573f0503ddb3dd1029221a9ee336d0e28155c392598286628dbf294da146995'),
 ('logo.signature.descriptor','07_SALY_FIRMA_CON_DESCRIPTOR.png','1KqcDXwur6JallAbybmlzKJ31JygYou0O','340c3fa384053be4fcba012f349fc5fc4969b85f213bed4e52fcc4316f418304')
)
INSERT INTO saly.brand_assets
(project_id,code,version_number,name,asset_kind,file_provider,external_file_id,sha256,
 approval_status,valid_from,valid_to,approval_reference,allowed_channels,metadata)
SELECT p.id,x.code,1,x.filename,'LOGO','GOOGLE_DRIVE',x.drive_id,x.sha256,
 'APPROVED',transaction_timestamp(),NULL,
 'GOOGLE_DRIVE_ACTA:1CUetXF_XIc5DA8Rgo5XmH3iG2X4rsA3M',ARRAY['GLOBAL']::text[],
 jsonb_build_object(
   'filename',x.filename,
   'source_folder_id','1hloW2-1LMxe322BQrBVk7Y_ZnnpaTQMv',
   'approval_acta_id','1CUetXF_XIc5DA8Rgo5XmH3iG2X4rsA3M',
   'approval_date','2026-11-18',
   'approval_scope','EIGHT_EXISTING_PNG_VARIANTS_ONLY',
   'sha256_origin','APPROVAL_ACTA',
   'sha256_independent_byte_check',false,
   'channel_specific_approval','NOT_DEFINED',
   'valid_from_meaning','REGISTERED_ACTIVE_SINCE_MIGRATION'
 )
FROM saly.proyecto p CROSS JOIN approved x WHERE p.codigo='SALY-001';
DO $post$
DECLARE n int; nf int; nc int; nh int;
BEGIN
 SELECT count(*),count(DISTINCT external_file_id),count(DISTINCT code),count(DISTINCT sha256)
 INTO n,nf,nc,nh
 FROM saly.brand_assets
 WHERE project_id=(SELECT id FROM saly.proyecto WHERE codigo='SALY-001')
 AND approval_status='APPROVED' AND asset_kind='LOGO' AND file_provider='GOOGLE_DRIVE'
 AND version_number=1 AND valid_from IS NOT NULL AND valid_to IS NULL
 AND approval_reference='GOOGLE_DRIVE_ACTA:1CUetXF_XIc5DA8Rgo5XmH3iG2X4rsA3M'
 AND metadata->>'sha256_origin'='APPROVAL_ACTA'
 AND metadata->>'sha256_independent_byte_check'='false';
 IF n<>8 OR nf<>8 OR nc<>8 OR nh<>8
 THEN RAISE EXCEPTION 'SALY_LOGO_POSTCHECK_WRONG_COUNTS:n=%,nf=%,nc=%,nh=%',n,nf,nc,nh; END IF;
 IF (SELECT count(*) FROM saly.brand_assets)<>8
 THEN RAISE EXCEPTION 'SALY_LOGO_UNEXPECTED_ROWS'; END IF;
 IF (SELECT count(*) FROM saly.identity_elements)<>0
 OR (SELECT count(*) FROM saly.identity_versions)<>0
 THEN RAISE EXCEPTION 'SALY_LOGO_IDENTITY_TABLE_DRIFT'; END IF;
END $post$;
COMMIT;
