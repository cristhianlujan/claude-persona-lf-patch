-- SALY-001 / AI_SALES_3_0 / U07: Google Places API (New) is a PLAN CANDIDATE only.
-- No API integration, spend, scraping, outbound activation, checkpoint closure or runtime changes.
-- Apply exclusively through governed ACTUALIZACION_DB_LF / LF Migration Merge Train.
BEGIN;
DO $preflight$ BEGIN
  IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001') <> 1
    THEN RAISE EXCEPTION 'BLOCK_SALY_PROJECT_NOT_UNIQUE'; END IF;
  IF (SELECT count(*) FROM programacion.engineering_plan_units
      WHERE plan_code='AI_SALES_3_0' AND unit_code='U07'
        AND unit_metadata->>'scope'='PLAN_ONLY_NO_EXECUTION') <> 1
    THEN RAISE EXCEPTION 'BLOCK_SALY_U07_PLAN_SCOPE_DRIFT'; END IF;
  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints c
      JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
      WHERE u.plan_code='AI_SALES_3_0' AND u.unit_code='U07'
        AND c.checkpoint_code BETWEEN 'U07-C01' AND 'U07-C20'
        AND c.status='PENDING') <> 20
    THEN RAISE EXCEPTION 'BLOCK_SALY_U07_CHECKPOINT_DRIFT'; END IF;
  IF EXISTS (SELECT 1 FROM saly.evidencias WHERE codigo='SALY-AIS30-U07-GPLACES-EVD-001')
     OR EXISTS (SELECT 1 FROM saly.decisiones WHERE codigo='SALY-AIS30-U07-GPLACES-DEC-001')
     OR EXISTS (SELECT 1 FROM programacion.engineering_plan_units
       WHERE plan_code='AI_SALES_3_0' AND unit_code='U07'
         AND unit_metadata ? 'google_places_new_candidate')
    THEN RAISE EXCEPTION 'BLOCK_SALY_U07_GOOGLE_PLACES_DUPLICATE'; END IF;
END $preflight$;

INSERT INTO saly.evidencias
  (codigo,tipo,titulo,descripcion,referencia,fecha_evidencia,hechos,estado)
VALUES
  ('SALY-AIS30-U07-GPLACES-EVD-001','REVISION_DOCUMENTAL_Y_DECISION_USUARIO',
   'U07 — Google Places API (New) como fuente candidata',
   'Google Maps/Places puede descubrir establecimientos por texto, tipo y zona. El proveedor exige control de facturación, cuotas, FieldMask, atribuciones, límites de caché y términos de uso. place_id tiene excepción específica para almacenamiento. No se verificaron credenciales, contrato de licencia para CRM, integración, capacidad de exportación ni costos efectivos.',
   'https://developers.google.com/maps/documentation/places/web-service/policies ; https://developers.google.com/maps/documentation/places/web-service/usage-and-billing ; conversación SALY 2026-11-07',
   DATE '2026-11-07',
   '{"project":"SALY-001","plan":"AI_SALES_3_0","unit":"U07","candidate_source":"GOOGLE_PLACES_API_NEW","checkpoints":["U07-C06","U07-C07","U07-C08","U07-C09","U07-C10"],"evidence_type":"OFFICIAL_DOCUMENTATION_AND_USER_DECISION","integration_tested":false,"license_review_completed":false,"commercial_use_for_crm_approved":false,"billing_authorized":false,"runtime_active":false,"sources":["https://developers.google.com/maps/documentation/places/web-service/policies","https://developers.google.com/maps/documentation/places/web-service/usage-and-billing"]}'::jsonb,
   'REFERENCIAL');

INSERT INTO saly.decisiones
  (codigo,categoria,titulo,decision,estado,evidencia_nivel,vigente,notas,metadata)
VALUES
  ('SALY-AIS30-U07-GPLACES-DEC-001','AI_SALES_DISCOVERY_SOURCES',
   'U07 — incorporar Google Places API (New) como fuente candidata',
   'Incorporar Google Places API (New) al inventario de descubrimiento multifuente de U07. C06: fuente/licencia/cobertura/costo; C07: consultas por categoria, texto y zona con cuotas; C08: place_id para referencia y RUC/razon social para identidad juridica, sin fusion automatica; C09: verificar web/direccion/telefono con fuentes independientes; C10: sedes no equivalen a numero de trabajadores. Requiere validacion contractual sobre usos de datos en CRM, limites de almacenamiento, atribucion, presupuesto y seguridad antes de cualquier activacion.',
   'PROPUESTA','DOCUMENTAL',true,
   'Autorizado agregar al plan; NO autoriza consumo API, compras, scraping, almacenamiento masivo ni contacto automatico.',
   '{"project":"SALY-001","plan":"AI_SALES_3_0","unit":"U07","checkpoints":["U07-C06","U07-C07","U07-C08","U07-C09","U07-C10"],"evidence_code":"SALY-AIS30-U07-GPLACES-EVD-001","candidate_source":"GOOGLE_PLACES_API_NEW","implementation_status":"NOT_IMPLEMENTED","runtime_active":false,"policy_status":"LICENSE_AND_BILLING_REVIEW_REQUIRED"}'::jsonb);

UPDATE programacion.engineering_plan_units
SET unit_metadata=jsonb_set(
    unit_metadata,
    '{google_places_new_candidate}',
    '{"source_code":"GOOGLE_PLACES_API_NEW","status":"CANDIDATE_RESEARCH_ONLY","scope":"PLAN_ONLY_NO_EXECUTION","business":"SALY-001","checkpoint_codes":["U07-C06","U07-C07","U07-C08","U07-C09","U07-C10"],"functions":["TEXT_SEARCH","NEARBY_SEARCH","PLACE_DETAILS"],"constraints":["NO_SCRAPING","TERMS_AND_LICENSE_REVIEW","NO_UNAUTHORIZED_STORAGE_OR_CRM_EXPORT","FIELD_MASK_COST_CONTROL","API_BILLING_AND_QUOTAS_APPROVAL_REQUIRED","GOOGLE_ATTRIBUTION","NO_AUTOMATED_CONTACT","PLACE_ID_NOT_A_LEGAL_ENTITY_KEY","HEADCOUNT_UNKNOWN_WITHOUT_INDEPENDENT_EVIDENCE"],"decision_code":"SALY-AIS30-U07-GPLACES-DEC-001","evidence_code":"SALY-AIS30-U07-GPLACES-EVD-001","runtime_active":false}'::jsonb,
    true)
WHERE plan_code='AI_SALES_3_0' AND unit_code='U07';

DO $readback$ BEGIN
 IF (SELECT count(*) FROM saly.evidencias WHERE codigo='SALY-AIS30-U07-GPLACES-EVD-001' AND estado='REFERENCIAL') <> 1
 OR (SELECT count(*) FROM saly.decisiones WHERE codigo='SALY-AIS30-U07-GPLACES-DEC-001' AND estado='PROPUESTA' AND vigente) <> 1
 OR (SELECT count(*) FROM programacion.engineering_plan_units
      WHERE plan_code='AI_SALES_3_0' AND unit_code='U07'
        AND unit_metadata#>>'{google_places_new_candidate,status}'='CANDIDATE_RESEARCH_ONLY'
        AND unit_metadata#>>'{google_places_new_candidate,runtime_active}'='false'
        AND unit_metadata->>'scope'='PLAN_ONLY_NO_EXECUTION') <> 1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
      WHERE u.plan_code='AI_SALES_3_0' AND u.unit_code='U07' AND c.status='PENDING') <> 20
 THEN RAISE EXCEPTION 'BLOCK_SALY_U07_GOOGLE_PLACES_READBACK'; END IF;
END $readback$;
COMMIT;
