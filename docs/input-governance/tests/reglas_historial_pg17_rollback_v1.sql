\set ON_ERROR_STOP on
-- La migracion se ejecuta ANTES del BEGIN, en Postgres 17 aislado.
-- Todas las alteraciones de reglas de prueba están en BEGIN/ROLLBACK real.
BEGIN;
DO $proof$
DECLARE v_n integer; v_actual integer; v_txt text; v_failed boolean;
BEGIN
  IF (SELECT count(*) FROM lf_ops.reglas_versiones) <> 3 THEN
    RAISE EXCEPTION 'BACKFILL_COUNT_INCORRECT';
  END IF;
  IF (SELECT count(*) FROM lf_ops.v_reglas_historial WHERE es_actual) <> 3 THEN
    RAISE EXCEPTION 'INITIAL_VIEW_COUNT_INCORRECT';
  END IF;
  IF (SELECT count(*) FROM lf_ops.v_reglas_historial) <> 3 THEN
    RAISE EXCEPTION 'INITIAL_VIEW_DUPLICATED';
  END IF;

  UPDATE lf_ops.reglas SET titulo='Cambio 1' WHERE codigo='TEST-VIG';
  SELECT count(*) INTO v_n FROM lf_ops.reglas_versiones
   WHERE codigo='TEST-VIG' AND version=1 AND vigente_hasta IS NOT NULL;
  SELECT version INTO v_actual FROM lf_ops.v_reglas_historial
   WHERE codigo='TEST-VIG' AND es_actual;
  IF v_n<>1 OR v_actual<>2 THEN
    RAISE EXCEPTION 'SUBSTANTIVE_UPDATE_DID_NOT_ARCHIVE: % %',v_n,v_actual;
  END IF;

  UPDATE lf_ops.reglas SET updated_at=updated_at + interval '1 second'
   WHERE codigo='TEST-VIG';
  SELECT count(*) INTO v_n FROM lf_ops.reglas_versiones WHERE codigo='TEST-VIG';
  IF v_n<>1 THEN RAISE EXCEPTION 'TIMESTAMP_ONLY_CREATED_VERSION'; END IF;

  UPDATE lf_ops.reglas SET valor_config='{"scope":"AUTH","config_key":"CHANGED"}'
   WHERE codigo='TEST-VIG';
  SELECT count(*) INTO v_n FROM lf_ops.reglas_versiones
   WHERE codigo='TEST-VIG' AND version=2 AND titulo='Cambio 1' AND vigente_hasta IS NOT NULL;
  SELECT version INTO v_actual FROM lf_ops.v_reglas_historial
   WHERE codigo='TEST-VIG' AND es_actual;
  IF v_n<>1 OR v_actual<>3 THEN RAISE EXCEPTION 'SECOND_UPDATE_VERSIONING_FAIL'; END IF;

  DELETE FROM lf_ops.reglas WHERE codigo='TEST-VIG';
  SELECT count(*) INTO v_n FROM lf_ops.reglas_versiones
   WHERE codigo='TEST-VIG' AND version=3 AND vigente_hasta IS NOT NULL;
  IF v_n<>1 OR (SELECT count(*) FROM lf_ops.v_reglas_historial
    WHERE codigo='TEST-VIG' AND es_actual)<>0 THEN
    RAISE EXCEPTION 'DELETE_LAST_VERSION_MISSING';
  END IF;

  -- El guard oficial debe bloquear la promoción no aprobada.
  v_failed:=false;
  BEGIN
    UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE codigo='TEST-CAN';
  EXCEPTION WHEN raise_exception THEN
    v_failed := SQLERRM LIKE 'LF_RULE_PROMOTION_REQUIRED:%';
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'PROMOTION_GUARD_NOT_BLOCKING'; END IF;
  IF (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo='TEST-CAN')<>1
    OR (SELECT estado FROM lf_ops.reglas WHERE codigo='TEST-CAN')<>'CANDIDATO' THEN
    RAISE EXCEPTION 'FAILED_PROMOTION_LEFT_HISTORY';
  END IF;

  INSERT INTO public.lf_rule_promotion_v1(rule_code,status,request_snapshot_sha256)
  VALUES('TEST-CAN','APPROVED',public.lf_asset_snapshot_sha_v1('REGLA','TEST-CAN'));
  UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE codigo='TEST-CAN';
  IF (SELECT version FROM lf_ops.v_reglas_historial
    WHERE codigo='TEST-CAN' AND es_actual)<>2
    OR (SELECT estado FROM lf_ops.reglas WHERE codigo='TEST-CAN')<>'VIGENTE' THEN
    RAISE EXCEPTION 'APPROVED_PROMOTION_WITH_HISTORY_FAIL';
  END IF;

  -- Misma sentencia UPDATE material que usa la rama CORRECT_VIGENTE de finalize_v2.
  UPDATE lf_ops.reglas SET
     categoria=coalesce('SEGURIDAD',categoria),
     titulo=coalesce('V2 corrected',titulo),
     descripcion=coalesce(NULL::text,descripcion),
     razon=coalesce(NULL::text,razon),
     valor_config=coalesce(NULL::jsonb,valor_config),
     es_transversal=coalesce(NULL::boolean,es_transversal),
     origen=coalesce(NULL::text,origen),
     pendiente_decision=false,pendiente_detalle=NULL,updated_at=now()
   WHERE codigo='TEST-V2-DML' AND estado='VIGENTE';
  IF (SELECT version FROM lf_ops.v_reglas_historial
    WHERE codigo='TEST-V2-DML' AND es_actual)<>2
    OR (SELECT titulo FROM lf_ops.reglas WHERE codigo='TEST-V2-DML')<>'V2 corrected' THEN
    RAISE EXCEPTION 'FINALIZE_V2_DML_WITH_TRIGGER_FAIL';
  END IF;

  IF (SELECT count(*) FROM pg_trigger t
       JOIN pg_class c ON c.oid=t.tgrelid
       JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='lf_ops' AND c.relname='reglas'
         AND t.tgname='trg_lf_rule_promotion_guard_v1')<>1 THEN
    RAISE EXCEPTION 'ORIGINAL_PROMOTION_GUARD_LOST';
  END IF;
  RAISE NOTICE 'PASS: UPDATE fondo, updated_at, DELETE, guard negativo/positivo, DML finalize_v2';
END;
$proof$;
-- La vista puede leerla service_role sin acceso directo a la tabla protegida.
SET LOCAL ROLE service_role;
SELECT codigo,version,es_actual FROM lf_ops.v_reglas_historial
 WHERE codigo='TEST-CAN' AND es_actual;
RESET ROLE;
ROLLBACK;

-- Readback independiente en una transacción nueva: todos los cambios de prueba desaparecieron.
DO $readback$
BEGIN
  IF (SELECT count(*) FROM lf_ops.reglas)<>3 OR
     (SELECT count(*) FROM lf_ops.reglas_versiones)<>3 OR
     (SELECT count(*) FROM lf_ops.v_reglas_historial)<>3 OR
     (SELECT count(*) FROM lf_ops.v_reglas_historial WHERE es_actual)<>3 OR
     (SELECT titulo FROM lf_ops.reglas WHERE codigo='TEST-VIG')<>'Titulo inicial' OR
     (SELECT estado FROM lf_ops.reglas WHERE codigo='TEST-CAN')<>'CANDIDATO' THEN
    RAISE EXCEPTION 'INDEPENDENT_ROLLBACK_READBACK_FAIL';
  END IF;
  RAISE NOTICE 'PASS: ROLLBACK real + SELECT independiente';
END;
$readback$;
SELECT 'PASS:PG17_BEGIN_ROLLBACK_AND_INDEPENDENT_READBACK' AS result;
