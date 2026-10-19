-- SALY_FONDEO_LEGAL, C1 lote 01: solo datos en schema saly; no DDL, no LF.
-- Evidencia normativa de naturaleza del adelanto y sujetos de obligación. C2 y C3 NO se alteran.
BEGIN;
DO $guard$ BEGIN
 IF (SELECT count(*) FROM saly.programas_investigacion p JOIN saly.proyecto pr ON pr.id=p.proyecto_id WHERE p.codigo='SALY_FONDEO_LEGAL' AND pr.codigo='SALY-001') <> 1
 THEN RAISE EXCEPTION 'BLOCK_SALY_PROGRAM_BINDING'; END IF;
 IF (SELECT count(*) FROM saly.checkpoints_investigacion c JOIN saly.unidades_investigacion u ON u.id=c.unidad_id JOIN saly.programas_investigacion p ON p.id=u.programa_id WHERE p.codigo='SALY_FONDEO_LEGAL' AND u.codigo IN ('SALY-LEG-01','SALY-LEG-02') AND c.codigo='C1' AND c.estado='PENDIENTE') <> 2
 THEN RAISE EXCEPTION 'BLOCK_SALY_C1_NOT_PENDING'; END IF;
END $guard$;

INSERT INTO saly.evidencias (codigo,tipo,titulo,descripcion,referencia,fecha_evidencia,hechos,estado)
VALUES
('SALY-EVD-LEG-01-C1','NORMATIVA_LEGAL','C1 fuentes legales: naturaleza del adelanto Saly','Compendio normativo oficial: remuneración según DS003-97-TR art.6, mutuo y pago por tercero según Código Civil art.1648 y 1222. Plus futuro y devengado se distinguen como hipótesis a verificar en C2; este C1 no habilita actividad financiera.','https://diariooficial.elperuano.pe/Normas/obtenerDocumento?idNorma=34',DATE '2026-10-15','{"schema":"saly-legal-normative-review/v1","program":"SALY_FONDEO_LEGAL","unit":"SALY-LEG-01","checkpoint":"C1","reviewed_on":"2026-10-15","jurisdiction":"Peru","labor_scope":"Régimen laboral privado DL 728 (no extrapolar al sector público)","normative_sources":[{"instrument":"DS 003-97-TR, TUO DL 728","article":"6","source":"https://diariooficial.elperuano.pe/Normas/obtenerDocumento?idNorma=34","finding":"Remuneración constituye el íntegro recibido por servicios, de libre disposición; fundamento de derecho salarial de origen laboral","authority":"El Peruano; tribunal constitucional como contraste"},{"instrument":"Código Civil","article":"1648","source":"https://diariooficial.elperuano.pe/Normas/obtenerDocumento?idNorma=60","page":147,"finding":"Mutuo: entrega de dinero con obligación de devolución; distinto de pagar una remuneración debida"},{"instrument":"Código Civil","article":"1222","source":"https://diariooficial.elperuano.pe/Normas/obtenerDocumento?idNorma=60","page":117,"finding":"Puede pagar un tercero, salvo cuando pacto o naturaleza impidan; no confundir ejecutor del pago con obligado principal"},{"instrument":"MTPE noticia sobre convenio colectivo","article":"Adelanto de remuneración","source":"https://www.gob.pe/institucion/mtpe/noticias/1337303-mtpe-promovio-suscripcion-de-convenio-entre-la-caja-municipal-de-credito-popular-de-lima-s-a-y-sindicato","finding":"Ejemplo público de adelanto de remuneración sujeto a pacto; no regla general universal","status":"referencia de práctica, no norma"}],"conclusions_c1":["La norma laboral define remuneración; no basta la etiqueta comercial Saly para clasificar la entrega.","Adelanto sobre salario ya devengado: verificar que exista obligación laboral y quién la satisface antes de concluir naturaleza.","Plus sobre días aún no trabajados: no asumir obligación salarial ya devengada; diferenciar anticipo empresarial de mutuo u otra financiación según hechos y contratos.","La financiación por tercero no demuestra por sí sola cesión ni novación de acreedor."],"assumptions":"No se han revisado contratos efectivos empleador-trabajador-Saly-financiador. No emitir APTO/NO_APTO en C1.","open_for_c2":["Modelar adelanto devengado vs Plus con N días configurables","Revisar contratos y consentimiento laboral","Evaluar comisión e IGV sin presumir naturaleza","Separar regímenes públicos y privados","Probar vínculo obligación, titularidad y cobro"],"confidence":"ALTA en textos citados; MEDIA en encaje Saly hasta ver contratos","legal_authorization":false}'::jsonb,'VIGENTE'),
('SALY-EVD-LEG-02-C1','NORMATIVA_LEGAL','C1 fuentes legales: obligaciones y actores Saly','Marco normativo oficial: cesión de derechos arts.1206,1207,1210,1212,1213,1215; pago por tercero art.1222; mutuo art.1648; riesgo de captación bajo Ley26702 art.11. Titularidad concreta y descuentos laborales requieren C2.','https://diariooficial.elperuano.pe/Normas/obtenerDocumento?idNorma=60',DATE '2026-10-15','{"schema":"saly-legal-normative-review/v1","program":"SALY_FONDEO_LEGAL","unit":"SALY-LEG-02","checkpoint":"C1","reviewed_on":"2026-10-15","jurisdiction":"Peru","normative_sources":[{"instrument":"Código Civil","article":"1206","source":"https://diariooficial.elperuano.pe/Normas/obtenerDocumento?idNorma=60","page":116,"finding":"Cesión transmite derecho de exigir al deudor aun sin asentimiento"},{"instrument":"Código Civil","article":"1207","source":"https://diariooficial.elperuano.pe/Normas/obtenerDocumento?idNorma=60","page":116,"finding":"Cesión debe constar por escrito, sanción nulidad"},{"instrument":"Código Civil","article":"1210","source":"https://diariooficial.elperuano.pe/Normas/obtenerDocumento?idNorma=60","page":116,"finding":"No puede cederse lo opuesto a ley, naturaleza de obligación o pacto"},{"instrument":"Código Civil","article":"1212-1213","source":"https://diariooficial.elperuano.pe/Normas/obtenerDocumento?idNorma=60","page":116,"finding":"Cedente garantiza existencia y exigibilidad; solvencia deudor no se presume garantizada"},{"instrument":"Código Civil","article":"1215","source":"https://diariooficial.elperuano.pe/Normas/obtenerDocumento?idNorma=60","page":116,"finding":"Cesión surte efectos frente a deudor cuando acepta o es comunicada fehacientemente"},{"instrument":"Código Civil","article":"1222","source":"https://diariooficial.elperuano.pe/Normas/obtenerDocumento?idNorma=60","page":117,"finding":"Pago por tercero posible sujeto a pacto/naturaleza"},{"instrument":"Código Civil","article":"1648","source":"https://diariooficial.elperuano.pe/Normas/obtenerDocumento?idNorma=60","page":147,"finding":"Mutuo origina devolución de dinero por prestatario"},{"instrument":"Ley 26702","article":"11","source":"https://www.sbs.gob.pe/boletin/detalleboletin/idbulletin/1241","finding":"Captación de dinero de terceros bajo modalidades reguladas requiere habilitación; no asumir libertad para represtar"}],"conclusions_c1":["Distinguir deudor (obligado), acreedor (titular derecho), pagador (quien desembolsa) y recaudador (quien cobra). Pueden ser sujetos diferentes.","La cesión de derecho de cobro depende de existencia, transferibilidad, formalidad y eficacia frente al deudor, no se desprende automáticamente de un convenio comercial.","Si empleador sigue debiendo remuneración, el pago por tercero no convierte sin más al trabajador en deudor de Saly.","Si hay préstamo distinto, identificar en contrato prestatario y prestamista, condiciones y titularidad.","Titularidad real de la cartera, responsabilidades por planilla y riesgos no pueden declararse resueltos sin contratos concretos."],"context_saly":["SALY-DEC-002 autofondeo vs externo","SALY-DEC-007 se fondea capital recibido","SALY-DEC-013 empleador aporta capital","SALY-DEC-014 línea por lotes","SALY-EVD-003 flujo histórico S/50 con descuento por planilla"],"open_for_c2":["Trazar cuatro flujos: empleador fondea / Saly adelanta / institución fondea / cesión efectiva","Identificar documentos habilitantes y autorización de descuentos","No presuponer titularidad del margen/comisión ni cesión salarial","Separar riesgo de crédito vs riesgo operacional vs riesgo empresa"],"confidence":"ALTA en marco del Código Civil; MEDIA en arquitectura concreta hasta contratos","legal_authorization":false}'::jsonb,'VIGENTE')
ON CONFLICT (codigo) DO NOTHING;

DO $apply$
DECLARE v_total integer; v_inserted integer; 
BEGIN
 SELECT count(*) INTO v_total FROM saly.evidencias WHERE codigo IN ('SALY-EVD-LEG-01-C1','SALY-EVD-LEG-02-C1');
 IF v_total<>2 THEN RAISE EXCEPTION 'BLOCK_SALY_LEGAL_EVIDENCE_COUNT'; END IF;
 UPDATE saly.checkpoints_investigacion c
 SET estado='DONE', dictamen_revision='PASS',
 evidencia_principal_id=e.id, ejecutor_ref='GPT_NATIVE_SALY_LEGAL_C1_20261015',
 nota_revision='PASS exclusivo de C1: fuentes normativas oficiales y aplicabilidad inicial contrastadas; no es habilitación legal, no es revisión independiente C3.',
 completado_en=now(), actualizado_en=now()
 FROM saly.unidades_investigacion u, saly.programas_investigacion p, saly.evidencias e
 WHERE c.unidad_id=u.id AND u.programa_id=p.id AND p.codigo='SALY_FONDEO_LEGAL'
 AND c.codigo='C1' AND c.estado='PENDIENTE'
 AND ((u.codigo='SALY-LEG-01' AND e.codigo='SALY-EVD-LEG-01-C1') OR (u.codigo='SALY-LEG-02' AND e.codigo='SALY-EVD-LEG-02-C1'));
 GET DIAGNOSTICS v_inserted=ROW_COUNT;
 IF v_inserted<>2 THEN RAISE EXCEPTION 'BLOCK_SALY_C1_UPDATE_COUNT: %',v_inserted; END IF;
END $apply$;

INSERT INTO saly.checkpoint_evidencias(checkpoint_id,evidencia_id,tipo_relacion)
SELECT c.id,e.id,'SUSTENTA'
FROM saly.checkpoints_investigacion c
JOIN saly.unidades_investigacion u ON u.id=c.unidad_id
JOIN saly.programas_investigacion p ON p.id=u.programa_id
JOIN saly.evidencias e ON (u.codigo='SALY-LEG-01' AND e.codigo='SALY-EVD-LEG-01-C1') OR (u.codigo='SALY-LEG-02' AND e.codigo='SALY-EVD-LEG-02-C1')
WHERE p.codigo='SALY_FONDEO_LEGAL' AND c.codigo='C1'
ON CONFLICT DO NOTHING;

UPDATE saly.programas_investigacion
SET estado='ACTIVO', actualizado_en=now()
WHERE codigo='SALY_FONDEO_LEGAL' AND estado='PLANIFICADO';

DO $verify$
BEGIN
 IF (SELECT count(*) FROM saly.checkpoints_investigacion c JOIN saly.unidades_investigacion u ON u.id=c.unidad_id JOIN saly.programas_investigacion p ON p.id=u.programa_id WHERE p.codigo='SALY_FONDEO_LEGAL' AND u.codigo IN ('SALY-LEG-01','SALY-LEG-02') AND c.codigo='C1' AND c.estado='DONE' AND c.dictamen_revision='PASS' AND c.evidencia_principal_id IS NOT NULL) <>2
 OR (SELECT count(*) FROM saly.checkpoints_investigacion c JOIN saly.unidades_investigacion u ON u.id=c.unidad_id JOIN saly.programas_investigacion p ON p.id=u.programa_id WHERE p.codigo='SALY_FONDEO_LEGAL' AND c.estado='DONE') <>2
 OR (SELECT count(*) FROM saly.checkpoint_evidencias ce JOIN saly.checkpoints_investigacion c ON c.id=ce.checkpoint_id JOIN saly.unidades_investigacion u ON u.id=c.unidad_id JOIN saly.programas_investigacion p ON p.id=u.programa_id WHERE p.codigo='SALY_FONDEO_LEGAL' AND c.codigo='C1') <>2
 THEN RAISE EXCEPTION 'BLOCK_SALY_C1_EVIDENCE_OR_STATUS_COUNT'; END IF;
END $verify$;
COMMIT;
