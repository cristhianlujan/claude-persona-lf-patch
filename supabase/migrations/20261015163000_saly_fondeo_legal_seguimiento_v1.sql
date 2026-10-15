-- SALY_FONDEO_LEGAL | SOLO esquema saly; ninguna mutación sobre LF o programacion.
-- Transporte: Migration Merge Train del proyecto Supabase existente.
-- Objetivo: 1 programa, 16 unidades, 48 checkpoints C1/C2/C3 y 54 dependencias.
BEGIN;
DO $$ BEGIN
 IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001') <> 1
 THEN RAISE EXCEPTION 'BLOCK_SALY_PROJECT_MISSING'; END IF;
END $$;

CREATE TABLE IF NOT EXISTS saly.programas_investigacion (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 proyecto_id bigint NOT NULL REFERENCES saly.proyecto(id) ON DELETE RESTRICT,
 codigo text NOT NULL UNIQUE,
 nombre text NOT NULL,
 proposito text NOT NULL,
 metodologia text NOT NULL DEFAULT 'C1_C2_C3' CHECK (metodologia='C1_C2_C3'),
 estado text NOT NULL DEFAULT 'PLANIFICADO' CHECK (estado IN ('PLANIFICADO','ACTIVO','PAUSADO','CERRADO')),
 creado_en timestamptz NOT NULL DEFAULT now(),
 actualizado_en timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS saly.unidades_investigacion (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 programa_id bigint NOT NULL REFERENCES saly.programas_investigacion(id) ON DELETE RESTRICT,
 codigo text NOT NULL UNIQUE,
 orden integer NOT NULL CHECK(orden>0),
 lote integer NOT NULL CHECK(lote BETWEEN 1 AND 4),
 titulo text NOT NULL,
 pregunta text NOT NULL,
 criterio_salida text NOT NULL,
 estado_trabajo text NOT NULL DEFAULT 'PENDIENTE' CHECK (estado_trabajo IN ('PENDIENTE','EN_CURSO','BLOQUEADO')),
 resultado_legal text CHECK (resultado_legal IN ('APTO','CONDICIONADO','NO_APTO')),
 razonamiento text,
 creado_en timestamptz NOT NULL DEFAULT now(),
 actualizado_en timestamptz NOT NULL DEFAULT now(),
 UNIQUE(programa_id,orden)
);
CREATE TABLE IF NOT EXISTS saly.checkpoints_investigacion (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 unidad_id bigint NOT NULL REFERENCES saly.unidades_investigacion(id) ON DELETE RESTRICT,
 codigo text NOT NULL CHECK(codigo IN ('C1','C2','C3')),
 titulo text NOT NULL,
 criterio text NOT NULL,
 estado text NOT NULL DEFAULT 'PENDIENTE' CHECK(estado IN ('PENDIENTE','EN_CURSO','BLOQUEADO','DONE')),
 dictamen_revision text CHECK(dictamen_revision IN ('PASS','FAIL','NEED_MORE_EVIDENCE')),
 evidencia_principal_id bigint REFERENCES saly.evidencias(id) ON DELETE RESTRICT,
 ejecutor_ref text,
 revisor_ref text,
 independencia_verificada boolean NOT NULL DEFAULT false,
 nota_revision text,
 completado_en timestamptz,
 creado_en timestamptz NOT NULL DEFAULT now(),
 actualizado_en timestamptz NOT NULL DEFAULT now(),
 UNIQUE(unidad_id,codigo),
 CONSTRAINT checkpoint_done_requires_evidence CHECK (
   estado <> 'DONE' OR (dictamen_revision='PASS' AND evidencia_principal_id IS NOT NULL AND completado_en IS NOT NULL)
 ),
 CONSTRAINT checkpoint_c3_requires_independence CHECK (
   estado <> 'DONE' OR codigo <> 'C3' OR
   (independencia_verificada AND NULLIF(btrim(revisor_ref),'') IS NOT NULL
    AND NULLIF(btrim(ejecutor_ref),'') IS NOT NULL AND revisor_ref<>ejecutor_ref)
 )
);
CREATE TABLE IF NOT EXISTS saly.unidades_dependencias (
 unidad_id bigint NOT NULL REFERENCES saly.unidades_investigacion(id) ON DELETE RESTRICT,
 depende_de_unidad_id bigint NOT NULL REFERENCES saly.unidades_investigacion(id) ON DELETE RESTRICT,
 motivo text NOT NULL DEFAULT 'Dependencia de investigación',
 PRIMARY KEY(unidad_id,depende_de_unidad_id),
 CHECK(unidad_id <> depende_de_unidad_id)
);
CREATE TABLE IF NOT EXISTS saly.checkpoint_evidencias (
 checkpoint_id bigint NOT NULL REFERENCES saly.checkpoints_investigacion(id) ON DELETE RESTRICT,
 evidencia_id bigint NOT NULL REFERENCES saly.evidencias(id) ON DELETE RESTRICT,
 tipo_relacion text NOT NULL DEFAULT 'SUSTENTA',
 PRIMARY KEY(checkpoint_id,evidencia_id)
);
ALTER TABLE saly.programas_investigacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.unidades_investigacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.checkpoints_investigacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.unidades_dependencias ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.checkpoint_evidencias ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE VIEW saly.v_investigacion_unidades_progreso WITH (security_invoker=true) AS
SELECT p.codigo AS programa,u.codigo AS unidad,u.lote,u.orden,u.titulo,
 u.estado_trabajo,u.resultado_legal,
 count(c.id)::integer AS checkpoints_presentes,
 count(c.id) FILTER(WHERE c.estado='DONE')::integer AS checkpoints_verificados,
 CASE WHEN count(c.id)=3 AND count(c.id) FILTER(WHERE c.estado='DONE')=3
 THEN 'CERRADA' ELSE u.estado_trabajo END AS estado_verificado,
 round(100.0 * count(c.id) FILTER(WHERE c.estado='DONE') / 3,1) AS avance_pct
FROM saly.unidades_investigacion u
JOIN saly.programas_investigacion p ON p.id=u.programa_id
LEFT JOIN saly.checkpoints_investigacion c ON c.unidad_id=u.id
GROUP BY p.codigo,u.codigo,u.lote,u.orden,u.titulo,u.estado_trabajo,u.resultado_legal;

CREATE OR REPLACE VIEW saly.v_investigacion_programas_progreso WITH (security_invoker=true) AS
SELECT programa,count(*)::integer AS unidades,
 sum(checkpoints_presentes)::integer AS checkpoints,
 sum(checkpoints_verificados)::integer AS checkpoints_verificados,
 count(*) FILTER(WHERE estado_verificado='CERRADA')::integer AS unidades_cerradas,
 round(100.0*sum(checkpoints_verificados)/NULLIF(3*count(*),0),1) AS avance_pct
FROM saly.v_investigacion_unidades_progreso GROUP BY programa;

INSERT INTO saly.programas_investigacion (proyecto_id,codigo,nombre,proposito)
SELECT id,'SALY_FONDEO_LEGAL','Saly — Investigación jurídica de fondeo',
 'Verificar viabilidad de fondeo empresarial, institucional, SAFI, FPF y emisiones para adelantos de nómina'
FROM saly.proyecto WHERE codigo='SALY-001'
ON CONFLICT(codigo) DO NOTHING;

INSERT INTO saly.unidades_investigacion (programa_id,codigo,orden,lote,titulo,pregunta,criterio_salida)
SELECT p.id,v.codigo,v.orden,v.lote,v.titulo,v.pregunta,v.criterio_salida
FROM saly.programas_investigacion p CROSS JOIN (VALUES
('SALY-LEG-01',1,1,'Naturaleza jurídica del adelanto','Determinar si el adelanto devengado y Saly Plus constituyen anticipo laboral, crédito u otra figura.','Clasificación jurídica por producto y supuestos documentados.'),
('SALY-LEG-02',2,1,'Obligaciones y actores','Identificar quién debe, desembolsa, cobra y soporta riesgo.','Mapa de obligaciones, titularidad y flujos de pago.'),
('SALY-LEG-03',3,1,'Captación de dinero y SBS','Determinar cuándo el fondeo configura captación regulada.','Restricciones y habilitaciones por fuente de recursos.'),
('SALY-LEG-04',4,1,'Derecho laboral y descuentos','Examinar autorizaciones, descuentos por planilla y límites.','Matriz laboral de cobros y deducciones permitidas.'),
('SALY-LEG-05',5,2,'Autofondeo empresarial','Analizar fondeo propio del empleador y la operación con Saly.','Flujo contractual y responsabilidades del empleador.'),
('SALY-LEG-06',6,2,'Fondeo institucional','Analizar líneas de crédito, préstamo y financiación de cartera.','Alternativas contractuales de financiamiento institucional.'),
('SALY-LEG-07',7,2,'SAFI y fondos','Analizar régimen SAFI, modalidades de fondo y activos elegibles.','Matriz de fondos y elegibilidad de activos asociados a Saly.'),
('SALY-LEG-08',8,3,'Cesión de derechos y cartera','Definir derechos de cobro transferibles y formalidades.','Flujo de transferencia, condiciones de oponibilidad y cobranza.'),
('SALY-LEG-09',9,2,'Crowdlending','Analizar régimen FPF, receptor y destino lícito de fondos.','Modelos directos viables y estructuras excluidas.'),
('SALY-LEG-10',10,2,'Bonos e instrumentos de deuda','Determinar régimen de emisión, colocación y destino de recursos.','Matriz de instrumentos, inversionistas y restricciones.'),
('SALY-LEG-11',11,3,'Inversión de personas naturales','Analizar elegibilidad, divulgación y selección de empresa.','Modelos de acceso minorista y límites legales.'),
('SALY-LEG-12',12,3,'Contratos y recuperación','Analizar contratos, garantías, incumplimiento y recuperación.','Mapa contractual y matriz de escenarios de impago.'),
('SALY-LEG-13',13,3,'Tributación y cumplimiento','Analizar impuestos, contabilidad, KYC/PLAFT y privacidad.','Obligaciones normativas y responsables por ruta.'),
('SALY-LEG-14',14,3,'Custodia y flujo de fondos','Analizar segregación, custodia, pagos y conciliación.','Flujos de fondos verificables y puntos de control.'),
('SALY-LEG-15',15,3,'Rentabilidad y emisiones','Analizar tasas fijas o variables y sus modificaciones.','Contrato económico y matriz de divulgación por emisión.'),
('SALY-LEG-16',16,4,'Habilitación jurídica por ruta','Integrar evidencia y evaluar viabilidad de cada estructura.','Dictamen consolidado APTO / CONDICIONADO / NO APTO con pendientes.')
) v(codigo,orden,lote,titulo,pregunta,criterio_salida)
WHERE p.codigo='SALY_FONDEO_LEGAL'
ON CONFLICT(codigo) DO NOTHING;

INSERT INTO saly.checkpoints_investigacion(unidad_id,codigo,titulo,criterio)
SELECT u.id,c.codigo,c.titulo,c.criterio
FROM saly.unidades_investigacion u
JOIN saly.programas_investigacion p ON p.id=u.programa_id
CROSS JOIN (VALUES
('C1','Investigación normativa','Fuente oficial vigente, alcance de la norma y vigencia verificados.'),
('C2','Análisis aplicado a SALY','Flujos, contratos, alternativas, restricciones y riesgos sustentados.'),
('C3','Validación independiente','Revisor distinto, evidencia contrastada y dictamen explícito PASS.')
) c(codigo,titulo,criterio)
WHERE p.codigo='SALY_FONDEO_LEGAL'
ON CONFLICT(unidad_id,codigo) DO NOTHING;

INSERT INTO saly.unidades_dependencias(unidad_id,depende_de_unidad_id)
SELECT u.id,dep.id
FROM (VALUES
('SALY-LEG-05','SALY-LEG-01'),
('SALY-LEG-05','SALY-LEG-02'),
('SALY-LEG-05','SALY-LEG-04'),
('SALY-LEG-06','SALY-LEG-01'),
('SALY-LEG-06','SALY-LEG-02'),
('SALY-LEG-06','SALY-LEG-03'),
('SALY-LEG-07','SALY-LEG-02'),
('SALY-LEG-07','SALY-LEG-03'),
('SALY-LEG-08','SALY-LEG-01'),
('SALY-LEG-08','SALY-LEG-02'),
('SALY-LEG-08','SALY-LEG-07'),
('SALY-LEG-09','SALY-LEG-01'),
('SALY-LEG-09','SALY-LEG-02'),
('SALY-LEG-09','SALY-LEG-03'),
('SALY-LEG-10','SALY-LEG-02'),
('SALY-LEG-10','SALY-LEG-03'),
('SALY-LEG-11','SALY-LEG-03'),
('SALY-LEG-11','SALY-LEG-07'),
('SALY-LEG-11','SALY-LEG-09'),
('SALY-LEG-11','SALY-LEG-10'),
('SALY-LEG-12','SALY-LEG-02'),
('SALY-LEG-12','SALY-LEG-04'),
('SALY-LEG-12','SALY-LEG-08'),
('SALY-LEG-12','SALY-LEG-09'),
('SALY-LEG-13','SALY-LEG-03'),
('SALY-LEG-13','SALY-LEG-05'),
('SALY-LEG-13','SALY-LEG-06'),
('SALY-LEG-13','SALY-LEG-07'),
('SALY-LEG-13','SALY-LEG-09'),
('SALY-LEG-13','SALY-LEG-10'),
('SALY-LEG-14','SALY-LEG-02'),
('SALY-LEG-14','SALY-LEG-05'),
('SALY-LEG-14','SALY-LEG-06'),
('SALY-LEG-14','SALY-LEG-07'),
('SALY-LEG-14','SALY-LEG-09'),
('SALY-LEG-15','SALY-LEG-07'),
('SALY-LEG-15','SALY-LEG-09'),
('SALY-LEG-15','SALY-LEG-10'),
('SALY-LEG-15','SALY-LEG-11'),
('SALY-LEG-16','SALY-LEG-01'),
('SALY-LEG-16','SALY-LEG-02'),
('SALY-LEG-16','SALY-LEG-03'),
('SALY-LEG-16','SALY-LEG-04'),
('SALY-LEG-16','SALY-LEG-05'),
('SALY-LEG-16','SALY-LEG-06'),
('SALY-LEG-16','SALY-LEG-07'),
('SALY-LEG-16','SALY-LEG-08'),
('SALY-LEG-16','SALY-LEG-09'),
('SALY-LEG-16','SALY-LEG-10'),
('SALY-LEG-16','SALY-LEG-11'),
('SALY-LEG-16','SALY-LEG-12'),
('SALY-LEG-16','SALY-LEG-13'),
('SALY-LEG-16','SALY-LEG-14'),
('SALY-LEG-16','SALY-LEG-15')
) x(unidad_codigo,prerrequisito_codigo)
JOIN saly.unidades_investigacion u ON u.codigo=x.unidad_codigo
JOIN saly.unidades_investigacion dep ON dep.codigo=x.prerrequisito_codigo
JOIN saly.programas_investigacion p ON p.id=u.programa_id
WHERE p.codigo='SALY_FONDEO_LEGAL' AND dep.programa_id=p.id
ON CONFLICT DO NOTHING;

DO $$ BEGIN
IF (SELECT count(*) FROM saly.programas_investigacion WHERE codigo='SALY_FONDEO_LEGAL') <> 1
 OR (SELECT count(*) FROM saly.unidades_investigacion u JOIN saly.programas_investigacion p ON p.id=u.programa_id WHERE p.codigo='SALY_FONDEO_LEGAL') <> 16
 OR (SELECT count(*) FROM saly.checkpoints_investigacion c JOIN saly.unidades_investigacion u ON u.id=c.unidad_id JOIN saly.programas_investigacion p ON p.id=u.programa_id WHERE p.codigo='SALY_FONDEO_LEGAL') <> 48
 OR (SELECT count(*) FROM saly.unidades_dependencias d JOIN saly.unidades_investigacion u ON u.id=d.unidad_id JOIN saly.programas_investigacion p ON p.id=u.programa_id WHERE p.codigo='SALY_FONDEO_LEGAL') <> 54
 THEN RAISE EXCEPTION 'BLOCK_SALY_FONDEO_COUNTS'; END IF;
END $$;
COMMIT;
