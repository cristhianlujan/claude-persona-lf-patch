-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · N-7 closure hotfix
-- EKB: INPUT-GOV-REBIND-CLASSIFIER-FINGERPRINT-001
-- R16 Git-first; R17 v3 judges required before merge/apply.

do $hotfix$
declare
  v_def text := pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure);
  v_new text;
begin
  if md5(v_def) <> 'edd9a8a4b9a78f62ead7008024ee0175' then
    raise exception 'IG_REBIND_FINGERPRINT_BASELINE_DRIFT:%', md5(v_def);
  end if;

  v_new := replace(
    v_def,
    $old$        'parent_run_id',v_parent,'parent_assessment_id',a.id,'direct_source_readback',true,
        'semantic_policy','NO_INVENTION_REBIND_ONLY'
      ),$old$,
    $new$        'parent_run_id',v_parent,'parent_assessment_id',a.id,'direct_source_readback',true,
        'semantic_policy','NO_INVENTION_REBIND_ONLY',
        'bootstrap_classifier_sha256',coalesce(
          nullif(a.curator_evidence->>'bootstrap_classifier_sha256',''),
          programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,a.family_code,v_version)->>'classifier_sha256'
        )
      ),$new$
  );

  if v_new = v_def then
    raise exception 'IG_REBIND_FINGERPRINT_ANCHOR_NOT_FOUND';
  end if;

  execute v_new;
end;
$hotfix$;

comment on function programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean) is
  'N-7 closure hotfix: rebind preserves the parent bootstrap classifier fingerprint, falling back to current-source recomputation only when absent; Validator v2 remains the independent equality gate.';
