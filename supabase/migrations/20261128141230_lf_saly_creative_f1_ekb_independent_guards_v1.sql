-- SALY F1: readback-governed learning from independent PG17/F3 host guards.
BEGIN;

UPDATE transversal.error_knowledge
SET frecuencia=coalesce(frecuencia,0)+1,
    evidencia=coalesce(evidencia,'') ||
      E'\n[INDEPENDENT_CASE_ROUTING_20261128] PR #4851 run 46153295756: F1 candidate absent; integrated T01-T15 job was SKIPPED while the independent job materially executed T09|PASS, T14|PASS and T15|PASS. This closes the false-green routing gap for those PR2-independent cases without claiming T01-T06/T10-T13.',
    validacion=coalesce(validacion,'') ||
      E'\n[VALIDACION_INDEPENDENT_CASE_ROUTING_20261128] Exact corrected head 5b2a1baad1bce0236fd2b41bb6e78e111e727bec: SALY Creative Order PG17 run 46153295756 SUCCESS; independent guards job SUCCESS; merge(train) PR #4851 = 2a9b163d01166452277ad2bbef978a70c0d37a77.',
    updated_at=clock_timestamp()
WHERE codigo='SALY-F1-CI-EMPTY-SUCCESS-20261128-001';

UPDATE transversal.error_knowledge
SET frecuencia=coalesce(frecuencia,0)+1,
    evidencia=coalesce(evidencia,'') ||
      E'\n[RECURRENCIA_SALY_PR4851_20261128] Initial head 7ed331da1a2c65243f69f977ef445446293f2d39 failed PASE run 46153194917 with FAIL_CHANGESET_FIXED_FAMILY_OVERRIDE because the workflow path was declared CI_WORKFLOW instead of fixed family WORKFLOW. Corrected head 5b2a1baad1bce0236fd2b41bb6e78e111e727bec used WORKFLOW; PASE run 46153295786 SUCCESS; merge(train) 2a9b163d01166452277ad2bbef978a70c0d37a77.',
    validacion=coalesce(validacion,'') ||
      E'\n[VALIDACION_RECURRENCIA_SALY_PR4851_20261128] Fixed-family registry remained authoritative; correction changed only manifest classification and exact-head PASE passed without weakening the guard.',
    updated_at=clock_timestamp()
WHERE codigo='GOV-CHANGESET-GOVERNANCE-LF-V1-001';

UPDATE transversal.error_knowledge
SET evidencia=coalesce(evidencia,'') ||
      E'\n[AUTH_EXEC01_READBACK_20261128] Read-only production: creative_native_render_wire_v1, creative_queue_admit_run_v1, creative_queue_claim_by_id_v1, creative_queue_native_reserve_dispatch_v1 and creative_queue_release_v1 are SECURITY DEFINER, owner postgres, proacl={postgres=X/postgres}, public_execute=false and current_user_execute=false. Recent logs exposed no native host/actor provenance. PR #4851 current-CI probe passed but explicitly kept native_runtime_attested=false and historical_status=NO_ACREDITADO_HISTORICAMENTE.',
    validacion=coalesce(validacion,'') ||
      E'\n[VALIDACION_AUTH_EXEC01_20261128] Run 46153295756 emitted AUTH-EXEC01-NEGATIVE|PASS, AUTH-EXEC01-POSITIVE-CI-ONLY|PASS and AUTH-EXEC01|NO_ACREDITADO_HISTORICAMENTE|CURRENT_CI_PROBE_OK. This is test-channel provenance only, not historical/native execution accreditation.',
    updated_at=clock_timestamp()
WHERE codigo='SALY-F1-AUTH-EXEC-PROVENANCE-20261128-001';

INSERT INTO transversal.best_practices(categoria,titulo,practica,evidencia)
SELECT
  'SALY_CREATIVE_F1',
  '[SALY-F1-BP-INDEPENDENT-CASE-ROUTING-20261128] Desacoplar casos independientes del gate de presencia del candidato',
  'Si una prueba fail-closed no depende del candidato bloqueado, ejecutarla en un job PG17 independiente. El gate de presencia del candidato puede controlar solo los casos que realmente lo requieren; NOT_RUN no equivale a PASS.',
  'PR #4851, exact head 5b2a1baad1bce0236fd2b41bb6e78e111e727bec, run 46153295756: candidato F1 ausente; integrated T01-T15 SKIPPED; T09/T14/T15 independientes PASS; HOST01/HOST02 PASS_HARNESS; merge 2a9b163d01166452277ad2bbef978a70c0d37a77.'
WHERE NOT EXISTS (
  SELECT 1 FROM transversal.best_practices
  WHERE titulo='[SALY-F1-BP-INDEPENDENT-CASE-ROUTING-20261128] Desacoplar casos independientes del gate de presencia del candidato'
);

DO $qa$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM transversal.error_knowledge
    WHERE codigo='SALY-F1-CI-EMPTY-SUCCESS-20261128-001'
      AND coalesce(evidencia,'') LIKE '%[INDEPENDENT_CASE_ROUTING_20261128]%'
      AND coalesce(validacion,'') LIKE '%[VALIDACION_INDEPENDENT_CASE_ROUTING_20261128]%'
  ) THEN RAISE EXCEPTION 'SALY_F1_EKB_INDEPENDENT_ROUTING_READBACK_MISSING'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM transversal.error_knowledge
    WHERE codigo='GOV-CHANGESET-GOVERNANCE-LF-V1-001'
      AND coalesce(evidencia,'') LIKE '%[RECURRENCIA_SALY_PR4851_20261128]%'
  ) THEN RAISE EXCEPTION 'SALY_F1_EKB_CHANGESET_RECURRENCE_READBACK_MISSING'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM transversal.error_knowledge
    WHERE codigo='SALY-F1-AUTH-EXEC-PROVENANCE-20261128-001'
      AND coalesce(evidencia,'') LIKE '%[AUTH_EXEC01_READBACK_20261128]%'
      AND coalesce(validacion,'') LIKE '%[VALIDACION_AUTH_EXEC01_20261128]%'
  ) THEN RAISE EXCEPTION 'SALY_F1_EKB_AUTH_EXEC_READBACK_MISSING'; END IF;

  IF (SELECT count(*) FROM transversal.best_practices
      WHERE titulo='[SALY-F1-BP-INDEPENDENT-CASE-ROUTING-20261128] Desacoplar casos independientes del gate de presencia del candidato')<>1
  THEN RAISE EXCEPTION 'SALY_F1_BP_INDEPENDENT_ROUTING_READBACK_INVALID'; END IF;

  RAISE NOTICE 'SALY_F1_EKB_INDEPENDENT_GUARDS_READBACK|PASS';
END
$qa$;

COMMIT;
