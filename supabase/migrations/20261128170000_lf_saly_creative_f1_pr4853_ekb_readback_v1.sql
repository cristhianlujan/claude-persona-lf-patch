-- SALY F1 PR2: governed learning and production readback closure after PR #4853.
BEGIN;

UPDATE transversal.error_knowledge
SET frecuencia=coalesce(frecuencia,0)+2,
    evidencia=coalesce(evidencia,'') ||
      E'\n[SALY_F1_PR4853_SCHEMA_FIRST_RECURRENCE_20261128] Two read-only SQLSTATE 42703 recurrences were contained before dependent DML while building the PG17 static baseline: (1) saly.proyecto.descripcion was assumed but the live table exposes significado_nombre/fase/estado/objetivo; (2) a pg_catalog query reused information_schema aliases table_name/ordinal_position instead of c.relname/a.attnum. Both statements aborted read-only, catalog introspection corrected the query, and execution continued without business writes derived from the failed reads.',
    validacion=coalesce(validacion,'') ||
      E'\n[VALIDACION_SALY_F1_PR4853_SCHEMA_FIRST_20261128] PR #4853 final Train-assigned head bba6764d52d846f20e8f21321d8f43fe815697a0 passed exact-head PG17 T01-T15, PASE, classify, migration-source-parity and Merge Train; production migration 20261128165350 has source SHA256 35e42f8deb2808e6129e5a6d767d63512d0ac3566d8760f0741feeb3385bf8b4.',
    ultima_vez=clock_timestamp(),
    updated_at=clock_timestamp()
WHERE codigo='DB-001';

UPDATE transversal.error_knowledge
SET frecuencia=coalesce(frecuencia,0)+1,
    evidencia=coalesce(evidencia,'') ||
      E'\n[SALY_F1_PR4853_CURRENTNESS_20261128] Exact head 1f020f61269443ef679f01d8d795a6a118507e6f had functional T01-T15 PASS but migration-source-parity failed only because main advanced from 35974989306e62c728cd4176871a3854c575ab1d to 74f84ee3e0dbaa54ba0925d8862465857d0ec661. After governed main integration, head 0a1f516bcd33b722fff5fa87d09bb978f6e170ae passed the required independent migration-source-parity check. The Train later retimestamped source-only to 20261128165350 on bba6764d52d846f20e8f21321d8f43fe815697a0; source blob 5f65e0077563747d45cc61707937f71f2e38f61d and SHA256 remained unchanged.',
    validacion=coalesce(validacion,'') ||
      E'\n[VALIDACION_SALY_F1_PR4853_CURRENTNESS_20261128] Final Train-assigned head bba6764d52d846f20e8f21321d8f43fe815697a0: migration-source-parity SUCCESS, pase-merge-gate SUCCESS, PASE SUCCESS and lf-migration-merge-train SUCCESS; PR #4853 merged as 0b6b35e91cbe1dcfd9e195534d298110e86fb821.',
    ultima_vez=clock_timestamp(),
    updated_at=clock_timestamp()
WHERE codigo='SALY-F1-CI-SHADOW-CHECK-20261128-001';

UPDATE transversal.error_knowledge
SET frecuencia=coalesce(frecuencia,0)+1,
    evidencia=coalesce(evidencia,'') ||
      E'\n[F1_MATRIX_MATERIAL_CLOSURE_PR4853_20261128] The final Train-assigned head bba6764d52d846f20e8f21321d8f43fe815697a0 executed the integrated PG17 matrix materially: T01 through T15 each emitted exactly one PASS and F1_MATRIX_15_15_PASS, with zero NOT_PROVEN/SKIPPED in matrix output.',
    validacion=coalesce(validacion,'') ||
      E'\n[VALIDACION_F1_MATRIX_MATERIAL_CLOSURE_PR4853_20261128] SALY Creative Order PG17 run 46167590992 / job 141048505530 SUCCESS. Independent guards + F3 host harness job 141048467455 SUCCESS; pg17-disposable job 141048467695 SUCCESS.',
    ultima_vez=clock_timestamp(),
    updated_at=clock_timestamp()
WHERE codigo='SALY-F1-CI-EMPTY-SUCCESS-20261128-001';

UPDATE transversal.best_practices
SET evidencia=coalesce(evidencia,'') ||
  E'\n[PR4853_PRODUCTION_READBACK_20261128] Production migration 20261128165350: creative_lf_prompt_seal_v1 exists with RLS=true/FORCE=true and row_count=0; prompt seal row and truncate guards are active; PUBLIC/anon/authenticated/service_role have zero effective privileges on the seal table and new LF helper functions.'
WHERE titulo='[SALY-F1-BP-IMMUTABLE-SEAL-20261128] Sello de prompt inmutable y acceso mínimo';

UPDATE transversal.best_practices
SET evidencia=coalesce(evidencia,'') ||
  E'\n[PR4853_FINAL_FIXTURE_20261128] Static PG17 baseline reconstructed live tables/constraints/FKs/indexes/triggers/ACL with files under 60 KB, minimal LF order 25 and SALY control fixtures, no claim_token or personal data. Final Train-assigned head bba6764d52d846f20e8f21321d8f43fe815697a0 passed T01-T15 plus independent HOST01/HOST02/AUTH-EXEC01 harness.'
WHERE titulo='[SALY-F1-BP-REAL-FIXTURE-20261128] Probar contra datos reales representativos antes de aprobar';

INSERT INTO transversal.best_practices(categoria,titulo,practica,evidencia)
SELECT
 'SALY_CREATIVE_F1',
 '[SALY-F1-BP-STATIC-BASELINE-RESTORE-20261128] Restaurar baseline por dependencias reales, no por orden nominal',
 'Para un sustrato PostgreSQL estático derivado de producción: introspectar catálogo; crear tablas antes de constraints; restaurar PK/UNIQUE e índices UNIQUE que sean claves referenciadas antes de FKs; no excluir un índice sólo porque aparezca como conindid de un FK; usar check_function_bodies=off únicamente durante la carga de funciones con referencias cruzadas y ejecutar después casos reales con validación normal; sembrar padres antes de hijos y respetar triggers de lifecycle (por ejemplo DRAFT -> evidencia/tokens -> SEALED y scope_json.literal_request antes del intake).',
 'PR #4853: el restore detectó y corrigió en CI dependencias reales de lf_decisiones_gov, creative_task_selection_v2, creative_execution_policy_v1, contexts SEALED y creative intake. Final head bba6764d52d846f20e8f21321d8f43fe815697a0: F1_BASELINE_MD5_7_7_PASS y F1_MATRIX_15_15_PASS; merge 0b6b35e91cbe1dcfd9e195534d298110e86fb821.'
WHERE NOT EXISTS (
 SELECT 1 FROM transversal.best_practices
 WHERE titulo='[SALY-F1-BP-STATIC-BASELINE-RESTORE-20261128] Restaurar baseline por dependencias reales, no por orden nominal'
);

DO $qa$
BEGIN
 IF NOT EXISTS (
   SELECT 1 FROM transversal.error_knowledge
   WHERE codigo='DB-001'
     AND coalesce(evidencia,'') LIKE '%[SALY_F1_PR4853_SCHEMA_FIRST_RECURRENCE_20261128]%'
 ) THEN RAISE EXCEPTION 'SALY_F1_PR4853_DB001_READBACK_MISSING'; END IF;

 IF NOT EXISTS (
   SELECT 1 FROM transversal.error_knowledge
   WHERE codigo='SALY-F1-CI-SHADOW-CHECK-20261128-001'
     AND coalesce(evidencia,'') LIKE '%[SALY_F1_PR4853_CURRENTNESS_20261128]%'
 ) THEN RAISE EXCEPTION 'SALY_F1_PR4853_CURRENTNESS_READBACK_MISSING'; END IF;

 IF NOT EXISTS (
   SELECT 1 FROM transversal.error_knowledge
   WHERE codigo='SALY-F1-CI-EMPTY-SUCCESS-20261128-001'
     AND coalesce(evidencia,'') LIKE '%[F1_MATRIX_MATERIAL_CLOSURE_PR4853_20261128]%'
 ) THEN RAISE EXCEPTION 'SALY_F1_PR4853_MATRIX_READBACK_MISSING'; END IF;

 IF (SELECT count(*) FROM transversal.best_practices
     WHERE titulo='[SALY-F1-BP-STATIC-BASELINE-RESTORE-20261128] Restaurar baseline por dependencias reales, no por orden nominal')<>1
 THEN RAISE EXCEPTION 'SALY_F1_PR4853_STATIC_BASELINE_BP_INVALID'; END IF;

 IF NOT EXISTS (
   SELECT 1 FROM transversal.best_practices
   WHERE titulo='[SALY-F1-BP-IMMUTABLE-SEAL-20261128] Sello de prompt inmutable y acceso mínimo'
     AND coalesce(evidencia,'') LIKE '%[PR4853_PRODUCTION_READBACK_20261128]%'
 ) THEN RAISE EXCEPTION 'SALY_F1_PR4853_SEAL_BP_READBACK_MISSING'; END IF;

 RAISE NOTICE 'SALY_F1_PR4853_EKB_READBACK|PASS';
END
$qa$;

COMMIT;
