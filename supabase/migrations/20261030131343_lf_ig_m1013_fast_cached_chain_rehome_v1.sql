-- IG M10.13 CP3: rehome only two internal calls of the ACTIVE cached
-- classifier to existing preoptimized _ctx implementations. Retain public
-- and external signatures, historical functions, grants, and the 47-family selector.
-- Exact source identity, 6 positive paired cases, performance ceiling, rollback.
-- This is NOT six-call cleanup completion; leave ZERO_LEGACY_CALLERS PENDING.
BEGIN;
DO $ig_fast_chain$
DECLARE
  v_current constant text := 'programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)';
  v_alternative constant text := 'programacion.fn_input_governance_bootstrap_classify_v2_ctx(integer,text,bigint,jsonb)';
  v_old_a constant text := 'programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(p_pantalla_id,p_family_code,p_version_id,p_graph)';
  v_new_a constant text := 'programacion.fn_input_governance_bootstrap_classify_v1_ctx(p_pantalla_id,p_family_code,p_version_id,p_graph)';
  v_old_b constant text := 'programacion.fn_input_governance_semantic_probe_v3_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph)';
  v_new_b constant text := 'programacion.fn_input_governance_semantic_probe_v3_ctx(p_pantalla_id,p_family_code,p_version_id,p_graph)';
  v_sql text; v_src text; v_alt text; v_changed text;
  v_acl aclitem[]; v_secdef boolean; v_vol "char"; v_owner oid;
  v_case record; v_graph jsonb; v_before jsonb; v_after jsonb;
  v_t0 timestamptz; v_old_ms numeric:=0; v_new_ms numeric:=0;
  v_case_old_ms numeric; v_case_new_ms numeric;
  v_pairs jsonb:='[]'::jsonb; v_meta jsonb; v_rows integer;
  v_post_hash text;
BEGIN
  IF (SELECT status FROM programacion.engineering_work_items WHERE id=474)<>'IN_PROGRESS'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS')<>'PENDING'
  THEN RAISE EXCEPTION 'IG_CP3_STATE_DRIFT'; END IF;
  SELECT pg_get_functiondef(p.oid),p.prosrc,p.proacl,p.prosecdef,p.provolatile,p.proowner
    INTO STRICT v_sql,v_src,v_acl,v_secdef,v_vol,v_owner
    FROM pg_proc p WHERE p.oid=to_regprocedure(v_current);
  SELECT p.prosrc INTO STRICT v_alt FROM pg_proc p WHERE p.oid=to_regprocedure(v_alternative);
  IF md5(v_src)<>'7257b9bbc86b1f61e5435a37479d63a1'
     OR md5(v_alt)<>'11bd4af470dffc3d2ae8c1316774c1ba'
     OR (length(v_src)-length(replace(v_src,v_old_a,'')))<>length(v_old_a)
     OR (length(v_src)-length(replace(v_src,v_old_b,'')))<>length(v_old_b)
  THEN RAISE EXCEPTION 'IG_CP3_EXACT_SOURCE_OR_CALLSITE_DRIFT'; END IF;
  v_changed:=replace(replace(v_src,v_old_a,v_new_a),v_old_b,v_new_b);
  IF v_changed IS DISTINCT FROM v_alt
     OR NOT EXISTS(
       SELECT 1 FROM pg_proc a JOIN pg_proc b
         ON a.oid=to_regprocedure(v_current) AND b.oid=to_regprocedure(v_alternative)
       WHERE a.prosecdef=b.prosecdef AND a.provolatile=b.provolatile)
  THEN RAISE EXCEPTION 'IG_CP3_ALTERNATIVE_NOT_IDENTICAL'; END IF;

  -- Bounded selected families/screen snapshots, not all 47 families by default.
  FOR v_case IN SELECT * FROM (VALUES
     (43,19::bigint,'ACTIONS'),(43,19::bigint,'ROUTING_NAVIGATION'),
     (2,19::bigint,'DESIGN_SYSTEM'),(2,19::bigint,'RESPONSIVE'),
     (43,19::bigint,'FIELDS'),(2,19::bigint,'VALIDATIONS')
  ) t(screen_id,version_id,family_code)
  LOOP
    v_graph:=programacion.fn_input_screen_canonical_graph(v_case.screen_id,v_case.version_id);
    v_t0:=clock_timestamp();
    v_before:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(
      v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
    v_case_old_ms:=round((extract(epoch from clock_timestamp()-v_t0)*1000)::numeric,3);
    v_t0:=clock_timestamp();
    v_after:=programacion.fn_input_governance_bootstrap_classify_v2_ctx(
      v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
    v_case_new_ms:=round((extract(epoch from clock_timestamp()-v_t0)*1000)::numeric,3);
    IF v_before IS DISTINCT FROM v_after
    THEN RAISE EXCEPTION 'IG_CP3_OUTPUT_DRIFT:%:%',v_case.screen_id,v_case.family_code; END IF;
    v_old_ms:=v_old_ms+v_case_old_ms;
    v_new_ms:=v_new_ms+v_case_new_ms;
    v_pairs:=v_pairs||jsonb_build_array(jsonb_build_object(
      'screen',v_case.screen_id,'family',v_case.family_code,
      'equal',true,'current_ms',v_case_old_ms,'alternative_ms',v_case_new_ms));
  END LOOP;
  IF jsonb_array_length(v_pairs)<>6 OR v_new_ms>v_old_ms*2+120
  THEN RAISE EXCEPTION 'IG_CP3_PERFORMANCE_OR_COVERAGE_REGRESSION:%.%',v_old_ms,v_new_ms; END IF;

  EXECUTE replace(replace(v_sql,v_old_a,v_new_a),v_old_b,v_new_b);
  SELECT md5(p.prosrc) INTO STRICT v_post_hash
    FROM pg_proc p WHERE p.oid=to_regprocedure(v_current);
  IF v_post_hash<>md5(v_alt)
     OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(v_current)
       AND p.proacl IS NOT DISTINCT FROM v_acl
       AND p.prosecdef IS NOT DISTINCT FROM v_secdef
       AND p.provolatile IS NOT DISTINCT FROM v_vol
       AND p.proowner IS NOT DISTINCT FROM v_owner)
  THEN RAISE EXCEPTION 'IG_CP3_POST_SOURCE_SECURITY_DRIFT'; END IF;

  SELECT unit_metadata INTO STRICT v_meta FROM programacion.engineering_plan_units
   WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.13'
     AND work_item_id=474 FOR UPDATE;
  IF v_meta ? 'cp3_fast_chain_rehome_v1'
  THEN RAISE EXCEPTION 'IG_CP3_REHOME_EVIDENCE_EXISTS'; END IF;
  UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(
    unit_metadata,'{cp3_fast_chain_rehome_v1}',jsonb_build_object(
      'preimage_md5',md5(v_src),'postimage_md5',v_post_hash,
      'comparison_count',6,'comparisons',v_pairs,
      'old_total_ms',v_old_ms,'alternative_total_ms',v_new_ms,
      'exact_body_identity',true,'source','pg_catalog.pg_proc',
      'legacy_callers_zero',false,'checkpoint_closed',false,
      'performance_certified',false,'scope','TWO_INTERNAL_EDGES_ONLY'),true)
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND unit_code='M10.13' AND work_item_id=474 AND unit_metadata=v_meta;
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows<>1 OR
    (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS')<>'PENDING'
  THEN RAISE EXCEPTION 'IG_CP3_FALSE_CLOSURE_OR_LEDGER_DRIFT'; END IF;
  RAISE NOTICE 'IG_CP3_REHOME: 2 callsites; 6/6 paired; old_ms=% alt_ms=%; CP3=PENDING',
    v_old_ms,v_new_ms;
END
$ig_fast_chain$;
COMMIT;
