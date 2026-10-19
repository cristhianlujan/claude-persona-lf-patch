-- M10.7 B: one-screen observational AB/BA sampling only.
-- No changes to runtime, source-writers, permissions or validation gates.
DO $m$
DECLARE
 v_run_id bigint:=933;
 v_snap record;
 v_i integer; v_j integer; v_baseline_first boolean;
 v_t timestamptz; v_base_ms numeric; v_opt_ms numeric;
 v_base_g1 jsonb; v_opt jsonb; v_manifest jsonb;
 v_base_full boolean; v_wins integer:=0; v_data jsonb:='[]'::jsonb;
 v_base_sum numeric:=0;v_opt_sum numeric:=0;
BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN
   ('IG-M107-LOT-A-PROFILE-027','IG-M107-B-GRAPH-INVOKE-REUSE-029',
    'IG-M107-B-MANIFEST-ONEPASS-030'))<>3 THEN
   RAISE EXCEPTION 'IG_M107_B_MEASUREMENT_EKB_DEPENDENCY_MISSING';
 END IF;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M107-B-ONEPASS-TIMING-031') THEN
   RAISE EXCEPTION 'IG_M107_B_TIMING_DUPLICATE';
 END IF;
 SELECT id,status,source_manifest,source_snapshot_sha256 INTO v_snap
 FROM programacion.input_readiness_runs WHERE id=v_run_id;
 IF NOT FOUND OR v_snap.status<>'COMPLETED'
   OR jsonb_array_length(v_snap.source_manifest)<>7 THEN
   RAISE EXCEPTION 'IG_M107_B_BASELINE_RUN_NOT_REPRODUCIBLE';
 END IF;
 FOR v_i IN 1..4 LOOP
   v_baseline_first:=(v_i%2=1);
   FOR v_j IN 1..2 LOOP
     IF (v_j=1)=v_baseline_first THEN
       v_t:=clock_timestamp();
       v_base_g1:=programacion.fn_input_governance_continuation_currentness_v1(v_run_id);
       v_manifest:=programacion.fn_input_build_source_manifest(v_run_id);
       v_base_full:=v_manifest IS NOT DISTINCT FROM v_snap.source_manifest
         AND programacion.fn_v09_sha256_jsonb(v_manifest)
             IS NOT DISTINCT FROM v_snap.source_snapshot_sha256;
       v_base_ms:=round((extract(epoch from clock_timestamp()-v_t)*1000)::numeric,3);
     ELSE
       v_t:=clock_timestamp();
       v_opt:=programacion.fn_ig_m107_manifest_guard_bundle_v1(v_run_id);
       v_opt_ms:=round((extract(epoch from clock_timestamp()-v_t)*1000)::numeric,3);
     END IF;
   END LOOP;
   IF v_base_g1 IS DISTINCT FROM v_opt->'g1'
      OR v_base_full IS DISTINCT FROM (v_opt->>'full_manifest_current')::boolean THEN
     RAISE EXCEPTION 'IG_M107_B_EXACT_PARITY_DRIFT_ON_PAIR:%',v_i;
   END IF;
   IF v_opt_ms<v_base_ms THEN v_wins:=v_wins+1; END IF;
   v_base_sum:=v_base_sum+v_base_ms;v_opt_sum:=v_opt_sum+v_opt_ms;
   v_data:=v_data||jsonb_build_array(jsonb_build_object(
     'pair',v_i,'order',case when v_baseline_first then 'AB' else 'BA' end,
     'legacy_ms',v_base_ms,'onepass_ms',v_opt_ms,
     'exact_g1_jsonb',true,'exact_full_manifest_verdict',true));
 END LOOP;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,created_at,updated_at,
  lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
 VALUES (
  gen_random_uuid(),'IG-M107-B-ONEPASS-TIMING-031','GOVERNANCE',
  'M10.7 B: rendimiento focal del doble cotejo con una lectura del manifiesto',
  'Cuatro pares alternados AB/BA sobre el único run histórico 933: G1 legacy + lectura full versus helper onepass; igualdad de JSONB G1 y resultado full exigida.',
  'La ruta previa hace dos reconstrucciones del manifiesto dentro de controles consecutivos para la misma unidad.',
  'ONEPASS_TWO_VERDICTS_ABBA_TIMING',
  'Mantener ambas verificaciones y medir antes de modificar guards. No afirmar tiempo de Validator, ni actuales sources pinned, ni concurrencia global.',
  '4 pares AB/BA completos: paridad G1 + full en cada par. Reducir trabajo medido sólo si al menos 3/4 pares favorecen onepass; sin activacion automatica.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),
  'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7/LOT_B','ACTIVO',
  jsonb_build_object('schema_version','IG_M107_B_ONEPASS_TIMING_V1',
     'pairs',v_data,'pair_count',4,'onepass_faster_pairs',v_wins,
     'mean_legacy_ms',round(v_base_sum/4,3),
     'mean_onepass_ms',round(v_opt_sum/4,3),
     'gain_reproducible_in_sample',v_wins>=3,
     'historical_run_id',933,'real_runtime_benchmark',false,
     'concurrency_proven',false,'runtime_trigger_modified',false,
     'lot_B_closed',false,'cp3_closed',false)::text,
  clock_timestamp(),clock_timestamp(),'VALIDATION','R5_EROSION_PROCESO','LOUD_EARLY',
  'Four one-screen observations; no source mutation or product changes',
  'supabase://programacion.input_readiness_runs/933');
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo='IG-M107-B-ONEPASS-TIMING-031')<>1
 THEN RAISE EXCEPTION 'IG_M107_B_EKB_READBACK_FAILED'; END IF;
END $m$;
