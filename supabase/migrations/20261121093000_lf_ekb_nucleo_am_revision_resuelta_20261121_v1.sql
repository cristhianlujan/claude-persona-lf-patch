-- AM EKB: resolve the existing finding; no new finding and no data changes elsewhere.
BEGIN;
DO $ekb$
DECLARE n integer;
BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge
     WHERE codigo='LF-NUCLEO-INITIAL-CANDIDATE-REVISION-DEADEND-20261121-001'
       AND estado='ACTIVO' AND md5(evidencia)='2e7ba0f5b595603ff4f063b40dc158d3')<>1
 THEN RAISE EXCEPTION 'AM_EKB_REVISION_BASE_DRIFT'; END IF;
 UPDATE public.lf_error_knowledge SET
 estado='RESUELTO', ultima_vez=clock_timestamp(), updated_at=clock_timestamp(),
 prevencion=concat_ws(E'\n',prevencion,
 'Solución verificada: tipo REVISION de nucleo_regla_proponer_v1 en LF y SALY, con versión/hash optimistas, motivo, autoridad validada, protección de identidad, descarte atómico del estado previo y alta CANDIDATA; el historial no se edita y el alcance solo puede ajustarse antes de publicar. No promover como atajo.'),
 validacion=concat_ws(E'\n',validacion,
 'PR #4528; PASE 44888756068 SUCCESS sobre HEAD exacto 33d7c4e18afb03779a7ec1c505f541f070ce72bd: PG17 17/17 y negativo inducido detectado, 17/17 después de ROLLBACK; pruebas específicas de REVISION (creación, motivo, hash, identidad, replay, alcance, preservación de historial) en ambas instancias.'),
 evidencia=concat_ws(E'\n',evidencia,
 'PR #4528 fusionado mediante Train 44888822639 SUCCESS, merge ab7907f33850c56fe5a8913a2185b9ddbdd340b2, migración 20261121092500. Readback: lf_ops función md5 473e02146d1d3a43a7f3b81e58a20c1d, saly md5 442f3c0a7a21deb50f3e42cac9eac2c3; PROPUESTA V2 VIGENTE, V1 REEMPLAZADO en ambas; 586 legadas, 10 candidatas piloto v1, 0 v2 y 0 PUBLICADA. Se resolvió la ruta técnica; pendientes nueve remediaciones semánticas.')
 WHERE codigo='LF-NUCLEO-INITIAL-CANDIDATE-REVISION-DEADEND-20261121-001'
 AND estado='ACTIVO';
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>1 OR (SELECT count(*) FROM public.lf_error_knowledge
 WHERE codigo='LF-NUCLEO-INITIAL-CANDIDATE-REVISION-DEADEND-20261121-001'
   AND estado='RESUELTO')<>1 THEN RAISE EXCEPTION 'AM_EKB_REVISION_UPDATE_FAILED'; END IF;
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE patron='INITIAL_CANDIDATE_REVISION_DEADEND')<>1
 THEN RAISE EXCEPTION 'AM_EKB_REVISION_DUPLICATE'; END IF;
 RAISE NOTICE 'AM_EKB_REVISION_RESUELTO: exactly one existing finding, no duplicate';
END $ekb$;
COMMIT;
