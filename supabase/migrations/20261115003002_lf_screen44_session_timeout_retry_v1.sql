-- Screen 44 / IG run 956: bind B2B session + existing timeout policies.
-- Links remain CANDIDATO; policy sources and rules are not promoted or altered.
BEGIN;
DO $repair$
BEGIN
 IF (SELECT count(*) FROM lf_ops.pantallas WHERE id=44 AND codigo='B2B-CARGA-002')<>1 THEN
   RAISE EXCEPTION 'SCREEN44_SESSION_TIMEOUT_SCREEN_DRIFT';
 END IF;
 IF (SELECT count(*) FROM lf_ops.politicas_sesion
   WHERE session_policy_id=1 AND policy_code='SESSION-B2B-DEFAULT'
   AND status='VIGENTE' AND scope_code='B2B_APP_SHELL')<>1 THEN
   RAISE EXCEPTION 'SCREEN44_SESSION_TIMEOUT_SESSION_SOURCE_DRIFT';
 END IF;
 IF (SELECT count(*) FROM lf_ops.politicas_timeout
   WHERE status='CANDIDATO' AND (
        (timeout_policy_id=2 AND policy_code='TIMEOUT-B2B-UPLOAD'
          AND operation_code='FILE_UPLOAD' AND timeout_seconds=300
          AND retry_limit=2 AND backoff_strategy='EXPONENTIAL')
      OR (timeout_policy_id=4 AND policy_code='TIMEOUT-B2B-VALIDATION'
          AND operation_code='FILE_VALIDATION' AND timeout_seconds=600
          AND retry_limit=1 AND backoff_strategy='FIXED')
      OR (timeout_policy_id=5 AND policy_code='TIMEOUT-B2B-PROCESSING'
          AND operation_code='LOAD_PROCESSING' AND timeout_seconds=1800
          AND retry_limit=0 AND backoff_strategy='NONE')
      ))<>3 THEN
   RAISE EXCEPTION 'SCREEN44_SESSION_TIMEOUT_TIMING_SOURCE_DRIFT';
 END IF;
 IF (SELECT count(*) FROM lf_ops.reglas
   WHERE id IN (399,400,417) AND estado='VIGENTE')<>3 THEN
   RAISE EXCEPTION 'SCREEN44_SESSION_TIMEOUT_RULE_SOURCE_DRIFT';
 END IF;

 INSERT INTO lf_ops.pantallas_politicas(
    pantalla_id,policy_kind,reference_role,session_policy_id,status
 ) VALUES(44,'SESSION','b2b_session_policy_id',1,'CANDIDATO')
 ON CONFLICT (pantalla_id,reference_role) DO NOTHING;

 INSERT INTO lf_ops.pantallas_politicas(
    pantalla_id,policy_kind,reference_role,timeout_policy_id,status
 ) VALUES
 (44,'TIMEOUT','upload_timeout_policy_id',2,'CANDIDATO'),
 (44,'TIMEOUT','validation_timeout_policy_id',4,'CANDIDATO'),
 (44,'TIMEOUT','processing_timeout_policy_id',5,'CANDIDATO')
 ON CONFLICT (pantalla_id,reference_role) DO NOTHING;

 IF (SELECT count(*) FROM lf_ops.pantallas_politicas
    WHERE pantalla_id=44 AND status='CANDIDATO'
      AND ((policy_kind='SESSION' AND reference_role='b2b_session_policy_id'
             AND session_policy_id=1)
        OR (policy_kind='TIMEOUT' AND reference_role='upload_timeout_policy_id'
             AND timeout_policy_id=2)
        OR (policy_kind='TIMEOUT' AND reference_role='validation_timeout_policy_id'
             AND timeout_policy_id=4)
        OR (policy_kind='TIMEOUT' AND reference_role='processing_timeout_policy_id'
             AND timeout_policy_id=5)))<>4 THEN
    RAISE EXCEPTION 'SCREEN44_SESSION_TIMEOUT_LINK_CONFLICT';
 END IF;

 INSERT INTO lf_ops.pantallas_politicas_reglas(pantalla_politica_id,regla_id)
 SELECT pp.pantalla_politica_id, refs.regla_id
 FROM (VALUES
   ('b2b_session_policy_id',399),
   ('b2b_session_policy_id',400),
   ('upload_timeout_policy_id',417),
   ('validation_timeout_policy_id',417),
   ('processing_timeout_policy_id',417)
 ) AS refs(role,regla_id)
 JOIN lf_ops.pantallas_politicas pp
   ON pp.pantalla_id=44 AND pp.reference_role=refs.role
 ON CONFLICT DO NOTHING;
END $repair$;

DO $readback$
BEGIN
 IF (SELECT count(*) FROM lf_ops.pantallas_politicas
     WHERE pantalla_id=44 AND reference_role IN (
       'b2b_session_policy_id','upload_timeout_policy_id',
       'validation_timeout_policy_id','processing_timeout_policy_id')
       AND status='CANDIDATO')<>4
   OR (SELECT count(*) FROM lf_ops.pantallas_politicas_reglas pr
      JOIN lf_ops.pantallas_politicas pp USING(pantalla_politica_id)
      WHERE pp.pantalla_id=44 AND pp.reference_role IN (
       'b2b_session_policy_id','upload_timeout_policy_id',
       'validation_timeout_policy_id','processing_timeout_policy_id'))<>5
   OR (SELECT count(*) FROM lf_ops.politicas_timeout
      WHERE timeout_policy_id IN (2,4,5) AND status='CANDIDATO')<>3
   OR (SELECT status FROM lf_ops.politicas_sesion WHERE session_policy_id=1)<>'VIGENTE' THEN
   RAISE EXCEPTION 'SCREEN44_SESSION_TIMEOUT_READBACK_FAILED';
 END IF;
END $readback$;
COMMIT;
