-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · N-7 / PAULO-172 closure hotfix
-- Root cause: screens 52/53/54/56 rebuild assertions from current templates while
-- rebind copied stale parent source_refs and classifier fingerprints. PERMISSIONS
-- also uses direct governed RULE sources and VISUAL_EVIDENCE uses the current
-- visual artifact source, but those exact sources were not declared by the
-- bootstrap classifier. Validator correctly fails closed on either mismatch.
-- Scope is intentionally limited to the four N-7 screens still missing chunk telemetry.

do $hotfix_classifier$
declare
  v_name text;
  v_reg regprocedure;
  v_def text;
  v_new text;
  v_pre_md5 text;
  v_expected_pre text;
  v_expected_post text;
  v_anchor text := '  v:=programacion.fn_input_apply_stage_authority_v2(v,p_pantalla_id,p_family_code,p_version_id);';
  v_inject text := $inject$
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

$inject$;
begin
  foreach v_name in array array[
    'fn_input_governance_bootstrap_classify_v2',
    'fn_input_governance_bootstrap_classify_v2_cached_v2'
  ] loop
    v_reg := case v_name
      when 'fn_input_governance_bootstrap_classify_v2'
        then 'programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure
      else 'programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'::regprocedure
    end;

    v_expected_pre := case v_name
      when 'fn_input_governance_bootstrap_classify_v2' then '253a87db56a2b37f08532d020a74f097'
      else '42053965d2cfd0f4644b1b8f71f0fb29'
    end;
    v_expected_post := case v_name
      when 'fn_input_governance_bootstrap_classify_v2' then '3ac3d9ee55e8aa917b7cbed56ac9aef5'
      else 'e242fbce4f1f4804e738044a2ed236b0'
    end;

    v_def := pg_get_functiondef(v_reg);
    v_pre_md5 := md5(v_def);
    if v_pre_md5 <> v_expected_pre then
      raise exception 'IG_N7_SOURCE_CONTRACT_CLASSIFIER_BASELINE_DRIFT:%:%', v_name, v_pre_md5;
    end if;

    v_new := replace(v_def, v_anchor, v_inject || v_anchor);
    if v_new = v_def then
      raise exception 'IG_N7_SOURCE_CONTRACT_CLASSIFIER_ANCHOR_NOT_FOUND:%', v_name;
    end if;

    execute v_new;
    if md5(pg_get_functiondef(v_reg)) <> v_expected_post then
      raise exception 'IG_N7_SOURCE_CONTRACT_CLASSIFIER_POST_MD5_MISMATCH:%:%', v_name, md5(pg_get_functiondef(v_reg));
    end if;
  end loop;
end;
$hotfix_classifier$;

do $hotfix_rebind$
declare
  v_reg regprocedure := 'programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure;
  v_def text;
  v_new text;
  v_pre_md5 text;
  v_expected_pre text := '7355137c95d5776215a63c6b53232f80';
  v_expected_post text := 'e0e537716d8afadaecb4ed83acecbe12';
  v_source_anchor text := '      a.source_refs,a.rationale,a.blockers,a.negative_requirements,a.test_obligations,''{}''::jsonb,';
  v_source_replacement text := $source$
      case when p_pantalla_id in (52,53,54,56) then
        programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,a.family_code,v_version)->'source_refs'
      else a.source_refs end,a.rationale,a.blockers,a.negative_requirements,a.test_obligations,'{}'::jsonb,
$source$;
  v_fingerprint_anchor text := $fingerprint_anchor$
        'bootstrap_classifier_sha256',coalesce(
          nullif(a.curator_evidence->>'bootstrap_classifier_sha256',''),
          programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,a.family_code,v_version)->>'classifier_sha256'
        )
$fingerprint_anchor$;
  v_fingerprint_replacement text := $fingerprint_replacement$
        'bootstrap_classifier_sha256',case
          when p_pantalla_id in (52,53,54,56) then
            programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,a.family_code,v_version)->>'classifier_sha256'
          else coalesce(
            nullif(a.curator_evidence->>'bootstrap_classifier_sha256',''),
            programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,a.family_code,v_version)->>'classifier_sha256'
          )
        end
$fingerprint_replacement$;
begin
  v_def := pg_get_functiondef(v_reg);
  v_pre_md5 := md5(v_def);
  if v_pre_md5 <> v_expected_pre then
    raise exception 'IG_N7_SOURCE_CONTRACT_REBIND_BASELINE_DRIFT:%', v_pre_md5;
  end if;

  v_new := replace(v_def, v_source_anchor, v_source_replacement);
  if v_new = v_def then
    raise exception 'IG_N7_SOURCE_CONTRACT_REBIND_SOURCE_ANCHOR_NOT_FOUND';
  end if;

  v_def := v_new;
  v_new := replace(v_def, v_fingerprint_anchor, v_fingerprint_replacement);
  if v_new = v_def then
    raise exception 'IG_N7_SOURCE_CONTRACT_REBIND_FINGERPRINT_ANCHOR_NOT_FOUND';
  end if;

  execute v_new;
  if md5(pg_get_functiondef(v_reg)) <> v_expected_post then
    raise exception 'IG_N7_SOURCE_CONTRACT_REBIND_POST_MD5_MISMATCH:%', md5(pg_get_functiondef(v_reg));
  end if;
end;
$hotfix_rebind$;

comment on function programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint) is
  'N-7 closure hotfix: screens 52/53/54/56 declare the exact governed sources consumed by PERMISSIONS and VISUAL_EVIDENCE assertions.';

comment on function programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb) is
  'N-7 closure hotfix cached parity: screens 52/53/54/56 declare the exact governed sources consumed by PERMISSIONS and VISUAL_EVIDENCE assertions.';

comment on function programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean) is
  'N-7 closure hotfix: for screens 52/53/54/56 rebind persists current classifier source_refs and classifier fingerprint before rebuilding current assertions; all other screens preserve prior behavior.';
