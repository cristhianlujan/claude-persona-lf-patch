-- PR-J phase 1: source-bound preflight only. The Merge Train makes the
-- canonical ACTUALIZACION_DB_LF receipt after applying this no-business-write migration.
-- The real PG17 RULE_CONTRACT_LEVEL report is a separate exact-head PR check.
-- No AUTH-020 UPDATE, no direct V2 decision and no invented Train receipt here.
BEGIN;
DO $pr_j_source$
DECLARE v_sha text; v_md5 text; v_ttl text;
BEGIN
 SELECT public.lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-020'),
        md5((to_jsonb(r)-'updated_at')::text)
 INTO v_sha,v_md5
 FROM lf_ops.reglas r WHERE codigo='B2B-RULE-AUTH-020' AND estado='VIGENTE';
 IF v_sha IS DISTINCT FROM '8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8'
 OR v_md5 IS DISTINCT FROM '7588d5a7de4d94a864fca9e63cd10ebe'
 THEN RAISE EXCEPTION 'PR_J_AUTH020_SOURCE_DRIFT'; END IF;
 SELECT config_value INTO v_ttl FROM public.lf_global_config
 WHERE scope='AUTH' AND config_key='TEMP_KEY_TTL_HOURS'
   AND value_type='INTEGER' AND value_status='REAL'
 ORDER BY valid_from DESC LIMIT 1;
 IF v_ttl IS DISTINCT FROM '24'
 THEN RAISE EXCEPTION 'PR_J_TTL_GLOBAL_DRIFT'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas)<>579
 OR (SELECT count(*) FROM lf_ops.perfiles_permisos WHERE permission_id=38 AND status='VIGENTE')<>0
 OR (SELECT count(*) FROM lf_ops.politicas_seguridad WHERE security_policy_id=20 AND status='CANDIDATO')<>1
 THEN RAISE EXCEPTION 'PR_J_SCOPE_BASELINE_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_ig_functional_train_evidence_v1
           WHERE rule_code='B2B-RULE-AUTH-020')
 THEN RAISE EXCEPTION 'PR_J_PREEXISTING_AUTH020_EVIDENCE'; END IF;
 RAISE NOTICE 'PR_J_SOURCE_PREFLIGHT_PASS sha=8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8 patch=adaffe6a15e705fc4ec48fa809135088736915cd0d4446691ede078899704a02 candidate=16729473fcfc98cb04a04d2489cfa6338cb59f1c1cace12ce9443a4c24bee061 scope=RULE_CONTRACT_LEVEL';
END
$pr_j_source$;
COMMIT;
