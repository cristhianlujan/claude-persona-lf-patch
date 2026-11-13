-- B07 PADRE/HIJA CANDIDATO: fail-closed. NO EJECUTAR EN SUPABASE.
-- Con historia BASELINE o GOVERNED nunca tirar la HIJA. Exportar, verificar y
-- aprobar custodia de historia antes de plan de downgrade por otra vía.
BEGIN;
DO $check$
BEGIN
 IF to_regclass('lf_ops.reglas_versiones_b07') IS NULL OR
    to_regclass('saly.reglas_versiones_b07') IS NULL
 THEN RAISE EXCEPTION 'B07_DOWN_HISTORY_MISSING'; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas_versiones_b07) OR
    EXISTS(SELECT 1 FROM saly.reglas_versiones_b07)
 THEN RAISE EXCEPTION 'B07_DOWN_HISTORY_ROWS_PRESENT'; END IF;
END $check$;

DROP TRIGGER lf_b07_parent_match ON lf_ops.reglas;
DROP TRIGGER saly_b07_parent_match ON saly.reglas;
DROP TRIGGER lf_b07_child_match ON lf_ops.reglas_versiones_b07;
DROP TRIGGER saly_b07_child_match ON saly.reglas_versiones_b07;
DROP TRIGGER lf_b07_history_immutable ON lf_ops.reglas_versiones_b07;
DROP TRIGGER saly_b07_history_immutable ON saly.reglas_versiones_b07;
DROP TRIGGER lf_b07_history_no_truncate ON lf_ops.reglas_versiones_b07;
DROP TRIGGER saly_b07_history_no_truncate ON saly.reglas_versiones_b07;
DROP FUNCTION public.lf_b07_append_version_candidate_v1(
 text,text,text,text,text,text,timestamptz,text) RESTRICT;
DROP FUNCTION public.lf_b07_assert_parent_latest_v1() RESTRICT;
DROP FUNCTION public.lf_b07_block_history_mutation_v1() RESTRICT;
DROP FUNCTION public.lf_b07_block_history_truncate_v1() RESTRICT;
DROP TABLE lf_ops.reglas_versiones_b07 RESTRICT;
DROP TABLE saly.reglas_versiones_b07 RESTRICT;
COMMIT;
