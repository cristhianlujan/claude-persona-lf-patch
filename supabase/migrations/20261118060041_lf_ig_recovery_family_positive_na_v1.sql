-- LF IG | Owner 2026-11-17 07:32 | candidate DRAFT only.
-- Correct positive N/A authority for restricted recovery contexts by semantic state entity_type.
-- Preserve absence-is-not-N/A; leave all VIGENTE rules and parameters untouched.
-- No new function, GRANT, profile EXECUTE, promotion or historical-run mutation.
-- Each candidate CREATE OR REPLACE is guarded by live pg_get_functiondef MD5.
-- Run PG regression with sandbox/ig_recovery_family_positive_na_v1/rollback_test.sql in BEGIN/ROLLBACK.
DO $ig$
DECLARE
  rec record;
  d text;
  previous_def text;
BEGIN
  FOR rec IN
    SELECT * FROM (VALUES
      ('AUTH','programacion.fn_input_na_positive_authority_v512(text,integer,bigint)','54de45cf44a62218493026503c441aee'),
      ('AUTH','programacion.fn_input_na_positive_authority_v512(text,integer,bigint,jsonb)','49b2c428ad873917b4e950761aca0e83'),
      ('AUTH','programacion.fn_input_na_positive_authority_v512_cached_v1(text,integer,bigint,jsonb)','1e1bed65856063b82a7d97ff588df390'),
      ('CLASS','programacion.fn_input_governance_bootstrap_classify_v1(integer,text,bigint)','adea36699afc83e09f54b92e1656fda2'),
      ('CLASS','programacion.fn_input_governance_bootstrap_classify_v1_ctx(integer,text,bigint,jsonb)','7ca4f143735f0c38922af862f5330e02'),
      ('CLASS','programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(integer,text,bigint,jsonb)','7bdb44ce517556a888c18d59dba1a04e'),
      ('GUARD','programacion.fn_guard_input_validator_semantic_coherence_v512()','6643c01d068fd81bf67cd6943e545c82')
    ) AS t(kind,signature,expected_md5)
  LOOP
    d := pg_get_functiondef(rec.signature::regprocedure);
    previous_def := d;
    IF d IS NULL OR md5(d) IS DISTINCT FROM rec.expected_md5 THEN
      RAISE EXCEPTION 'IG_RECOVERY_SELECT_SOURCE_DRIFT:% expected=% got=%',
        rec.signature,rec.expected_md5,coalesce(md5(d),'<missing>');
    END IF;
    IF rec.kind='AUTH' THEN
      IF position('v_client_recovery_no_access boolean := false;' in d)=0
         OR position('if p_family_code=''SESSION'' then' in d)=0
         OR position('elsif p_family_code=''PERMISSIONS''' in d)=0
         OR position('if v_rule->>''rule_code''=''B2B-RULE-INPUT-APPLICABILITY-001''' in d)=0
      THEN RAISE EXCEPTION 'IG_RECOVERY_AUTH_ANCHOR_MISSING:%',rec.signature; END IF;
      d := replace(d,
        'v_client_recovery_no_access boolean := false;',
        'v_client_recovery_no_access boolean := false;'||E'\n  v_restricted_recovery_context boolean := false;'
      );
      d := replace(d,
        $old$  if p_family_code='SESSION' then$old$,
        $new$  -- Semantic context, not screen IDs. No operational session != no recovery context.
  select exists (
    select 1
    from lf_ops.pantallas_estados pe
    join lf_ops.estados_catalogo ec on ec.state_code=pe.state_code
    where pe.pantalla_id=p_pantalla_id
      and pe.status not in ('ARCHIVADO','DEPRECATED')
      and ec.entity_type ~* '(RECOVERY|RECUPER|PASSWORD_UPDATE)'
  ) into v_restricted_recovery_context;

  if p_family_code='SESSION' and not v_restricted_recovery_context then$new$
      );
      d := replace(d,
        $old$elsif p_family_code='PERMISSIONS'$old$,
        $new$elsif p_family_code='PERMISSIONS' and not v_restricted_recovery_context$new$
      );
      -- Existing explicit FF/I18N exclusions only qualify from a VIGENTE rule.
      d := replace(d,
        $old$if v_rule->>'rule_code'='B2B-RULE-INPUT-APPLICABILITY-001'$old$,
        $new$if v_rule->>'rule_code'='B2B-RULE-INPUT-APPLICABILITY-001'
         and v_rule->>'status'='VIGENTE'$new$
      );
    ELSIF rec.kind='CLASS' THEN
      IF position($old$if coalesce((v_na->>'qualified')::boolean,false) then$old$ in d)=0
        OR position($old$'source_refs',v_source_refs,'blockers','[]'::jsonb,$old$ in d)=0
      THEN RAISE EXCEPTION 'IG_RECOVERY_CLASS_ANCHOR_MISSING:%',rec.signature; END IF;
      -- Fail open to APPLICABLE when an alleged exclusion lacks a concrete rule.
      d := replace(d,
        $old$if coalesce((v_na->>'qualified')::boolean,false) then$old$,
        $new$if coalesce((v_na->>'qualified')::boolean,false)
     and jsonb_array_length(coalesce(v_na->'rule_codes','[]'::jsonb))>0 then$new$
      );
      -- Cite each actual positive authority in source_refs; graph-only is not sufficient.
      d := replace(d,
        $old$'source_refs',v_source_refs,'blockers','[]'::jsonb,$old$,
        $new$'source_refs',v_source_refs||coalesce((
           select jsonb_agg(jsonb_build_object('kind','RULE','codigo',q.code) order by q.code)
           from jsonb_array_elements_text(coalesce(v_na->'rule_codes','[]'::jsonb)) q(code)
         ),'[]'::jsonb),'blockers','[]'::jsonb,$new$
      );
    ELSIF rec.kind='GUARD' THEN
      IF position($old$if coalesce((v_session_na_authority->>'qualified')::boolean,false) is not true then$old$ in d)=0
        OR position($old$if v_session_applicability<>'NOT_APPLICABLE' then$old$ in d)=0
      THEN RAISE EXCEPTION 'IG_RECOVERY_VALIDATOR_ANCHOR_MISSING:%',rec.signature; END IF;
      -- Still enforce operational-session DENY, but recovery context SESSION must APPLY.
      d := replace(d,
        $old$if coalesce((v_session_na_authority->>'qualified')::boolean,false) is not true then$old$,
        $new$if coalesce((v_session_na_authority->>'qualified')::boolean,false) is true then$new$
      );
      d := replace(d,
        $old$if v_session_applicability<>'NOT_APPLICABLE' then$old$,
        $new$if v_session_applicability<>'APPLICABLE' then$new$
      );
      d := replace(d,
        $old$The SESSION family must remain positively N/A.$old$,
        $new$The SESSION family applies to a restricted recovery context, not an operational session.$new$
      );
      d := replace(d,
        $old$V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_EXCLUSION_AUTHORITY_MISSING$old$,
        $new$V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_FALSE_NA_AUTHORITY$new$
      );
    END IF;
    IF d IS NOT DISTINCT FROM previous_def THEN
      RAISE EXCEPTION 'IG_RECOVERY_NO_CHANGE:%',rec.signature;
    END IF;
    EXECUTE d;
  END LOOP;
END;
$ig$;
