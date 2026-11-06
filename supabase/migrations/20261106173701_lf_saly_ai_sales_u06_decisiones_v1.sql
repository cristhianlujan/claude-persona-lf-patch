-- CANDIDATO SALY-001 / AI_SALES_3_0 / U06.
-- Registro de decisiones y evidencia, sin activar canales ni cerrar checkpoints.
-- SOLO mediante ACTUALIZACION_DB_LF -> Merge Train gobernado; nunca consola directa.
BEGIN;
DO $preflight$ BEGIN
 IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001') <> 1
 THEN RAISE EXCEPTION 'BLOCK_SALY_PROJECT_AUTHORITY'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints c
     JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
     WHERE u.plan_code='AI_SALES_3_0' AND u.unit_code='U06'
       AND c.checkpoint_code IN ('U06-C01','U06-C02','U06-C03','U06-C04','U06-C05','U06-C06','U06-C07','U06-C08','U06-C09')
       AND c.status='PENDING') <> 9
 THEN RAISE EXCEPTION 'BLOCK_SALY_U06_CHECKPOINT_DRIFT'; END IF;
 IF EXISTS (SELECT 1 FROM saly.evidencias WHERE codigo='SALY-AIS30-U06-EVD-001')
 OR EXISTS (SELECT 1 FROM saly.decisiones WHERE codigo IN
     ('SALY-AIS30-U06-DEC-001','SALY-AIS30-U06-DEC-002','SALY-AIS30-U06-DEC-003'))
 THEN RAISE EXCEPTION 'BLOCK_SALY_U06_DUPLICATE'; END IF;
END $preflight$;

INSERT INTO saly.evidencias (codigo,tipo,titulo,descripcion,referencia,fecha_evidencia,hechos,estado) VALUES (
 'SALY-AIS30-U06-EVD-001','DECISION_USUARIO_Y_REVISION_DOCUMENTAL',
 'AI Sales 3.0 — alternativas de LinkedIn y señales sociales para SALY',
 'Opciones aprobadas para investigación: Sales Navigator con búsqueda y alertas permitidas; registro manual mínimo en hoja; corroboración por fuentes autorizadas y análisis de señales profesionales públicas de empresas. No se ha demostrado exportación masiva autorizada, acceso a APIs, integración CRM ni envío automático.',
 'Conversación del proyecto Saly - Ventas, 2026-11-05; plan GitHub v0.8 commit 9784adf03a3e2a0f5eeb0426e99b4aac57c885ec',
 DATE '2026-11-05',
 '{"project":"SALY-001","plan":"AI_SALES_3_0","unit":"U06","source_kind":"CHAT_PLUS_DOCUMENTARY_ANALYSIS","source_plan_sha":"9784adf03a3e2a0f5eeb0426e99b4aac57c885ec","checkpoints":["U06-C01","U06-C02","U06-C04","U06-C06","U06-C07","U06-C08","U06-C09"],"restrictions":["no_unauthorized_scraping","no_unverified_bulk_export","no_automatic_messaging","source_terms_and_privacy_check","no_unverified_consumers"],"runtime_verified":false,"official_checkpoint_status_changed":false}'::jsonb,
 'REFERENCIAL'
);
INSERT INTO saly.decisiones (codigo,categoria,titulo,decision,estado,evidencia_nivel,vigente,notas,metadata)
VALUES
('SALY-AIS30-U06-DEC-001','AI_SALES_SOCIAL_SELLING','U06 — prospección asistida permitida',
 'Evaluar búsquedas y alertas oficiales de Sales Navigator, registro manual mínimo a Excel/CSV cuando esté permitido y CRM Sync solo si el plan y CRM son compatibles. Verificar cada vía antes de conectar; no presuponer descarga masiva.',
 'PROPUESTA','CHAT',true,'Diseño acordado, no integración ejecutada.',
 '{"project":"SALY-001","plan":"AI_SALES_3_0","unit":"U06","checkpoints":["U06-C01","U06-C02","U06-C08"],"evidence_code":"SALY-AIS30-U06-EVD-001","implementation_status":"NOT_VERIFIED"}'::jsonb),
('SALY-AIS30-U06-DEC-002','AI_SALES_SOCIAL_SIGNALS','U06 — señales profesionales corporativas',
 'Evaluar actividad y publicaciones profesionales a las que pueda accederse legítimamente, vinculando empresa, cargo, fuente, fecha, señal y corroboración. Una publicación no prueba intención de compra, necesidad financiera ni potestad para contratar.',
 'PROPUESTA','CHAT',true,'Sin scraping prohibido, perfiles sensibles ni envío automático.',
 '{"project":"SALY-001","plan":"AI_SALES_3_0","unit":"U06","checkpoints":["U06-C06","U06-C07","U06-C08"],"evidence_code":"SALY-AIS30-U06-EVD-001","implementation_status":"NOT_VERIFIED"}'::jsonb),
('SALY-AIS30-U06-DEC-003','AI_SALES_GOVERNANCE','U06 — responsabilidades y trazabilidad',
 'U06 registra señales sociales; U02 resuelve identidad y CRM; U03 verifica afirmaciones; U07 califica ICP; U11 mide atribución. No crear productores, ejecutores, consumidores, revisores independientes ni pruebas no demostradas para satisfacer un checkpoint. Mantener PENDING oficiales.',
 'PROPUESTA','CHAT',true,'Sin nuevos motores ni ZIP, transporte gobernado y readback obligatorio.',
 '{"project":"SALY-001","plan":"AI_SALES_3_0","unit":"U06","checkpoints":["U06-C02","U06-C04","U06-C06","U06-C07","U06-C08","U06-C09"],"evidence_code":"SALY-AIS30-U06-EVD-001","implementation_status":"NOT_VERIFIED"}'::jsonb);

DO $readback$ BEGIN
 IF (SELECT count(*) FROM saly.evidencias WHERE codigo='SALY-AIS30-U06-EVD-001'
       AND hechos->>'project'='SALY-001' AND hechos->>'plan'='AI_SALES_3_0'
       AND estado='REFERENCIAL') <> 1
 OR (SELECT count(*) FROM saly.decisiones WHERE codigo IN
      ('SALY-AIS30-U06-DEC-001','SALY-AIS30-U06-DEC-002','SALY-AIS30-U06-DEC-003')
      AND estado='PROPUESTA' AND metadata->>'project'='SALY-001'
      AND metadata->>'evidence_code'='SALY-AIS30-U06-EVD-001') <> 3
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
     JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
     WHERE u.plan_code='AI_SALES_3_0' AND u.unit_code='U06' AND c.status='PENDING') <> 9
 THEN RAISE EXCEPTION 'BLOCK_SALY_U06_READBACK'; END IF;
END $readback$;
COMMIT;
