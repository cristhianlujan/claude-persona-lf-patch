-- IG M8.12 / PAULO-146: declared peer-completion gate, with self exclusion.
-- Preserve published-timing gate (M8.2). No domain payloads or status mutation.
CREATE OR REPLACE FUNCTION programacion.fn_engineering_terminal_acceptance_assert_v1(
 p_plan_code text,p_unit_code text,p_checkpoint_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO 'programacion','public','pg_catalog'
AS $f$
DECLARE
 v_work_item_id bigint; v_seq int;
 v_prior_open int:=0; v_prior_done_without_evidence int:=0;
 v_unmet_dependencies int:=0; v_open_blockers int:=0;
 v_gate_code text; v_metrics_status text;
 v_peer_scope jsonb; v_peer_value text; v_peer_count int:=0; v_peer_non_done int:=0;
BEGIN
 SELECT pu.work_item_id,c.sequence_no,
        pu.unit_metadata #>> array['action_specs_v1',p_checkpoint_code,'terminal_acceptance_contract','published_metrics_gate'],
        pu.unit_metadata #> array['action_specs_v1',p_checkpoint_code,'terminal_acceptance_contract','peer_completion_scope']
 INTO v_work_item_id,v_seq,v_gate_code,v_peer_scope
 FROM programacion.engineering_plan_units pu
 JOIN programacion.engineering_work_checkpoints c
   ON c.work_item_id=pu.work_item_id AND c.checkpoint_code=p_checkpoint_code
 WHERE pu.plan_code=p_plan_code AND pu.unit_code=p_unit_code AND pu.disposition='ASSIGNED';
 IF v_work_item_id IS NULL THEN
  RAISE EXCEPTION 'ENGINEERING_TERMINAL_ASSERT_TARGET_NOT_FOUND:%/%/%',p_plan_code,p_unit_code,p_checkpoint_code;
 END IF;
 SELECT count(*) FILTER(WHERE c.status NOT IN ('DONE','NOT_APPLICABLE')),
        count(*) FILTER(WHERE c.status='DONE' AND nullif(btrim(coalesce(c.evidence_ref,'')),'') IS NULL)
 INTO v_prior_open,v_prior_done_without_evidence
 FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=v_work_item_id AND c.required AND c.sequence_no<v_seq;
 SELECT count(*) INTO v_unmet_dependencies
 FROM programacion.fn_engineering_effective_dependencies_v1(v_work_item_id) d WHERE d.is_unmet;
 v_open_blockers:=programacion.fn_engineering_effective_open_blocker_count_v1(v_work_item_id);
 IF v_gate_code IS NOT NULL THEN
  IF v_gate_code <> 'IG_PERFORMANCE_TIMING_PUBLISHED_V1' THEN
   RAISE EXCEPTION 'ENGINEERING_TERMINAL_METRICS_GATE_UNSUPPORTED:%',v_gate_code;
  END IF;
  SELECT m.status INTO v_metrics_status FROM programacion.fn_ig_performance_timing_metrics_v1() m WHERE m.scope='SUMMARY';
  IF v_metrics_status IS DISTINCT FROM 'PUBLISHED' THEN
   RAISE EXCEPTION 'ENGINEERING_TERMINAL_METRICS_NOT_PUBLISHED:%/%/% status=%',p_plan_code,p_unit_code,p_checkpoint_code,coalesce(v_metrics_status,'MISSING_SUMMARY');
  END IF;
 END IF;
 IF v_peer_scope IS NOT NULL THEN
  IF jsonb_typeof(v_peer_scope)<>'object'
     OR v_peer_scope->>'field' IS DISTINCT FROM 'v1_macrolote'
     OR v_peer_scope->>'exclude_self' IS DISTINCT FROM 'true'
     OR nullif(btrim(v_peer_scope->>'value'),'') IS NULL THEN
   RAISE EXCEPTION 'ENGINEERING_TERMINAL_PEER_SCOPE_INVALID:%/%/%',p_plan_code,p_unit_code,p_checkpoint_code;
  END IF;
  v_peer_value:=v_peer_scope->>'value';
  SELECT count(*),count(*) FILTER(WHERE w.status IS DISTINCT FROM 'DONE')
  INTO v_peer_count,v_peer_non_done
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
  WHERE u.plan_code=p_plan_code AND u.disposition='ASSIGNED'
    AND u.v1_macrolote=v_peer_value AND u.unit_code<>p_unit_code;
  IF v_peer_count=0 OR v_peer_non_done<>0 THEN
   RAISE EXCEPTION 'ENGINEERING_TERMINAL_PEERS_NOT_DONE:%/%/% scope=% peers=% non_done=%',
     p_plan_code,p_unit_code,p_checkpoint_code,v_peer_value,v_peer_count,v_peer_non_done;
  END IF;
 END IF;
 IF v_prior_open<>0 OR v_prior_done_without_evidence<>0 OR v_unmet_dependencies<>0 OR v_open_blockers<>0 THEN
  RAISE EXCEPTION 'ENGINEERING_TERMINAL_ACCEPTANCE_NOT_READY:%/%/% prior_open=% prior_done_without_evidence=% unmet_dependencies=% open_blockers=%',
   p_plan_code,p_unit_code,p_checkpoint_code,v_prior_open,v_prior_done_without_evidence,v_unmet_dependencies,v_open_blockers;
 END IF;
 RETURN jsonb_build_object(
  'schema_version','ENGINEERING_TERMINAL_ACCEPTANCE_ASSERT_V1','status','PASS',
  'plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code,
  'prior_required_open',v_prior_open,'prior_done_without_evidence',v_prior_done_without_evidence,
  'unmet_dependencies',v_unmet_dependencies,'open_blockers',v_open_blockers)
  || CASE WHEN v_gate_code IS NULL THEN '{}'::jsonb
          ELSE jsonb_build_object('published_metrics_gate',v_gate_code,'published_metrics_status',v_metrics_status) END
  || CASE WHEN v_peer_scope IS NULL THEN '{}'::jsonb
          ELSE jsonb_build_object('peer_scope',v_peer_value,'peer_done',v_peer_count,'peer_non_done',v_peer_non_done) END;
END;
$f$;

-- Reuse the existing guarded-transition function/trigger, preserving timing behavior.
CREATE OR REPLACE FUNCTION programacion.fn_engineering_terminal_metrics_transition_guard_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'programacion','public','pg_catalog'
AS $f$
DECLARE v_plan_code text; v_unit_code text; v_gate_code text; v_peer_scope jsonb;
BEGIN
 IF new.status NOT IN ('DONE','NOT_APPLICABLE') OR old.status IN ('DONE','NOT_APPLICABLE') THEN RETURN new; END IF;
 SELECT pu.plan_code,pu.unit_code,
        pu.unit_metadata #>> array['action_specs_v1',new.checkpoint_code,'terminal_acceptance_contract','published_metrics_gate'],
        pu.unit_metadata #> array['action_specs_v1',new.checkpoint_code,'terminal_acceptance_contract','peer_completion_scope']
 INTO v_plan_code,v_unit_code,v_gate_code,v_peer_scope
 FROM programacion.engineering_plan_units pu
 WHERE pu.work_item_id=new.work_item_id AND pu.disposition='ASSIGNED';
 IF v_gate_code IS NULL AND v_peer_scope IS NULL THEN RETURN new; END IF;
 IF new.status <> 'DONE' THEN
  RAISE EXCEPTION 'ENGINEERING_TERMINAL_GATED_NOT_APPLICABLE_FORBIDDEN:%/%/%',v_plan_code,v_unit_code,new.checkpoint_code;
 END IF;
 PERFORM programacion.fn_engineering_terminal_acceptance_assert_v1(v_plan_code,v_unit_code,new.checkpoint_code);
 RETURN new;
END;
$f$;

UPDATE programacion.engineering_plan_units
SET unit_metadata=jsonb_set(unit_metadata,
 '{action_specs_v1,M8_ALL_DONE_GATE,terminal_acceptance_contract,peer_completion_scope}',
 '{"field":"v1_macrolote","value":"M8","exclude_self":true}'::jsonb,true)
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M8.12' AND disposition='ASSIGNED'
 AND unit_metadata #>> '{action_specs_v1,M8_ALL_DONE_GATE,terminal_acceptance_contract,entrypoint}'
 = 'programacion.fn_engineering_terminal_acceptance_assert_v1';

DO $guard$
BEGIN
 IF (SELECT count(*) FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M8.12'
 AND unit_metadata #>> '{action_specs_v1,M8_ALL_DONE_GATE,terminal_acceptance_contract,peer_completion_scope,value}'='M8')<>1
 THEN RAISE EXCEPTION 'M812_PEER_GATE_BINDING_FAILED'; END IF;
END;
$guard$;