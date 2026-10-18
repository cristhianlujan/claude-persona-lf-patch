-- PE10 one coordinated run / 32 independent method checkpoints, same frozen P0.
-- Administrative registration only. No experiment runs, no agent activation, no runtime or production mutation.
-- Preserve existing PE10_C1..C7 checkpoints and existing work item separately.
DO $pe10$
DECLARE
 v_stream_id bigint;
 v_work_id bigint;
 v_methods integer;
 v_a integer;
 v_b integer;
 v_inserted integer;
BEGIN
 SELECT id INTO STRICT v_stream_id
 FROM programacion.engineering_workstreams
 WHERE stream_code='PROFILE_UPDATER_EVOLUTION_V1';

 SELECT count(*),count(*) FILTER (WHERE base_code='A'),count(*) FILTER (WHERE base_code='B')
 INTO v_methods,v_a,v_b
 FROM programacion.pe10_method_variants
 WHERE case_ref='PE10-IG-M107-M109-P0' AND status='DRAFT';
 IF (v_methods,v_a,v_b) IS DISTINCT FROM (32,16,16) THEN
   RAISE EXCEPTION 'PE10_METHOD_CATALOG_NOT_FROZEN count=% A=% B=%',v_methods,v_a,v_b;
 END IF;
 IF EXISTS(SELECT 1 FROM programacion.engineering_work_items WHERE work_code='PEVO-PE10-METHODS32-P0') THEN
   RAISE EXCEPTION 'PE10_32_CHECKPOINT_WORK_ALREADY_EXISTS';
 END IF;
 INSERT INTO programacion.engineering_work_items
   (work_code,workstream_id,title,objective,expected_result,work_type,priority,status,
    assignee_type,assignee_ref,target_repo,target_domain,target_component,source_ref,acceptance_criteria)
 VALUES
   ('PEVO-PE10-METHODS32-P0',v_stream_id,'One coordinated run / 32 PE10 method checkpoints',
    'Run the SAME frozen P0 on 32 separately isolated methods without findings or evaluator leakage',
    'Exactly 32 raw method reports, each with independent evidence; B methods have 5 isolated producer RAWs and one independent synthesis RAW; external evaluation follows only after all freezing',
    'QA','P1','BACKLOG','AGENT','PE10_ORCHESTRATOR_REQUIRED_NOT_BOUND',
    'cristhianlujan/claude-persona-lf-patch','LF_PE10','PE10-IG-M107-M109-P0',
    'supabase://programacion.pe10_method_variants/PE10-IG-M107-M109-P0',
    jsonb_build_array(
     'One coordinator run id for all 32 checkpoints; method researchers use isolated real sessions',
     'Each checkpoint maps one-to-one to a persisted method code; only that method algorithms apply',
     'For B: 5 isolated specialist RAW reports plus independent synthesizer RAW; no logical perspectives substituted for sessions',
     'Diagnostic producers use SELECT only and frozen original P0; neither prior findings nor evaluation rubric is disclosed',
     'A checkpoint can be completed only after raw result, provenance and executed-session evidence, not from catalog preparation',
     'No external evaluator scores are fed into producers; no number of SQL queries or investigation rounds is imposed',
     'If orchestrator isolation or governed evidence recording unavailable, keep checkpoint pending and report real blocker; do not claim run complete'
    )
   )
 RETURNING id INTO v_work_id;

 INSERT INTO programacion.engineering_work_checkpoints
 (work_item_id,checkpoint_code,title,sequence_no,weight,required,status)
 SELECT v_work_id, v.method_code,
        'Independent method test '||v.method_code||' ('||v.base_code||'; '||
          CASE WHEN coalesce(array_length(v.algorithm_codes,1),0)=0 THEN 'SRCR baseline' ELSE array_to_string(v.algorithm_codes,'+') END||')',
        substring(v.method_code from 7)::integer,
        1,true,'PENDING'
 FROM programacion.pe10_method_variants v
 WHERE v.case_ref='PE10-IG-M107-M109-P0' AND v.status='DRAFT'
 ORDER BY v.method_code;
 GET DIAGNOSTICS v_inserted=ROW_COUNT;
 IF v_inserted<>32 THEN RAISE EXCEPTION 'PE10_EXPECTED_32_CHECKPOINTS_GOT_%',v_inserted; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_work_id AND status='PENDING')<>32 THEN
   RAISE EXCEPTION 'PE10_UNEXPECTED_INITIAL_CHECKPOINT_STATUS';
 END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints c
      JOIN programacion.pe10_method_variants v ON v.method_code=c.checkpoint_code
      WHERE c.work_item_id=v_work_id)<>32 THEN
   RAISE EXCEPTION 'PE10_CHECKPOINT_METHOD_JOIN_MISMATCH';
 END IF;
 IF EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints c
       WHERE c.work_item_id=v_work_id AND (c.evidence_ref IS NOT NULL OR c.completed_at IS NOT NULL)) THEN
   RAISE EXCEPTION 'PE10_CHECKPOINT_FALSE_EXECUTION_RECEIPT';
 END IF;
END;
$pe10$;