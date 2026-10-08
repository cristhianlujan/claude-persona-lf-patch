-- M7.9 independently owned behavioral tests. Execute manually via Supabase SQL
-- in one BEGIN/ROLLBACK; never a global test suite dependency.
-- CASE 3 uses the actual source authority, freshwater delta, planner and Curator.
-- The canonical source is temporarily renamed within a single rollback-only transaction;
-- neither the terminal run nor the guards/validators are modified.
BEGIN;
SET LOCAL statement_timeout='180s';
SET LOCAL lock_timeout='3s';
CREATE TEMP TABLE m79_cases
 (case_code text primary key,outcome text NOT NULL,observed jsonb NOT NULL)
 ON COMMIT DROP;
DO $m79$
DECLARE
  parent_id bigint;screen_id integer;p jsonb;m jsonb;rid bigint;
  code text;v_count int;pending_count int;parent_of_new bigint;
  before_runs int;after_runs int;v_rows int;v_error_count int;
  d jsonb; blocked_plan jsonb;blocked_materialized jsonb;postrestore_plan jsonb;
  v_orig_code text;v_fixture_code text;
BEGIN
 SELECT id,pantalla_id INTO parent_id,screen_id
 FROM programacion.input_readiness_runs
 WHERE status='COMPLETED' AND invalidated_at IS NULL
   AND source_manifest @> '[{"ref":{"kind":"EKB_PREVENTION_SET"}}]'::jsonb
 ORDER BY id DESC LIMIT 1;
 IF parent_id IS NULL THEN RAISE EXCEPTION 'M79_NO_COMPLETED_FIXTURE';END IF;

 p:=programacion.fn_input_governance_curator_plan_v1(screen_id,true,parent_id);
 INSERT INTO m79_cases VALUES
 ('REBIND_ELIGIBLE',CASE WHEN p->>'strategy'='REBIND' AND (p->>'completed_run_id')::bigint=parent_id
 THEN 'PASS' ELSE 'FAIL' END,jsonb_build_object('plan',p,'parent',parent_id));

 p:=programacion.fn_input_governance_curator_plan_v1(screen_id,true,-1);
 INSERT INTO m79_cases VALUES
 ('REBIND_INELIGIBLE',CASE WHEN p->>'strategy'='BOOTSTRAP' AND p->>'reason'='NO_COMPLETED_RUN'
 THEN 'PASS' ELSE 'FAIL' END,jsonb_build_object('plan',p,'nonexistent_parent',-1));

 -- Integrated negative through the REAL source resolver; never tamper with a
 -- completed run or bypass the immutability guard. Source row restored before COPY.
 SELECT e.value->'ref'->'codes'->>0 INTO v_orig_code
 FROM programacion.input_readiness_runs r
 CROSS JOIN LATERAL jsonb_array_elements(r.source_manifest) e(value)
 WHERE r.id=parent_id
   AND e.value->'ref'->>'kind'='EKB_PREVENTION_SET'
   AND jsonb_array_length(e.value->'ref'->'codes')=1
 ORDER BY e.value->'ref'->'codes'->>0 LIMIT 1;
 IF v_orig_code IS NULL THEN RAISE EXCEPTION 'M79_ORIGIN_FIXTURE_NOT_FOUND'; END IF;
 v_fixture_code:='M79_ROLLBACK_ONLY_'||v_orig_code;
 IF EXISTS(SELECT 1 FROM transversal.prevention_rules WHERE regla_codigo=v_fixture_code)
 THEN RAISE EXCEPTION 'M79_TEST_SOURCE_NAMESPACE_OCCUPIED';END IF;
 p:=programacion.fn_input_governance_curator_plan_v1(screen_id,false,parent_id);
 IF p->>'strategy'<>'NOOP' OR (p->>'resolution_error_count')::int<>0
 THEN RAISE EXCEPTION 'M79_NEGATIVE_BASELINE_NOT_CURRENT:%',p;END IF;
 SELECT count(*) INTO before_runs FROM programacion.input_readiness_runs
 WHERE pantalla_id=screen_id;
 UPDATE transversal.prevention_rules SET regla_codigo=v_fixture_code
 WHERE regla_codigo=v_orig_code;
 GET DIAGNOSTICS v_rows=ROW_COUNT;
 IF v_rows<>1 THEN RAISE EXCEPTION 'M79_SOURCE_AUTHORITY_COUNT:%',v_rows;END IF;
 d:=programacion.fn_input_freshness_delta(parent_id);
 SELECT count(*) INTO v_error_count
 FROM jsonb_array_elements(coalesce(d->'source_changes','[]'::jsonb)) e(value)
 WHERE e.value->>'state'='RESOLUTION_ERROR'
   AND e.value->'ref'->>'kind'='EKB_PREVENTION_SET'
   AND e.value->'ref'->'codes' @> jsonb_build_array(v_orig_code);
 blocked_plan:=programacion.fn_input_governance_curator_plan_v1(screen_id,false,parent_id);
 blocked_materialized:=programacion.fn_input_governance_curator_materialize_v1(
  screen_id,'STORY_CREATOR',
  'INPUT_CURATOR:SQL:ig-governed-dispatch-v1:77777777-1111-4222-8333-999999999998',false);
 SELECT count(*) INTO after_runs FROM programacion.input_readiness_runs
 WHERE pantalla_id=screen_id;
 -- Restore the origin BEFORE testing REBIND in this same transaction.
 UPDATE transversal.prevention_rules SET regla_codigo=v_orig_code
 WHERE regla_codigo=v_fixture_code;
 GET DIAGNOSTICS v_rows=ROW_COUNT;
 IF v_rows<>1 THEN RAISE EXCEPTION 'M79_SOURCE_RESTORE_FAILED:%',v_rows;END IF;
 postrestore_plan:=programacion.fn_input_governance_curator_plan_v1(
 screen_id,false,parent_id);
 INSERT INTO m79_cases VALUES ('REBIND_RESOLUTION_ERROR_FAIL_CLOSED',
 CASE WHEN v_error_count=1 AND blocked_plan->>'strategy'='BLOCK'
 AND blocked_plan->>'reason'='SOURCE_RESOLUTION_ERROR'
 AND (blocked_plan->>'resolution_error_count')::int>=1
 AND blocked_materialized->>'status'='BLOCKED'
 AND blocked_materialized->>'strategy'='BLOCK'
 AND coalesce((blocked_materialized->>'write_performed')::boolean,true)=false
 AND after_runs=before_runs AND postrestore_plan->>'strategy'='NOOP'
 THEN 'PASS' ELSE 'FAIL' END,
 jsonb_build_object('origin',v_orig_code,'resolution_errors',v_error_count,
 'plan',blocked_plan->>'strategy','reason',blocked_plan->>'reason',
 'curator_status',blocked_materialized->>'status',
 'write_performed',blocked_materialized->>'write_performed',
 'runs_created',after_runs-before_runs,'restored_plan',postrestore_plan->>'strategy'));

 m:=programacion.fn_input_governance_curator_materialize_v1(
  screen_id,'STORY_CREATOR',
  'INPUT_CURATOR:SQL:ig-governed-dispatch-v1:77777777-1111-4222-8333-999999999999',
  true);
 rid:=(m->>'run_id')::bigint;
 SELECT count(*),count(*) FILTER(WHERE validator_outcome='PENDING')
 INTO v_count,pending_count
 FROM programacion.input_family_assessments WHERE run_id=rid;
 SELECT supersedes_run_id INTO parent_of_new FROM programacion.input_readiness_runs WHERE id=rid;
 INSERT INTO m79_cases VALUES ('REBIND_COPY_PENDING',
 CASE WHEN rid IS NOT NULL AND parent_of_new=parent_id
 AND v_count=47 AND pending_count=47 AND m->>'status'='VALIDATOR_RUNTIME_REQUIRED'
 THEN 'PASS' ELSE 'FAIL' END,
 jsonb_build_object('new_run_id',rid,'parent_run_id',parent_of_new,
 'families',v_count,'pending',pending_count,'curator_result',m->>'status'));
 IF (SELECT count(*) FROM m79_cases WHERE outcome='PASS')<>4
    OR (SELECT count(*) FROM m79_cases)<>4
 THEN RAISE EXCEPTION 'M79_FOUR_CASE_ASSERTION_FAILED';END IF;
END;$m79$;
SELECT case_code,outcome,observed FROM m79_cases ORDER BY case_code;
ROLLBACK;
