-- PE10 P0: repair artificial independent-session dependency; retain fixed case, 32 checkpoints, algorithms, roles.
-- Only metadata contracts. Does not execute methods, grant privileges, or activate an agent.
DO $pe10$
DECLARE x integer; work_id bigint;
BEGIN
 IF (SELECT count(*) FROM programacion.pe10_method_variants WHERE case_ref='PE10-IG-M107-M109-P0') <> 32 THEN
  RAISE EXCEPTION 'PE10_VARIANT_SET_NOT_32';
 END IF;
 SELECT id INTO STRICT work_id FROM programacion.engineering_work_items
 WHERE work_code='PEVO-PE10-METHODS32-P0' AND status IN ('BACKLOG','READY','IN_PROGRESS');
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=work_id AND status='PENDING') <> 32 THEN
  RAISE EXCEPTION 'PE10_CHECKPOINTS_ALREADY_STARTED_OR_INCOMPLETE';
 END IF;

 UPDATE programacion.pe10_method_modules
 SET definition=(
  definition-'must_not_simulate'
  || jsonb_build_object(
   'runtime','Five sequential role-bound specialist investigations within the SAME coordinated run, followed by one role-bound synthesis; no autonomous chat session required',
   'execution_mode','ONE_RUN_ROLE_CHECKPOINT',
   'truthfulness','Record every specialist role result as a distinct frozen artifact; describe as role-bound investigation unless actually executed by autonomous agent; do not fabricate independent sessions',
   'isolation','Provide same original P0 and method-specific algorithms in each role invocation. Previous checkpoint outputs are not inputs; only synthesizer reads five role outputs',
   'roles',jsonb_build_array('ARCHITECTURE','PERFORMANCE','AUTHORITY','COVERAGE','INNOVATION'),
   'synthesizer','SYNTHESIZER'))
 WHERE module_code='B' AND status='DRAFT';
 GET DIAGNOSTICS x=ROW_COUNT;
 IF x<>1 THEN RAISE EXCEPTION 'PE10_B_MODULE_NOT_UPDATED'; END IF;

 UPDATE programacion.pe10_method_variants
 SET execution_contract=execution_contract
  ||jsonb_build_object(
    'execution','One coordinated run; five specialized role-bound research passes, each freezes its original result, then one role-bound synthesizer receives only those five reports',
    'independence','Contract and input-bound per-checkpoint isolation; separate GPT sessions are NOT required. Do not claim independent agents when role passes ran in one model context',
    'producer_input',jsonb_build_array('original unchanged P0','assigned role contract','algorithms in this one method only'),
    'mode','READ_ONLY',
    'session_gate',false)
 WHERE base_code='B' AND case_ref='PE10-IG-M107-M109-P0' AND status='DRAFT';
 GET DIAGNOSTICS x=ROW_COUNT;
 IF x<>16 THEN RAISE EXCEPTION 'PE10_B_VARIANTS_NOT_16'; END IF;

 UPDATE programacion.pe10_method_roles
 SET role_contract=role_contract || jsonb_build_object(
   'isolation','Specialty defines which questions are prioritized, not an exclusive boundary. In shared coordinator context, use checkpoint-specific input and freeze role RAW before synthesizing; explicitly report any non-isolation risk',
   'runtime','Can run as role-bound research within one execution, without additional chat creation')
 WHERE role_code IN ('ARCHITECTURE','PERFORMANCE','AUTHORITY','COVERAGE','INNOVATION','SYNTHESIZER') AND status='DRAFT';
 GET DIAGNOSTICS x=ROW_COUNT;
 IF x<>6 THEN RAISE EXCEPTION 'PE10_SPECIALISTS_NOT_6'; END IF;

 UPDATE programacion.engineering_work_items
 SET assignee_ref='PE10_ONE_RUN_COORDINATOR',
     acceptance_criteria = jsonb_build_array(
      'One coordinator run for 32 method checkpoints; no separate GPT session creation requirement',
      'Each checkpoint uses frozen P0, only its recorded method definition and role contracts, own SELECT observations, RAW output and explicit evidence',
      'For B: 5 role-bound specialist RAW results plus one synthesized RAW, all in one coordinated execution; indicate true execution modality, no fake agents',
      'Checkpoint outputs frozen before subsequent method; previous findings never provided as next method inputs, evaluator receives all only after freeze',
      'No arbitrary SQL/query/round cap; no answers or evaluation hints shared with investigative roles',
      'Never mark DONE from catalog readiness; only recorded executed method, query evidence, and correct historical/current data separation',
      'If a method algorithm or tool cannot actually run, label that component UNVERIFIED without blocking unrelated methods',
      'No production mutation; method checkpoint execution and governed receipt transitions only'
     )
 WHERE id=work_id;
 GET DIAGNOSTICS x=ROW_COUNT;
 IF x<>1 THEN RAISE EXCEPTION 'PE10_WORK_NOT_UPDATED'; END IF;
END;
$pe10$;