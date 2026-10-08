-- M7.9 independently owned behavioral tests. Execute manually via Supabase SQL
-- in one BEGIN/ROLLBACK; never a global test suite dependency.
-- CASE 3 deliberately reports PARTIAL until a real RESOLUTION_ERROR plan fixture exists.
BEGIN;
SET LOCAL statement_timeout='180s';
CREATE TEMP TABLE m79_cases
 (case_code text primary key,outcome text NOT NULL,observed jsonb NOT NULL)
 ON COMMIT DROP;
DO $m79$
DECLARE
  parent_id bigint;screen_id integer;p jsonb;m jsonb;rid bigint;
  code text;v_count int;pending_count int;parent_of_new bigint;
  guard_present boolean;resolver_failed boolean:=false;
BEGIN
 SELECT id,pantalla_id INTO parent_id,screen_id
 FROM programacion.input_readiness_runs
 WHERE status='COMPLETED' AND invalidated_at IS NULL
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

 BEGIN
  PERFORM programacion.fn_input_resolve_source_ref(
   jsonb_build_object('kind','M79_UNSUPPORTED_SOURCE_NEGATIVE', 'pantalla_id',screen_id),
   screen_id,19);
 EXCEPTION WHEN OTHERS THEN
  resolver_failed:=SQLERRM LIKE 'UNSUPPORTED_SOURCE_REF_KIND:%';
 END;
 guard_present:=position('if v_resolution_errors>0 then' in
  pg_get_functiondef('programacion.fn_input_governance_curator_plan_v1(integer,boolean,bigint)'::regprocedure))>0;
 INSERT INTO m79_cases VALUES ('REBIND_RESOLUTION_ERROR_FAIL_CLOSED',
  CASE WHEN resolver_failed AND guard_present THEN 'PARTIAL_REQUIRES_REAL_PLAN_ERROR_FIXTURE' ELSE 'FAIL' END,
  jsonb_build_object('resolver_fails_closed',resolver_failed,
   'planner_blocks_resolution_error_branch',guard_present,
   'end_to_end_actual_source_error_proven',false));

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
END;$m79$;
SELECT case_code,outcome,observed FROM m79_cases ORDER BY case_code;
ROLLBACK;
