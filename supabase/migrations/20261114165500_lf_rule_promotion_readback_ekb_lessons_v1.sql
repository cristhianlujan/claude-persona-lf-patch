-- LF EKB source-first, 2026-11-14. Evidence-only. No changes to rules or promotions.
-- Source: read-only SELECT of 412 VIGENTE and 166 CANDIDATO; 0/166 eligible.
BEGIN;
DO $lesson$
DECLARE codes text[] := ARRAY['LF-PROMO-166-HOLD-ELIGIBILITY-20261114-001','LF-PROMO-42501-VERDICT-READ-20261114-001','LF-PROMO-INDEPENDENT-JUDGE-OWNER-20261114-001','LF-PROMO-R17-PG-FIXTURE-20261114-001']; n integer;
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=ANY(codes))
 THEN RAISE EXCEPTION 'LF_EKB_PROMO_DUPLICATE_CODE'; END IF;
 INSERT INTO public.lf_error_knowledge(
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
 validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
 pr,estado,evidencia,created_at,updated_at,lifecycle_phase,
 consumer_role,root_cause_family,detectability,source_context,source_ref)
 SELECT gen_random_uuid(),v.codigo,v.categoria,v.titulo,v.descripcion,v.causa_raiz,
 v.patron,v.prevencion,v.validacion,'HIGH',1,clock_timestamp(),clock_timestamp(),
 'LF_RULE_PROMOTION_CANDIDATES_20261114','#3898/#3905','ACTIVO',
 'SELECT 2026-11-14: 0 PASS / 166 HOLD; no promotion applied',
 clock_timestamp(),clock_timestamp(),'RULE_GOVERNANCE',
 ARRAY['PRODUCT_DIRECTOR','ENGINEERING','RULE_GOVERNANCE'],
 'R5_EROSION_PROCESO','LOUD_EARLY',
 '412 VIGENTE/166 CANDIDATO; reconstructed verdict, not official receipt; owner unverified',
 'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3898'
 FROM (VALUES
 ('LF-PROMO-166-HOLD-ELIGIBILITY-20261114-001','RULE_GOVERNANCE','166 candidatos: ninguno elegible','SELECT 2026-11-14 412 VIGENTE/166 CANDIDATO; reconstruccion de cinco criterios 0 PASS/166 HOLD; fallos solapados: 148 pantallas, 66 marcadores, 57 decision, 3 razon y 0 duplicado.','La aprobacion general no sustituye elegibilidad de cada regla ni fuentes por pantalla.','CANDIDATE_NOT_READY_FOR_PROMOTION','Product/UX revisa vinculaciones reales y no inventa pantallas; Product Director agrega razones verificadas; owner resuelve decisiones pendientes; recalcular antes de request.','SELECT lf_ops.reglas y reglas_pantallas; docs/rule-promotion/lf_candidate_verdicts_reconstructed_20261114.json (PR #3898).'),
('LF-PROMO-42501-VERDICT-READ-20261114-001','RULE_GOVERNANCE','Lectura de veredictos con permisos minimos','La funcion fn_t_remed_rule_promotion_verdicts_v1(5,NULL) devolvio 42501 al rol de inspeccion; SELECT equivalente no es recibo de funcion oficial.','Falta EXECUTE y USAGE efectiva a la ruta invocadora pese a SECURITY DEFINER.','VERDICT_FUNCTION_NOT_CALLABLE_BY_INSPECTION','Ingenieria prepara wrapper SECURITY DEFINER read-only en public, EXECUTE solo service_role, sin grants amplios a anon/authenticated; probar PG17/18.','pg_get_functiondef y 42501 observados; wrapper propuesto PR #3898.'),
('LF-PROMO-INDEPENDENT-JUDGE-OWNER-20261114-001','RULE_GOVERNANCE','Separar juez independiente de aprobacion humana autenticada','Sin Step70 independiente acreditado y con owner identity_mode UNVERIFIED_CHAT_DECLARATION. IDs 438,439,440,577 conservan owner_decision_identity_verified=false; 0 solicitudes.','Un texto HUMAN: y un juez del mismo contexto no certifican identidad ni independencia.','UNVERIFIED_JUDGE_OR_OWNER_RECEIPT','Arquitectura integra acto real de juez separado con hash candidato/alcance; Seguridad autentica owner y vincula evidencia al lote antes de decide/apply; no simular.','SELECT public.lf_ig_project_owner_v2 y public.lf_rule_promotion_v1; PR #3898.'),
('LF-PROMO-R17-PG-FIXTURE-20261114-001','TESTS','R17: firma negativa y nombre de migracion Train','R17 PR #3898 fallo por fixture negativo con parametros anonimos y por test Step40 que referia 20261114153500 en lugar de 20261114155757.','El error de firma ocurre antes del guard de hash; las pruebas usan rutas pre-Train obsoletas.','TEST_FALSE_NEGATIVE_AND_TRAIN_PATH_DRIFT','QA modifica solo el cuerpo de la funcion preservando parametros; actualiza ruta real; exige CI HEAD exacto y ROLLBACK PG17/18.','R17 run 43614091462; correcciones #3898 5e895677 y #3905 d6c5eb98.')
 ) AS v(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion);
 SELECT COUNT(*) INTO n FROM public.lf_error_knowledge WHERE codigo=ANY(codes) AND estado='ACTIVO';
 IF n<>4 THEN RAISE EXCEPTION 'LF_EKB_PROMO_EXPECTED_FOUR_GOT_%',n; END IF;
END $lesson$;
COMMIT;
