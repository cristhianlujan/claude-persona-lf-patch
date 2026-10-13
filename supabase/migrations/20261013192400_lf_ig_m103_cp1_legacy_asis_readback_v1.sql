-- IG M10.3 CP1 OBSERVE_ONCE with live database, canonical asset and external Edge readback.
-- No legacy deletion, no security policy mutation, no runtime traffic assertion.
-- External Supabase Edge list observed:
-- curator slug input-governance-curator-v1 ACTIVE v14 sha31fff4bc...
-- validator slug input-governance-validator-v1 ACTIVE v18 sha57bfa7fc...
-- agent slug input-governance-agent-v1 ACTIVE v17 sha95977bfd...
DO $m103_cp1$
DECLARE
 p constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 cp constant text := 'LEGACY_ASIS';
 actor constant text := 'IG_M103_CP1_LIVE_READBACK_20261013';
 ev constant text := 'supabase://programacion.engineering_work_checkpoints/M10.3#LEGACY_ASIS;supabase://pg_catalog.pg_proc+pg_catalog.pg_namespace;supabase://public.lf_activos/EDGE_FN_INPUT_GOVERNANCE_*;supabase://edge-functions/input-governance-agent-v1@17+input-governance-curator-v1@14+input-governance-validator-v1@18';
 v_boot jsonb; v_transition jsonb;
 v_total bigint; v_anon bigint; v_auth bigint; v_service bigint;
 v_assets bigint; v_distinct bigint; v_missing bigint; v_fake bigint;
 v_cur text; v_detail text;
BEGIN
 v_boot := programacion.fn_engineering_unit_bootstrap_v3(p,'M10.3');
 IF v_boot->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT'
   OR v_boot#>>'{current_checkpoint,checkpoint_code}'<>cp
   OR v_boot#>>'{execution_readiness,status}'<>'READY'
   OR v_boot#>>'{state,progress_pct}' NOT IN ('0.00','0')
   OR v_boot#>>'{state,open_blockers}'<>'0'
   OR v_boot#>>'{state,unmet_deps}'<>'0'
 THEN RAISE EXCEPTION 'M103_CP1_BOOTSTRAP_NOT_READY:%',v_boot#>'{current_checkpoint}'; END IF;

 IF (SELECT unit_metadata#>>'{m103_contract_governance_v1,phase}'
     FROM programacion.engineering_plan_units
     WHERE plan_code=p AND unit_code='M10.3') <> 'CONSTRUCTION_SANDBOX'
 THEN RAISE EXCEPTION 'M103_CP1_PREFLIGHT_CONTRACT_NOT_APPLIED'; END IF;

 SELECT count(*),
        count(*) FILTER(WHERE has_function_privilege('anon',f.oid,'EXECUTE')),
        count(*) FILTER(WHERE has_function_privilege('authenticated',f.oid,'EXECUTE')),
        count(*) FILTER(WHERE has_function_privilege('service_role',f.oid,'EXECUTE'))
 INTO v_total,v_anon,v_auth,v_service
 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace
 WHERE n.nspname IN ('programacion','public')
   AND (f.proname LIKE 'fn_input_governance%'
    OR f.proname LIKE 'fn_input_readiness%'
    OR f.proname LIKE 'fn_input_na_positive%'
    OR f.proname LIKE 'fn_input_bootstrap%'
    OR f.proname LIKE 'fn_guard_input_%');

 SELECT count(*),count(DISTINCT codigo_activo) INTO v_assets,v_distinct
 FROM public.lf_activos WHERE codigo_activo IN (
   'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
   'EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1',
   'EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1')
 AND archived_at IS NULL AND tipo_activo='CAPABILITY'
 AND estado_operativo='READ_ONLY' AND runtime_estado='CANDIDATE_READ_ONLY';

 SELECT count(*) INTO v_fake FROM public.lf_activos
 WHERE codigo_activo='EDGE_FN_INPUT_GOVERNANCE_FAKE_V1';
 -- Live readback positive: 3 original assets, nonempty SQL signatures,
 -- negative: a forged fourth Edge asset does not pass.
 IF v_total<1 OR v_assets<>3 OR v_distinct<>3 OR v_fake<>0
 THEN RAISE EXCEPTION 'M103_CP1_READBACK_CONTRADICTION functions:% assets:% distinct:% forged:%',v_total,v_assets,v_distinct,v_fake; END IF;

 -- Exactly the live database conditions measured. External Edge status is
 -- independently observed via Supabase list_edge_functions and NOT inferred
 -- from canonical asset runtime_state.
 SELECT version INTO v_cur FROM public.lf_capability_current
 WHERE capability_code='INPUT_GOVERNANCE';
 IF v_cur IS DISTINCT FROM '1.0.0' THEN
    RAISE EXCEPTION 'M103_CP1_RELEASE_BASELINE_DRIFT:%',v_cur;
 END IF;

 v_detail := format('Observed-only SQL function signatures=%s; EXECUTE effective anon=%s, authenticated=%s, service_role=%s; canonical Edge assets=%s distinct=%s, forged_negative=%s; Supabase Edge list: agent ACTIVE v17 SHA95977bfd7be64aef68a4c18c2e7fe15914aa510bcc1c1ee668863068cc5e656c, curator ACTIVE v14 SHA31fff4bc573c6832f7c3ce53c783c31b735ead263e3262af5d43b3a7b64b3d5c, validator ACTIVE v18 SHA57bfa7fcf19002378a5f1ffcdd3f3777223a4c8ca3417df8220b55c996e59a77; CURRENT INPUT_GOVERNANCE=%s. Edge ACTIVE means deployed not receiving traffic; no removals/revokes/activation.',v_total,v_anon,v_auth,v_service,v_assets,v_distinct,v_fake,v_cur);
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
   p,'M10.3',cp,'DONE',ev,actor,v_detail);
 IF v_transition#>>'{transition,status}'<>'APPLIED' THEN
    RAISE EXCEPTION 'M103_CP1_TRANSITION_REJECTED:%',v_transition;
 END IF;
 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(p,'M10.3');
 IF v_boot#>>'{current_checkpoint,checkpoint_code}'<>'NOT_ACTIVE'
    OR v_boot#>>'{state,done_checkpoint_count}'<>'1'
    OR v_boot#>>'{state,progress_pct}' NOT IN ('20.00','20')
 THEN RAISE EXCEPTION 'M103_CP1_POST_READBACK_FAILED:%',v_boot#>'{state}'; END IF;
END
$m103_cp1$;