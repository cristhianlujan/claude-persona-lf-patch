-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · N-7 / PAULO-172 closure hotfix
-- Root cause: screens 52/53/54/56 use governed direct RULE assertions for PERMISSIONS,
-- but the bootstrap classifier persisted only SCREEN_CANONICAL_GRAPH in source_refs.
-- AUD-039 requires the exact RULE used by the validator to be declared in assessment.source_refs.
-- Scope is intentionally limited to the four N-7 screens still missing chunk telemetry.

do $hotfix$
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
      when 'fn_input_governance_bootstrap_classify_v2' then 'aa17bb1ed9c85596412e256b1d2ac427'
      else 'ccfa1258d79b094a0be129fe5e6335ea'
    end;

    v_def := pg_get_functiondef(v_reg);
    v_pre_md5 := md5(v_def);
    if v_pre_md5 <> v_expected_pre then
      raise exception 'IG_N7_PERMISSIONS_SOURCE_REFS_BASELINE_DRIFT:%:%', v_name, v_pre_md5;
    end if;

    v_new := replace(v_def, v_anchor, v_inject || v_anchor);
    if v_new = v_def then
      raise exception 'IG_N7_PERMISSIONS_SOURCE_REFS_ANCHOR_NOT_FOUND:%', v_name;
    end if;

    execute v_new;
    if md5(pg_get_functiondef(v_reg)) <> v_expected_post then
      raise exception 'IG_N7_PERMISSIONS_SOURCE_REFS_POST_MD5_MISMATCH:%:%', v_name, md5(pg_get_functiondef(v_reg));
    end if;
  end loop;
end;
$hotfix$;

comment on function programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint) is
  'N-7 closure hotfix: screens 52/53/54/56 PERMISSIONS explicit canonical exclusions declare their exact governed RULE authority in source_refs (AUD-039).';

comment on function programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb) is
  'N-7 closure hotfix cached parity: screens 52/53/54/56 PERMISSIONS explicit canonical exclusions declare their exact governed RULE authority in source_refs (AUD-039).';
