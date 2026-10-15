-- SALY-only business-premise correction; no LF mutation, no change to DONE verdicts.
BEGIN;
DO $guard$ BEGIN
 IF (SELECT count(*) FROM saly.programas_investigacion p JOIN saly.proyecto q ON q.id=p.proyecto_id WHERE p.codigo='SALY_FONDEO_LEGAL' AND q.codigo='SALY-001')<>1
 THEN RAISE EXCEPTION 'BLOCK_SALY_PROJECT_AUTHORITY'; END IF;
 IF (SELECT count(*) FROM saly.checkpoints_investigacion c JOIN saly.unidades_investigacion u ON u.id=c.unidad_id JOIN saly.programas_investigacion p ON p.id=u.programa_id WHERE p.codigo='SALY_FONDEO_LEGAL' AND u.codigo IN ('SALY-LEG-01','SALY-LEG-02','SALY-LEG-05') AND c.codigo='C2' AND c.estado='PENDIENTE')<>3
 THEN RAISE EXCEPTION 'BLOCK_SALY_C2_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM saly.evidencias WHERE codigo='SALY-EVD-FONDEO-PRESTAMO-PLANILLA-20261015')
 OR EXISTS(SELECT 1 FROM saly.decisiones WHERE codigo='SALY-DEC-FONDEO-PRESTAMO-PLANILLA-20261015')
 THEN RAISE EXCEPTION 'BLOCK_SALY_PREMISE_ALREADY_EXISTS'; END IF;
END $guard$;

INSERT INTO saly.evidencias(codigo,tipo,titulo,descripcion,referencia,fecha_evidencia,hechos,estado)
VALUES('SALY-EVD-FONDEO-PRESTAMO-PLANILLA-20261015','DECLARACION_MODELO_USUARIO',
 'Aclaración operativa Tu Sueldo Ya: préstamo y descuento de planilla',
 'Aclaración del usuario: Tu Sueldo Ya desembolsa financiación similar a préstamo y la recuperación se pacta por convenio y autorización de planilla del trabajador; no es el empleador pagando remuneración devengada a través de Saly. Evaluar para SALY empresa prestamista/Saly mandatario versus empresa fondeadora/Saly prestamista; sin presuponer licencia, validez irrestricta del descuento ni tratamiento tributario.','Declaración del usuario, conversación SALY Fondeo, 2026-10-15',
 DATE '2026-10-15','{"schema":"saly-business-premise/v1","project":"SALY","program":"SALY_FONDEO_LEGAL","source":"DECLARACION_USUARIO_2026-10-15","historical_service":"Tu Sueldo Ya","target_under_study":"Saly","documentary_confirmation":"PENDING","facts_from_user":["Tu Sueldo Ya desembolsa dinero al trabajador bajo un servicio parecido a un préstamo y genera obligación de repago; no paga por cuenta del empleador una remuneración ya exigible.","Tu Sueldo Ya y el empleador tienen un convenio; mediante él se practica la recuperación de operaciones mediante descuentos en planilla.","En el alta, el trabajador acepta condiciones contractuales y autorización para descuentos de sus operaciones.","La operación descrita ha existido en Tu Sueldo Ya; el diseño de Saly debe partir de ese antecedente sin presumir que todos sus contratos están jurídicamente validados."],"routes_to_assess":[{"route":"A","employer":"prestamista/acreedor eventual","saly":"mandatario, operador y administrador sin ser el prestamista","payroll":"empleador descuenta autorizado dentro de límites"},{"route":"B","employer":"fondeador de Saly mediante préstamo/línea o estructura a definir","saly":"prestamista/acreedor de empleados beneficiarios","payroll":"empleador descuenta por autorización y convenios"},{"route":"B1","employer":"fondo propiedad empleador y mandante","saly":"custodio/gestor por cuenta ajena, sujeto a segregación, mandato y derecho aplicable","payroll":"requiere autorización"}],"questions_for_checkpoints":["Quién es acreedor, qué contratos sustentan cada desembolso, y cómo se acredita autorización de descuento por cada operación.","Límites constitucionales de remuneración y descuentos (STC 02275-2023-PA/TC; art 648.6 CPC), incluso cuando exista consentimiento.","Permisos y registro SBS para prestamista habitual con fondos propios versus empleador que presta incidentalmente.","Naturaleza y fiscalidad del rendimiento/interés/comisión (SUNAT Informe 000055-2025).","Efectos de liquidación, renuncia, salario insuficiente, impagos, disputa y retiro de consentimiento.","Si el empleador puede mantenerse como simple fondeador sin ser prestamista habitual, y quién soporta riesgo crediticio."],"legal_characterization":"HYPOTHESIS_SUBJECT_TO_C2_C3","business_fact_not_formal_legal_opinion":true}'::jsonb,'VIGENTE');

INSERT INTO saly.decisiones(codigo,categoria,titulo,decision,estado,evidencia_nivel,vigente,notas,metadata)
VALUES('SALY-DEC-FONDEO-PRESTAMO-PLANILLA-20261015','AUTOFONDEO',
 'Premisa contractual para evaluar autofondeo empresarial',
 'Modelo descrito de Tu Sueldo Ya: desembolso de financiación semejante a préstamo al trabajador, compromiso de repago mediante descuento de planilla autorizado en alta y operado bajo convenio con la empresa. Investigar en Saly ruta A (empresa acreedora, Saly operador) versus ruta B (empresa financia, Saly acreedora de empleados), y diferenciar custodia bajo mandato B1. El salario es mecanismo de recuperación, no remuneración pagada por adelantado por Saly.',
 'PROPUESTA','CHAT',true,
 'Premisa comercial y operativa del usuario; requiere revisar convenios, términos del trabajador, límites de deducción, SBS, SUNAT y dictamen C2/C3. No es autorización legal.',
 '{"project":"SALY","program":"SALY_FONDEO_LEGAL","evidence_code":"SALY-EVD-FONDEO-PRESTAMO-PLANILLA-20261015","units":["SALY-LEG-01","SALY-LEG-02","SALY-LEG-04","SALY-LEG-05","SALY-LEG-13"],"formal_legal_validation":false,"references":["https://www.tc.gob.pe/jurisprudencia/2025/02275-2023-AA.html","https://www.sbs.gob.pe/supervisados-y-registros/registros/otros-registros/casas-de-cambio-prestamos-y-empenos/informacion-sobre-registro-de-casas-de-cambio-prestamos-y-o-empenos","https://www.sunat.gob.pe/legislacion/oficios/2025/indcor.htm"]}'::jsonb);

INSERT INTO saly.checkpoint_evidencias(checkpoint_id,evidencia_id,tipo_relacion)
SELECT c.id,e.id,'CONTEXTO_C2_PENDIENTE'
FROM saly.checkpoints_investigacion c
JOIN saly.unidades_investigacion u ON u.id=c.unidad_id
JOIN saly.programas_investigacion p ON p.id=u.programa_id
JOIN saly.evidencias e ON e.codigo='SALY-EVD-FONDEO-PRESTAMO-PLANILLA-20261015'
WHERE p.codigo='SALY_FONDEO_LEGAL' AND u.codigo IN ('SALY-LEG-01','SALY-LEG-02','SALY-LEG-05') AND c.codigo='C2';

DO $readback$ BEGIN
 IF (SELECT count(*) FROM saly.evidencias WHERE codigo='SALY-EVD-FONDEO-PRESTAMO-PLANILLA-20261015' AND hechos->>'source'='DECLARACION_USUARIO_2026-10-15')<>1
 OR (SELECT count(*) FROM saly.decisiones WHERE codigo='SALY-DEC-FONDEO-PRESTAMO-PLANILLA-20261015' AND estado='PROPUESTA' AND evidencia_nivel='CHAT')<>1
 OR (SELECT count(*) FROM saly.checkpoint_evidencias ce JOIN saly.evidencias e ON e.id=ce.evidencia_id WHERE e.codigo='SALY-EVD-FONDEO-PRESTAMO-PLANILLA-20261015')<>3
 OR (SELECT count(*) FROM saly.checkpoints_investigacion c JOIN saly.unidades_investigacion u ON u.id=c.unidad_id JOIN saly.programas_investigacion p ON p.id=u.programa_id WHERE p.codigo='SALY_FONDEO_LEGAL' AND c.estado='DONE')<>2
 THEN RAISE EXCEPTION 'BLOCK_SALY_PREMISE_READBACK'; END IF;
END $readback$;
COMMIT;
