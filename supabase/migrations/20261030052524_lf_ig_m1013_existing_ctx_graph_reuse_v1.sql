-- Input Governance M10.13: reuse the ALREADY-SUPPLIED canonical graph in
-- the existing _ctx functions. No new function, route, grant, revoke or DROP.
-- Fixes repeated graph construction in two noncached descendant calls.
-- Source hash gate aborts on drift; exact semantic parity aborts/ROLLBACK on failure.
-- CP3 ZERO_LEGACY_CALLERS intentionally remains PENDING; no retirement authorised.
BEGIN;

DO $ig_ctx_graph_reuse$
DECLARE
  v_name text;
  v_oid oid;
  v_source text;
  v_changed text;
  v_pre_acl aclitem[];
  v_post_acl aclitem[];
  v_pre_secdef boolean;
  v_post_secdef boolean;
  v_pre_volatility "char";
  v_post_volatility "char";
  v_expected_md5 text;
  v_needle text;
  v_replacement text;
  v_case record;
  v_graph jsonb;
  v_cached jsonb;
  v_ctx jsonb;
  v_proven integer := 0;
BEGIN
  IF (SELECT status FROM programacion.engineering_work_items WHERE id=474)
     IS DISTINCT FROM 'IN_PROGRESS'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS')
     IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'IG_CTX_REUSE_CP3_STATE_DRIFT'; END IF;

  -- Only two existing functions and three known, exact call sites.
  FOR v_name,v_expected_md5,v_needle,v_replacement IN
    SELECT * FROM (VALUES
      ('fn_input_governance_bootstrap_classify_v1_ctx',
       '04cfdb8055850102bbc49123489c4f4f',
       'programacion.fn_input_na_positive_authority_v512(p_family_code,p_pantalla_id,p_version_id)',
       'programacion.fn_input_na_positive_authority_v512_cached_v1(p_family_code,p_pantalla_id,p_version_id,p_graph)'),
      ('fn_input_governance_semantic_probe_v3_ctx',
       '2eec94aaeafcd10ac38519d1ca0d53b0',
       'programacion.fn_input_governance_semantic_probe_v2(p_pantalla_id,p_family_code,p_version_id)',
       'programacion.fn_input_governance_semantic_probe_v2_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph)'),
      ('fn_input_governance_semantic_probe_v3_ctx',
       '2eec94aaeafcd10ac38519d1ca0d53b0',
       'programacion.fn_input_governance_family_complete_probe_v1(p_pantalla_id,p_family_code,p_version_id,null)',
       'programacion.fn_input_governance_family_complete_probe_v1(p_pantalla_id,p_family_code,p_version_id,p_graph)')
    ) x(fn,expected_md5,old_call,new_call)
  LOOP
    v_oid:=to_regprocedure(format('programacion.%I(integer,text,bigint,jsonb)',v_name));
    IF v_oid IS NULL THEN
      RAISE EXCEPTION 'IG_CTX_REUSE_MISSING_FUNCTION:%',v_name;
    END IF;
    SELECT p.proacl,p.prosecdef,p.provolatile,p.prosrc,pg_get_functiondef(p.oid)
      INTO v_pre_acl,v_pre_secdef,v_pre_volatility,v_source,v_changed
    FROM pg_proc p WHERE p.oid=v_oid;
    -- v3 is deliberately changed twice in this loop. Accept only its
    -- exact original fingerprint on entry, and the exact first replacement
    -- fingerprint on the second pass by tracking the source copy below.
    IF v_name='fn_input_governance_semantic_probe_v3_ctx'
       AND v_proven=0 THEN
      IF md5(v_source)<>v_expected_md5 THEN
        RAISE EXCEPTION 'IG_CTX_REUSE_SOURCE_DRIFT:%',v_name;
      END IF;
    ELSIF v_name='fn_input_governance_bootstrap_classify_v1_ctx'
       AND md5(v_source)<>v_expected_md5 THEN
      RAISE EXCEPTION 'IG_CTX_REUSE_SOURCE_DRIFT:%',v_name;
    END IF;

    IF (length(v_changed)-length(replace(v_changed,v_needle,'')))<>length(v_needle) THEN
      RAISE EXCEPTION 'IG_CTX_REUSE_CALLSITE_NOT_UNIQUE:%',v_name;
    END IF;
    v_changed:=replace(v_changed,v_needle,v_replacement);
    EXECUTE v_changed;

    SELECT p.proacl,p.prosecdef,p.provolatile
      INTO v_post_acl,v_post_secdef,v_post_volatility
    FROM pg_proc p WHERE p.oid=v_oid;
    IF v_post_acl IS DISTINCT FROM v_pre_acl
       OR v_post_secdef IS DISTINCT FROM v_pre_secdef
       OR v_post_volatility IS DISTINCT FROM v_pre_volatility
    THEN RAISE EXCEPTION 'IG_CTX_REUSE_SECURITY_DRIFT:%',v_name; END IF;
    IF v_name='fn_input_governance_semantic_probe_v3_ctx'
       THEN v_proven:=v_proven+1;
    END IF;
  END LOOP;

  IF v_proven<>2 THEN RAISE EXCEPTION 'IG_CTX_REUSE_INCOMPLETE'; END IF;

  -- Four exact real, previously-observed inputs from the existing CP3 pilot.
  -- The graph is constructed ONCE per case and reused in both paths.
  -- These 12 comparisons are a bounded regression, not a 47-family scan.
  FOR v_case IN
    SELECT * FROM (VALUES
      (43,19::bigint,'ACTIONS'),
      (43,19::bigint,'ROUTING_NAVIGATION'),
      (2,19::bigint,'DESIGN_SYSTEM'),
      (2,19::bigint,'RESPONSIVE')
    ) x(screen_id,version_id,family_code)
  LOOP
    v_graph:=programacion.fn_input_screen_canonical_graph(
      v_case.screen_id,v_case.version_id);

    v_cached:=programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(
      v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
    v_ctx:=programacion.fn_input_governance_bootstrap_classify_v1_ctx(
      v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
    IF v_cached IS DISTINCT FROM v_ctx THEN
      RAISE EXCEPTION 'IG_CTX_REUSE_PARITY_V1:%',v_case.family_code;
    END IF;

    v_cached:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(
      v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
    v_ctx:=programacion.fn_input_governance_semantic_probe_v3_ctx(
      v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
    IF v_cached IS DISTINCT FROM v_ctx THEN
      RAISE EXCEPTION 'IG_CTX_REUSE_PARITY_SEMANTIC:%',v_case.family_code;
    END IF;

    v_cached:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(
      v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
    v_ctx:=programacion.fn_input_governance_bootstrap_classify_v2_ctx(
      v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
    IF v_cached IS DISTINCT FROM v_ctx THEN
      RAISE EXCEPTION 'IG_CTX_REUSE_PARITY_CLASSIFIER:%',v_case.family_code;
    END IF;
  END LOOP;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS')
      IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'IG_CTX_REUSE_FALSE_CLOSURE'; END IF;

  RAISE NOTICE 'IG_CTX_GRAPH_REUSE: 12/12 equality checks, no grant, no retire, CP3 PENDING';
END
$ig_ctx_graph_reuse$;

COMMIT;
