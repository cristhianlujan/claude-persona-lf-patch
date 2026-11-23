-- SALY Planeamiento. Solo EKB de alcance visual; no define nuevos estados ni altera procesos.
INSERT INTO transversal.error_knowledge (
 codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,lote_origen,estado,evidencia,lifecycle_phase,
 consumer_role,root_cause_family,detectability,source_context,source_ref
) VALUES (
 'SALY-SEGUIMIENTO-EN-PROCESO-PANTALLA-INCIDENCIA-20261123-001',
 'SALY_PROCESOS_HALLAZGO',
 'Pantalla citada para En proceso representa incidencia de tarjeta bloqueada',
 'Claude transmitio que la pantalla referencial de En proceso es SALY_SEGUIMIENTO_INCIDENCIA_IPHONE16PRO_v1.4.png; su contenido visual presenta Solicitud confirmada, Intento de abono no completado, tarjeta bloqueada y Proximo procesamiento. Ese caso ilustrativo no define el catalogo general de estados ni la respuesta a un fallo en SQS.',
 'El artefacto de ejemplo de incidencia fue citado tambien como referencia de En proceso sin equivalencia funcional acreditada.',
 'Referencia visual particular interpretada como definicion universal del estado de solicitud.',
 'Preservar ambos hechos en la extraccion: referencia de pantalla citada y naturaleza ilustrativa de incidencia; no derivar estados o transiciones del ejemplo.',
 'Comprobar que el inventario no equipara la pantalla de tarjeta bloqueada con todos los casos En proceso, y mantiene VACIO el catalogo de estados y el manejo de fallo en cola.',
 'LOW',1,'SALY_PLANEAMIENTO_EXTRACCION_B2C_20261123','ACTIVO',
 'Fuente: instruccion Claude->GPT 2026-11-23 12:25 Lima y pantalla SALY_SEGUIMIENTO_INCIDENCIA_IPHONE16PRO_v1.4.png en Drive.',
 'DESIGN',ARRAY['PROGRAMADOR','PRODUCTO'],
 'R2_NO_VE','PROCESS_DEPENDENT',
 'SALY Planeamiento; extraccion Solicitud y Seguimiento B2C',
 'https://drive.google.com/file/d/1mxhNYTHnoPuabvNEyzXRmmX1wxElJCb4/view'
)
ON CONFLICT (codigo) DO UPDATE
SET frecuencia=transversal.error_knowledge.frecuencia+1,ultima_vez=now(),updated_at=now();

DO $qa$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM transversal.error_knowledge
   WHERE codigo='SALY-SEGUIMIENTO-EN-PROCESO-PANTALLA-INCIDENCIA-20261123-001'
     AND frecuencia>=1 AND estado='ACTIVO') THEN
   RAISE EXCEPTION 'SALY_SEGUIMIENTO_HALLAZGO_EKB_MISSING';
 END IF;
 RAISE NOTICE 'SALY_SEGUIMIENTO_HALLAZGO_EKB_PASS';
END $qa$;
