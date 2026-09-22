-- S30-R15 rollback-only regression for ACTUALIZACION_ESTRATEGIA_LF physical pre-write enforcement.
-- No direct writes to Strategy/execution-step stores, no disabled controls, no persistent residue.
BEGIN;

DO $r15$
DECLARE
  s public.lf_strategy_snapshots%rowtype;
  st record;
  b public.lf_operation_step_judge_bindings%rowtype;
  j public.lf_operation_judges%rowtype;
  r jsonb;
  evidence jsonb;
  assertions jsonb;
  trust jsonb;
  patch jsonb;
  expected_sha text;
  observed_sha text;
  msg text;
  blocked boolean;
  evidence_before integer;
  evidence_after integer;
  log_before integer;
  log_after integer;
  exec_init text := 'EXEC-S30-R15-REG-INIT-ONLY';
  exec_reorder text := 'EXEC-S30-R15-REG-REORDER';
  exec_retry text := 'EXEC-S30-R15-REG-NONCLEAN-RETRY';
BEGIN
  SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=35;
  IF NOT FOUND THEN RAISE EXCEPTION 'R15_REGRESSION_SNAPSHOT_35_MISSING'; END IF;

  IF strpos(
       pg_get_functiondef('public.lf_strategy_update_write_v1(text,bigint,text,jsonb)'::regprocedure),
       'LF_STRATEGY_UPDATE_REQUIRED_PREWRITE_SEQUENCE_NOT_CLEAN'
     )=0 THEN
    RAISE EXCEPTION 'R15_REGRESSION_GUARD_NOT_LIVE';
  END IF;

  patch:=jsonb_build_object(
    'progress',s.metadata->'progress',
    'metadata_merge','{}'::jsonb,
    'backlog',s.backlog,
    'evidence_refs_append',jsonb_build_array('S30-R15-ROLLBACK-REGRESSION'),
    'change_log_append',jsonb_build_array(jsonb_build_object('test','S30-R15-ROLLBACK-REGRESSION'))
  );

  -- Case 1: init_execution only -> writer must fail closed with zero snapshot mutation.
  PERFORM public.lf_strategy_update_begin_v1(
    exec_init,35,
    encode(extensions.digest(convert_to('S30-R15 init-only regression','UTF8'),'sha256'),'hex'),
    'S30:R15:REG:INIT-ONLY',exec_init,
    jsonb_build_object('scope','S30_R15_ROLLBACK_REGRESSION','persistent_effect',false)
  );
  SELECT encode(extensions.digest(to_jsonb(z)::text,'sha256'),'hex') INTO expected_sha
  FROM public.lf_strategy_snapshots z WHERE z.id=35;
  blocked:=false;
  BEGIN
    PERFORM public.lf_strategy_update_write_v1(exec_init,35,expected_sha,patch);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
    IF msg LIKE 'LF_STRATEGY_UPDATE_REQUIRED_PREWRITE_SEQUENCE_NOT_CLEAN:%' THEN blocked:=true; ELSE RAISE; END IF;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'R15_REGRESSION_INIT_ONLY_FALSE_PASS'; END IF;
  SELECT encode(extensions.digest(to_jsonb(z)::text,'sha256'),'hex') INTO observed_sha
  FROM public.lf_strategy_snapshots z WHERE z.id=35;
  IF observed_sha IS DISTINCT FROM expected_sha THEN RAISE EXCEPTION 'R15_REGRESSION_INIT_ONLY_MUTATED_SNAPSHOT'; END IF;

  -- Case 2: try to record a later middle step before router/strategy_resolve.
  PERFORM public.lf_strategy_update_begin_v1(
    exec_reorder,35,
    encode(extensions.digest(convert_to('S30-R15 reordered-step regression','UTF8'),'sha256'),'hex'),
    'S30:R15:REG:REORDER',exec_reorder,
    jsonb_build_object('scope','S30_R15_ROLLBACK_REGRESSION','persistent_effect',false)
  );
  SELECT * INTO st FROM public.lf_operation_steps
   WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND step_id='baseline_read' AND active=true;
  SELECT * INTO b FROM public.lf_operation_step_judge_bindings
   WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND step_id='baseline_read' AND step_order=st.step_order AND status='ACTIVE_ENFORCEMENT';
  SELECT * INTO j FROM public.lf_operation_judges
   WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND judge_code=b.judge_code AND status='ACTIVE_ENFORCEMENT';
  SELECT coalesce(jsonb_object_agg(k,to_jsonb('R15_REGRESSION'::text)),'{}'::jsonb)
    INTO evidence FROM jsonb_array_elements_text(b.required_evidence_keys) k;
  IF jsonb_typeof(j.pass_if)='array' THEN assertions:=j.pass_if;
  ELSIF jsonb_typeof(j.pass_if)='object' AND jsonb_typeof(j.pass_if->'pass_if')='array' THEN assertions:=j.pass_if->'pass_if';
  ELSE SELECT coalesce(jsonb_agg(key order by key),'[]'::jsonb) INTO assertions FROM jsonb_each(j.pass_if) WHERE value='true'::jsonb; END IF;
  trust:=jsonb_build_object('valid',true,'server_assertions',assertions,'server_hard_fails','[]'::jsonb,'code','R15_REGRESSION_SERVER_VALIDATED');
  r:=public.lf_record_operation_step_core_v1(
    exec_reorder,'baseline_read','regression://s30/r15/reordered',evidence,exec_reorder,
    'ACTUALIZACION_ESTRATEGIA_LF','STRATEGY','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',trust,false,'r15_required_prewrite_sequence_regression'
  );
  IF r->>'outcome'<>'BLOCKED' OR r->>'code'<>'PRIOR_REQUIRED_STEP_NOT_CLEAN' THEN
    RAISE EXCEPTION 'R15_REGRESSION_REORDER_NOT_BLOCKED:%',r;
  END IF;
  SELECT encode(extensions.digest(to_jsonb(z)::text,'sha256'),'hex') INTO expected_sha FROM public.lf_strategy_snapshots z WHERE z.id=35;
  blocked:=false;
  BEGIN
    PERFORM public.lf_strategy_update_write_v1(exec_reorder,35,expected_sha,patch);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
    IF msg LIKE 'LF_STRATEGY_UPDATE_REQUIRED_PREWRITE_SEQUENCE_NOT_CLEAN:%' THEN blocked:=true; ELSE RAISE; END IF;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'R15_REGRESSION_REORDER_FALSE_PASS'; END IF;
  SELECT encode(extensions.digest(to_jsonb(z)::text,'sha256'),'hex') INTO observed_sha FROM public.lf_strategy_snapshots z WHERE z.id=35;
  IF observed_sha IS DISTINCT FROM expected_sha THEN RAISE EXCEPTION 'R15_REGRESSION_REORDER_MUTATED_SNAPSHOT'; END IF;

  -- Case 3: non-clean router -> writer blocks; retry router clean + ordered remaining chain -> exactly one bounded write.
  PERFORM public.lf_strategy_update_begin_v1(
    exec_retry,35,
    encode(extensions.digest(convert_to('S30-R15 nonclean retry regression','UTF8'),'sha256'),'hex'),
    'S30:R15:REG:NONCLEAN-RETRY',exec_retry,
    jsonb_build_object('scope','S30_R15_ROLLBACK_REGRESSION','persistent_effect',false)
  );
  SELECT * INTO st FROM public.lf_operation_steps
   WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND step_id='router' AND active=true;
  SELECT * INTO b FROM public.lf_operation_step_judge_bindings
   WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND step_id='router' AND step_order=st.step_order AND status='ACTIVE_ENFORCEMENT';
  SELECT coalesce(jsonb_object_agg(k,to_jsonb('R15_REGRESSION'::text)),'{}'::jsonb)
    INTO evidence FROM jsonb_array_elements_text(b.required_evidence_keys) k;
  r:=public.lf_record_operation_step_core_v1(
    exec_retry,'router','regression://s30/r15/router-nonclean',evidence,exec_retry,
    'ACTUALIZACION_ESTRATEGIA_LF','STRATEGY','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    jsonb_build_object('valid',false,'code','R15_REGRESSION_FORCED_NONCLEAN','details',jsonb_build_object('case','nonclean')),
    false,'r15_required_prewrite_sequence_regression'
  );
  IF r->>'outcome'<>'BLOCKED' THEN RAISE EXCEPTION 'R15_REGRESSION_NONCLEAN_NOT_PERSISTED_BLOCKED:%',r; END IF;
  SELECT encode(extensions.digest(to_jsonb(z)::text,'sha256'),'hex') INTO expected_sha FROM public.lf_strategy_snapshots z WHERE z.id=35;
  blocked:=false;
  BEGIN
    PERFORM public.lf_strategy_update_write_v1(exec_retry,35,expected_sha,patch);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
    IF msg LIKE 'LF_STRATEGY_UPDATE_REQUIRED_PREWRITE_SEQUENCE_NOT_CLEAN:%' THEN blocked:=true; ELSE RAISE; END IF;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'R15_REGRESSION_NONCLEAN_FALSE_PASS'; END IF;
  SELECT encode(extensions.digest(to_jsonb(z)::text,'sha256'),'hex') INTO observed_sha FROM public.lf_strategy_snapshots z WHERE z.id=35;
  IF observed_sha IS DISTINCT FROM expected_sha THEN RAISE EXCEPTION 'R15_REGRESSION_NONCLEAN_MUTATED_SNAPSHOT'; END IF;

  -- Retry router clean, then all remaining required pre-write steps in canonical order.
  FOR st IN
    SELECT s.step_id,s.step_order,s.execution_order
    FROM public.lf_operation_steps s
    WHERE s.operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND s.active=true AND s.required=true
      AND coalesce(s.execution_order,s.step_order) BETWEEN 10 AND 60
    ORDER BY coalesce(s.execution_order,s.step_order),s.step_order
  LOOP
    SELECT * INTO b FROM public.lf_operation_step_judge_bindings
     WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND step_id=st.step_id AND step_order=st.step_order AND status='ACTIVE_ENFORCEMENT';
    SELECT * INTO j FROM public.lf_operation_judges
     WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND judge_code=b.judge_code AND status='ACTIVE_ENFORCEMENT';
    SELECT coalesce(jsonb_object_agg(k,to_jsonb('R15_REGRESSION'::text)),'{}'::jsonb)
      INTO evidence FROM jsonb_array_elements_text(b.required_evidence_keys) k;
    IF jsonb_typeof(j.pass_if)='array' THEN assertions:=j.pass_if;
    ELSIF jsonb_typeof(j.pass_if)='object' AND jsonb_typeof(j.pass_if->'pass_if')='array' THEN assertions:=j.pass_if->'pass_if';
    ELSE SELECT coalesce(jsonb_agg(key order by key),'[]'::jsonb) INTO assertions FROM jsonb_each(j.pass_if) WHERE value='true'::jsonb; END IF;
    trust:=jsonb_build_object('valid',true,'server_assertions',assertions,'server_hard_fails','[]'::jsonb,'code','R15_REGRESSION_SERVER_VALIDATED');
    r:=public.lf_record_operation_step_core_v1(
      exec_retry,st.step_id,'regression://s30/r15/'||st.step_id,evidence,exec_retry,
      'ACTUALIZACION_ESTRATEGIA_LF','STRATEGY','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',trust,false,'r15_required_prewrite_sequence_regression'
    );
    IF r->>'outcome'<>'STEP_RECORDED' THEN RAISE EXCEPTION 'R15_REGRESSION_CLEAN_CHAIN_STEP_FAILED:%:%',st.step_id,r; END IF;
  END LOOP;

  SELECT encode(extensions.digest(to_jsonb(z)::text,'sha256'),'hex'),
         jsonb_array_length(coalesce(z.evidence_refs,'[]'::jsonb)),
         jsonb_array_length(coalesce(z.change_log,'[]'::jsonb))
    INTO expected_sha,evidence_before,log_before
  FROM public.lf_strategy_snapshots z WHERE z.id=35;

  r:=public.lf_strategy_update_write_v1(exec_retry,35,expected_sha,patch);
  IF r->>'result'<>'STRATEGY_UPDATED_WITH_EVIDENCE' THEN RAISE EXCEPTION 'R15_REGRESSION_CLEAN_WRITE_FAILED:%',r; END IF;
  SELECT jsonb_array_length(coalesce(z.evidence_refs,'[]'::jsonb)),
         jsonb_array_length(coalesce(z.change_log,'[]'::jsonb))
    INTO evidence_after,log_after
  FROM public.lf_strategy_snapshots z WHERE z.id=35;
  IF evidence_after<>evidence_before+1 OR log_after<>log_before+1 THEN
    RAISE EXCEPTION 'R15_REGRESSION_CLEAN_WRITE_NOT_EXACTLY_ONE:%:%:%:%',evidence_before,evidence_after,log_before,log_after;
  END IF;

  RAISE NOTICE 'S30_R15_REQUIRED_PREWRITE_SEQUENCE_REGRESSION=PASS init_only=BLOCKED reorder=BLOCKED nonclean=BLOCKED clean_chain=ONE_BOUNDED_WRITE persistent_effect=false';
END
$r15$;

ROLLBACK;
