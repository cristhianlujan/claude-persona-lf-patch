-- N-12 / RC-001
-- Retire the temporary N-7 screen allowlist from classifier + Curator rebind.
-- Source selection is governed by semantic authority/evidence, never screen identity.

DO $patch_classifiers$
DECLARE
  v_reg regprocedure;
  v_def text;
  v_next text;
  v_expected_md5 text;
  v_old text := $old$
  if p_family_code='PERMISSIONS'
     and p_pantalla_id in (52,53,54,56)
     and v->>'applicability'='NOT_APPLICABLE'
     and v#>>'{probe,authority_kind}'='EXPLICIT_CANONICAL_EXCLUSION'
     and jsonb_typeof(v#>'{probe,rule_codes}')='array' then
    v:=jsonb_set(
      v,
      '{source_refs}',
      coalesce(v->'source_refs','[]'::jsonb)
      || coalesce((
        select jsonb_agg(
          jsonb_build_object('kind','RULE','codigo',x.value)
          order by x.value
        )
        from jsonb_array_elements_text(v#>'{probe,rule_codes}') x(value)
      ),'[]'::jsonb),
      true
    );
  elsif p_family_code='VISUAL_EVIDENCE'
        and p_pantalla_id in (52,53,54,56) then
    v:=jsonb_set(
      v,
      '{source_refs}',
      coalesce(v->'source_refs','[]'::jsonb)
      || jsonb_build_array(
        jsonb_build_object('kind','CURRENT_VISUAL_ARTIFACT','pantalla_id',p_pantalla_id)
      ),
      true
    );
  end if;
$old$;
  v_new text := $new$
  if p_family_code='PERMISSIONS'
     and v->>'applicability'='NOT_APPLICABLE'
     and v#>>'{probe,authority_kind}'='EXPLICIT_CANONICAL_EXCLUSION'
     and jsonb_typeof(v#>'{probe,rule_codes}')='array' then
    v:=jsonb_set(
      v,
      '{source_refs}',
      coalesce(v->'source_refs','[]'::jsonb)
      || coalesce((
        select jsonb_agg(
          jsonb_build_object('kind','RULE','codigo',x.value)
          order by x.value
        )
        from jsonb_array_elements_text(v#>'{probe,rule_codes}') x(value)
        where not coalesce(v->'source_refs','[]'::jsonb)
          @> jsonb_build_array(jsonb_build_object('kind','RULE','codigo',x.value))
      ),'[]'::jsonb),
      true
    );
  elsif p_family_code='VISUAL_EVIDENCE'
        and exists (
          select 1
          from lf_ops.pantalla_artefactos pa
          where pa.pantalla_id=p_pantalla_id
            and pa.is_current=true
        )
        and not coalesce(v->'source_refs','[]'::jsonb)
          @> jsonb_build_array(
            jsonb_build_object('kind','CURRENT_VISUAL_ARTIFACT','pantalla_id',p_pantalla_id)
          ) then
    v:=jsonb_set(
      v,
      '{source_refs}',
      coalesce(v->'source_refs','[]'::jsonb)
      || jsonb_build_array(
        jsonb_build_object('kind','CURRENT_VISUAL_ARTIFACT','pantalla_id',p_pantalla_id)
      ),
      true
    );
  end if;
$new$;
BEGIN
  FOREACH v_reg IN ARRAY ARRAY[
    'programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure,
    'programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'::regprocedure
  ] LOOP
    v_expected_md5 := CASE v_reg::text
      WHEN 'fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'
        THEN '904e0a4af4ab3df27281c9da2d1d4b10'
      ELSE '5acdff656b9e65bc92b51abd45d5706e'
    END;

    v_def := pg_get_functiondef(v_reg);
    IF md5(v_def) <> v_expected_md5 THEN
      RAISE EXCEPTION 'N12_CLASSIFIER_BASELINE_DRIFT:% expected=% actual=%',v_reg,v_expected_md5,md5(v_def);
    END IF;
    IF position(v_old in v_def)=0 THEN
      RAISE EXCEPTION 'N12_CLASSIFIER_ALLOWLIST_BLOCK_NOT_FOUND:%',v_reg;
    END IF;

    v_next := replace(v_def,v_old,v_new);
    IF v_next=v_def THEN
      RAISE EXCEPTION 'N12_CLASSIFIER_REWRITE_NOOP:%',v_reg;
    END IF;
    EXECUTE v_next;
  END LOOP;
END;
$patch_classifiers$;

DO $patch_curator$
DECLARE
  v_reg regprocedure := 'programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure;
  v_def text;
  v_next text;
  v_expected_md5 text := 'aa985473993e4cb4ddee8156dd0ad610';
  v_loop_old text := $loop_old$
  for a in select * from programacion.input_family_assessments where run_id=v_parent order by family_code
  loop
    insert into programacion.input_family_assessments(
$loop_old$;
  v_loop_new text := $loop_new$
  for a in select * from programacion.input_family_assessments where run_id=v_parent order by family_code
  loop
    v_classifier:=programacion.fn_input_governance_bootstrap_classify_v2(
      p_pantalla_id,a.family_code,v_version
    );
    insert into programacion.input_family_assessments(
$loop_new$;
  v_refs_old text := $refs_old$
      case when p_pantalla_id in (52,53,54,56) then
        programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,a.family_code,v_version)->'source_refs'
      else a.source_refs end,a.rationale,a.blockers,a.negative_requirements,a.test_obligations,'{}'::jsonb,
$refs_old$;
  v_refs_new text := $refs_new$
      coalesce(v_classifier->'source_refs','[]'::jsonb),a.rationale,a.blockers,a.negative_requirements,a.test_obligations,'{}'::jsonb,
$refs_new$;
  v_fp_old text := $fp_old$
        'bootstrap_classifier_sha256',case
          when p_pantalla_id in (52,53,54,56) then
            programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,a.family_code,v_version)->>'classifier_sha256'
          else coalesce(
            nullif(a.curator_evidence->>'bootstrap_classifier_sha256',''),
            programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,a.family_code,v_version)->>'classifier_sha256'
          )
        end
$fp_old$;
  v_fp_new text := $fp_new$
        'bootstrap_classifier_sha256',v_classifier->>'classifier_sha256'
$fp_new$;
BEGIN
  v_def:=pg_get_functiondef(v_reg);
  IF md5(v_def)<>v_expected_md5 THEN
    RAISE EXCEPTION 'N12_CURATOR_BASELINE_DRIFT expected=% actual=%',v_expected_md5,md5(v_def);
  END IF;

  v_next:=replace(v_def,'  v_payload jsonb;','  v_payload jsonb;'||chr(10)||'  v_classifier jsonb;');
  IF v_next=v_def THEN RAISE EXCEPTION 'N12_CURATOR_DECLARE_ANCHOR_NOT_FOUND'; END IF;
  v_def:=v_next;

  v_next:=replace(v_def,v_loop_old,v_loop_new);
  IF v_next=v_def THEN RAISE EXCEPTION 'N12_CURATOR_LOOP_ANCHOR_NOT_FOUND'; END IF;
  v_def:=v_next;

  v_next:=replace(v_def,v_refs_old,v_refs_new);
  IF v_next=v_def THEN RAISE EXCEPTION 'N12_CURATOR_SOURCE_REFS_ANCHOR_NOT_FOUND'; END IF;
  v_def:=v_next;

  v_next:=replace(v_def,v_fp_old,v_fp_new);
  IF v_next=v_def THEN RAISE EXCEPTION 'N12_CURATOR_FINGERPRINT_ANCHOR_NOT_FOUND'; END IF;

  EXECUTE v_next;
END;
$patch_curator$;

COMMENT ON FUNCTION programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint) IS
  'N-12 RC-001: source refs derive from governed semantic authority and current visual evidence; no screen-ID allowlist.';
COMMENT ON FUNCTION programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb) IS
  'N-12 RC-001 cached parity: source refs derive from governed semantic authority and current visual evidence; no screen-ID allowlist.';
COMMENT ON FUNCTION programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean) IS
  'N-12 RC-001: rebind copies current classifier source refs/fingerprint once per family; no screen-ID allowlist. N-10/N-11 boundaries preserved.';

DO $verify$
DECLARE
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_classify text:=pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure);
  v_cached text:=pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'::regprocedure);
  v_curator text:=pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure);
  v_graph jsonb;
  v_perm jsonb;
  v_visual jsonb;
  v_has_visual boolean;
  v_has_visual_ref boolean;
  v_screen_count integer:=0;
  r record;
  x text;
BEGIN
  IF position('p_pantalla_id in (52,53,54,56)' in v_classify)>0
     OR position('p_pantalla_id in (52,53,54,56)' in v_cached)>0
     OR position('p_pantalla_id in (52,53,54,56)' in v_curator)>0 THEN
    RAISE EXCEPTION 'N12_SCREEN_ALLOWLIST_REMAINS';
  END IF;

  IF position('fn_input_v58_build_assertions' in v_curator)>0 THEN
    RAISE EXCEPTION 'N12_REGRESSION_N10_CURATOR_VALIDATOR_BOUNDARY';
  END IF;
  IF v_curator ~ '(curator_component_id\s*,\s*46|''component_id''\s*,\s*46)' THEN
    RAISE EXCEPTION 'N12_REGRESSION_N11_CURATOR_COMPONENT_BINDING';
  END IF;
  IF position('programacion.componentes' in v_curator)=0 OR position('INPUT_CURATOR' in v_curator)=0 THEN
    RAISE EXCEPTION 'N12_REGRESSION_N11_CURATOR_REGISTRY_BINDING';
  END IF;

  FOR r IN
    SELECT DISTINCT rr.pantalla_id
    FROM programacion.input_readiness_runs rr
    WHERE rr.version_id=v_version AND rr.status='COMPLETED'
    ORDER BY rr.pantalla_id
  LOOP
    v_screen_count:=v_screen_count+1;
    v_graph:=programacion.fn_input_screen_canonical_graph(r.pantalla_id,v_version);
    v_perm:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(r.pantalla_id,'PERMISSIONS',v_version,v_graph);
    v_visual:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(r.pantalla_id,'VISUAL_EVIDENCE',v_version,v_graph);

    IF v_perm->>'applicability'='NOT_APPLICABLE'
       AND v_perm#>>'{probe,authority_kind}'='EXPLICIT_CANONICAL_EXCLUSION'
       AND jsonb_typeof(v_perm#>'{probe,rule_codes}')='array' THEN
      FOR x IN SELECT value FROM jsonb_array_elements_text(v_perm#>'{probe,rule_codes}') LOOP
        IF NOT coalesce(v_perm->'source_refs','[]'::jsonb)
          @> jsonb_build_array(jsonb_build_object('kind','RULE','codigo',x)) THEN
          RAISE EXCEPTION 'N12_PERMISSIONS_RULE_REF_MISSING screen=% rule=%',r.pantalla_id,x;
        END IF;
      END LOOP;
    END IF;

    SELECT exists(
      SELECT 1 FROM lf_ops.pantalla_artefactos pa
      WHERE pa.pantalla_id=r.pantalla_id AND pa.is_current=true
    ) INTO v_has_visual;
    v_has_visual_ref:=coalesce(v_visual->'source_refs','[]'::jsonb)
      @> jsonb_build_array(jsonb_build_object('kind','CURRENT_VISUAL_ARTIFACT','pantalla_id',r.pantalla_id));
    IF v_has_visual IS DISTINCT FROM v_has_visual_ref THEN
      RAISE EXCEPTION 'N12_VISUAL_SELECTOR_MISMATCH screen=% has_artifact=% has_ref=%',r.pantalla_id,v_has_visual,v_has_visual_ref;
    END IF;
  END LOOP;

  IF v_screen_count<13 THEN
    RAISE EXCEPTION 'N12_SCREEN_COVERAGE_TOO_SMALL expected_at_least=13 actual=%',v_screen_count;
  END IF;
END;
$verify$;
