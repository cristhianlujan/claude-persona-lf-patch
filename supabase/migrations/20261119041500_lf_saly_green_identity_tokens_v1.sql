-- SALY-only authorized green identity tokens v1.
-- Owner approval: ChatGPT conversation, 2026-11-18 (America/Lima), "Ok"
-- immediately after recommendation of #00C853 brand + #008200 functional CTA.
-- Provenance: "Identidad de Marca SALY.png" (Library reference) for #00C853;
-- SALY_DS_V1 candidate GitHub PR #3715 for #008200; original proposals were
-- candidates, and only these two values were selected by owner here.
-- No LF tokens, typography, navy, other colors, channels, or new logo values.
-- Canonical route: PR -> exact-head CI/PASE -> ready-to-merge -> Merge Train -> ledger/readback.
BEGIN;
DO $preflight$
BEGIN
  IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001')<>1 THEN
    RAISE EXCEPTION 'SALY_GREEN_PROJECT_NOT_UNIQUE';
  END IF;
  IF (SELECT count(*) FROM saly.identity_elements)<>0
    OR (SELECT count(*) FROM saly.identity_versions)<>0 THEN
    RAISE EXCEPTION 'SALY_GREEN_IDENTITY_TARGET_NOT_EMPTY';
  END IF;
  IF (SELECT count(*) FROM saly.brand_assets WHERE approval_status='APPROVED')<>8 THEN
    RAISE EXCEPTION 'SALY_GREEN_APPROVED_LOGO_BASELINE_DRIFT';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='saly.identity_versions'::regclass
                   AND conname='identity_versions_no_overlap') THEN
    RAISE EXCEPTION 'SALY_GREEN_TEMPORAL_GUARD_MISSING';
  END IF;
END
$preflight$;

WITH seed(code,name,description) AS (
  VALUES
    ('color.brand.primary','Saly Primary Green',
      'Approved SALY brand/identity green. Accent and branding only; not white-text button.'),
    ('color.action.primary.bg','Saly Primary Action Green',
      'Approved darker SALY green for primary buttons and white functional text.')
)
INSERT INTO saly.identity_elements
  (project_id,code,family,value_type,name,description,
   is_required,is_protected,status,decision_id,metadata)
SELECT
  p.id,s.code,'COLOR','COLOR',s.name,s.description,
  true,true,'ACTIVE',NULL,
  jsonb_build_object(
    'approval_authority','OWNER_EXPLICIT_CHAT_CONFIRMATION',
    'approval_date_local','2026-11-18',
    'approval_conversation_scope','SALY_GREEN_BRAND_AND_CTA_ONLY',
    'base_variants_source','SALY brand identity Library and SALY_DS_V1 candidate',
    'protected_semantics','REQUIRES_GOVERNED_CHANGE'
  )
FROM saly.proyecto p CROSS JOIN seed s
WHERE p.codigo='SALY-001';

WITH seed(code,hex,usage,source) AS (
  VALUES
    ('color.brand.primary','#00C853',
      'BRAND_ONLY_NOT_WHITE_TEXT_CTA',
      'LIBRARY:Identidad de Marca SALY.png'),
    ('color.action.primary.bg','#008200',
      'CTA_BACKGROUND_FOR_WHITE_TEXT',
      'GITHUB:PR3715:SALY_DS_V1_CANDIDATE')
)
INSERT INTO saly.identity_versions
 (element_id,version_number,channel_code,audience_code,value_json,
  approval_status,valid_from,valid_to,decision_id,approval_reference,change_reason,metadata)
SELECT
  e.id,1,'GLOBAL','ALL',
  jsonb_build_object('value',s.hex,'format','HEX','usage',s.usage),
  'APPROVED',transaction_timestamp(),NULL,NULL,
  'OWNER_CHAT_APPROVAL:2026-11-18:SALY_GREEN_BRAND_CTA',
  'Owner selected #00C853 identity and #008200 CTA; other proposed SALY tokens not approved here.',
  jsonb_build_object(
    'source',s.source,
    'approval_authority','OWNER_EXPLICIT_CHAT_CONFIRMATION',
    'approval_date_local','2026-11-18',
    'valid_from_meaning','REGISTRY_ACTIVATION_NOT_RETROACTIVE_DESIGN_APPROVAL',
    'white_text_usage',CASE WHEN s.code='color.action.primary.bg'
      THEN 'WCAG_AA_NORMAL_TEXT_CONTRAST_VERIFIED_5_TO_1'
      ELSE 'NOT_APPROVED_FOR_WHITE_TEXT_CTA' END
  )
FROM saly.identity_elements e
JOIN saly.proyecto p ON p.id=e.project_id
JOIN seed s ON s.code=e.code
WHERE p.codigo='SALY-001';

DO $postflight$
DECLARE
  v_count integer;
  v_asset_count integer;
  v_app_count integer;
  v_web_count integer;
  v_duplicate_rejected boolean := false;
BEGIN
  SELECT count(*) INTO v_count
  FROM saly.identity_elements e
  JOIN saly.proyecto p ON p.id=e.project_id
  JOIN saly.identity_versions v ON v.element_id=e.id
  WHERE p.codigo='SALY-001'
    AND e.status='ACTIVE' AND e.is_required
    AND e.is_protected AND e.family='COLOR' AND e.value_type='COLOR'
    AND v.approval_status='APPROVED' AND v.channel_code='GLOBAL'
    AND v.audience_code='ALL' AND v.version_number=1
    AND v.valid_from<=transaction_timestamp() AND v.valid_to IS NULL
    AND v.approval_reference='OWNER_CHAT_APPROVAL:2026-11-18:SALY_GREEN_BRAND_CTA'
    AND ((e.code='color.brand.primary' AND v.value_json->>'value'='#00C853')
      OR (e.code='color.action.primary.bg' AND v.value_json->>'value'='#008200'));
  IF v_count<>2 THEN RAISE EXCEPTION 'SALY_GREEN_POSTFLIGHT_PAIR_NOT_EXACT'; END IF;
  IF (SELECT count(*) FROM saly.identity_elements)<>2 OR
     (SELECT count(*) FROM saly.identity_versions)<>2 THEN
    RAISE EXCEPTION 'SALY_GREEN_UNEXPECTED_IDENTITY_ROWS';
  END IF;
  SELECT count(*) INTO v_asset_count FROM saly.brand_assets
  WHERE approval_status='APPROVED';
  IF v_asset_count<>8 THEN
    RAISE EXCEPTION 'SALY_GREEN_LOGO_BASELINE_CHANGED';
  END IF;

  SELECT count(*) INTO v_app_count
  FROM saly.resolve_identity('SALY-001','APP','B2C',transaction_timestamp());
  SELECT count(*) INTO v_web_count
  FROM saly.resolve_identity('SALY-001','WEB','B2B',transaction_timestamp());
  IF v_app_count<>2 OR v_web_count<>2 THEN
    RAISE EXCEPTION 'SALY_GREEN_RESOLVER_INHERITANCE_FAILED APP=% WEB=%',
      v_app_count,v_web_count;
  END IF;

  BEGIN
    INSERT INTO saly.identity_versions
      (element_id,version_number,channel_code,audience_code,
       value_json,approval_status,valid_from,approval_reference)
    SELECT e.id,2,'GLOBAL','ALL',
      '{"value":"#FFFFFF"}'::jsonb,'APPROVED',transaction_timestamp(),
      'SELFTEST_NEVER_PERSIST'
    FROM saly.identity_elements e
    WHERE e.code='color.brand.primary';
  EXCEPTION WHEN exclusion_violation THEN
    v_duplicate_rejected := true;
  END;
  IF NOT v_duplicate_rejected THEN
    RAISE EXCEPTION 'SALY_GREEN_TEMPORAL_NEGATIVE_TEST_FAILED';
  END IF;
  IF (SELECT count(*) FROM saly.identity_versions)<>2 THEN
    RAISE EXCEPTION 'SALY_GREEN_NEGATIVE_TEST_LEAK';
  END IF;
END
$postflight$;
COMMIT;
