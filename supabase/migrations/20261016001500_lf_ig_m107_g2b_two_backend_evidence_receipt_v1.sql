-- IG M10.7: exact evidence of G2B two PostgreSQL backend fixture run.
-- Evidence only: does not change runtime, validators, triggers, guards, source rules, or CP3.
DO $receipt$
DECLARE
 v_code constant text:='IG-M107-G2B-TWO-BACKEND-EXECUTED-021';
 v_triggers integer;
 v_evidence jsonb;
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN
   RAISE EXCEPTION 'IG_G2B_EVIDENCE_ALREADY_EXISTS';
 END IF;
 IF (SELECT count(*) FROM programacion.input_g2b_source_fixture_v1)<>0
 THEN RAISE EXCEPTION 'IG_G2B_FIXTURE_NOT_CLEAN'; END IF;
 SELECT count(*) INTO v_triggers
 FROM pg_trigger t JOIN pg_class c ON t.tgrelid=c.oid
 JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE NOT t.tgisinternal AND t.tgenabled IN ('O','A')
 AND n.nspname='programacion'
 AND c.relname IN ('input_family_assessments','input_gap_proposals','input_readiness_runs');
 IF v_triggers<>21 THEN RAISE EXCEPTION 'IG_G2B_TRIGGER_UNIVERSE_DRIFT'; END IF;
 IF md5(pg_get_functiondef('programacion.fn_input_g2b_fixture_commit_gate_v1(uuid,bigint,integer,text,bigint,text)'::regprocedure))
 <> '4499f9baaf98786b8a6146596da6ff3e'
 OR md5(pg_get_functiondef('programacion.fn_input_governance_run_context_packet_v1(bigint)'::regprocedure))
 <> 'c0d4e5e8515e79343358fa1d490d0ca6'
 THEN RAISE EXCEPTION 'IG_G2B_PROVENANCE_DRIFT'; END IF;
 v_evidence:=jsonb_build_object(
  'schema_version','IG_M107_G2B_TWO_SESSION_EVIDENCE_V1',
  'github_run_id',38827928190,
  'github_job_id',116739743662,
  'github_pr',2801,
  'github_request_head','8280c47112d70d580407ede6f192d4fcc48ab3d3',
  'trusted_runner_pr',2800,
  'trusted_runner_main_merge','bcca1949bf5c10a37df5ebedd0648939238c3108',
  'postgres_backend_pids',jsonb_build_array(654445,654447),
  'isolation','READ COMMITTED',
  'fixture_test_result','PASS_FIXTURE_ONLY',
  'checks_total',12,
  'checks_passed',12,
  'two_real_sessions',true,
  'committed_concurrent_write',true,
  'stale_source_rejected',true,
  'cross_run_rejected',true,
  'contract_tamper_rejected',true,
  'source_hash_tamper_rejected',true,
  'writer_blocked_until_final_commit',true,
  'elapsed_ms',1098,
  'stale_negatives_ms',130,
  'fixture_residual_rows',0,
  'canonical_triggers',v_triggers,
  'production_rules_changed',false,
  'all_real_source_writers_covered',false,
  'g2b_global_pass',false,
  'g3_activation_allowed',false,
  'cp3_closed',false,
  'evidence_url','https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/38827928190'
 );
 INSERT INTO public.lf_error_knowledge
 (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
 frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,created_at,updated_at,
 lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
 VALUES(
 gen_random_uuid(),v_code,'GOVERNANCE',
 'M10.7 G2B dos sesiones reales: commit fuente y fence final del fixture',
 'Prueba material protegida: 12 comprobaciones en dos backends PostgreSQL (654445,654447), sesión B commit fuente, sesión A rechazo stale, bloqueo writer hasta commit y 0 residuos. Evidencia acotada solo a fixture.',
 'Se carecía de Operation admitida de dos sesiones sobre el fixture; se reutilizó transporte confiable existente bajo modo fijo sin SQL/credenciales en el PR solicitante.',
 'G2B_TWO_SESSION_COMMIT_AND_FINAL_LOCK_FIXTURE',
 'No declarar G2B global ni activar consumidores hasta comprobar cobertura transaccional de todos los writers de fuentes reales, paridades y rendimiento CP3; conservar currentness actual.',
 'PASS_FIXTURE_ONLY: run 38827928190, job 116739743662, 12/12, READ COMMITTED, write commit, TOCTOU lock, readback 0 filas, 21 triggers. NO equivale a G2B global PASS.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','#2800/#2801','ACTIVO',
 v_evidence::text,clock_timestamp(),clock_timestamp(),'VALIDATION',
 'R4_NO_CUESTIONA','LOUD_EARLY',
 'Fixture-only protected two-session proof; not product authority',
 'https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/38827928190'
 );
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
 THEN RAISE EXCEPTION 'IG_G2B_EKB_READBACK_FAILED'; END IF;
END $receipt$;
