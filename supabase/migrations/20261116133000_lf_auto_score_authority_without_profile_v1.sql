-- IG 08:15 owner: AUTO promotion uses current score/RAW/snapshot, not a profile allowlist.
-- HUMAN/MANUAL, hard_block categories and native score/source-binding remain unchanged.
-- PR #3795/#3948/#3777 are not modified or merged by this migration.
BEGIN;
DO $ig0815$
DECLARE d text; d0 text;
BEGIN
  d:=pg_get_functiondef('public.lf_rule_promotion_request_v1(text,text,text)'::regprocedure);
  IF md5(d)<>'61ab4c8363f09309385ff80a82697717' THEN RAISE EXCEPTION 'IG0815_REQUEST_PREIMAGE_DRIFT'; END IF;
  d0:=d;
  IF (length(d)-length(replace(d,$site$ if not exists(select 1 from public.lf_profile_write_authority_v1 a where a.profile_code=par.target_code and a.operation_code='PROMOCION_REGLA_LF' and a.status='ACTIVE') then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROFILE_NOT_AUTHORIZED_FOR_PROMOTION','profile',par.target_code); end if;$site$,'')))<>length($site$ if not exists(select 1 from public.lf_profile_write_authority_v1 a where a.profile_code=par.target_code and a.operation_code='PROMOCION_REGLA_LF' and a.status='ACTIVE') then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROFILE_NOT_AUTHORIZED_FOR_PROMOTION','profile',par.target_code); end if;$site$)
  THEN RAISE EXCEPTION 'IG0815_REQUEST_AUTH_SITE_NOT_UNIQUE'; END IF;
  d:=replace(d,$site$ if not exists(select 1 from public.lf_profile_write_authority_v1 a where a.profile_code=par.target_code and a.operation_code='PROMOCION_REGLA_LF' and a.status='ACTIVE') then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROFILE_NOT_AUTHORIZED_FOR_PROMOTION','profile',par.target_code); end if;$site$,$replacement$ -- Only a fully attested AUTO scorer bypasses the profile role grant. HUMAN/MANUAL is unchanged.
 v_score:=public.lf_rule_promotion_score_v1(p_execution_id,p_rule_code);
 if (v_score->>'decision' IS DISTINCT FROM 'AUTO'
     OR coalesce((v_score->>'score')::integer,-1)<85
     OR v_score->>'hard_block' IS DISTINCT FROM 'false'
     OR v_score->>'next_gate' IS DISTINCT FROM 'PROMOTION_REQUEST')
    AND NOT EXISTS(select 1 from public.lf_profile_write_authority_v1 a where a.profile_code=par.target_code and a.operation_code='PROMOCION_REGLA_LF' and a.status='ACTIVE') then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROFILE_NOT_AUTHORIZED_FOR_PROMOTION','profile',par.target_code); end if;$replacement$);
  IF (length(d)-length(replace(d,$site$ v_score:=public.lf_rule_promotion_score_v1(p_execution_id,p_rule_code);
 IF v_score->>'decision'='BLOCKED'$site$,'')))<>length($site$ v_score:=public.lf_rule_promotion_score_v1(p_execution_id,p_rule_code);
 IF v_score->>'decision'='BLOCKED'$site$)
  THEN RAISE EXCEPTION 'IG0815_REQUEST_SCORE_SITE_NOT_UNIQUE'; END IF;
  d:=replace(d,$site$ v_score:=public.lf_rule_promotion_score_v1(p_execution_id,p_rule_code);
 IF v_score->>'decision'='BLOCKED'$site$,$replacement$ IF v_score->>'decision'='BLOCKED'$replacement$);
  IF d=d0 OR position('AUTO scorer bypasses the profile role grant' IN d)=0
  THEN RAISE EXCEPTION 'IG0815_REQUEST_PATCH_INCOMPLETE'; END IF;
  EXECUTE d;

  d:=pg_get_functiondef('public.lf_rule_promotion_decide_v1(text,text,text,text)'::regprocedure);
  IF md5(d)<>'e36f54b29ad49e2b87b1a670e31cde30' THEN RAISE EXCEPTION 'IG0815_DECIDE_PREIMAGE_DRIFT'; END IF;
  d0:=d;
  IF (length(d)-length(replace(d,$site$   IF p.requested_by_profile<>'PERFIL-PRODUCT-DIRECTOR-LF'
      OR NOT EXISTS (SELECT 1 FROM public.lf_profile_write_authority_v1 a
        WHERE a.profile_code=p.requested_by_profile AND a.operation_code='PROMOCION_REGLA_LF' AND a.status='ACTIVE')
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_SCORE_PROFILE_NOT_AUTHORIZED'); END IF;$site$,'')))<>length($site$   IF p.requested_by_profile<>'PERFIL-PRODUCT-DIRECTOR-LF'
      OR NOT EXISTS (SELECT 1 FROM public.lf_profile_write_authority_v1 a
        WHERE a.profile_code=p.requested_by_profile AND a.operation_code='PROMOCION_REGLA_LF' AND a.status='ACTIVE')
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_SCORE_PROFILE_NOT_AUTHORIZED'); END IF;$site$)
  THEN RAISE EXCEPTION 'IG0815_DECIDE_PROFILE_SITE_NOT_UNIQUE'; END IF;
  d:=replace(d,$site$   IF p.requested_by_profile<>'PERFIL-PRODUCT-DIRECTOR-LF'
      OR NOT EXISTS (SELECT 1 FROM public.lf_profile_write_authority_v1 a
        WHERE a.profile_code=p.requested_by_profile AND a.operation_code='PROMOCION_REGLA_LF' AND a.status='ACTIVE')
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_SCORE_PROFILE_NOT_AUTHORIZED'); END IF;$site$,$replacement$   -- AUTO authority is the scored, source-bound parent RUN; no privileged profile literal.$replacement$);
  IF (length(d)-length(replace(d,$site$     IF (v_score->>'score')::int<85 OR v_score->>'decision'<>'AUTO' OR v_score->>'hard_block'<>'false'
         OR v_score->>'next_gate'<>'PROMOTION_REQUEST'$site$,'')))<>length($site$     IF (v_score->>'score')::int<85 OR v_score->>'decision'<>'AUTO' OR v_score->>'hard_block'<>'false'
         OR v_score->>'next_gate'<>'PROMOTION_REQUEST'$site$)
  THEN RAISE EXCEPTION 'IG0815_DECIDE_SCORE_SITE_NOT_UNIQUE'; END IF;
  d:=replace(d,$site$     IF (v_score->>'score')::int<85 OR v_score->>'decision'<>'AUTO' OR v_score->>'hard_block'<>'false'
         OR v_score->>'next_gate'<>'PROMOTION_REQUEST'$site$,$replacement$     IF coalesce((v_score->>'score')::int,-1)<85 OR v_score->>'decision' IS DISTINCT FROM 'AUTO'
         OR v_score->>'hard_block' IS DISTINCT FROM 'false'
         OR v_score->>'next_gate' IS DISTINCT FROM 'PROMOTION_REQUEST'$replacement$);
  IF d=d0 OR position('AUTO authority is the scored, source-bound parent RUN' IN d)=0
     OR position($site$p_decided_by !~ '^HUMAN:.+'$site$ IN d)=0
     OR position($site$AUTO_SCORE_PARENT_NOT_COMPLETED_CLEAN$site$ IN d)=0
     OR position($site$PROMOTION_STALE$site$ IN d)=0
  THEN RAISE EXCEPTION 'IG0815_DECIDE_PATCH_INCOMPLETE'; END IF;
  EXECUTE d;
END $ig0815$;
COMMIT;
