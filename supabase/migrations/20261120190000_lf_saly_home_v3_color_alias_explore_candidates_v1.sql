-- SALY HOME V3 EXPLORE: six candidate colors/aliases only. No production promotion.
-- Source: approved-as-IMAGE Home Rewards/Sorteos v3; token colors are ESTIMATES.
-- Existing 32 reused DS_V1 candidates are not cloned.
-- No effect on approved brand=#00C853 or functional CTA=#008200.
BEGIN;
DO $preflight$
BEGIN
 IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001' AND estado='ACTIVO')<>1
 THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_PROJECT_DRIFT'; END IF;
 IF (SELECT count(*) FROM saly.identity_elements e JOIN saly.proyecto p ON p.id=e.project_id
    WHERE p.codigo='SALY-001')<>48
    OR (SELECT count(*) FROM saly.identity_versions v JOIN saly.identity_elements e ON e.id=v.element_id
      JOIN saly.proyecto p ON p.id=e.project_id WHERE p.codigo='SALY-001')<>48
 THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_EXPECTED_BASELINE_48'; END IF;
 IF (SELECT count(*) FROM saly.v_identity_current WHERE project_code='SALY-001')<>2
 THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_APPROVED_BASELINE_DRIFT'; END IF;
 IF (SELECT count(*) FROM saly.v_identity_current WHERE project_code='SALY-001' AND
     ((element_code='color.brand.primary' AND value_json->>'value'='#00C853')
       OR (element_code='color.action.primary.bg' AND value_json->>'value'='#008200')))<>2
 THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_OFFICIAL_GREEN_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM visual.source_assets a WHERE
      a.brand_code='SALY' AND a.asset_code='SALY_REWARDS_HOME_SORTEOS'
      AND a.provider='GOOGLE_DRIVE'
      AND a.file_ref='1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ'
      AND a.source_sha256='d8dd1a4da97f3ac180e060a4fb23ba4f91d7e37668fe905135c769fd3aa68850'
      AND a.independent_sha_verified=true AND a.approval_status='CANDIDATE')
 THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_REFERENCE_IMAGE_NOT_VERIFIED'; END IF;
 IF EXISTS(SELECT 1 FROM saly.identity_elements e JOIN saly.proyecto p ON p.id=e.project_id
    WHERE p.codigo='SALY-001' AND e.code LIKE 'candidate.saly_home_v3.%')
 THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_ALREADY_IMPORTED'; END IF;
END $preflight$;
DO $seed$
DECLARE
 x jsonb;
 project_id bigint;
 element_id bigint;
 n integer:=0;
 root text;
 alias_valid boolean;
BEGIN
 SELECT id INTO STRICT project_id FROM saly.proyecto WHERE codigo='SALY-001';
 FOR x IN SELECT t.value FROM jsonb_array_elements($input$[{"key":"color.surface.benefits","family":"COLOR","value_type":"COLOR","value":"#F4E7FD","kind":"ESTIMATED_COLOR","target_code":null},{"key":"semantic.color.navigation.active","family":"COLOR","value_type":"JSON","value":"{color.action.primary.bg}","kind":"ALIAS","target_code":"color.action.primary.bg"},{"key":"semantic.color.navigation.inactive","family":"COLOR","value_type":"JSON","value":"{color.ink.gray.600}","kind":"ALIAS","target_code":"candidate.saly_ds_v1.color.ink.gray.600"},{"key":"semantic.color.navigation.background","family":"COLOR","value_type":"JSON","value":"{color.surface.white}","kind":"ALIAS","target_code":"candidate.saly_ds_v1.color.surface.white"},{"key":"semantic.color.module.benefits.bg","family":"COLOR","value_type":"JSON","value":"{color.surface.benefits}","kind":"ALIAS","target_code":"candidate.saly_home_v3.color.surface.benefits"},{"key":"semantic.color.notification.badge","family":"COLOR","value_type":"COLOR","value":"#E62F40","kind":"ESTIMATED_COLOR","target_code":null}]$input$::jsonb) t(value)
 LOOP
   IF x->>'family' IS DISTINCT FROM 'COLOR'
      OR x->>'key' IS NULL OR x->>'value' IS NULL
      OR x->>'value_type' NOT IN ('COLOR','JSON')
      OR x->>'kind' NOT IN ('ALIAS','ESTIMATED_COLOR')
   THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_SEED_INVALID'; END IF;
   IF (x->>'kind'='ALIAS') THEN
      IF (x->>'value') !~ '^\\{[a-z0-9.]+\\}$'
        OR nullif(x->>'target_code','') IS NULL
      THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_ALIAS_SHAPE_INVALID'; END IF;
      alias_valid := EXISTS(SELECT 1 FROM saly.identity_elements e
        WHERE e.project_id=project_id AND e.code=x->>'target_code')
        OR (x->>'target_code'='candidate.saly_home_v3.color.surface.benefits');
      IF NOT alias_valid THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_ALIAS_TARGET_MISSING:%',x->>'target_code'; END IF;
   ELSIF (x->>'value') !~ '^#[A-F0-9]{6}$' THEN
      RAISE EXCEPTION 'SALY_HOME_TOKENS_COLOR_VALUE_INVALID'; 
   END IF;
   INSERT INTO saly.identity_elements
      (project_id,code,family,value_type,name,description,is_required,is_protected,status,decision_id,metadata)
   VALUES(project_id,'candidate.saly_home_v3.'||(x->>'key'),'COLOR',
      x->>'value_type',x->>'key',
      'Proposed from flattened Home v3 image; EXPLORE ONLY, not a brand or UI standard',
      false,false,'DRAFT',NULL,
      jsonb_build_object('source_artifact','SALY_HOME_REWARDS_SORTEOS_V3',
        'source_file_id','1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ',
        'source_file_sha256','d8dd1a4da97f3ac180e060a4fb23ba4f91d7e37668fe905135c769fd3aa68850',
        'source_pack_sha256','0571e2de1e5bdb7dd2b9afb06a024abb293beff6a37bacc1e24c33c80e04fbdb',
        'proposed_key',x->>'key','source_confidence',
          CASE WHEN x->>'kind'='ESTIMATED_COLOR' THEN 'APPROXIMATE'
            ELSE 'PROPOSED_ALIAS' END,
        'alias_target_code',x->>'target_code',
        'import_status','CANDIDATE_ONLY',
        'canonical_binding','NOT_MAPPED_TO_APPROVED_KEYS',
        'not_design_source_verified',true))
   RETURNING id INTO element_id;
   INSERT INTO saly.identity_versions
      (element_id,version_number,channel_code,audience_code,value_json,
       approval_status,valid_from,valid_to,decision_id,approval_reference,change_reason,metadata)
   VALUES(element_id,1,'GLOBAL','ALL',jsonb_build_object('value',x->'value'),
      'CANDIDATE',NULL,NULL,NULL,NULL,
      'SALY Home v3 exploration only; no owner approval for these values or role bindings',
      jsonb_build_object('not_effective',true,'approval_required_for_activation',true,
        'source_file_id','1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ',
        'source_file_sha256','d8dd1a4da97f3ac180e060a4fb23ba4f91d7e37668fe905135c769fd3aa68850',
        'source_pack_sha256','0571e2de1e5bdb7dd2b9afb06a024abb293beff6a37bacc1e24c33c80e04fbdb',
        'kind',x->>'kind','alias_target_code',x->>'target_code'));
   n:=n+1;
 END LOOP;
 IF n<>6 THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_EXPECTED_SIX_IMPORTED:%',n; END IF;
END $seed$;
DO $postflight$
BEGIN
 IF (SELECT count(*) FROM saly.identity_elements e JOIN saly.proyecto p ON p.id=e.project_id
    WHERE p.codigo='SALY-001')<>54
  OR (SELECT count(*) FROM saly.identity_versions v JOIN saly.identity_elements e ON e.id=v.element_id JOIN saly.proyecto p ON p.id=e.project_id WHERE p.codigo='SALY-001')<>54
 THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_MISMATCH_54'; END IF;
 IF (SELECT count(*) FROM saly.identity_elements e JOIN saly.identity_versions v ON v.element_id=e.id
      WHERE e.code LIKE 'candidate.saly_home_v3.%' AND e.status='DRAFT'
       AND NOT e.is_required AND NOT e.is_protected
       AND v.approval_status='CANDIDATE' AND v.version_number=1
       AND v.channel_code='GLOBAL' AND v.audience_code='ALL'
       AND v.valid_from IS NULL AND v.valid_to IS NULL AND v.approval_reference IS NULL)<>6
 THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_CANDIDATE_VISIBILITY_MISMATCH'; END IF;
 IF (SELECT count(*) FROM saly.v_identity_current WHERE project_code='SALY-001')<>2
 OR (SELECT count(*) FROM saly.v_identity_current WHERE project_code='SALY-001'
     AND ((element_code='color.brand.primary' AND value_json->>'value'='#00C853')
       OR (element_code='color.action.primary.bg' AND value_json->>'value'='#008200')))<>2
 THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_LEAKED_TO_CURRENT'; END IF;
 IF (SELECT count(*) FROM saly.identity_elements WHERE code='candidate.saly_ds_v1.semantic.color.action.primary.bg')<>1
 THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_DS_CONFLICT_WAS_TOUCHED'; END IF;
 IF (SELECT count(*) FROM visual.standard_activations)<>0
 THEN RAISE EXCEPTION 'SALY_HOME_TOKENS_UNEXPECTED_VISUAL_ACTIVATION'; END IF;
END $postflight$;
COMMIT;
