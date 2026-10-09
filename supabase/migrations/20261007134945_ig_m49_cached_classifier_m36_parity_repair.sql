
do $patch$
declare
  v_def text;
  v_new text;
  v_old_review constant text := 'when upper(coalesce(b.value->>''code'','''')) ~ ''(SEMANTIC|SUBJECT|THREAT|COMPONENT).*(UNRESOLVED|MISSING|PENDING|INCOMPLETE|NOT_READY)''';
  v_new_review constant text := 'when upper(coalesce(b.value->>''code'','''')) ~ ''(SEMANTIC|SUBJECT|THREAT|COMPONENT).*(UNRESOLVED|MISSING|PENDING|INCOMPLETE|NOT_READY|REVIEW_REQUIRED)''';
  v_old_state constant text := $old$when upper(coalesce(b.value->>'code','')) ~ '(MISSING|NOT_LINKED|SOURCE.*INCOMPLETE|SOURCE_IDENTIFICATION|CANONICAL.*MISSING|REQUIREMENT.*MISSING|REFERENCE_UNRESOLVED)'$old$;
  v_new_state constant text := $new$when upper(coalesce(b.value->>'code',''))='SCREEN_STATE_SET_EMPTY'
          then 'MISSING_SOURCE'
        when upper(coalesce(b.value->>'code','')) ~ '(MISSING|NOT_LINKED|SOURCE.*INCOMPLETE|SOURCE_IDENTIFICATION|CANONICAL.*MISSING|REQUIREMENT.*MISSING|REFERENCE_UNRESOLVED)'$new$;
  v_old_transition constant text := $old$when upper(coalesce(b.value->>'code','')) ~ '(PARTIAL|INCOMPLETE)'
          then 'INCOMPLETE_EVIDENCE'$old$;
  v_new_transition constant text := $new$when upper(coalesce(b.value->>'code',''))='CANONICAL_TRANSITIONS_INSUFFICIENT'
          then 'INCOMPLETE_EVIDENCE'
        when upper(coalesce(b.value->>'code','')) ~ '(PARTIAL|INCOMPLETE)'
          then 'INCOMPLETE_EVIDENCE'$new$;
begin
  v_def:=pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'::regprocedure);

  if md5(v_def) <> 'c7d8f602dc32ff21a0ea50dffd46658c' then
    raise exception 'M49_CACHED_CLASSIFIER_PREIMAGE_DRIFT expected=% actual=%',
      'c7d8f602dc32ff21a0ea50dffd46658c',md5(v_def);
  end if;

  if position(v_old_review in v_def)=0 or position(v_old_state in v_def)=0 or position(v_old_transition in v_def)=0 then
    raise exception 'M49_CACHED_CLASSIFIER_EXPECTED_M36_FRAGMENTS_MISSING';
  end if;

  v_new:=replace(v_def,v_old_review,v_new_review);
  v_new:=replace(v_new,v_old_state,v_new_state);
  v_new:=replace(v_new,v_old_transition,v_new_transition);

  if v_new=v_def then
    raise exception 'M49_CACHED_CLASSIFIER_PATCH_NOOP';
  end if;

  execute v_new;
end;
$patch$;

do $verify$
declare
  v_def text;
begin
  v_def:=pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'::regprocedure);

  if position('(SEMANTIC|SUBJECT|THREAT|COMPONENT).*(UNRESOLVED|MISSING|PENDING|INCOMPLETE|NOT_READY|REVIEW_REQUIRED)' in v_def)=0 then
    raise exception 'M49_CACHED_CLASSIFIER_REVIEW_FIX_MISSING';
  end if;
  if position('SCREEN_STATE_SET_EMPTY' in v_def)=0 then
    raise exception 'M49_CACHED_CLASSIFIER_STATE_FIX_MISSING';
  end if;
  if position('CANONICAL_TRANSITIONS_INSUFFICIENT' in v_def)=0 then
    raise exception 'M49_CACHED_CLASSIFIER_TRANSITION_FIX_MISSING';
  end if;
end;
$verify$;
