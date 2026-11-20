-- SALY Home v3: optional card elevation prototype. EXPLORE/CANDIDATE ONLY.
-- All values are a proposal inferred from a flattened PNG, not exact native design source.
BEGIN;
DO $preflight$
BEGIN
 IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001' AND estado='ACTIVO')<>1
 OR (SELECT count(*) FROM saly.identity_elements e JOIN saly.proyecto p ON e.project_id=p.id WHERE p.codigo='SALY-001')<>54
 OR (SELECT count(*) FROM saly.identity_versions v JOIN saly.identity_elements e ON e.id=v.element_id JOIN saly.proyecto p ON p.id=e.project_id WHERE p.codigo='SALY-001')<>54
 OR (SELECT count(*) FROM saly.v_identity_current WHERE project_code='SALY-001')<>2
 OR (SELECT count(*) FROM saly.identity_elements WHERE code LIKE 'candidate.saly_home_v3.%')<>6
 THEN RAISE EXCEPTION 'SALY_HOME_ELEVATION_BASELINE_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM saly.identity_elements WHERE code='candidate.saly_home_v3.elevation.card.hero')
 THEN RAISE EXCEPTION 'SALY_HOME_ELEVATION_ALREADY_REGISTERED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM visual.source_assets
    WHERE asset_code='SALY_REWARDS_HOME_SORTEOS' AND source_sha256='d8dd1a4da97f3ac180e060a4fb23ba4f91d7e37668fe905135c769fd3aa68850'
      AND independent_sha_verified AND approval_status='CANDIDATE')
 THEN RAISE EXCEPTION 'SALY_HOME_ELEVATION_IMAGE_SOURCE_MISSING'; END IF;
END $preflight$;
WITH created AS (
INSERT INTO saly.identity_elements
 (project_id,code,family,value_type,name,description,is_required,is_protected,status,metadata)
SELECT p.id,'candidate.saly_home_v3.elevation.card.hero','LAYOUT','JSON','elevation.card.hero',
'Flexible visual exploration for card shadow. Not native px and not locked as design system.',
false,false,'DRAFT',
jsonb_build_object(
 'source_artifact','SALY_HOME_REWARDS_SORTEOS_V3',
 'source_file_id','1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ',
 'source_file_sha256','d8dd1a4da97f3ac180e060a4fb23ba4f91d7e37668fe905135c769fd3aa68850',
 'source_pack_sha256','0571e2de1e5bdb7dd2b9afb06a024abb293beff6a37bacc1e24c33c80e04fbdb',
 'source_confidence','PROPOSED_NOT_MEASURED',
 'creative_policy','FLEXIBLE_OPTIONAL',
 'device_coordinates','FLATTENED_MOCKUP_PIXELS_NOT_NATIVE',
 'import_status','CANDIDATE_ONLY',
 'canonical_binding','NOT_MAPPED_TO_APPROVED_KEYS'
)
FROM saly.proyecto p WHERE p.codigo='SALY-001'
RETURNING id
)
INSERT INTO saly.identity_versions
 (element_id,version_number,channel_code,audience_code,value_json,
  approval_status,valid_from,valid_to,approval_reference,change_reason,metadata)
SELECT c.id,1,'GLOBAL','ALL',
 jsonb_build_object('value',jsonb_build_object(
   'offset_x',0,'offset_y',4,'blur',16,'spread',0,
   'color','#081631','opacity',0.1)),
 'CANDIDATE',NULL,NULL,NULL,
 'Home screenshot suggests soft shadow; values proposed to experiment, not exact measured geometry',
 jsonb_build_object('not_effective',true,'approval_required_for_activation',true,
    'source_file_id','1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ',
    'source_pack_sha256','0571e2de1e5bdb7dd2b9afb06a024abb293beff6a37bacc1e24c33c80e04fbdb',
    'device_coordinate_warning','FLATTENED_MOCKUP_NOT_NATIVE',
    'creative_policy','OPTIONAL')
FROM created c;
DO $postflight$
DECLARE
 v_one int;
BEGIN
 SELECT count(*) INTO v_one FROM saly.identity_elements e
 JOIN saly.identity_versions v ON v.element_id=e.id
 WHERE e.code='candidate.saly_home_v3.elevation.card.hero'
  AND e.family='LAYOUT' AND e.value_type='JSON' AND e.status='DRAFT'
  AND NOT e.is_required AND NOT e.is_protected
  AND v.approval_status='CANDIDATE' AND v.valid_from IS NULL
  AND v.approval_reference IS NULL AND v.value_json#>>'{value,blur}'='16'
  AND v.value_json#>>'{value,opacity}'='0.1'
  AND v.metadata->>'creative_policy'='OPTIONAL';
 IF v_one<>1 THEN RAISE EXCEPTION 'SALY_HOME_ELEVATION_CANDIDATE_READBACK_FAIL'; END IF;
 IF (SELECT count(*) FROM saly.identity_elements e JOIN saly.proyecto p ON p.id=e.project_id WHERE p.codigo='SALY-001')<>55
 OR (SELECT count(*) FROM saly.identity_versions v JOIN saly.identity_elements e ON e.id=v.element_id JOIN saly.proyecto p ON p.id=e.project_id WHERE p.codigo='SALY-001')<>55
 OR (SELECT count(*) FROM saly.v_identity_current WHERE project_code='SALY-001')<>2
 OR (SELECT count(*) FROM visual.standard_activations)<>0
 THEN RAISE EXCEPTION 'SALY_HOME_ELEVATION_LEAKED_OFFICIAL_OR_COUNT_DRIFT'; END IF;
END $postflight$;
COMMIT;
