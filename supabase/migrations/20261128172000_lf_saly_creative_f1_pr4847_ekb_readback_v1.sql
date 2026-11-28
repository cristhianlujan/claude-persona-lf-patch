-- SALY F1 PR3: governed production readback + Train recovery learning.
BEGIN;

UPDATE transversal.error_knowledge
SET frecuencia=coalesce(frecuencia,0)+1,
    evidencia=coalesce(evidencia,'') ||
      E'\n[PR4847_PRODUCTION_SEMANTIC_QA_20261128] PR #4847 merged as 9107e5129080bc8c9f9d9bf7fc65d8d2b1f79d54 after migration 20261128170449. Read-only production: order 23 remained EN_PROCESO; item 27 TU_OFERTA remained PRODUCIENDO; acceptance_json minus semantic_qa retained SHA256 428435754a4ba4128d10eeadad6eb29632e054e2618d7b1cd911271cd906532c. semantic_qa schema=LF_SEMANTIC_QA_L3C_V1, original_request_sha256=78160d6438c2908d469e9ece838b0a14b57eb317b1215cfb702e507e7bbb1f40, require_artifact_evidence=true, require_independent_interpretation=true, original_messages=2 and checks=5.',
    validacion=coalesce(validacion,'') ||
      E'\n[VALIDACION_PR4847_PRODUCTION_20261128] Checks persisted exactly: LF_SEM_OFFER_INTENT, LF_SEM_AMOUNT_MEANING, LF_SEM_TRANSFER_MEANING, LF_SEM_LETTER_CONDITION, LF_SEM_SCOPE_AND_ACTION. Ledger name=lf_saly_creative_lf_item27_semantic_qa_v1 version=20261128170449.',
    ultima_vez=clock_timestamp(),
    updated_at=clock_timestamp()
WHERE codigo='SALY-F1-SEMANTIC-HASH-DOMAIN-20261128-001';

UPDATE transversal.error_knowledge
SET frecuencia=coalesce(frecuencia,0)+1,
    evidencia=coalesce(evidencia,'') ||
      E'\n[PR4847_RETSTAMP_TEST_PATH_20261128] Merge Train retimestamped the governed migration from 20261128130000 to 20261128170449. Exact-head pg17-disposable then failed PR3_BLOCK_FILES_MISSING because saly_creative_item27_semantic_qa_v1_pg17.sh hardcoded the old versioned filename. The test was repaired to glob *_lf_saly_creative_lf_item27_semantic_qa_v1.sql and require exactly one match; corrected HEAD 35c3f9c9c9815d457f93525ac04c660c45ffa581 passed the exact semantic QA rollback and pg17-disposable.',
    validacion=coalesce(validacion,'') ||
      E'\n[VALIDACION_PR4847_RETSTAMP_20261128] Corrected HEAD 35c3f9c9c9815d457f93525ac04c660c45ffa581: pg17-disposable SUCCESS, F1 integrated T01-T15 SUCCESS, independent HOST01/HOST02/AUTH-EXEC01 harness SUCCESS, PASE/classify/migration-source-parity SUCCESS.',
    ultima_vez=clock_timestamp(),
    updated_at=clock_timestamp()
WHERE codigo='TRAIN-MIGRATION-TEST-PATH-BRITTLE-015';

INSERT INTO transversal.best_practices(categoria,titulo,practica,evidencia)
SELECT
 'SALY_CREATIVE_F1',
 '[SALY-F1-BP-TRAIN-POSTAPPLY-RESUME-20261128] Si HEAD se mueve después de apply, revalidar y reanudar sin re-aplicar',
 'Si el Merge Train ya aplicó y leyó el ledger pero el exact-head cambia antes del merge, el merge debe fallar por HEAD moved. Corregir únicamente el source/test necesario, exigir CI exact-head verde y re-entregar al Train. La siguiente corrida debe reconocer la versión ya aplicada, omitir un segundo apply, ejecutar parity contra la fuente corregida y hacer merge exact-head. Nunca duplicar ni revertir manualmente la migración sólo para reconciliar Git.',
 'PR #4847: run 46168494765 aplicó 20261128170449 y luego merge exact-head falló con FAIL_TRAIN_PREMERGE_HEAD_MOVED al cambiar a HEAD 35c3f9c9c9815d457f93525ac04c660c45ffa581. Run 46168755125 reanudó: Persist source=SKIPPED, Apply exact version=SKIPPED, changeset parity=SUCCESS y merge exact head=SUCCESS. PR merged como 9107e5129080bc8c9f9d9bf7fc65d8d2b1f79d54.'
WHERE NOT EXISTS (
  SELECT 1 FROM transversal.best_practices
  WHERE titulo='[SALY-F1-BP-TRAIN-POSTAPPLY-RESUME-20261128] Si HEAD se mueve después de apply, revalidar y reanudar sin re-aplicar'
);

DO $qa$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM transversal.error_knowledge
    WHERE codigo='SALY-F1-SEMANTIC-HASH-DOMAIN-20261128-001'
      AND coalesce(evidencia,'') LIKE '%[PR4847_PRODUCTION_SEMANTIC_QA_20261128]%'
  ) THEN RAISE EXCEPTION 'PR4847_SEMANTIC_EKB_READBACK_MISSING'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM transversal.error_knowledge
    WHERE codigo='TRAIN-MIGRATION-TEST-PATH-BRITTLE-015'
      AND coalesce(evidencia,'') LIKE '%[PR4847_RETSTAMP_TEST_PATH_20261128]%'
  ) THEN RAISE EXCEPTION 'PR4847_RETSTAMP_EKB_READBACK_MISSING'; END IF;

  IF (SELECT count(*) FROM transversal.best_practices
      WHERE titulo='[SALY-F1-BP-TRAIN-POSTAPPLY-RESUME-20261128] Si HEAD se mueve después de apply, revalidar y reanudar sin re-aplicar')<>1
  THEN RAISE EXCEPTION 'PR4847_TRAIN_RESUME_BP_INVALID'; END IF;

  RAISE NOTICE 'SALY_F1_PR4847_EKB_READBACK|PASS';
END
$qa$;

COMMIT;
