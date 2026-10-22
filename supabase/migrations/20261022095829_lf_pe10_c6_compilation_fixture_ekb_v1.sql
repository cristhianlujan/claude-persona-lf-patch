-- LF PE10_C6: two distinct EKB learnings, only via ACTUALIZACION_DB_LF Merge Train.
-- Does not close C6/C7, change v0.1, or enable step 35/37.
BEGIN;
DO $preflight$
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN ('PE10_C6_SQL_SCRIPT_PREFLIGHT_NO_PARSE_V1','PE10_C6_SYNTHETIC_BLOCK_TRIGGERS_PRE_EKB_V1'))
    OR (SELECT count(*) FROM public.lf_eventos
        WHERE entidad_codigo='PE10_C6.RECORDER_ROUTE_GUARD_ROLLBACK_PROBE.V1')<>1
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=1103 AND checkpoint_code IN ('PE10_C6','PE10_C7') AND status='PENDING')<>2
 THEN RAISE EXCEPTION 'PE10_C6_EKB_PRESTATE_CHANGED'; END IF;
END $preflight$;
CREATE TEMP TABLE pe10_c6_ekb_staging ON COMMIT DROP AS
SELECT * FROM jsonb_to_recordset($ekb$[{"categoria":"PROFILE_EVOLUTION","severidad":"MEDIUM","frecuencia":2,"lote_origen":"PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C6","pr":3080,"estado":"ACTIVO","source_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3080","lifecycle_phase":"construction","root_cause_family":"R2_NO_VE","codigo":"PE10_C6_SQL_SCRIPT_PREFLIGHT_NO_PARSE_V1","titulo":"SQL compuesto sin prueba de parser antes del Train","descripcion":"Runs 39756770752 y 39757185853 abortaron: faltaba semicolon después de pg_get_functiondef y había una expresión CASE problemática en IF del ensayo.","causa_raiz":"Se concatenó definición SQL válida individualmente sin validar compilación de archivo completo de migración PostgreSQL.","patron":"SQL_ARTIFACT_FINAL_UNPARSED_BEFORE_TRAIN","prevencion":"Cerrar cada CREATE FUNCTION con punto y coma, inspeccionar límites del SQL generado y compilar el archivo final en PostgreSQL local/aislado antes del Train.","validacion":"Run 39758572318 PASS; merge a73e7b74b4cfaabee1711bcd133a314330b8f251; evento 21476 rollback PASS; C6 sigue PENDING.","detectability":"LOUD_EARLY","source_context":"PE10_C6_PR3080_SQL_COMPOSITION_20261022"},{"categoria":"PROFILE_EVOLUTION","severidad":"MEDIUM","frecuencia":2,"lote_origen":"PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C6","pr":3080,"estado":"ACTIVO","source_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3080","lifecycle_phase":"construction","root_cause_family":"R2_NO_VE","codigo":"PE10_C6_SYNTHETIC_BLOCK_TRIGGERS_PRE_EKB_V1","titulo":"Fixtures de mini-jueces sin staging completo e interferencia con PRE_EKB","descripcion":"Runs 39757543491/39758231961 fallaron antes del apply: bloqueos sintéticos del recorder dispararon autopersistencia EKB y la prueba positiva omitió habilitar jueces candidatos junto a bindings.","causa_raiz":"Fixture del proceso de evolución no contempló toda la autoridad de los mini-jueces ni efectos de errores durables fuera del escenario simulado.","patron":"FIXTURE_JUDGE_STATUS_AND_SYNTHETIC_EKB_EFFECT_MISMATCH","prevencion":"Activar temporalmente pasos, contratos, bindings y mini-jueces en una sola subtransacción. Comprobar negativos puros con el guard STABLE; no generar fallos operativos ficticios ni deshabilitar EKB.","validacion":"PR 3080 merged, evento 21476 guard/recorder/rollback true, rutas UPDATE y NO_CHANGE; todas las etapas candidatas retornaron inactivas tras rollback.","detectability":"PROCESS_DEPENDENT","source_context":"PE10_C6_PR3080_FIXTURE_20261022"}]$ekb$::jsonb)
  AS r(
    codigo text,
    categoria text,
    titulo text,
    descripcion text,
    causa_raiz text,
    patron text,
    prevencion text,
    validacion text,
    severidad text,
    frecuencia integer,
    lote_origen text,
    pr integer,
    estado text,
    source_ref text,
    lifecycle_phase text,
    root_cause_family text,
    detectability text,
    source_context text
  );
DO $staging$
BEGIN
 IF (SELECT count(*) FROM pg_temp.pe10_c6_ekb_staging)<>2
 THEN RAISE EXCEPTION 'PE10_C6_EKB_STAGING_COUNT_WRONG'; END IF;
END $staging$;
SAVEPOINT pe10_c6_ekb_rehearsal;
INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,lote_origen,pr,estado,source_ref,lifecycle_phase,root_cause_family,detectability,source_context)
SELECT codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,lote_origen,pr,estado,source_ref,lifecycle_phase,root_cause_family,detectability,source_context FROM pg_temp.pe10_c6_ekb_staging;
DO $positive$
BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN ('PE10_C6_SQL_SCRIPT_PREFLIGHT_NO_PARSE_V1','PE10_C6_SYNTHETIC_BLOCK_TRIGGERS_PRE_EKB_V1'))<>2
 THEN RAISE EXCEPTION 'PE10_C6_EKB_POSITIVE_TEST_FAIL'; END IF;
END $positive$;
ROLLBACK TO SAVEPOINT pe10_c6_ekb_rehearsal;
RELEASE SAVEPOINT pe10_c6_ekb_rehearsal;
DO $negative$
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN ('PE10_C6_SQL_SCRIPT_PREFLIGHT_NO_PARSE_V1','PE10_C6_SYNTHETIC_BLOCK_TRIGGERS_PRE_EKB_V1'))
 THEN RAISE EXCEPTION 'PE10_C6_EKB_ROLLBACK_LEAK'; END IF;
END $negative$;
INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,lote_origen,pr,estado,source_ref,lifecycle_phase,root_cause_family,detectability,source_context)
SELECT codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,lote_origen,pr,estado,source_ref,lifecycle_phase,root_cause_family,detectability,source_context FROM pg_temp.pe10_c6_ekb_staging;
DO $readback$
BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge
     WHERE codigo IN ('PE10_C6_SQL_SCRIPT_PREFLIGHT_NO_PARSE_V1','PE10_C6_SYNTHETIC_BLOCK_TRIGGERS_PRE_EKB_V1') AND estado='ACTIVO'
       AND categoria='PROFILE_EVOLUTION'
       AND lote_origen='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C6')<>2
   OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=1103 AND checkpoint_code IN ('PE10_C6','PE10_C7')
         AND status='PENDING')<>2
 THEN RAISE EXCEPTION 'PE10_C6_EKB_READBACK_FAIL'; END IF;
END $readback$;
COMMIT;
