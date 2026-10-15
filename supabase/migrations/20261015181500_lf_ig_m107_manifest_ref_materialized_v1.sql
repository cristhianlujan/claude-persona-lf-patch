-- IG M10.7 A5: qualify once-only resolution of unique manifest refs.
-- Only source function may change; candidate is removed within same transaction.
-- No reuse between SQL calls, statements, transactions or sessions; independent currentness unchanged.
DO $a5$
DECLARE
 v_code constant text:='IG-M107-A5-MANIFEST-REFS-MATERIALIZED-018';
 v_fn constant text:='programacion.fn_input_build_source_manifest_safe_v1';
 v_candidate_fn constant text:='programacion.fn_input_build_source_manifest_safe_v1_a5_candidate';
 v_original text; v_candidate text; v_promoted text;
 v_old jsonb;v_new jsonb;v_old_error text;v_new_error text;
 v_screen bigint; v_trial integer;
 v_start timestamptz;v_old_ms numeric;v_new_ms numeric;
 v_better integer:=0; v_samples jsonb:='[]'::jsonb;
 v_acl text;v_before_triggers int;v_after_triggers int;
 v_evidence jsonb;
BEGIN
 v_original:=pg_get_functiondef('programacion.fn_input_build_source_manifest_safe_v1(bigint)'::regprocedure);
 IF md5(v_original)<>'cbe9282a0fe72628cc3e0b707973fd02'
 THEN RAISE EXCEPTION 'IG_M107_A5_MANIFEST_SOURCE_DRIFT'; END IF;
 IF to_regprocedure('programacion.fn_input_build_source_manifest_safe_v1_a5_candidate(bigint)') IS NOT NULL
    OR EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
 THEN RAISE EXCEPTION 'IG_M107_A5_ALREADY_EXISTS'; END IF;
 SELECT p.proacl::text INTO v_acl FROM pg_proc p
 WHERE p.oid='programacion.fn_input_build_source_manifest_safe_v1(bigint)'::regprocedure;
 SELECT count(*) INTO v_before_triggers FROM pg_trigger t
 JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE NOT t.tgisinternal AND t.tgenabled IN ('O','A') AND n.nspname='programacion'
 AND c.relname IN ('input_family_assessments','input_gap_proposals','input_readiness_runs');
 IF v_before_triggers<>21 THEN RAISE EXCEPTION 'IG_M107_A5_TRIGGER_TOPOLOGY_DRIFT'; END IF;
 -- Only three source-scoped, semantic-preserving CTE fences; no global cache.
 v_candidate:=replace(v_original,
    'FUNCTION programacion.fn_input_build_source_manifest_safe_v1(',
    'FUNCTION programacion.fn_input_build_source_manifest_safe_v1_a5_candidate(');
 v_candidate:=replace(v_candidate,'with refs as (','with refs as MATERIALIZED (');
 v_candidate:=replace(v_candidate,'full_receipts as (','full_receipts as MATERIALIZED (');
 v_candidate:=replace(v_candidate,'resolved as (','resolved as MATERIALIZED (');
 IF v_candidate=v_original
    OR (length(v_candidate)-length(replace(v_candidate,'MATERIALIZED (',''))) / length('MATERIALIZED (')<>3
    OR position('FUNCTION programacion.fn_input_build_source_manifest_safe_v1_a5_candidate(' IN v_candidate)=0
 THEN RAISE EXCEPTION 'IG_M107_A5_EXPECTED_PATCH_STRUCTURE_DRIFT'; END IF;
 EXECUTE v_candidate||';';
 EXECUTE 'REVOKE ALL ON FUNCTION programacion.fn_input_build_source_manifest_safe_v1_a5_candidate(bigint) FROM PUBLIC';
 -- Matching exact JSON and digest for representative runs without source mutation.
 FOREACH v_screen IN ARRAY ARRAY[931::bigint,933::bigint] LOOP
   v_old:=programacion.fn_input_build_source_manifest_safe_v1(v_screen);
   v_new:=programacion.fn_input_build_source_manifest_safe_v1_a5_candidate(v_screen);
   IF v_old IS DISTINCT FROM v_new OR
     programacion.fn_v09_sha256_jsonb(v_old) IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_new)
   THEN RAISE EXCEPTION 'IG_M107_A5_PARITY_FAIL_RUN_%',v_screen; END IF;
 END LOOP;
 v_old_error:=NULL;v_new_error:=NULL;v_old:=NULL;v_new:=NULL;
 BEGIN
   v_old:=programacion.fn_input_build_source_manifest_safe_v1(2147483647);
 EXCEPTION WHEN OTHERS THEN v_old_error:=SQLSTATE||':'||SQLERRM; END;
 BEGIN
   v_new:=programacion.fn_input_build_source_manifest_safe_v1_a5_candidate(2147483647);
 EXCEPTION WHEN OTHERS THEN v_new_error:=SQLSTATE||':'||SQLERRM; END;
 IF v_old_error IS NULL OR v_new_error IS DISTINCT FROM v_old_error
    OR v_new IS DISTINCT FROM v_old
 THEN RAISE EXCEPTION 'IG_M107_A5_NEGATIVE_RUN_NOT_FAIL_CLOSED'; END IF;
 -- Warm both paths; interleaved AB/BA on the same run, not an unpaired cold-start claim.
 PERFORM programacion.fn_input_build_source_manifest_safe_v1(933);
 PERFORM programacion.fn_input_build_source_manifest_safe_v1_a5_candidate(933);
 FOR v_trial IN 1..4 LOOP
   IF mod(v_trial,2)=1 THEN
     v_start:=clock_timestamp();
     v_old:=programacion.fn_input_build_source_manifest_safe_v1(933);
     v_old_ms:=round((extract(epoch from(clock_timestamp()-v_start))*1000)::numeric,3);
     v_start:=clock_timestamp();
     v_new:=programacion.fn_input_build_source_manifest_safe_v1_a5_candidate(933);
     v_new_ms:=round((extract(epoch from(clock_timestamp()-v_start))*1000)::numeric,3);
   ELSE
     v_start:=clock_timestamp();
     v_new:=programacion.fn_input_build_source_manifest_safe_v1_a5_candidate(933);
     v_new_ms:=round((extract(epoch from(clock_timestamp()-v_start))*1000)::numeric,3);
     v_start:=clock_timestamp();
     v_old:=programacion.fn_input_build_source_manifest_safe_v1(933);
     v_old_ms:=round((extract(epoch from(clock_timestamp()-v_start))*1000)::numeric,3);
   END IF;
   IF v_old IS DISTINCT FROM v_new OR
       programacion.fn_v09_sha256_jsonb(v_old) IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_new)
   THEN RAISE EXCEPTION 'IG_M107_A5_BENCH_PARITY_CHANGED_%',v_trial; END IF;
   IF v_new_ms < v_old_ms THEN v_better:=v_better+1; END IF;
   v_samples:=v_samples||jsonb_build_array(jsonb_build_object(
     'trial',v_trial,'old_ms',v_old_ms,'candidate_ms',v_new_ms,
     'candidate_faster',v_new_ms<v_old_ms));
 END LOOP;
 -- Performance is a genuine admission condition, not assumed from MATERIALIZED syntax.
 IF v_better<3 THEN RAISE EXCEPTION
   'IG_M107_A5_NO_REPRODUCIBLE_PERFORMANCE_GAIN: % of 4',v_better; END IF;
 v_promoted:=replace(v_candidate,
   'FUNCTION programacion.fn_input_build_source_manifest_safe_v1_a5_candidate(',
   'FUNCTION programacion.fn_input_build_source_manifest_safe_v1(');
 EXECUTE v_promoted||';';
 IF pg_get_functiondef('programacion.fn_input_build_source_manifest_safe_v1(bigint)'::regprocedure)
    IS DISTINCT FROM v_promoted
    OR (SELECT proacl::text FROM pg_proc
        WHERE oid='programacion.fn_input_build_source_manifest_safe_v1(bigint)'::regprocedure)
        IS DISTINCT FROM v_acl
 THEN RAISE EXCEPTION 'IG_M107_A5_POST_PROMOTION_MISMATCH'; END IF;
 -- Ensure former and new results identical after actual canonical replacement.
 FOREACH v_screen IN ARRAY ARRAY[931::bigint,933::bigint] LOOP
   v_old:=programacion.fn_input_build_source_manifest_safe_v1(v_screen);
   v_new:=programacion.fn_input_build_source_manifest_safe_v1_a5_candidate(v_screen);
   IF v_old IS DISTINCT FROM v_new OR
     programacion.fn_v09_sha256_jsonb(v_old) IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_new)
   THEN RAISE EXCEPTION 'IG_M107_A5_POST_PROMOTION_PARITY_%',v_screen; END IF;
 END LOOP;
 EXECUTE 'DROP FUNCTION programacion.fn_input_build_source_manifest_safe_v1_a5_candidate(bigint)';
 SELECT count(*) INTO v_after_triggers FROM pg_trigger t
 JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE NOT t.tgisinternal AND t.tgenabled IN ('O','A') AND n.nspname='programacion'
 AND c.relname IN ('input_family_assessments','input_gap_proposals','input_readiness_runs');
 IF v_after_triggers<>v_before_triggers THEN
   RAISE EXCEPTION 'IG_M107_A5_TRIGGER_COUNT_REGRESSION'; END IF;
 v_evidence:=jsonb_build_object('schema','IG_M107_A5_MANIFEST_CTE_SINGLE_RESOLUTION_V1',
   'old_md5','cbe9282a0fe72628cc3e0b707973fd02',
   'new_md5',md5(v_promoted),'sample_runs',jsonb_build_array(931,933),
   'sample_size',4,'candidate_faster_count',v_better,'timings',v_samples,
   'old_and_new_exact_json_sha',true,'missing_run_negative_pass',true,
   'trigger_count_unchanged',v_after_triggers,'grants_unchanged',true,
   'new_cache_between_calls',false,'g2b_completed',false,
   'validator_p90_proven',false,'cp3_closed',false);
 INSERT INTO public.lf_error_knowledge
 (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
  validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
  estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
  detectability,source_context,source_ref)
 VALUES (gen_random_uuid(),v_code,'GOVERNANCE',
   'A5 materializar una sola vez referencias de manifiesto dentro de cada invocación',
   'CTE referenciales MATERIALIZED, datos fuente re-leídos en cada invocación, paridad JSON/SHA, negativo inexistente y benchmark AB/BA; todos los triggers conservados.',
   'El SQL del manifiesto no forzaba materialización explícita de las siete referencias únicas.',
   'INPUT_MANIFEST_LOCAL_SINGLE_RESOLUTION',
   'No usar cache entre statements o sesiones hasta aprobar G2B. Mantener currentness fail-closed, recibos independientes y 150s.',
   'Migration Train exige 3 de 4 ensayos favorables, misma fuente y digest, ACL íntegra y negativo.',
   'HIGH',1,clock_timestamp(),clock_timestamp(),'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',
   v_evidence::text,clock_timestamp(),clock_timestamp(),'PREFLIGHT',
   'R4_NO_CUESTIONA','LOUD_EARLY','Manifest materialization with safe bounded benchmark',
   'programacion.fn_input_build_source_manifest_safe_v1(bigint)');
END $a5$;
