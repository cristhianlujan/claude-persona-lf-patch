-- Single EKB finding for the CI regression gate, no prior findings touched.
BEGIN;
DO $ekb$
DECLARE
  v_code constant text := 'LF-NUCLEO-CI-PG17-REGRESSION-20261121-001';
  v_id uuid := gen_random_uuid();
  v_n integer;
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo = v_code) THEN
    RAISE EXCEPTION 'LF_EKB_NUCLEO_CI_DUPLICATE';
  END IF;
  INSERT INTO public.lf_error_knowledge (
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
    primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
    detectability,source_context,source_ref,created_at,updated_at
  ) VALUES (
    v_id,v_code,'RULE_GOVERNANCE',
    'Pruebas conjuntas del núcleo ausentes del CI obligatorio previo al merge',
    'Antes de PR #4509 las pruebas se ejecutaban al aplicar migraciones y no en cada PR del motor. Una regresión podía llegar al Train sin prueba conjunta previa.',
    'No existía ejecutor reproducible de las dependencias y migraciones del motor en el CI de PASE.',
    'NUCLEUS_REGRESSION_NOT_REQUIRED_PREMERGE',
    'Ejecutar las 15 funciones reales LF/SALY en PG17 aislado con base sintética versionada y migraciones en orden. Exigir veredicto exacto, detectar el fallo inducido, comprobar rollback y repetir la suite; certificar el HEAD exacto. No confundir fixture con producción ni shadow con checks obligatorios.',
    'PASE positivo 44874030529: PG17.12, 20 migraciones, 15/15, mutante exit 3 y 15/15 tras rollback. Negativo 44874109935: PASE FAILURE por PUERTA 0/26. Recertificación 44875016992: PASS; Train 44875077407 SUCCESS; readback main del workflow positivo.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4509','RESUELTO',
    'PR #4509 merge 699adb1d7b1d0fab1842b4c6b48774a8a184ac5d; blob pase.yml 1abfecf7d953094415de775899973b9bfb64234c; 4/4 checks requeridos del Train',
    'VALIDATION',ARRAY['CLAUDE_NATIVE','PROGRAMADOR','INPUT_GOVERNANCE']::text[],'R2_NO_VE','LOUD_EARLY',
    'Criterio S del plan de núcleo LF/SALY','https://github.com/cristhianlujan/claude-persona-lf-patch/pull/4509',clock_timestamp(),clock_timestamp()
  );
  SELECT count(*) INTO v_n FROM public.lf_error_knowledge WHERE codigo = v_code AND id = v_id AND estado = 'RESUELTO' AND pr = '#4509';
  IF v_n <> 1 THEN RAISE EXCEPTION 'LF_EKB_NUCLEO_CI_READBACK_FAILED'; END IF;
END $ekb$;
COMMIT;
