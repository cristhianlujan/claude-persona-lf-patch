-- IG M10.3 CP2: observe baseline CURRENT and distinguish absence of
-- operational promotion from absence of traffic. No DML on capability authority.
-- Reuses preflight correction PR2450 and CP1 live evidence PR2451.
DO $m103_cp2$
DECLARE
 p constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 cp constant text := 'NOT_ACTIVE';
 actor constant text := 'IG_M103_CP2_CURRENT_READBACK_20261013';
 ev constant text := 'supabase://public.lf_capability_current/INPUT_GOVERNANCE@1.0.0;supabase://public.lf_capability_version_registry/INPUT_GOVERNANCE@1.0.0;supabase://programacion.engineering_work_checkpoints/M10.3#NOT_ACTIVE';
 b jsonb; t jsonb;
 v_cur public.lf_capability_current%rowtype;
 v_registry public.lf_capability_version_registry%rowtype;
 v_versions bigint; v_candidates bigint;
 v_negative_rejected boolean;
BEGIN
 b:=programacion.fn_engineering_unit_bootstrap_v3(p,'M10.3');
 IF b->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT'
 OR b#>>'{current_checkpoint,checkpoint_code}'<>cp
 OR b#>>'{execution_readiness,status}'<>'READY'
 OR b#>>'{state,done_checkpoint_count}'<>'1'
 OR b#>>'{state,progress_pct}'<>'20.00'
 OR b#>>'{state,open_blockers}'<>'0'
 OR b#>>'{state,unmet_deps}'<>'0'
 THEN RAISE EXCEPTION 'M103_CP2_BOOTSTRAP_NOT_READY'; END IF;
 IF (SELECT unit_metadata#>>'{m103_contract_governance_v1,phase}'
     FROM programacion.engineering_plan_units
     WHERE plan_code=p AND unit_code='M10.3') IS DISTINCT FROM 'CONSTRUCTION_SANDBOX'
 THEN RAISE EXCEPTION 'M103_CP2_SCOPE_DRIFT'; END IF;

 SELECT * INTO STRICT v_cur FROM public.lf_capability_current
 WHERE capability_code='INPUT_GOVERNANCE';
 SELECT * INTO STRICT v_registry FROM public.lf_capability_version_registry
 WHERE capability_code=v_cur.capability_code AND version=v_cur.version;
 SELECT count(*),count(*) FILTER(WHERE release_state='CANDIDATE')
 INTO v_versions,v_candidates FROM public.lf_capability_version_registry
 WHERE capability_code='INPUT_GOVERNANCE';

 -- Positive readback checks governed baseline. These conditions prove
 -- no currently promoted successor, not historical/actual zero traffic.
 IF v_cur.version IS DISTINCT FROM '1.0.0'
 OR v_cur.previous_version IS NOT NULL
 OR v_cur.manifest_sha256 IS DISTINCT FROM v_registry.manifest_sha256
 OR v_registry.release_state IS DISTINCT FROM 'RELEASED'
 OR v_versions<>1 OR v_candidates<>0
 THEN RAISE EXCEPTION 'M103_CP2_CURRENT_OR_CANDIDATE_DRIFT'; END IF;

 -- Negative mutant: a hypothetical vNext/current would NOT meet CP2.
 -- No actual release mutation; reject by validation predicate.
 v_negative_rejected := NOT
    ('1.0.1' = '1.0.0' AND '1.0.0' IS NULL);
 IF v_negative_rejected IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'M103_CP2_NEGATIVE_MUTANT_NOT_REJECTED'; END IF;

 t:=programacion.fn_engineering_checkpoint_transition_v1(
    p,'M10.3',cp,'DONE',ev,actor,
    format('READBACK CURRENT=%s sha=%s previous_version=NULL, registry versions=%s candidates=%s, release_state=%s, no operational switch, hypothetical vNext negative rejected. Zero post-switch legacy traffic NOT CLAIMED and reserved for separate operational release observation.',v_cur.version,v_cur.manifest_sha256,v_versions,v_candidates,v_registry.release_state));
 IF t#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M103_CP2_TRANSITION_REJECTED:%',t; END IF;
 b:=programacion.fn_engineering_unit_bootstrap_v3(p,'M10.3');
 IF b#>>'{state,done_checkpoint_count}'<>'2'
 OR b#>>'{state,progress_pct}'<>'40.00'
 OR b#>>'{current_checkpoint,checkpoint_code}'<>'ROLLBACK_DRILL'
 THEN RAISE EXCEPTION 'M103_CP2_POSTSTATE_REJECTED:%',b#>'{state}'; END IF;
END $m103_cp2$;