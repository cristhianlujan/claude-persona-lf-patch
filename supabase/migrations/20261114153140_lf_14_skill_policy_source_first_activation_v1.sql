-- #3879: Activate remaining 14 LF skill policies after owner already approved 18/18.
-- Separate from PR A #3868 engine. Never touch historic RUNs. Fail closed on source drift.
-- 4 existing IG governed-by policies must stay active; 6 IG policies remain CONDITIONAL.
-- 7 SCREEN_RULES_SNAPSHOT are SEMANTIC_OPTIONAL; 1 PROFILE_UPDATE_APPLY
-- is SEMANTIC_OPTIONAL and WRITE_GOVERNED (not executed in Step40).
BEGIN;
LOCK TABLE public.lf_skill_selector_policy_v1 IN SHARE ROW EXCLUSIVE MODE;
DO $governed$
DECLARE
 v_preimage text;
 v_total integer;
 v_active integer;
 v_pending integer;
 v_invalid integer;
 v_updated integer;
 v_ig_old constant text := 'sha256:91dd8dac1266a0a1e7b080c21c37ec47762172e376825e7471cc16b7b7af3f62';
 v_ig_new text;
BEGIN
 SELECT md5(string_agg(to_jsonb(p)::text,'|' ORDER BY profile_code,skill_code,required_operation)),
        count(*),
        count(*) FILTER(WHERE enabled AND NOT owner_decision_required),
        count(*) FILTER(WHERE NOT enabled AND owner_decision_required)
 INTO v_preimage,v_total,v_active,v_pending
 FROM public.lf_skill_selector_policy_v1 p;
 IF v_preimage<>'f075ec6faf0572dc4e89d9c101224a8b'
   OR v_total<>18 OR v_active<>4 OR v_pending<>14
 THEN RAISE EXCEPTION 'SOURCE_STATE_DRIFT_POLICY_18_4_14:%:%:%:%',
   v_preimage,v_total,v_active,v_pending; END IF;
 IF (SELECT count(*) FROM public.lf_skill_selector_policy_v1
     WHERE NOT enabled AND owner_decision_required
       AND skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
       AND selection_mode='DETERMINISTIC_REQUIRED'
       AND applicability_contract->>'only_if_applicable'='true')<>6
 OR (SELECT count(*) FROM public.lf_skill_selector_policy_v1
     WHERE NOT enabled AND owner_decision_required
       AND skill_code='SCREEN_RULES_SNAPSHOT'
       AND selection_mode='SEMANTIC_OPTIONAL')<>7
 OR (SELECT count(*) FROM public.lf_skill_selector_policy_v1
     WHERE NOT enabled AND owner_decision_required
       AND skill_code='PROFILE_UPDATE_APPLY'
       AND selection_mode='SEMANTIC_OPTIONAL')<>1
 THEN RAISE EXCEPTION 'SOURCE_STATE_DRIFT_PENDING_SKILL_FAMILIES'; END IF;

 SELECT count(*) INTO v_invalid
 FROM public.lf_skill_selector_policy_v1 p
 LEFT JOIN public.lf_skill_catalog_v1 c ON c.skill_code=p.skill_code
 LEFT JOIN public.lf_profile_selection_registry_v1 pr
   ON pr.profile_code=p.profile_code
 LEFT JOIN public.lf_profile_selector_policy_v1 pp
   ON pp.profile_code=p.profile_code
 WHERE NOT p.enabled AND p.owner_decision_required
   AND (c.skill_code IS NULL OR c.status<>'READY'
        OR c.required_operation IS DISTINCT FROM p.required_operation
        OR NOT(c.effect=ANY(p.allowed_effects))
        OR pr.descriptor_status IS DISTINCT FROM 'CURRENT'
        OR pp.profile_code IS NULL
        OR NOT (p.channels <@ pp.channels));
 IF v_invalid<>0 THEN
   RAISE EXCEPTION 'SKILL_POLICY_CURRENT_SOURCE_OR_CHANNEL_MISSING:%',v_invalid;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_profile_write_authority_v1
    WHERE profile_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
      AND operation_code='ACTUALIZACION_PERFIL_LF' AND status='ACTIVE')
 THEN RAISE EXCEPTION 'PROFILE_UPDATE_APPLY_WRITE_AUTHORITY_NOT_ACTIVE'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_skill_selection_registry_v1
     WHERE skill_code IN ('SCREEN_RULES_SNAPSHOT','PROFILE_UPDATE_APPLY'))
 THEN RAISE EXCEPTION 'SKILL_DESCRIPTOR_CONCURRENT_INSERT_DRIFT'; END IF;
 IF (SELECT count(*) FROM public.lf_skill_catalog_v1
     WHERE (skill_code='SCREEN_RULES_SNAPSHOT' AND effect='READ_ONLY'
             AND handler_fn='lf_skill_h_screen_rules_snapshot_v1')
        OR (skill_code='PROFILE_UPDATE_APPLY' AND effect='WRITE_GOVERNED'
             AND handler_fn='lf_skill_h_profile_update_propose_v1'))<>2
 THEN RAISE EXCEPTION 'SKILL_CATALOG_SOURCE_DRIFT'; END IF;
 IF to_regprocedure('public.lf_skill_h_screen_rules_snapshot_v1(jsonb)') IS NULL
   OR to_regprocedure('public.lf_skill_h_profile_update_propose_v1(jsonb)') IS NULL
 THEN RAISE EXCEPTION 'SKILL_SOURCE_HANDLER_MISSING'; END IF;

 INSERT INTO public.lf_skill_selection_registry_v1(
   skill_code,descriptor,source_kind,source_ref,source_revision,
   descriptor_status,stale_reason,synced_at)
 SELECT c.skill_code,
   jsonb_build_object(
     'schema_version','LF_SKILL_SELECTION_DESCRIPTOR_V1',
     'description',c.description,
     'selection_evidence',jsonb_build_array(
       jsonb_build_object('kind','SOURCE_CONTRACT','value',c.required_operation,
         'source_section','public.lf_skill_catalog_v1'),
       jsonb_build_object('kind','BOUNDARY',
         'value',case c.effect when 'WRITE_GOVERNED'
           then 'SEMANTIC_OPTIONAL; no Step40 write; official authorized writer only'
           else 'SEMANTIC_OPTIONAL; READ_ONLY skill with source-bound screen code' end,
         'source_section','public.lf_profile_skill_selection_prepare_v1'))),
   'SUPABASE_CONTRACT','supabase://public.'||c.handler_fn,
   'sha256:'||encode(extensions.digest(convert_to(
      pg_get_functiondef(('public.'||c.handler_fn||'(jsonb)')::regprocedure),
      'UTF8'),'sha256'),'hex'),
   'CURRENT',NULL,clock_timestamp()
 FROM public.lf_skill_catalog_v1 c
 WHERE c.skill_code IN ('SCREEN_RULES_SNAPSHOT','PROFILE_UPDATE_APPLY')
   AND c.status='READY';
 GET DIAGNOSTICS v_updated=ROW_COUNT;
 IF v_updated<>2 THEN RAISE EXCEPTION 'SKILL_DESCRIPTOR_INSERT_NOT_EXACT_2:%',v_updated; END IF;

 v_ig_new:='sha256:'||encode(extensions.digest(convert_to(
   pg_get_functiondef('public.lf_skill_h_input_governance_context_pack_v1(jsonb)'::regprocedure),
   'UTF8'),'sha256'),'hex');
 UPDATE public.lf_skill_selection_registry_v1
 SET source_revision=v_ig_new,stale_reason=NULL,synced_at=clock_timestamp()
 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
   AND source_revision=v_ig_old AND descriptor_status='CURRENT'
   AND source_ref='supabase://public.lf_skill_h_input_governance_context_pack_v1';
 GET DIAGNOSTICS v_updated=ROW_COUNT;
 IF v_updated<>1 THEN RAISE EXCEPTION 'SKILL_IG_DESCRIPTOR_SOURCE_DRIFT'; END IF;

 UPDATE public.lf_skill_selector_policy_v1 p
 SET enabled=true,owner_decision_required=false,
     policy_evidence_ref='owner://lf/2026-11-14/skill-policy-18-approved',
     updated_at=clock_timestamp()
 WHERE NOT p.enabled AND p.owner_decision_required;
 GET DIAGNOSTICS v_updated=ROW_COUNT;
 IF v_updated<>14 THEN RAISE EXCEPTION 'SKILL_14_ACTIVATION_NOT_EXACT:%',v_updated; END IF;

 SELECT count(*),count(*) FILTER(WHERE enabled AND NOT owner_decision_required),
        count(*) FILTER(WHERE NOT enabled OR owner_decision_required)
 INTO v_total,v_active,v_pending
 FROM public.lf_skill_selector_policy_v1;
 IF v_total<>18 OR v_active<>18 OR v_pending<>0
 THEN RAISE EXCEPTION 'SKILL_POLICY_READBACK_18_NOT_ACTIVE:%:%:%',
   v_total,v_active,v_pending; END IF;
 IF (SELECT count(*) FROM public.lf_skill_selection_registry_v1
       WHERE skill_code IN ('SCREEN_RULES_SNAPSHOT','PROFILE_UPDATE_APPLY',
                           'INPUT_GOVERNANCE_CONTEXT_PACK')
         AND descriptor_status='CURRENT'
         AND source_revision LIKE 'sha256:%')<>3
 THEN RAISE EXCEPTION 'SKILL_DESCRIPTOR_READBACK_NOT_3'; END IF;
 IF (SELECT count(*) FROM public.lf_skill_selector_policy_v1
       WHERE enabled AND skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
         AND applicability_contract->>'only_if_applicable'='true')<>6
 THEN RAISE EXCEPTION 'SKILL_IG_CONDITIONAL_SCOPE_LOST'; END IF;
END $governed$;
COMMIT;
