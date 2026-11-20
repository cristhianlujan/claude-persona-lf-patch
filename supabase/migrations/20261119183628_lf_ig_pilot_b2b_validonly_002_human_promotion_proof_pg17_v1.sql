-- LF IG 13:30: AUTHORIZED OWNER APPROVAL, exact promotion_id + request_snapshot_sha256.
-- PG17 proof executes all official transition + replacement effects, then fully reverts
-- using real exception subtransaction AND outer ROLLBACK. No persistent change.
-- Production twin may change ONLY v_proof_only:=false and terminal COMMIT.
BEGIN;
DO $lf_ig_1330_b2b_validonly_replacement$
DECLARE
 v_proof_only boolean := true;
 v_old CONSTANT text := 'B2B-RULE-VALIDATION-VALID-ONLY-001';
 v_new CONSTANT text := 'B2B-RULE-VALIDATION-VALID-ONLY-002';
 v_pid CONSTANT text := 'PROM-25842222C948EDA4';
 v_hash CONSTANT text := 'be400abfbbf9f5a8deed36e673c84dc71a93e74414a4549ad25c69b35ff43b60';
 v_actor CONSTANT text := 'Cristhian Lujan';
 v_delete_reason CONSTANT text := 'REEMPLAZADA_POR:B2B-RULE-VALIDATION-VALID-ONLY-002';
 v_old_id integer;
 v_new_id integer;
 v_old_before jsonb;
 v_new_before jsonb;
 v_old_conf jsonb;
 v_new_conf jsonb;
 v_promotion_before jsonb;
 v_ci_before jsonb;
 v_cards_before jsonb;
 v_before_links jsonb;
 v_before_tests jsonb;
 v_before_versions text;
 v_before_all_rules text;
 v_before_cards_digest text;
 v_after_versions text;
 v_after_all_rules text;
 v_after_cards_digest text;
 v_preexisting_versions integer;
 v_preexisting_rules integer;
 v_dec jsonb;
 v_apply jsonb;
 v_score jsonb;
 v_count integer;
 v_link_count integer;
 v_test_count integer;
 v_citation_count integer;
 v_audit_ok boolean:=false;
BEGIN
 IF current_setting('server_version_num')::integer/10000<>17 THEN
   RAISE EXCEPTION 'LF_IG_1330_PG17_REQUIRED';
 END IF;
 SELECT count(*) INTO v_preexisting_rules FROM lf_ops.reglas;
 SELECT count(*) INTO v_preexisting_versions FROM lf_ops.reglas_versiones;
 IF v_preexisting_rules<>587 OR v_preexisting_versions<>586 THEN
   RAISE EXCEPTION 'LF_IG_1330_BASELINE_RULE_HISTORY_DRIFT:rules=%,versions=%',v_preexisting_rules,v_preexisting_versions;
 END IF;
 SELECT id,to_jsonb(r),valor_config INTO STRICT v_old_id,v_old_before,v_old_conf
 FROM lf_ops.reglas r WHERE codigo=v_old AND estado='VIGENTE';
 SELECT id,to_jsonb(r),valor_config INTO STRICT v_new_id,v_new_before,v_new_conf
 FROM lf_ops.reglas r WHERE codigo=v_new AND estado='CANDIDATO' AND pendiente_decision=true;
 SELECT to_jsonb(p) INTO STRICT v_promotion_before
 FROM public.lf_rule_promotion_v1 p WHERE promotion_id=v_pid
   AND rule_code=v_new AND status='PENDING' AND request_snapshot_sha256=v_hash
   AND decided_by IS NULL AND decided_at IS NULL AND applied_at IS NULL
   AND request_execution_id='EXEC-PROFILE-GATE2-8B455BD3FABBC952FFD3CB43';
 -- Official SHA function, exactly as used by decide_v1 and apply_v1.
 IF public.lf_asset_snapshot_sha_v1('REGLA',v_new) IS DISTINCT FROM v_hash THEN
   RAISE EXCEPTION 'LF_IG_1330_PROMOTION_HASH_STALE:%,expected=%',
    public.lf_asset_snapshot_sha_v1('REGLA',v_new),v_hash;
 END IF;
 v_score:=public.lf_rule_promotion_score_v1(
    'EXEC-PROFILE-GATE2-8B455BD3FABBC952FFD3CB43',v_new);
 IF v_score->>'decision' IS DISTINCT FROM 'MANUAL'
   OR (v_score->>'score')::integer<>80
   OR (v_score->>'A')::integer<>40 OR (v_score->>'B')::integer<>30
   OR (v_score->>'C')::integer<>0 OR (v_score->>'D')::integer<>10
 THEN RAISE EXCEPTION 'LF_IG_1330_PROMOTION_SCORE_DRIFT:%',v_score; END IF;
 IF (v_new_conf - 'lf_rule_scope' - 'lf_screen_ids' - 'lf_applicability'
      - 'lf_replaces_rule_code' - 'lf_promotion_authorized') IS DISTINCT FROM v_old_conf
   OR v_new_conf->>'lf_replaces_rule_code' IS DISTINCT FROM v_old
   OR v_new_conf->'lf_screen_ids' IS DISTINCT FROM '[44,66,67]'::jsonb
 THEN RAISE EXCEPTION 'LF_IG_1330_REPLACEMENT_CONFIG_DRIFT'; END IF;
 SELECT jsonb_agg(to_jsonb(l) ORDER BY l.pantalla_id) INTO v_before_links
   FROM lf_ops.reglas_pantallas l WHERE l.regla_id=v_old_id;
 SELECT jsonb_agg(to_jsonb(t) ORDER BY t.test_ref) INTO v_before_tests
   FROM lf_ops.regla_behavior_tests t WHERE t.regla_codigo=v_old;
 SELECT jsonb_agg(jsonb_build_object('codigo',r.codigo,'valor_config',r.valor_config)
     ORDER BY r.codigo) INTO v_cards_before FROM lf_ops.reglas r
     WHERE r.codigo IN ('B2B-RULE-LOAD-MULTI-OFFER-001',
       'B2B-RULE-LOAD-RESULT-FINAL-001','B2B-RULE-LOAD-WIZARD-001');
 SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.codigo,v.version)::text,'[]'))
  INTO v_before_versions FROM lf_ops.reglas_versiones v;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]'))
  INTO v_before_all_rules FROM lf_ops.reglas r;
 SELECT md5(coalesce(jsonb_agg(jsonb_build_object('codigo',r.codigo,'config',r.valor_config)
      ORDER BY r.codigo)::text,'[]')) INTO v_before_cards_digest
  FROM lf_ops.reglas r WHERE r.codigo IN ('B2B-RULE-LOAD-MULTI-OFFER-001',
       'B2B-RULE-LOAD-RESULT-FINAL-001','B2B-RULE-LOAD-WIZARD-001');
 IF (SELECT array_agg(pantalla_id ORDER BY pantalla_id) FROM lf_ops.reglas_pantallas
     WHERE regla_id=v_old_id) IS DISTINCT FROM ARRAY[44,66,67]::integer[]
 OR (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE regla_id=v_new_id)<>0
 OR (SELECT count(*) FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_old)<>1
 OR (SELECT count(*) FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_new)<>1
 OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=v_old
     AND version=1 AND vigente_hasta IS NULL AND estado='VIGENTE')<>1
 OR EXISTS (SELECT 1 FROM lf_ops.reglas_versiones WHERE codigo=v_new)
 THEN RAISE EXCEPTION 'LF_IG_1330_DEPENDENCY_OR_HISTORY_PREIMAGE_DRIFT'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas r
     WHERE r.codigo<>v_old AND r.codigo<>v_new
       AND r.valor_config::text LIKE '%'||v_old||'%')<>3
 OR (SELECT count(*) FROM lf_ops.reglas r WHERE r.codigo<>v_old AND r.codigo<>v_new
   AND concat_ws(' ',r.descripcion,r.razon) LIKE '%'||v_old||'%')<>0
 OR EXISTS(SELECT 1 FROM lf_ops.pantallas_politicas_reglas WHERE regla_id=v_old_id)
 OR EXISTS(SELECT 1 FROM programacion.input_family_inheritable_sources_v1 WHERE rule_id=v_old_id)
 OR EXISTS(SELECT 1 FROM programacion.input_family_reuse_map_v1 WHERE transversal_regla_id=v_old_id OR existing_candidate_regla_id=v_old_id)
 OR EXISTS(SELECT 1 FROM programacion.input_readiness_runs WHERE universe_rule_id=v_old_id)
 THEN RAISE EXCEPTION 'LF_IG_1330_CROSS_LINKS_OR_CITATIONS_UNEXPECTED'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas WHERE codigo IN (
 'B2B-RULE-LOAD-MULTI-OFFER-001','B2B-RULE-LOAD-RESULT-FINAL-001')
 AND valor_config->>'valid_only_rule'=v_old)<>2
 OR (SELECT count(*) FROM lf_ops.reglas
 WHERE codigo='B2B-RULE-LOAD-WIZARD-001'
 AND valor_config#>>'{third_state_operational_contract,error_export_contract,rule_code}'=v_old)<>1
 THEN RAISE EXCEPTION 'LF_IG_1330_CITATION_JSON_PATH_DRIFT'; END IF;

 RAISE NOTICE 'LF_IG_1330_BEFORE:PROM=%:HASH=%:OLD=VIGENTE:NEW=CANDIDATO:3SCREENS_OLD:0SCREENS_NEW:TESTS_OLD=1:TESTS_NEW=1:CITES_OLD=3:VERSIONS=%',
   v_pid,v_hash,v_preexisting_versions;
 BEGIN
   PERFORM pg_catalog.set_config('lf.reglas_cambiado_por',v_actor||' | '||v_pid,true);
   PERFORM pg_catalog.set_config('lf.reglas_cambio_motivo','PROMOCION_APROBADA:'||v_pid,true);
   -- Official approval, exactly identity, decision, id and owner-provided SHA.
   v_dec:=public.lf_rule_promotion_decide_v1(v_pid,'APPROVE',
      'HUMAN:'||v_actor,
      'Aprobación explícita del dueño por chat 2026-11-19 13:29 Lima; promotion_id='
      ||v_pid||'; request_snapshot_sha256='||v_hash);
   IF v_dec->>'status' IS DISTINCT FROM 'APPROVED'
     OR v_dec->>'promotion_id' IS DISTINCT FROM v_pid
   THEN RAISE EXCEPTION 'LF_IG_1330_DECIDE_DENIED:%',v_dec; END IF;
   v_apply:=public.lf_rule_promotion_apply_v1(v_pid);
   IF v_apply->>'status' IS DISTINCT FROM 'APPLIED'
     OR v_apply->>'rule_code' IS DISTINCT FROM v_new
   THEN RAISE EXCEPTION 'LF_IG_1330_APPLY_DENIED:%',v_apply; END IF;
   IF (SELECT estado FROM lf_ops.reglas WHERE codigo=v_new) IS DISTINCT FROM 'VIGENTE'
    OR (SELECT status FROM public.lf_rule_promotion_v1 WHERE promotion_id=v_pid) IS DISTINCT FROM 'APPLIED'
   THEN RAISE EXCEPTION 'LF_IG_1330_PROMOTION_READBACK_FAILED'; END IF;

   -- Preserve the original 3 link rows, ids, notes and timestamps.
   UPDATE lf_ops.reglas_pantallas SET regla_id=v_new_id WHERE regla_id=v_old_id;
   GET DIAGNOSTICS v_link_count=ROW_COUNT;
   -- Preserve the original test_ref and ci_run, plus existing ...002 test.
   UPDATE lf_ops.regla_behavior_tests SET regla_codigo=v_new WHERE regla_codigo=v_old;
   GET DIAGNOSTICS v_test_count=ROW_COUNT;
   IF v_link_count<>3 OR v_test_count<>1 THEN
     RAISE EXCEPTION 'LF_IG_1330_RELINK_COUNT_MISMATCH:%,%',v_link_count,v_test_count; END IF;

   PERFORM pg_catalog.set_config('lf.reglas_cambio_motivo',
       'MIGRACION_CITAS_POR_REEMPLAZO:'||v_new,true);
   UPDATE lf_ops.reglas SET valor_config=pg_catalog.jsonb_set(
      valor_config,'{valid_only_rule}',pg_catalog.to_jsonb(v_new),false)
   WHERE codigo IN ('B2B-RULE-LOAD-MULTI-OFFER-001','B2B-RULE-LOAD-RESULT-FINAL-001')
     AND valor_config->>'valid_only_rule'=v_old;
   GET DIAGNOSTICS v_citation_count=ROW_COUNT;
   IF v_citation_count<>2 THEN
     RAISE EXCEPTION 'LF_IG_1330_TOP_CITATION_COUNT:%',v_citation_count; END IF;
   UPDATE lf_ops.reglas SET valor_config=pg_catalog.jsonb_set(
      valor_config,'{third_state_operational_contract,error_export_contract,rule_code}',
      pg_catalog.to_jsonb(v_new),false)
   WHERE codigo='B2B-RULE-LOAD-WIZARD-001'
     AND valor_config#>>'{third_state_operational_contract,error_export_contract,rule_code}'=v_old;
   GET DIAGNOSTICS v_count=ROW_COUNT;
   v_citation_count:=v_citation_count+v_count;
   IF v_citation_count<>3 THEN
     RAISE EXCEPTION 'LF_IG_1330_ALL_CITATION_COUNT:%',v_citation_count; END IF;
   IF EXISTS(SELECT 1 FROM lf_ops.reglas r WHERE r.codigo<>v_old AND r.codigo<>v_new
       AND concat_ws(' ',r.descripcion,r.razon,r.valor_config::text) LIKE '%'||v_old||'%')
   THEN RAISE EXCEPTION 'LF_IG_1330_OLD_CITATIONS_REMAIN'; END IF;

   -- Only now remove old rule. Its BEFORE DELETE trigger must retain the VIGENTE
   -- preimage and close history with the required owner reason.
   PERFORM pg_catalog.set_config('lf.reglas_cambio_motivo',v_delete_reason,true);
   DELETE FROM lf_ops.reglas WHERE codigo=v_old AND estado='VIGENTE';
   GET DIAGNOSTICS v_count=ROW_COUNT;
   IF v_count<>1 THEN RAISE EXCEPTION 'LF_IG_1330_DELETE_NOT_EXACTLY_ONE'; END IF;
   IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_old)
   OR (SELECT count(*) FROM lf_ops.reglas)<>v_preexisting_rules-1
   OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=v_old AND version=1
       AND estado='VIGENTE' AND motivo=v_delete_reason AND vigente_hasta IS NOT NULL
       AND cambiado_por LIKE v_actor||'%')<>1
   OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=v_new
       AND estado='CANDIDATO' AND vigente_hasta IS NOT NULL)<>1
   OR (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE regla_id=v_old_id)<>0
   OR (SELECT array_agg(pantalla_id ORDER BY pantalla_id) FROM lf_ops.reglas_pantallas
        WHERE regla_id=v_new_id) IS DISTINCT FROM ARRAY[44,66,67]::integer[]
   OR (SELECT count(*) FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_old)<>0
   OR (SELECT count(*) FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_new
        AND pg17='PASS' AND pg18='PASS')<>2
   OR (SELECT count(*) FROM lf_ops.reglas_versiones)<>v_preexisting_versions+1
   THEN RAISE EXCEPTION 'LF_IG_1330_FULL_REPLACEMENT_READBACK_FAILED'; END IF;
   IF (SELECT status FROM public.lf_rule_promotion_v1 WHERE promotion_id=v_pid)<>'APPLIED'
   OR (SELECT estado FROM lf_ops.reglas WHERE codigo=v_new)<>'VIGENTE'
   THEN RAISE EXCEPTION 'LF_IG_1330_PROMOTION_NOT_APPLIED_POST_DELETE'; END IF;
   RAISE NOTICE 'LF_IG_1330_AFTER:PROM=APPLIED:NEW=VIGENTE:OLD=DELETED:3SCREENS_NEW:2TESTS_NEW:CITES_NEW=3:OLD_HISTORY=REEMPLAZADA_POR:VERSIONS=%',
     (SELECT count(*) FROM lf_ops.reglas_versiones);
   IF v_proof_only THEN RAISE EXCEPTION 'LF_IG_1330_PROOF_ROLLBACK_SENTINEL'; END IF;
 EXCEPTION WHEN OTHERS THEN
   IF v_proof_only AND SQLERRM='LF_IG_1330_PROOF_ROLLBACK_SENTINEL'
   THEN v_audit_ok:=true;
   ELSE RAISE; END IF;
 END;
 IF v_proof_only THEN
   SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.codigo,v.version)::text,'[]'))
      INTO v_after_versions FROM lf_ops.reglas_versiones v;
   SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]'))
      INTO v_after_all_rules FROM lf_ops.reglas r;
   SELECT md5(coalesce(jsonb_agg(jsonb_build_object('codigo',r.codigo,'config',r.valor_config)
      ORDER BY r.codigo)::text,'[]')) INTO v_after_cards_digest
      FROM lf_ops.reglas r WHERE r.codigo IN ('B2B-RULE-LOAD-MULTI-OFFER-001',
       'B2B-RULE-LOAD-RESULT-FINAL-001','B2B-RULE-LOAD-WIZARD-001');
   IF NOT v_audit_ok
     OR v_after_all_rules IS DISTINCT FROM v_before_all_rules
     OR v_after_versions IS DISTINCT FROM v_before_versions
     OR v_after_cards_digest IS DISTINCT FROM v_before_cards_digest
     OR (SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE codigo=v_old) IS DISTINCT FROM v_old_before
     OR (SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE codigo=v_new) IS DISTINCT FROM v_new_before
     OR (SELECT to_jsonb(p) FROM public.lf_rule_promotion_v1 p WHERE promotion_id=v_pid) IS DISTINCT FROM v_promotion_before
     OR (SELECT jsonb_agg(to_jsonb(l) ORDER BY l.pantalla_id) FROM lf_ops.reglas_pantallas l
            WHERE regla_id=v_old_id) IS DISTINCT FROM v_before_links
     OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.test_ref) FROM lf_ops.regla_behavior_tests t
            WHERE regla_codigo=v_old) IS DISTINCT FROM v_before_tests
     OR (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE regla_id=v_new_id)<>0
     OR (SELECT count(*) FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_new)<>1
   THEN RAISE EXCEPTION 'LF_IG_1330_PROOF_ROLLBACK_READBACK_FAILED'; END IF;
   RAISE NOTICE 'LF_IG_1330_PROOF_PASS:decide=APPROVED:apply=APPLIED:old=DELETE+HISTORY:links=3:tests=1:cites=3:ROLLBACK_VERIFIED:source_sha=%',v_hash;
 ELSE
   IF (SELECT status FROM public.lf_rule_promotion_v1 WHERE promotion_id=v_pid)<>'APPLIED'
      OR (SELECT estado FROM lf_ops.reglas WHERE codigo=v_new)<>'VIGENTE'
      OR EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_old)
   THEN RAISE EXCEPTION 'LF_IG_1330_APPLY_POST_TX_CHECK_FAIL'; END IF;
   RAISE NOTICE 'LF_IG_1330_APPLY_PERSISTENT_PASS:promotion=%:sha=%',v_pid,v_hash;
 END IF;
END;
$lf_ig_1330_b2b_validonly_replacement$;
ROLLBACK;
