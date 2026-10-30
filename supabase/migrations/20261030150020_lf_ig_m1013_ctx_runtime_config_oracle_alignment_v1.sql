-- M10.13: restore exact existing RUNTIME_CONFIG authority in the non-frozen
-- optimized semantic reader. No new oracle, no edits to frozen sources/rules.
-- One screen × selector-chosen families (not all screens), plus one targeted
-- second-screen RUNTIME_CONFIG check. Transaction rolls back on any mismatch.
BEGIN;
DO $ig_ctx_runtime$
DECLARE
 v_ident constant text := 'programacion.fn_input_governance_semantic_probe_v3_ctx(integer,text,bigint,jsonb)';
 v_marker constant text := 'if p_family_code=''RUNTIME_CONFIG'' then';
 v_add constant text :=
   E'\n    v_base:=programacion.fn_input_runtime_config_existing_authority_probe_v1(p_pantalla_id,p_version_id,p_graph);\n    if coalesce((v_base->>''handled'')::boolean,false) then return v_base; end if;\n';
 v_fn oid; v_body text; v_ddl text; v_expected text;
 v_acl aclitem[]; v_owner oid; v_definer boolean; v_vol "char";
 v_version bigint; v_graph jsonb; v_f text; v_cached jsonb; v_ctx jsonb;
 v_total integer:=0; v_violations integer:=0;
 v_frozen_count integer; v_frozen_drift integer;
 v_meta jsonb; v_rows integer; v_post_hash text; v_case record;
BEGIN
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=474)<>'IN_PROGRESS'
   OR (SELECT status FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS')<>'PENDING'
 THEN RAISE EXCEPTION 'IG_CTX_RUNTIME_CP3_STATE_CHANGED'; END IF;
 v_fn:=to_regprocedure(v_ident);
 SELECT p.prosrc,pg_get_functiondef(p.oid),p.proacl,p.proowner,p.prosecdef,p.provolatile
   INTO STRICT v_body,v_ddl,v_acl,v_owner,v_definer,v_vol
 FROM pg_proc p WHERE p.oid=v_fn;
 IF md5(v_body)<>'9077a6a308f87f67aa8669c734e8c3de'
   OR (length(v_body)-length(replace(v_body,v_marker,'')))<>length(v_marker)
   OR position('fn_input_runtime_config_existing_authority_probe_v1' IN v_body)>0
 THEN RAISE EXCEPTION 'IG_CTX_RUNTIME_EXACT_PREIMAGE_CHANGED'; END IF;

 -- The frozen V3 source already calls this same governed probe. Reuse it.
 IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=to_regprocedure(
 'programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)'))
 <> 'ff726ab1c658769389b65c8479af84fb'
 THEN RAISE EXCEPTION 'IG_CTX_RUNTIME_FROZEN_ORACLE_CHANGED'; END IF;
 IF NOT EXISTS (
 SELECT 1 FROM pg_proc p
 WHERE p.oid=to_regprocedure(
 'programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)')
   AND position(v_marker||v_add IN p.prosrc)>0
 ) THEN RAISE EXCEPTION 'IG_CTX_RUNTIME_ORACLE_NOT_AUTHORIZED_PRECEDENT'; END IF;

 v_expected:=replace(v_body,v_marker,v_marker||v_add);
 EXECUTE replace(v_ddl,v_marker,v_marker||v_add);
 SELECT md5(prosrc) INTO STRICT v_post_hash FROM pg_proc WHERE oid=v_fn;
 IF v_post_hash<>md5(v_expected) OR NOT EXISTS(
   SELECT 1 FROM pg_proc p WHERE p.oid=v_fn
   AND p.proacl IS NOT DISTINCT FROM v_acl AND p.proowner=v_owner
   AND p.prosecdef=v_definer AND p.provolatile=v_vol)
 THEN RAISE EXCEPTION 'IG_CTX_RUNTIME_SECURITY_OR_SOURCE_DRIFT'; END IF;

 v_version:=public.fn_lf_version_compatibility_current_version_id_v1(
   'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
 IF v_version IS NULL THEN RAISE EXCEPTION 'IG_CTX_RUNTIME_CURRENT_VERSION_MISSING'; END IF;
 v_graph:=programacion.fn_input_screen_canonical_graph(43,v_version);
 FOR v_f IN SELECT jsonb_array_elements_text(r.valor_config->'families')
    FROM lf_ops.reglas r WHERE r.codigo='B2B-RULE-STORY-READINESS-001'
 LOOP
   v_cached:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(
     43,v_f,v_version,v_graph);
   v_ctx:=programacion.fn_input_governance_bootstrap_classify_v2_ctx(
     43,v_f,v_version,v_graph);
   v_total:=v_total+1;
   IF v_cached IS DISTINCT FROM v_ctx THEN
     RAISE EXCEPTION 'IG_CTX_RUNTIME_FAMILY_MISMATCH:%',v_f;
   END IF;
 END LOOP;
 IF v_total<>47 THEN RAISE EXCEPTION 'IG_CTX_RUNTIME_SELECTOR_COUNT:%',v_total; END IF;

 v_graph:=programacion.fn_input_screen_canonical_graph(2,v_version);
 v_cached:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(
   2,'RUNTIME_CONFIG',v_version,v_graph);
 v_ctx:=programacion.fn_input_governance_bootstrap_classify_v2_ctx(
   2,'RUNTIME_CONFIG',v_version,v_graph);
 IF v_cached IS DISTINCT FROM v_ctx
 THEN RAISE EXCEPTION 'IG_CTX_RUNTIME_SECOND_SCREEN_MISMATCH'; END IF;

 -- M10.4's immutable source receipts remain the guard for historical assets.
 WITH frozen AS (
   SELECT x.value->>'identity' ident,x.value->>'prosrc_md5' expected
   FROM programacion.engineering_plan_units u
   CROSS JOIN LATERAL jsonb_array_elements(
       u.unit_metadata#>'{m104_freeze_baseline_v1,legacy_functions}') x
   WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.4'
 ), live AS (
   SELECT f.expected,md5(p.prosrc) actual FROM frozen f LEFT JOIN LATERAL (
      SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname||'.'||p.proname||'('||
       pg_get_function_identity_arguments(p.oid)||')'=f.ident
   ) p ON true
 ) SELECT count(*),count(*) FILTER(WHERE expected IS DISTINCT FROM actual)
   INTO v_frozen_count,v_frozen_drift FROM live;
 IF v_frozen_count<>26 OR v_frozen_drift<>0
 THEN RAISE EXCEPTION 'IG_CTX_RUNTIME_HISTORICAL_FREEZE_DRIFT'; END IF;

 SELECT unit_metadata INTO STRICT v_meta
 FROM programacion.engineering_plan_units WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND unit_code='M10.13' AND work_item_id=474 FOR UPDATE;
 IF v_meta?'cp3_runtime_config_oracle_alignment_v1'
 THEN RAISE EXCEPTION 'IG_CTX_RUNTIME_DUPLICATE_EVIDENCE'; END IF;
 UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(
   unit_metadata,'{cp3_runtime_config_oracle_alignment_v1}',
   jsonb_build_object('source','pg_proc',
     'root_cause','RUNTIME_CONFIG_EXISTING_AUTHORITY_PROBE_SKIPPED',
     'consumer','fn_input_governance_semantic_probe_v3_ctx',
     'before_md5',md5(v_body),'after_md5',v_post_hash,
     'canonical_version_id',v_version,'families_checked',v_total,
     'second_screen_runtime_config_equal',true,
     'historical_functions_checked',v_frozen_count,'historical_drift',v_frozen_drift,
     'scope_rules_changed',false,'checkpoint_closed',false),true)
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND unit_code='M10.13' AND work_item_id=474 AND unit_metadata=v_meta;
 GET DIAGNOSTICS v_rows=ROW_COUNT;
 IF v_rows<>1 THEN RAISE EXCEPTION 'IG_CTX_RUNTIME_RECEIPT_DRIFT'; END IF;
END
$ig_ctx_runtime$;
COMMIT;
