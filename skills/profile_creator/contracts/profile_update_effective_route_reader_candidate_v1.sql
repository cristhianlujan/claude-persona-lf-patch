-- Profile Updater v0.2 route resolver, CANDIDATE SOURCE ONLY (not deployed).
-- This is a read-only derivation; no editing execution manifest or policies.
-- MUST be wired into BOTH the existing Profile step recorder and the Edge
-- operationSnapshot before registering route-enabled step contracts.
--
-- The legacy path deliberately returns the immutable v0.1 required-step list.
CREATE OR REPLACE FUNCTION public.lf_profile_update_effective_route_v1(
    p_execution_id text
) RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog,public
AS $route$
DECLARE
    e public.lf_operation_execution%rowtype;
    frozen jsonb;
    routes jsonb;
    prefix jsonb;
    update_steps jsonb;
    no_change_steps jsonb;
    decision_row public.lf_operation_execution_steps%rowtype;
    selected jsonb;
    outcome text;
    x text;
BEGIN
    SELECT * INTO e
      FROM public.lf_operation_execution
     WHERE execution_id = p_execution_id;
    IF NOT FOUND OR e.operation_code <> 'ACTUALIZACION_PERFIL_LF' THEN
        RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_UPDATE_EXECUTION_UNRESOLVED');
    END IF;
    frozen := e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}';
    IF frozen IS NULL THEN
        RETURN jsonb_build_object('outcome','LEGACY_NO_SNAPSHOT','effective_steps',null);
    END IF;
    IF jsonb_typeof(frozen) <> 'array' OR jsonb_array_length(frozen)=0
       OR EXISTS (
         SELECT 1 FROM jsonb_array_elements(frozen) a
          WHERE jsonb_typeof(a.value) <> 'string'
       )
       OR (SELECT count(*) FROM jsonb_array_elements_text(frozen))
           <> (SELECT count(DISTINCT value) FROM jsonb_array_elements_text(frozen) a(value))
       OR EXISTS (
         SELECT 1 FROM jsonb_array_elements_text(frozen) a(value)
          WHERE NULLIF(btrim(a.value),'') IS NULL
             OR NOT EXISTS (
                SELECT 1 FROM public.lf_operation_steps s
                 WHERE s.operation_code=e.operation_code AND s.step_id=a.value
                   AND s.required AND s.active
             )
       )
    THEN RETURN jsonb_build_object('outcome','BLOCKED','code','FROZEN_REQUIRED_STEPS_INVALID'); END IF;

    routes := e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps_by_outcome}';
    IF routes IS NULL THEN
        RETURN jsonb_build_object('outcome','LEGACY_FROZEN','effective_steps',frozen);
    END IF;
    prefix := e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps_before_decision}';
    update_steps := routes->'UPDATE';
    no_change_steps := routes->'NO_CHANGE';
    IF jsonb_typeof(routes) <> 'object'
       OR jsonb_typeof(prefix) <> 'array'
       OR jsonb_typeof(update_steps) <> 'array'
       OR jsonb_typeof(no_change_steps) <> 'array'
       OR update_steps <> frozen
       OR jsonb_array_length(prefix) <> 6
       OR jsonb_array_length(no_change_steps) < 6
       OR prefix <> (
            SELECT jsonb_agg(value ORDER BY ordinality)
              FROM jsonb_array_elements(update_steps) WITH ORDINALITY a(value,ordinality)
             WHERE ordinality <= 6
       )
       OR prefix <> (
            SELECT jsonb_agg(value ORDER BY ordinality)
              FROM jsonb_array_elements(no_change_steps) WITH ORDINALITY a(value,ordinality)
             WHERE ordinality <= 6
       )
       OR prefix->>4 <> 'method_selection'
       OR prefix->>5 <> 'evolution_decision'
       OR no_change_steps ? 'github_write'
       OR no_change_steps ? 'pre_write_execution_binding_gate'
       OR no_change_steps ? 'post_merge_reconcile'
       OR EXISTS (
         SELECT 1 FROM jsonb_array_elements_text(no_change_steps) b(value)
          WHERE NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements_text(frozen) f(value)
             WHERE f.value=b.value
          )
       )
    THEN
        RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID');
    END IF;

    SELECT * INTO decision_row
      FROM public.lf_operation_execution_steps
     WHERE execution_id=p_execution_id AND step_id='evolution_decision';
    IF NOT FOUND OR decision_row.status <> 'STEP_PASS_WITH_EVIDENCE' THEN
        RETURN jsonb_build_object('outcome','AWAITING_EVOLUTION_DECISION','effective_steps',prefix);
    END IF;
    IF decision_row.evidence_payload->>'recorded_by_rpc' <> 'lf_record_profile_operation_step_v1'
       OR decision_row.evidence_payload->>'mini_judge_result' <> 'STEP_PASS_WITH_EVIDENCE' THEN
        RETURN jsonb_build_object('outcome','BLOCKED','code','EVOLUTION_DECISION_UNVERIFIED_RECORDER');
    END IF;
    outcome := decision_row.evidence_payload->>'decision';
    IF outcome NOT IN ('UPDATE','NO_CHANGE') OR outcome IS NULL THEN
        RETURN jsonb_build_object('outcome','BLOCKED','code','EVOLUTION_DECISION_NOT_ADMITTED');
    END IF;
    selected := routes->outcome;
    RETURN jsonb_build_object('outcome',outcome,'effective_steps',selected);
END;
$route$;

-- NOTE: no GRANT here. Do not apply while caller and recorder use different
-- route functions, since that would violate invariant:
--    cursor.next_step == recorder.authorized_next_step.
-- Test under a Train ROLLBACK with cases:
-- legacy 15/15; UPDATE 17/17; NO_CHANGE 10/10 and zero write; pending 6/17;
-- malformed; stale/forged decision; historical 22 unmodified;
-- missing method qualification/assessment fail-closed.
