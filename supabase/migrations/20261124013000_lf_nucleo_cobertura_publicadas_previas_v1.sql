-- Coberturas funcionales de TODAS las reglas núcleo PUBLICADAS previas a SECURITY S1-C01..06.
-- Fuente vinculante: origen de versión publicada contrastado con lf_ops.v_reglas_compat_v1.
BEGIN;
DO $gate$ BEGIN
 IF (SELECT count(*) FROM lf_ops.lf_nucleo_cobertura_legada)<>6
    OR (SELECT count(*) FROM lf_ops.nucleo_reglas WHERE estado='VIGENTE')<>64
    OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
    OR (SELECT count(*) FROM lf_ops.reglas) NOT IN (215,586)
 THEN RAISE EXCEPTION 'COB58_BASELINE_DRIFT'; END IF;
END $gate$;
CREATE TEMP TABLE cob58_fuentes ON COMMIT DROP AS
WITH publicados AS (
 SELECT r.codigo nucleo_codigo,r.familia,v.version, v.descripcion descripcion_nueva,v.ficha->'origen'->>'ref' ref_origen
 FROM lf_ops.nucleo_reglas r
 JOIN LATERAL (
  SELECT vv.* FROM lf_ops.nucleo_regla_versiones vv
  WHERE vv.regla=r.codigo AND vv.estado='PUBLICADA' ORDER BY vv.version DESC LIMIT 1
 ) v ON true
 WHERE r.codigo NOT IN ('S1-C01','S1-C02','S1-C03','S1-C04','S1-C05','S1-C06')
), src AS (
 SELECT p.*,(m)[1]::int legacy_id
 FROM publicados p CROSS JOIN LATERAL regexp_matches(coalesce(p.ref_origen,''),'[0-9]+','g') m
)
SELECT s.*,l.codigo codigo_legado,l.descripcion descripcion_legada
FROM src s JOIN lf_ops.v_reglas_compat_v1 l ON l.id=s.legacy_id
WHERE NOT EXISTS (
 SELECT 1 FROM lf_ops.lf_nucleo_cobertura_legada c
 WHERE c.legacy_id=s.legacy_id AND c.nucleo_codigo=s.nucleo_codigo AND c.version_nucleo=s.version);
DO $coverage$
DECLARE source_count int; n_replaced int; n_partial int;
BEGIN
 SELECT count(*) INTO source_count FROM cob58_fuentes;
 IF source_count<45 THEN RAISE EXCEPTION 'COB58_SOURCES_INSUFFICIENT: %',source_count; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada
 (legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 SELECT x.legacy_id,x.nucleo_codigo,x.version,
 CASE
  WHEN x.legacy_id IN (183,185,157,238,13126,209,524,212,280,292,327,316,208,226,289,277,548,580,533,425)
      OR (x.nucleo_codigo='REG_CHK_004' AND x.legacy_id IN (208,228))
      OR (x.nucleo_codigo='REG_CHK_005')
      OR (x.nucleo_codigo='REG_CHK_008')
      OR (x.nucleo_codigo='M1-C02')
  THEN 'PARCIAL' ELSE 'REEMPLAZADA' END,
 CASE
  WHEN x.legacy_id=183 THEN 'La fuente legada agrupa conservación offline de onboarding y bloqueo de pago sin conexión; la regla del núcleo cubre una de estas operaciones. Se requiere la otra regla publicada para completar la intención.'
  WHEN x.legacy_id=185 THEN 'La fuente exige idempotencia tanto en onboarding como en checkout; esta regla del núcleo se limita a una de las dos superficies.'
  WHEN x.legacy_id=157 THEN 'La nueva regla no establece expresamente los tres planes iniciales visibles previstos por la legada.'
  WHEN x.legacy_id=238 THEN 'La nueva regla protege selección al cerrar modal, pero no exige explícitamente apertura sin navegación.'
  WHEN x.legacy_id=13126 THEN 'La nueva regla bloquea recibo con destinatario o estado inválido; flujo de incidencia y separación del correo técnico Niubiz todavía son obligaciones operativas sin acreditación.'
  WHEN x.legacy_id IN (209,524) THEN 'La nueva regla controla la presentación de éxito, pero la fuente legada también cubre efectos backend posteriores al pago.'
  WHEN x.legacy_id IN (212,280,292,327) THEN 'La regla núcleo gobierna inicio de gestión documental tras liquidación; presentación de copy, estados posteriores y descarga requieren otras obligaciones.'
  WHEN x.legacy_id=316 THEN 'La regla núcleo protege confirmación autoritativa, pero el legado además exige las dos rutas de interacción Yape QR visibles.'
  WHEN x.legacy_id=208 THEN 'El núcleo gobierna reintento seguro pero no impone explícitamente bloqueo inmediato del CTA al primer clic.'
  WHEN x.legacy_id=228 THEN 'El núcleo exige reintento con outcome normalizado, permiso backend y quote válida, pero la legada puede imponer salvaguardas adicionales de reintento.'
  WHEN x.legacy_id=226 THEN 'El núcleo exige comisión visible, pero el legado también obliga a incluir ambas comisiones en el total final.'
  WHEN x.legacy_id=289 THEN 'El núcleo impide penalidad al cancelar recurrencia pero no obliga a mostrar esa política en checkout.'
  WHEN x.legacy_id=277 THEN 'El núcleo cubre cancelación sin penalidad; la legada también gobierna carta de no adeudo tras liquidación.'
  WHEN x.legacy_id=548 THEN 'Núcleo impide promesas prematuras de carta, pero el copy de trust card permanece pendiente de reconciliación aprobada.'
  WHEN x.legacy_id=580 THEN 'El núcleo evita autenticación anticipada o duplicada, pero faltan foco, aria-live y validación local del Login progresivo.'
  WHEN x.legacy_id=533 THEN 'El núcleo bloquea SETTLED_CONFIRMED sin pruebas financieras; la fuente también determina el estado de deuda para todas las vistas y transiciones.'
  WHEN x.legacy_id=425 THEN 'El núcleo impide enumeración por respuesta, pero las respuestas externas deben ser indistinguibles también en tiempos observables.'
  ELSE 'La regla legada es descriptiva del resultado; la regla del núcleo lo expresa como condición/efecto verificable para su mismo ámbito, sin acreditar binding runtime. No cambia la intención sustantiva.' END,
 jsonb_build_object(
  'fuente','lf_ops.v_reglas_compat_v1/'||x.legacy_id||' '||x.codigo_legado,
  'contraste','LEGADA: '||x.descripcion_legada||' NUCLEO PUBLICADO: '||x.descripcion_nueva,
  'residual',CASE
    WHEN x.legacy_id=183 THEN 'Completar las obligaciones offline de onboarding y checkout como unidad funcional; aquí solo se vincula cobertura fragmentada.'
    WHEN x.legacy_id=185 THEN 'Una misma regla no cubre simultáneamente idempotencia onboarding y checkout; falta certificación conjunta.'
    WHEN x.legacy_id=157 THEN 'Mostrar tres planes iniciales y habilitar enlace solo cuando existen adicionales.'
    WHEN x.legacy_id=238 THEN 'Apertura sin navegación y conservación íntegra del estado al abrir el modal.'
    WHEN x.legacy_id=13126 THEN 'Registrar incidencia de fallo del recibo y separar los identificadores técnicos de correo del destinatario real.'
    WHEN x.legacy_id IN (209,524) THEN 'Efectos posteriores al pago confirmado: estados, procesamiento por deuda y acciones backend.'
    WHEN x.legacy_id IN (212,280,292,327) THEN 'Copy y estados de ciclo documental, descarga disponible únicamente en AVAILABLE.'
    WHEN x.legacy_id=316 THEN 'Las dos rutas visibles de confirmación Yape QR y la transición intermedia CONFIRMANDO.'
    WHEN x.legacy_id=208 THEN 'Bloqueo inmediato del primer clic de pago antes de recibir resultado autoritativo.'
    WHEN x.legacy_id=228 THEN 'Completar salvaguardas operativas del reintento desde el texto de la legada sin diluir criterios de outcome seguro.'
    WHEN x.legacy_id=226 THEN 'Monto final debe incluir las dos comisiones y mostrarlas correctamente.'
    WHEN x.legacy_id=289 THEN 'Aviso visible de cancelación sin penalidad previo al pago.'
    WHEN x.legacy_id=277 THEN 'La carta de no adeudo depende de liquidación total y no de cancelar recurrencia.'
    WHEN x.legacy_id=548 THEN 'Reconciliación del copy de la tarjeta de confianza con condición real de carta.'
    WHEN x.legacy_id=580 THEN 'Validación local de correo, foco, aria-live y comportamiento de etapas progresivas.'
    WHEN x.legacy_id=533 THEN 'Todos los estados de deuda y su fuente de verdad más allá del guard de transición.'
    WHEN x.legacy_id=425 THEN 'Indistinguibilidad observable de tiempos de respuesta a fallos de credenciales.'
    ELSE '' END,
  'familia_nucleo',x.familia,
  'metodo','Contraste version PUBLICADA, origen en ficha y descripcion legada; no prueba binding fisico',
  'corte','2026-11-23T20:18:00-05:00'),
 lf_ops.nucleo_hash_paquete_v1(x.nucleo_codigo,x.version),
 'GPT-6 revision individual fuente/condicion 2026-11-23'
 FROM cob58_fuentes x;
 SELECT count(*) INTO n_replaced FROM lf_ops.lf_nucleo_cobertura_legada WHERE estado_cobertura='REEMPLAZADA';
 SELECT count(*) INTO n_partial FROM lf_ops.lf_nucleo_cobertura_legada WHERE estado_cobertura='PARCIAL';
 IF n_replaced<30 OR n_partial<3 THEN RAISE EXCEPTION 'COB58_COVERAGE_COUNT_LOW replaced=% partial=%',n_replaced,n_partial; END IF;
 RAISE NOTICE 'COB58_APLICACION_PASS source_links=% reemplazadas_filas=% parciales_filas=%',source_count,n_replaced,n_partial;
END $coverage$;
SAVEPOINT cob58_negative;
DO $test$
DECLARE ok boolean:=false; id0 int;
BEGIN
 SELECT legacy_id INTO id0 FROM lf_ops.lf_nucleo_cobertura_legada WHERE estado_cobertura='REEMPLAZADA' LIMIT 1;
 BEGIN
  UPDATE lf_ops.lf_nucleo_cobertura_legada SET hash_paquete=repeat('0',64) WHERE legacy_id=id0;
 EXCEPTION WHEN check_violation THEN ok:=SQLERRM='LF_COBERTURA_HASH_PAQUETE_INVALIDO'; END;
 IF NOT ok THEN RAISE EXCEPTION 'COB58_BAD_HASH_ACCEPTED'; END IF;
 ok:=false;
 BEGIN
  UPDATE lf_ops.lf_nucleo_cobertura_legada SET estado_cobertura='PARCIAL'
  WHERE legacy_id=id0 AND estado_cobertura='REEMPLAZADA';
 EXCEPTION WHEN check_violation THEN ok:=SQLERRM='LF_COBERTURA_RESIDUAL_REQUERIDO'; END;
 IF NOT ok THEN RAISE EXCEPTION 'COB58_EMPTY_RESIDUAL_ACCEPTED'; END IF;
 RAISE NOTICE 'COB58_NEGATIVE_HASH_RESIDUAL_PASS';
END $test$;
ROLLBACK TO SAVEPOINT cob58_negative;
DO $final$
DECLARE n int; v int;
BEGIN
 SELECT count(DISTINCT c.legacy_id) INTO n FROM lf_ops.lf_nucleo_cobertura_legada c
 JOIN lf_ops.nucleo_regla_versiones v ON v.regla=c.nucleo_codigo AND v.version=c.version_nucleo
 WHERE c.estado_cobertura='REEMPLAZADA' AND v.estado='PUBLICADA';
 SELECT count(*) INTO v FROM lf_ops.lf_nucleo_cobertura_legada c
 JOIN lf_ops.nucleo_regla_versiones x ON x.regla=c.nucleo_codigo AND x.version=c.version_nucleo
 WHERE x.estado<>'PUBLICADA';
 IF n<30 OR v<>0 OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
 THEN RAISE EXCEPTION 'COB58_FINAL_INVALID: % %',n,v; END IF;
 RAISE NOTICE 'COB58_FINAL_PASS distinct_reemplazadas=% no_deprecations',n;
END $final$;
COMMIT;
