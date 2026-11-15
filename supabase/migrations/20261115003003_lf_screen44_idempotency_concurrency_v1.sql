-- Screen 44 / IG run 956: candidate association only, no rule/policy promotion.
BEGIN;
DO $repair$
BEGIN
 IF (SELECT count(*) FROM lf_ops.pantallas WHERE id=44 AND codigo='B2B-CARGA-002')<>1 THEN
   RAISE EXCEPTION 'SCREEN44_IDEMPOTENCY_SCREEN_DRIFT';
 END IF;
 IF (SELECT count(*) FROM lf_ops.politicas_seguridad
     WHERE security_policy_id=9 AND policy_code='SEC-B2B-IDEMPOTENCY'
       AND status='CANDIDATO' AND category='INTEGRITY')<>1 THEN
   RAISE EXCEPTION 'SCREEN44_IDEMPOTENCY_POLICY_SOURCE_DRIFT';
 END IF;
 IF (SELECT count(*) FROM lf_ops.reglas
     WHERE id=403 AND codigo='B2B-RULE-IDEMP-001'
       AND estado='CANDIDATO' AND pendiente_decision=false)<>1
   OR (SELECT count(*) FROM lf_ops.reglas_pantallas
     WHERE pantalla_id=44 AND regla_id=403)<>1 THEN
   RAISE EXCEPTION 'SCREEN44_IDEMPOTENCY_RULE_SOURCE_DRIFT';
 END IF;
 IF (SELECT count(*) FROM lf_ops.estados_transiciones
     WHERE entity_type='UPLOAD_BATCH' AND transition_code IN (
       'TR_LOAD_CREATE','TR_LOAD_VALIDATE_START','TR_LOAD_VALIDATE_OK')
       AND requires_idempotency_key=true)<>3 THEN
   RAISE EXCEPTION 'SCREEN44_IDEMPOTENCY_TRANSITION_SOURCE_DRIFT';
 END IF;

 INSERT INTO lf_ops.pantallas_politicas(
   pantalla_id,policy_kind,reference_role,security_policy_id,status
 ) VALUES(44,'SECURITY','idempotency_security_policy_id',9,'CANDIDATO')
 ON CONFLICT (pantalla_id,reference_role) DO NOTHING;

 IF (SELECT count(*) FROM lf_ops.pantallas_politicas
     WHERE pantalla_id=44 AND policy_kind='SECURITY'
       AND reference_role='idempotency_security_policy_id'
       AND security_policy_id=9 AND status='CANDIDATO')<>1 THEN
   RAISE EXCEPTION 'SCREEN44_IDEMPOTENCY_LINK_CONFLICT';
 END IF;
 INSERT INTO lf_ops.pantallas_politicas_reglas(pantalla_politica_id,regla_id)
 SELECT pp.pantalla_politica_id,403
 FROM lf_ops.pantallas_politicas pp
 WHERE pp.pantalla_id=44 AND pp.reference_role='idempotency_security_policy_id'
   AND pp.security_policy_id=9 AND pp.status='CANDIDATO'
 ON CONFLICT DO NOTHING;
END $repair$;

DO $readback$
BEGIN
 IF (SELECT count(*) FROM lf_ops.pantallas_politicas
     WHERE pantalla_id=44 AND reference_role='idempotency_security_policy_id'
       AND security_policy_id=9 AND status='CANDIDATO')<>1
   OR (SELECT count(*) FROM lf_ops.pantallas_politicas_reglas pr
      JOIN lf_ops.pantallas_politicas pp USING(pantalla_politica_id)
      WHERE pp.pantalla_id=44 AND pp.security_policy_id=9 AND pr.regla_id=403)<>1
   OR (SELECT status FROM lf_ops.politicas_seguridad WHERE security_policy_id=9)<>'CANDIDATO'
   OR (SELECT estado FROM lf_ops.reglas WHERE id=403)<>'CANDIDATO' THEN
   RAISE EXCEPTION 'SCREEN44_IDEMPOTENCY_READBACK_FAILED';
 END IF;
END $readback$;
COMMIT;
