-- PR-J3-A prerequisite to AUTH-020 owner decision.
-- EKB LF-OWNER-OVERRIDE-NO_PROMOTION-MANIFEST-20261115-001: do not
-- use manifest.no_promotion as veto. Current native runs set it false.
-- Keep parent RUN, Router, read_only/no_write, Step40/60, Step70
-- independent, screen, source snapshot, exact patch and owner checks.
-- No changes to AUTH-018/019/020, permission38, policies, RLS or finalizer.
DO $j3$
DECLARE before_ddl text; after_ddl text; old_guard text;
        old_count integer; post_md5 text;
BEGIN
 IF to_regprocedure('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)') IS NULL
 THEN RAISE EXCEPTION 'PR_J3_OWNER_V2_FUNCTION_MISSING'; END IF;
 before_ddl:=pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure);
 IF md5(before_ddl)<>'e9bd839b8978a3f7872dd82a104ce99c'
 THEN RAISE EXCEPTION 'PR_J3_OWNER_V2_SOURCE_MD5_DRIFT:%',md5(before_ddl); END IF;
 old_guard:=$old$AND manifest->>'no_write'='true' AND manifest->>'no_promotion'='true'$old$;
 old_count:=(length(before_ddl)-length(replace(before_ddl,old_guard,'')))/length(old_guard);
 IF old_count<>1 THEN RAISE EXCEPTION 'PR_J3_OWNER_V2_GUARD_NOT_UNIQUE:%',old_count; END IF;
 after_ddl:=replace(before_ddl,old_guard,$new$AND manifest->>'no_write'='true'$new$);
 IF after_ddl IS NOT DISTINCT FROM before_ddl
 OR position(old_guard IN after_ddl)>0
 OR position($keep$AND manifest->>'read_only'='true'$keep$ IN after_ddl)=0
 OR position($keep$AND manifest->>'no_write'='true'$keep$ IN after_ddl)=0
 OR position($keep$v_judge->>'verdict','') <> 'PASS_INDEPENDENT_SEMANTIC'$keep$ IN after_ddl)=0
 THEN RAISE EXCEPTION 'PR_J3_OWNER_V2_REPLACEMENT_OR_SECURITY_GATES_DRIFT'; END IF;
 EXECUTE after_ddl;
 post_md5:=md5(pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure));
 IF post_md5<>md5(after_ddl) THEN RAISE EXCEPTION 'PR_J3_OWNER_V2_POSTIMAGE_UNEXPECTED'; END IF;
 IF post_md5<>'d537e91abe7da40fb54636ccfb8c51ef' THEN
  RAISE EXCEPTION 'PR_J3_OWNER_V2_EXACT_CANDIDATE_MD5_DRIFT:%',post_md5; END IF;
 IF has_function_privilege('anon','public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'PR_J3_OWNER_V2_ACL_EXPOSED'; END IF;
 RAISE NOTICE 'PR_J3_OWNER_V2_GUARD_ONLY_PASS before=e9bd839b8978a3f7872dd82a104ce99c after=% independent_judge_retained=true rules_untouched=true',post_md5;
END
$j3$;
