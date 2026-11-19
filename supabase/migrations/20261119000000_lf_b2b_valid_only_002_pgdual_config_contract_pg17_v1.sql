-- PG17 reversible readback: proves same functional configuration as ...001.
-- CI from existing LF Edge Operation R17 Tests checks PG17/18 DB behavior separately.
-- No fictitious CI PASS is recorded here. Behavior registry is written only after green CI.
BEGIN;
DO $lf_b2b_002_pgdual_config$
DECLARE
 oldcfg jsonb;
 newcfg jsonb;
 old_state text;
 new_state text;
 old_id bigint;
 new_id bigint;
 old_links integer;
 new_links integer;
 v_ref text;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17
 THEN RAISE EXCEPTION 'B2B_002_PG17_EXPECTED'; END IF;
 SELECT id,valor_config,estado INTO STRICT old_id,oldcfg,old_state
 FROM lf_ops.reglas WHERE codigo='B2B-RULE-VALIDATION-VALID-ONLY-001';
 SELECT id,valor_config,estado INTO STRICT new_id,newcfg,new_state
 FROM lf_ops.reglas WHERE codigo='B2B-RULE-VALIDATION-VALID-ONLY-002';
 IF old_state<>'VIGENTE' OR new_state<>'CANDIDATO'
 OR (newcfg-'lf_rule_scope'-'lf_screen_ids'-'lf_applicability'
    -'lf_replaces_rule_code'-'lf_promotion_authorized') IS DISTINCT FROM oldcfg
 OR newcfg#>>'{lf_replaces_rule_code}' IS DISTINCT FROM 'B2B-RULE-VALIDATION-VALID-ONLY-001'
 OR newcfg#>>'{lf_rule_scope}' IS DISTINCT FROM 'PANTALLA'
 OR newcfg->'lf_screen_ids' IS DISTINCT FROM '[44,66,67]'::jsonb
 THEN RAISE EXCEPTION 'B2B_002_FUNCTIONAL_CONFIG_NOT_IDENTICAL_TO_VIGENTE'; END IF;
 SELECT count(*) INTO old_links FROM lf_ops.reglas_pantallas WHERE regla_id=old_id;
 SELECT count(*) INTO new_links FROM lf_ops.reglas_pantallas WHERE regla_id=new_id;
 IF old_links<>3 OR new_links<>0
 OR (SELECT count(*) FROM lf_ops.regla_behavior_tests
    WHERE regla_codigo='B2B-RULE-VALIDATION-VALID-ONLY-002')<>0
 THEN RAISE EXCEPTION 'B2B_002_PRETEST_DEPENDENCY_DRIFT'; END IF;
 IF (SELECT count(*) FROM pg_constraint c
     WHERE c.conname IN ('cargas_lotes_valid_only_processed_chk',
       'cargas_lotes_counts_sum_chk','cargas_archivos_ext_mime_chk',
       'cargas_archivos_checksum_chk') AND c.convalidated)<>4
 OR NOT EXISTS(SELECT 1 FROM pg_trigger t
     WHERE t.tgname='trg_cargas_lotes_block_unsafe_processing_v1' AND NOT t.tgisinternal)
 THEN RAISE EXCEPTION 'B2B_002_HARDENING_CONTRACT_MISSING_LIVE'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas)<>587
 THEN RAISE EXCEPTION 'B2B_002_RULE_COUNT_DRIFT'; END IF;
 RAISE NOTICE 'B2B_002_FUNCTIONAL_SCOPE_EXACT_PASS:PG17:old=VIGENTE:new=CANDIDATO:configs_equivalent:true:old_links=3:new_links=0';
END;
$lf_b2b_002_pgdual_config$;
ROLLBACK;
