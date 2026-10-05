-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M3.4 / PAULO-043
-- Explicit semantic eligibility + execution state, sourced from INPUT_FAMILY_POLICY_REGISTRY.
-- Scope: existing semantic classifier set only. No runtime deployment or production activation.

DO $m34$
DECLARE
  v_def text;
  v_new text;
  v_token constant text := '  v:=v-''classifier_sha256'';';
  v_patch constant text := $patch$
  if not exists (
    select 1
    from programacion.contratos c
    where c.version_id=p_version_id
      and c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
      and c.fail_closed
      and c.estado='defined'
      and c.especificacion->'families' ? p_family_code
      and upper(coalesce(c.especificacion->'families'->p_family_code->'stage_policy'->>'coverage_required_by',''))
          in ('STORY','IMPLEMENTATION','QA','PRODUCTION')
  ) then
    raise exception 'INPUT_FAMILY_POLICY_REGISTRY_ENTRY_INVALID:%:%',p_version_id,p_family_code;
  end if;

  v:=v || (
    select jsonb_build_object(
      'eligibility',
        case
          when coalesce(v->>'applicability','')='NOT_APPLICABLE' then 'NOT_REQUIRED'
          when upper(c.especificacion->'families'->p_family_code->'stage_policy'->>'coverage_required_by')='STORY' then 'REQUIRED'
          else 'CONDITIONAL'
        end,
      'execution_state',
        case
          when coalesce(v->>'applicability','')='NOT_APPLICABLE' then 'NOT_REQUIRED'
          when coalesce(v->>'coverage_status','')='COMPLETE' then 'DONE'
          when upper(c.especificacion->'families'->p_family_code->'stage_policy'->>'coverage_required_by')='STORY' then 'BLOCKED'
          else 'PENDING'
        end,
      'eligibility_source',
        jsonb_build_object(
          'contract','INPUT_FAMILY_POLICY_REGISTRY',
          'version_id',p_version_id,
          'coverage_required_by',upper(c.especificacion->'families'->p_family_code->'stage_policy'->>'coverage_required_by'),
          'authority',c.especificacion->'families'->p_family_code->'stage_policy'->>'authority'
        )
    )
    from programacion.contratos c
    where c.version_id=p_version_id
      and c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
      and c.fail_closed
      and c.estado='defined'
  );
$patch$;
  j jsonb;
  v_graph jsonb;
BEGIN
  v_def:=pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure);
  IF md5(v_def)<>'6dea9e0756942181a5adec56b4dba94e' THEN
    RAISE EXCEPTION 'M34_BASE_CLASSIFIER_PREIMAGE_DRIFT:%',md5(v_def);
  END IF;
  IF position(v_token in v_def)=0 THEN
    RAISE EXCEPTION 'M34_BASE_CLASSIFIER_PATCH_ANCHOR_MISSING';
  END IF;
  v_new:=replace(v_def,v_token,v_patch||E'\n'||v_token);
  IF v_new=v_def THEN
    RAISE EXCEPTION 'M34_BASE_CLASSIFIER_PATCH_NOOP';
  END IF;
  EXECUTE v_new;

  v_def:=pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'::regprocedure);
  IF md5(v_def)<>'3f63a9b2da1c22e9753f06803d88b9f0' THEN
    RAISE EXCEPTION 'M34_CACHED_CLASSIFIER_PREIMAGE_DRIFT:%',md5(v_def);
  END IF;
  IF position(v_token in v_def)=0 THEN
    RAISE EXCEPTION 'M34_CACHED_CLASSIFIER_PATCH_ANCHOR_MISSING';
  END IF;
  v_new:=replace(v_def,v_token,v_patch||E'\n'||v_token);
  IF v_new=v_def THEN
    RAISE EXCEPTION 'M34_CACHED_CLASSIFIER_PATCH_NOOP';
  END IF;
  EXECUTE v_new;

  -- Positive NOT_REQUIRED readback from existing governed recovery exclusion.
  j:=programacion.fn_input_governance_bootstrap_classify_v2(58,'PROFILES',19);
  IF j->>'eligibility'<>'NOT_REQUIRED' OR j->>'execution_state'<>'NOT_REQUIRED' THEN
    RAISE EXCEPTION 'M34_NOT_REQUIRED_SELFTEST_FAILED:%',j;
  END IF;

  -- Applicable family must expose explicit eligibility/state and registry provenance.
  j:=programacion.fn_input_governance_bootstrap_classify_v2(51,'PROFILES',19);
  IF j->>'eligibility' NOT IN ('REQUIRED','CONDITIONAL')
     OR j->>'execution_state' NOT IN ('DONE','BLOCKED','PENDING')
     OR j->'eligibility_source'->>'contract'<>'INPUT_FAMILY_POLICY_REGISTRY' THEN
    RAISE EXCEPTION 'M34_APPLICABLE_SELFTEST_FAILED:%',j;
  END IF;
  IF j->>'eligibility'='REQUIRED'
     AND coalesce(j->>'coverage_status','')<>'COMPLETE'
     AND j->>'execution_state'<>'BLOCKED' THEN
    RAISE EXCEPTION 'M34_REQUIRED_FAIL_CLOSED_SELFTEST_FAILED:%',j;
  END IF;

  -- Cached active path must emit the same eligibility/state for the same canonical graph.
  v_graph:=programacion.fn_input_screen_canonical_graph(51,19);
  IF v_graph IS NULL THEN
    RAISE EXCEPTION 'M34_CANONICAL_GRAPH_SELFTEST_MISSING';
  END IF;
  IF (programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(51,'PROFILES',19,v_graph)->>'eligibility')
       IS DISTINCT FROM (j->>'eligibility')
     OR (programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(51,'PROFILES',19,v_graph)->>'execution_state')
       IS DISTINCT FROM (j->>'execution_state') THEN
    RAISE EXCEPTION 'M34_CACHED_PARITY_SELFTEST_FAILED';
  END IF;
END;
$m34$;
