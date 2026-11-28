-- SALY F3-A PR4857: governed production readback and execution learnings.
-- EKB only. No SALY runtime changes, grants, runs, claims or order mutations.
BEGIN;

UPDATE transversal.error_knowledge
SET frecuencia=coalesce(frecuencia,0)+1,
    evidencia=coalesce(evidencia,'') ||
      E'\n[PR4857_F3A_REAL_FIXTURE_20261128] PR #4857 replicated production order 23/item 27 into isolated PG17 as order 9323/item 9327 without claim_token or personal data. Context set 6 was represented by 109 exact LF tokens; snapshot SHA256=f4bc5bf450bdfb220191305c134121c266cbd4ff14d8a69910085e4b211914aa; full-token manifest SHA256=6b5f5eea5fe000441a7b774e5e02ec19709da6dd2603e8d6feebb88afc6c22fd. The real semantic interpretation had the historical five-key governed shape and was not exercised by the earlier synthetic 9300/9301 fixture.',
    validacion=coalesce(validacion,'') ||
      E'\n[VALIDACION_PR4857_F3A_REAL_FIXTURE_20261128] Exact HEAD 2da42f028e096c1dc3a67deb2e7a4a89023c092a: compiler executed twice on the real-data fixture; both prompts were 118792 bytes with SHA256=6aafc4d49c04e5a62107a1846ad4a1a1f8b5fe26c9770b6b052d699b5dd53850. Independent controls F3A-01..10 passed; one-byte, amount and term mutants failed their target controls. Production migration 20261128173000; order 23 remained EN_PROCESO, item 27 PRODUCIENDO, creative run count for order 23 remained 0.',
    ultima_vez=clock_timestamp(),
    updated_at=clock_timestamp()
WHERE codigo='SALY-F1-FIXTURE-COVERAGE-20261128-001';

INSERT INTO transversal.error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,lote_origen,pr,estado,evidencia,
  root_cause_family,detectability,source_context,source_ref
)
VALUES(
  'SOURCE-JS-STRING-REPLACE-DOLLAR-SQL-20261128-001',
  'SOURCE_CONTROL_TOOLING',
  'String.replace de JavaScript puede corromper SQL cuando el reemplazo contiene secuencias dollar',
  'Durante F3-A una transformación textual de la migración usó String.replace(old,replacementString). El SQL de reemplazo contenía el final de regex dollar seguido de comilla; JavaScript interpretó esa secuencia como sustitución especial y produjo una migración truncada/duplicada. PASE/A4 falló antes del merge.',
  'Semántica de replacement string de JavaScript aplicada a SQL con caracteres dollar; faltó readback estructural antes de escribir el primer parche.',
  'Transformación programática de SQL con replacement strings no literales que contienen dollar, backreferences u otros tokens especiales.',
  'Para transformar SQL desde JavaScript usar callback de reemplazo, por ejemplo replace(old,()=>replacement), o construcción AST. Antes de escribir exigir invariantes estructurales: una función esperada, pares de dollar-tags, un COMMIT y anclas críticas únicas. Hacer readback exacto del archivo antes de confiar en CI.',
  'En PR #4857 la migración se reconstruyó desde el HEAD limpio 9f2c8f7f52a2c0ea1ed2afe5354d797f66f4b6dd usando callback de reemplazo. Invariantes: compiler=1, function tags=2, qa tags=2, COMMIT=1, semantic interpretation=1, context call=1. HEAD final 2da42f028e096c1dc3a67deb2e7a4a89023c092a pasó PASE y PG17; PR merge 83041a330071ea051f3ed47abd80bca1117f206d.',
  'HIGH',1,'SALY_F3A_PR4857','#4857','activo',
  'PASE inicial: A4 ValueError unterminated SQL dollar string; PG17 reportó trailing junk after numeric literal. Corrección validada por CI exact-head y producción.',
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'F3-A source transformation during governed PR preparation',
  'github://cristhianlujan/claude-persona-lf-patch/pull/4857'
)
ON CONFLICT (codigo) DO UPDATE
SET frecuencia=coalesce(transversal.error_knowledge.frecuencia,0)+1,
    evidencia=coalesce(transversal.error_knowledge.evidencia,'') ||
      E'\n[RECURRENCIA_PR4857_20261128] Validated correction on exact HEAD 2da42f028e096c1dc3a67deb2e7a4a89023c092a.',
    validacion=EXCLUDED.validacion,
    ultima_vez=clock_timestamp(),
    updated_at=clock_timestamp();

INSERT INTO transversal.best_practices(categoria,titulo,practica,evidencia)
SELECT
  'SALY_CREATIVE_F3A',
  '[SALY-F3A-BP-REAL-BYTES-DETERMINISM-20261128] Acreditar compiladores con contexto real, bytes independientes y mutantes dirigidos',
  'Para un compilador determinista, replicar en PG aislado el contexto real representativo sin secretos ni datos personales; ejecutar el compilador al menos dos veces; comparar longitud y SHA256 de los bytes; reconstruir los bytes esperados desde tablas/contratos por una ruta independiente que no consuma los PASS declarados por el compilador; y matar mutantes dirigidos de byte y campos semánticos críticos. Un harness sintético o el QA auto-reportado por el propio compilador no acredita el pedido real.',
  'PR #4857 HEAD 2da42f028e096c1dc3a67deb2e7a4a89023c092a: 109 tokens reales, prompt run1/run2 118792 bytes, SHA256 6aafc4d49c04e5a62107a1846ad4a1a1f8b5fe26c9770b6b052d699b5dd53850; inputs SHA256 29eeee96d65c60d689e7c57689d7380bf370449cf2bf7bdd8e8fdea679f9ce6d; F3A-01..10 independientes PASS; byte/amount/term FAIL_EXPECTED; merge Train 83041a330071ea051f3ed47abd80bca1117f206d.'
WHERE NOT EXISTS (
  SELECT 1 FROM transversal.best_practices
  WHERE titulo='[SALY-F3A-BP-REAL-BYTES-DETERMINISM-20261128] Acreditar compiladores con contexto real, bytes independientes y mutantes dirigidos'
);

DO $qa$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM transversal.error_knowledge
    WHERE codigo='SALY-F1-FIXTURE-COVERAGE-20261128-001'
      AND coalesce(evidencia,'') LIKE '%[PR4857_F3A_REAL_FIXTURE_20261128]%'
      AND coalesce(validacion,'') LIKE '%[VALIDACION_PR4857_F3A_REAL_FIXTURE_20261128]%'
  ) THEN RAISE EXCEPTION 'PR4857_REAL_FIXTURE_EKB_READBACK_MISSING'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM transversal.error_knowledge
    WHERE codigo='SOURCE-JS-STRING-REPLACE-DOLLAR-SQL-20261128-001'
      AND coalesce(evidencia,'') <> ''
      AND pr='#4857'
  ) THEN RAISE EXCEPTION 'PR4857_JS_REPLACE_EKB_MISSING'; END IF;

  IF (SELECT count(*) FROM transversal.best_practices
      WHERE titulo='[SALY-F3A-BP-REAL-BYTES-DETERMINISM-20261128] Acreditar compiladores con contexto real, bytes independientes y mutantes dirigidos')<>1
  THEN RAISE EXCEPTION 'PR4857_F3A_BP_INVALID'; END IF;

  RAISE NOTICE 'SALY_F3A_PR4857_EKB_READBACK|PASS';
END
$qa$;

COMMIT;
