-- PR-G: owner username-only input (not authentication), preserve V2 source/step/judge gates.
-- Owner registry and owner_sub remain documentary; proponente != decisor remains.
-- No alteration of lf_ig_rule_finalize_v2, lf_ig_rule_child_guard_v2 or rules.
-- Failure to match exact deployed original MD5 raises before any authoritative changes.
DO $prg$
DECLARE
  v_function text;
  v_before int;
  v_c text;
  v_md5 text;
BEGIN
  IF to_regprocedure('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)') IS NULL
     OR to_regclass('public.lf_ig_owner_decision_v2') IS NULL THEN
    RAISE EXCEPTION 'PR_G_OWNER_V2_MISSING';
  END IF;
  SELECT md5(pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure))
    INTO v_md5;
  IF v_md5 <> '2d6f2592e8f7e002ab29f212bcca0663' THEN
    RAISE EXCEPTION 'PR_G_OWNER_WRITER_PREIMAGE_MD5_DRIFT:%',v_md5;
  END IF;
  SELECT pg_get_constraintdef(oid) INTO v_c FROM pg_constraint
   WHERE conrelid='public.lf_ig_owner_decision_v2'::regclass
   AND conname='lf_ig_owner_decision_v2_identity_mode_check';
  IF md5(v_c) IS DISTINCT FROM 'f2e2c80a1d8e7d85ac15b7238df02a2b' THEN
    RAISE EXCEPTION 'PR_G_IDENTITY_CONSTRAINT_PREIMAGE_DRIFT';
  END IF;
  IF (SELECT count(*) FROM public.lf_ig_owner_decision_v2)<>0 THEN
    RAISE EXCEPTION 'PR_G_PREEXISTING_OWNER_DECISIONS_REQUIRE_REVIEW';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.lf_ig_project_owner_v2
    WHERE project_code='LF' AND owner_name='Cristhian Luján'
      AND identity_mode='UNVERIFIED_CHAT_DECLARATION'
      AND status='TEMP_DOCUMENTARY_ACTIVE')
  THEN RAISE EXCEPTION 'PR_G_SINGLE_LF_OWNER_REGISTRY_MISSING'; END IF;
  IF has_function_privilege('anon','public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)','EXECUTE')
  THEN RAISE EXCEPTION 'PR_G_OWNER_WRITER_CLIENT_EXECUTE_EXPOSED'; END IF;
  SELECT pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure)
  INTO v_function;
  v_before:=length(v_function);
  v_function:=replace(v_function,$prg_old_0$v_decision_date timestamptz; v_decision_sha text;$prg_old_0$,$prg_new_0$v_decision_date timestamptz; v_decision_sha text; v_decision_record jsonb;$prg_new_0$);
  IF v_before-length(v_function) <> -25 THEN
    RAISE EXCEPTION 'PR_G_FUNCTION_REPLACEMENT_MISMATCH_INDEX_0';
  END IF;
  v_before:=length(v_function);
  v_function:=replace(v_function,$prg_old_1$(SELECT count(*) FROM jsonb_object_keys(p_decision))<>6$prg_old_1$,$prg_new_1$(SELECT count(*) FROM jsonb_object_keys(p_decision))<>2$prg_new_1$);
  IF v_before-length(v_function) <> 0 THEN
    RAISE EXCEPTION 'PR_G_FUNCTION_REPLACEMENT_MISMATCH_INDEX_1';
  END IF;
  v_before:=length(v_function);
  v_function:=replace(v_function,$prg_old_2$p_decision ?& ARRAY['codigo_regla','propuesta_sha256',
        'veredicto','decisor','fecha','frase_literal']$prg_old_2$,$prg_new_2$p_decision ?& ARRAY['usuario','veredicto']$prg_new_2$);
  IF v_before-length(v_function) <> 67 THEN
    RAISE EXCEPTION 'PR_G_FUNCTION_REPLACEMENT_MISMATCH_INDEX_2';
  END IF;
  v_before:=length(v_function);
  v_function:=replace(v_function,$prg_old_3$v_decisor:=p_decision->>'decisor';$prg_old_3$,$prg_new_3$v_decisor:=CASE WHEN p_decision->>'usuario'='Cristhian Lujan' THEN 'Cristhian Luján' ELSE p_decision->>'usuario' END;$prg_new_3$);
  IF v_before-length(v_function) <> -83 THEN
    RAISE EXCEPTION 'PR_G_FUNCTION_REPLACEMENT_MISMATCH_INDEX_3';
  END IF;
  v_before:=length(v_function);
  v_function:=replace(v_function,$prg_old_4$v_phrase:=p_decision->>'frase_literal';$prg_old_4$,$prg_new_4$v_phrase:='OWNER_USERNAME_ONLY_NO_SIGNED_PHRASE';$prg_new_4$);
  IF v_before-length(v_function) <> -10 THEN
    RAISE EXCEPTION 'PR_G_FUNCTION_REPLACEMENT_MISMATCH_INDEX_4';
  END IF;
  v_before:=length(v_function);
  v_function:=replace(v_function,$prg_old_5$    OR p_decision->>'codigo_regla' IS DISTINCT FROM p_rule
$prg_old_5$,$prg_new_5$$prg_new_5$);
  IF v_before-length(v_function) <> 59 THEN
    RAISE EXCEPTION 'PR_G_FUNCTION_REPLACEMENT_MISMATCH_INDEX_5';
  END IF;
  v_before:=length(v_function);
  v_function:=replace(v_function,$prg_old_6$    OR coalesce(p_decision->>'propuesta_sha256','') !~ '^[0-9a-f]{64}$'
$prg_old_6$,$prg_new_6$$prg_new_6$);
  IF v_before-length(v_function) <> 72 THEN
    RAISE EXCEPTION 'PR_G_FUNCTION_REPLACEMENT_MISMATCH_INDEX_6';
  END IF;
  v_before:=length(v_function);
  v_function:=replace(v_function,$prg_old_7$    OR length(btrim(coalesce(v_phrase,'')))<6
$prg_old_7$,$prg_new_7$$prg_new_7$);
  IF v_before-length(v_function) <> 46 THEN
    RAISE EXCEPTION 'PR_G_FUNCTION_REPLACEMENT_MISMATCH_INDEX_7';
  END IF;
  v_before:=length(v_function);
  v_function:=replace(v_function,$prg_old_8$ IF coalesce(p_decision->>'fecha','') !~
  '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$'
 THEN RAISE EXCEPTION 'LF_IG_OWNER_DECISION_DATE_INVALID'; END IF;
 v_decision_date:=(p_decision->>'fecha')::timestamptz;$prg_old_8$,$prg_new_8$ v_decision_date:=clock_timestamp();$prg_new_8$);
  IF v_before-length(v_function) <> 223 THEN
    RAISE EXCEPTION 'PR_G_FUNCTION_REPLACEMENT_MISMATCH_INDEX_8';
  END IF;
  v_before:=length(v_function);
  v_function:=replace(v_function,$prg_old_9$ IF p_decision->>'propuesta_sha256' IS DISTINCT FROM v_sha
 THEN RAISE EXCEPTION 'LF_IG_OWNER_PROPOSAL_SHA256_MISMATCH'; END IF;
 v_decision_sha:=encode(extensions.digest(convert_to(p_decision::text,'UTF8'),'sha256'),'hex');$prg_old_9$,$prg_new_9$ v_decision_record:=jsonb_build_object(
  'codigo_regla',p_rule,'propuesta_sha256',v_sha,'veredicto',v_verdict,
  'decisor',v_decisor,'fecha',to_char(v_decision_date AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'frase_literal',v_phrase);
 v_decision_sha:=encode(extensions.digest(convert_to(v_decision_record::text,'UTF8'),'sha256'),'hex');$prg_new_9$);
  IF v_before-length(v_function) <> -126 THEN
    RAISE EXCEPTION 'PR_G_FUNCTION_REPLACEMENT_MISMATCH_INDEX_9';
  END IF;
  v_before:=length(v_function);
  v_function:=replace(v_function,$prg_old_10$   p_decision,v_decision_sha,p_parent,p_rule,v_kind,$prg_old_10$,$prg_new_10$   v_decision_record,v_decision_sha,p_parent,p_rule,v_kind,$prg_new_10$);
  IF v_before-length(v_function) <> -7 THEN
    RAISE EXCEPTION 'PR_G_FUNCTION_REPLACEMENT_MISMATCH_INDEX_10';
  END IF;
  v_before:=length(v_function);
  v_function:=replace(v_function,$prg_old_11$'decision_record',p_decision,'decision_record_sha256'$prg_old_11$,$prg_new_11$'decision_record',v_decision_record,'decision_record_sha256'$prg_new_11$);
  IF v_before-length(v_function) <> -14 THEN
    RAISE EXCEPTION 'PR_G_FUNCTION_REPLACEMENT_MISMATCH_INDEX_11';
  END IF;
  v_before:=length(v_function);
  v_function:=replace(v_function,$prg_old_12$'identity_mode','UNVERIFIED_CHAT_DECLARATION'$prg_old_12$,$prg_new_12$'identity_mode','USERNAME_ONLY_UNVERIFIED'$prg_new_12$);
  IF v_before-length(v_function) <> 3 THEN
    RAISE EXCEPTION 'PR_G_FUNCTION_REPLACEMENT_MISMATCH_INDEX_12';
  END IF;

  IF md5(v_function) <> 'e9bd839b8978a3f7872dd82a104ce99c' THEN
    RAISE EXCEPTION 'PR_G_OWNER_WRITER_POSTIMAGE_MD5_DRIFT';
  END IF;

  -- A username-only documentary record has no verified external identity.
  -- Keep all existing mandatory columns and downstream six-field archival record.
  ALTER TABLE public.lf_ig_owner_decision_v2
    DROP CONSTRAINT lf_ig_owner_decision_v2_identity_mode_check;
  ALTER TABLE public.lf_ig_owner_decision_v2
    ADD CONSTRAINT lf_ig_owner_decision_v2_identity_mode_check
    CHECK (identity_mode='USERNAME_ONLY_UNVERIFIED');
  ALTER TABLE public.lf_ig_owner_decision_v2
    ALTER COLUMN identity_mode SET DEFAULT 'USERNAME_ONLY_UNVERIFIED';

  EXECUTE v_function;
  IF md5(pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure))
     <> 'e9bd839b8978a3f7872dd82a104ce99c'
  THEN RAISE EXCEPTION 'PR_G_OWNER_WRITER_READBACK_MD5_DRIFT'; END IF;
  SELECT pg_get_constraintdef(oid) INTO v_c FROM pg_constraint
   WHERE conrelid='public.lf_ig_owner_decision_v2'::regclass
   AND conname='lf_ig_owner_decision_v2_identity_mode_check';
  IF md5(v_c) <> 'e1c17dcff3b03c5a9623e77aa1674cae' THEN
    RAISE EXCEPTION 'PR_G_IDENTITY_CONSTRAINT_POSTIMAGE_MD5_DRIFT'; END IF;
  IF has_function_privilege('anon','public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)','EXECUTE')
  THEN RAISE EXCEPTION 'PR_G_OWNER_EXECUTE_ACL_DRIFT'; END IF;
END
$prg$;
