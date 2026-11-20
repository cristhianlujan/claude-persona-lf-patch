-- SALY_VISUAL_CONTEXT_INVENTORY_V0_1 — SELECT read-only.
-- SOLO para fuente de inventario de SALY, no habilita render ni modifica tablas.
-- Proyecto SALY-001 se valida externamente contra el RUN autorizado.
WITH project AS (
  SELECT p.id,p.codigo
  FROM saly.proyecto p
  WHERE p.codigo='SALY-001'
),
tokens AS (
 SELECT v.element_code,v.version_id,v.version_number,v.channel_code,
        v.audience_code,v.value_json,v.valid_from,v.valid_to
 FROM saly.v_identity_current v
 JOIN project p ON p.codigo=v.project_code
),
logos AS (
 SELECT a.id,a.code,a.version_number,a.file_provider,a.external_file_id,
        a.sha256,a.approval_status,a.approval_reference,a.metadata,
        a.valid_from,a.valid_to
 FROM saly.brand_assets a JOIN project p ON p.id=a.project_id
 WHERE a.approval_status='APPROVED' AND now()>=a.valid_from
   AND (a.valid_to IS NULL OR now()<a.valid_to)
)
SELECT jsonb_build_object(
 'schema_version','SALY_VISUAL_CONTEXT_INVENTORY_V0_1',
 'status','SOURCE_INVENTORY_ONLY',
 'business_code','SALY',
 'project_code',(SELECT codigo FROM project LIMIT 1),
 'as_of',now(),
 'effective_token_count',(SELECT count(*) FROM tokens),
 'effective_tokens',(
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'element_code',t.element_code,'version_id',t.version_id,
      'version_number',t.version_number,'channel',t.channel_code,
      'audience',t.audience_code,'value_json',t.value_json,
      'valid_from',t.valid_from,'valid_to',t.valid_to)
      ORDER BY t.element_code),'[]'::jsonb) FROM tokens t),
 'approved_asset_count',(SELECT count(*) FROM logos),
 'approved_assets',(
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'code',a.code,'asset_id',a.id,'version_number',a.version_number,
      'provider',a.file_provider,'file_ref',a.external_file_id,
      'registered_sha256',a.sha256,
      'independent_sha_verified',
        coalesce((a.metadata->>'sha256_independent_byte_check')::boolean,false),
      'approval_reference',a.approval_reference)
      ORDER BY a.code),'[]'::jsonb) FROM logos a),
 'standard_catalog_exists',(to_regclass('visual.standard_activations') IS NOT NULL),
 'active_standard_version_id',NULL,
 'blocking_codes',jsonb_build_array(
   CASE WHEN to_regclass('visual.standard_activations') IS NULL
     THEN 'STANDARD_CATALOG_NOT_IMPLEMENTED'
     ELSE 'STANDARD_CATALOG_EXISTS_BUT_NOT_RESOLVED' END,
   'ACTIVE_STANDARD_NOT_RESOLVED','APP_SCREEN_AND_MOCKUP_SOURCES_NOT_VERIFIED'),
 'image_generation_allowed',false
) AS result;
