-- M8.2 declared terminal timing publication gate. No provenance/sink/semantic SHA modification.
-- Base fn_engineering_terminal_acceptance_assert_v1 md5: 9fb149f2f363af60f5dd50bebd5c1e89
CREATE OR REPLACE FUNCTION programacion.fn_engineering_terminal_acceptance_assert_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_work_item_id bigint;
  v_seq int;
  v_prior_open int := 0;
  v_prior_done_without_evidence int := 0;
  v_unmet_dependencies int := 0;
  v_open_blockers int := 0;
  v_gate_code text;
  v_metrics_status text;
begin
  select pu.work_item_id,c.sequence_no,
    pu.unit_metadata #>> array['action_specs_v1',p_checkpoint_code,'terminal_acceptance_contract','published_metrics_gate']
    into v_work_item_id,v_seq,v_gate_code
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_checkpoints c
    on c.work_item_id=pu.work_item_id
   and c.checkpoint_code=p_checkpoint_code
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    raise exception 'ENGINEERING_TERMINAL_ASSERT_TARGET_NOT_FOUND:%/%/%',
      p_plan_code,p_unit_code,p_checkpoint_code;
  end if;

  select
    count(*) filter(where c.status not in ('DONE','NOT_APPLICABLE')),
    count(*) filter(where c.status='DONE' and nullif(btrim(coalesce(c.evidence_ref,'')),'') is null)
  into v_prior_open,v_prior_done_without_evidence
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.required
    and c.sequence_no<v_seq;

  select count(*)
    into v_unmet_dependencies
  from programacion.fn_engineering_effective_dependencies_v1(v_work_item_id) d
  where d.is_unmet;

  v_open_blockers:=programacion.fn_engineering_effective_open_blocker_count_v1(v_work_item_id);

  if v_gate_code is not null then
    if v_gate_code <> 'IG_PERFORMANCE_TIMING_PUBLISHED_V1' then
      raise exception 'ENGINEERING_TERMINAL_METRICS_GATE_UNSUPPORTED:%',v_gate_code;
    end if;
    select m.status into v_metrics_status
    from programacion.fn_ig_performance_timing_metrics_v1() m
    where m.scope='SUMMARY';
    if v_metrics_status is distinct from 'PUBLISHED' then
      raise exception 'ENGINEERING_TERMINAL_METRICS_NOT_PUBLISHED:%/%/% status=%',
        p_plan_code,p_unit_code,p_checkpoint_code,coalesce(v_metrics_status,'MISSING_SUMMARY');
    end if;
  end if;

  if v_prior_open<>0
     or v_prior_done_without_evidence<>0
     or v_unmet_dependencies<>0
     or v_open_blockers<>0 then
    raise exception
      'ENGINEERING_TERMINAL_ACCEPTANCE_NOT_READY:%/%/% prior_open=% prior_done_without_evidence=% unmet_dependencies=% open_blockers=%',
      p_plan_code,p_unit_code,p_checkpoint_code,
      v_prior_open,v_prior_done_without_evidence,v_unmet_dependencies,v_open_blockers;
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_TERMINAL_ACCEPTANCE_ASSERT_V1',
    'status','PASS',
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'prior_required_open',v_prior_open,
    'prior_done_without_evidence',v_prior_done_without_evidence,
    'unmet_dependencies',v_unmet_dependencies,
    'open_blockers',v_open_blockers
  ) || case when v_gate_code is null then '{}'::jsonb
            else jsonb_build_object('published_metrics_gate',v_gate_code,
                                    'published_metrics_status',v_metrics_status)
       end;
end;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_terminal_metrics_transition_guard_v1()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO 'programacion','public','pg_catalog'
AS $function$
DECLARE
  v_plan_code text;
  v_unit_code text;
  v_gate_code text;
BEGIN
  IF new.status NOT IN ('DONE','NOT_APPLICABLE') OR old.status IN ('DONE','NOT_APPLICABLE') THEN
    RETURN new;
  END IF;
  SELECT pu.plan_code,pu.unit_code,
         pu.unit_metadata #>> array['action_specs_v1',new.checkpoint_code,'terminal_acceptance_contract','published_metrics_gate']
    INTO v_plan_code,v_unit_code,v_gate_code
  FROM programacion.engineering_plan_units pu
  WHERE pu.work_item_id=new.work_item_id AND pu.disposition='ASSIGNED';
  IF v_gate_code IS NULL THEN RETURN new; END IF;
  IF new.status <> 'DONE' THEN
    RAISE EXCEPTION 'ENGINEERING_TERMINAL_METRICS_NOT_APPLICABLE_FORBIDDEN:%/%/%',
      v_plan_code,v_unit_code,new.checkpoint_code;
  END IF;
  PERFORM programacion.fn_engineering_terminal_acceptance_assert_v1(v_plan_code,v_unit_code,new.checkpoint_code);
  RETURN new;
END;
$function$;

CREATE TRIGGER trg_engineering_terminal_metrics_transition_guard_v1
BEFORE UPDATE OF status ON programacion.engineering_work_checkpoints
FOR EACH ROW EXECUTE FUNCTION programacion.fn_engineering_terminal_metrics_transition_guard_v1();

UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(
  unit_metadata,
  '{action_specs_v1,TERMINAL,terminal_acceptance_contract,published_metrics_gate}',
  to_jsonb('IG_PERFORMANCE_TIMING_PUBLISHED_V1'::text),true)
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M8.2'
  AND disposition='ASSIGNED'
  AND unit_metadata #>> '{action_specs_v1,TERMINAL,terminal_acceptance_contract,entrypoint}'
    = 'programacion.fn_engineering_terminal_acceptance_assert_v1';

DO $guard$
BEGIN
 IF (SELECT count(*) FROM programacion.engineering_plan_units
     WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M8.2'
       AND unit_metadata #>> '{action_specs_v1,TERMINAL,terminal_acceptance_contract,published_metrics_gate}'
         = 'IG_PERFORMANCE_TIMING_PUBLISHED_V1')<>1
 THEN RAISE EXCEPTION 'M82_TERMINAL_METADATA_GATE_NOT_BOUND'; END IF;
END;
$guard$;
