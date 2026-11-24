-- Exact row snapshot from Supabase read-only on 2026-11-23, for isolated PG17.
-- Initial business rows preserved. NO SALY real writes.
\set ON_ERROR_STOP on
ALTER TABLE saly.creative_order_items
 ADD COLUMN order_id bigint,
 ADD COLUMN code text,
 ADD COLUMN status text NOT NULL DEFAULT 'PENDIENTE',
 ADD COLUMN kind text NOT NULL DEFAULT 'SCREEN',
 ADD COLUMN ordinal integer NOT NULL DEFAULT 1,
 ADD COLUMN required boolean NOT NULL DEFAULT true,
 ADD COLUMN variant_of_item_id bigint,
 ADD COLUMN context_json jsonb NOT NULL DEFAULT '{}'::jsonb,
 ADD COLUMN acceptance_json jsonb NOT NULL DEFAULT '{}'::jsonb,
 ADD COLUMN qa_receipt jsonb NOT NULL DEFAULT '{}'::jsonb,
 ADD COLUMN approved_at timestamptz,
 ADD COLUMN approved_by text,
 ADD COLUMN updated_at timestamptz NOT NULL DEFAULT clock_timestamp();
ALTER TABLE saly.creative_order_items ADD CONSTRAINT creative_item_approval_chk
 CHECK ((status='APROBADO')=(approved_at IS NOT NULL) AND
        (status='APROBADO')=(approved_by IS NOT NULL));
CREATE TABLE saly.creative_orders(
 id bigint PRIMARY KEY,
 code text NOT NULL,
 requested_by text NOT NULL,
 status text NOT NULL,
 request_kind text NOT NULL,
 scope_json jsonb NOT NULL,
 context_set_id bigint,
 design_mode text,
 identity_snapshot jsonb NOT NULL,
 completed_at timestamptz);
ALTER TABLE saly.creative_orders ADD CONSTRAINT creative_orders_closure_chk
 CHECK ((status IN ('TERMINADO','COMPLETADO'))=(completed_at IS NOT NULL));
CREATE TABLE saly.creative_item_dependencies(
 order_id bigint, item_id bigint,depends_on_item_id bigint);
CREATE TABLE saly.creative_queue_claims_v1(
 id bigint PRIMARY KEY,order_id bigint NOT NULL,item_id bigint NOT NULL,
 worker_ref text NOT NULL,claim_token uuid NOT NULL UNIQUE,
 state text NOT NULL,lease_until timestamptz NOT NULL,
 finished_at timestamptz,note text);
CREATE TABLE saly.creative_queue_native_delivery_evidence_v1(
 id bigint PRIMARY KEY,claim_id bigint NOT NULL,run_id bigint NOT NULL,
 order_id bigint NOT NULL,item_id bigint NOT NULL,
 artifact_ref text NOT NULL,artifact_sha256 text NOT NULL,
 host_surface text NOT NULL,message_id text NOT NULL,executor_mode text NOT NULL,
 host_evidence_ref text NOT NULL,host_evidence_sha256 text NOT NULL,
 state text NOT NULL DEFAULT 'STAGED',verifier_ref text,verified_at timestamptz,
 recorded_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE saly.creative_runs ADD COLUMN queue_claim_id bigint,
 ADD COLUMN worker_ref text, ADD COLUMN started_at timestamptz,
 ADD COLUMN finished_at timestamptz, ADD COLUMN idempotency_key text,
 ADD COLUMN input_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb;
CREATE TABLE saly.identity_elements(
 id bigint PRIMARY KEY,project_id bigint,code text NOT NULL UNIQUE,family text);
CREATE TABLE saly.identity_versions(
 id bigint PRIMARY KEY,element_id bigint REFERENCES saly.identity_elements(id),
 approval_status text NOT NULL,value_json jsonb NOT NULL,metadata jsonb NOT NULL);
CREATE TABLE saly.creative_context_sets(
 id bigint PRIMARY KEY,code text,state text,project_id bigint);
CREATE TABLE saly.creative_context_tokens(
 context_set_id bigint REFERENCES saly.creative_context_sets(id),
 identity_version_id bigint REFERENCES saly.identity_versions(id),
 role text,value_sha256 text,
 PRIMARY KEY(context_set_id,identity_version_id));
INSERT INTO saly.creative_orders (id,code,requested_by,status,request_kind,scope_json,
 context_set_id,design_mode,identity_snapshot)
VALUES
(8,'SALY_ADELANTO_V015_SINGLE_20261123','CHAT_USER','PLANIFICADO','APP_SCREEN_SINGLE','{"screen":"SOLICITAR_ADELANTO","ordinal":2,"queue_mode":"SERIAL_V1","review_only":true,"block_reason":"NATIVE_DISPATCH_NOT_DEPLOYED","prompt_sha256":"c77ce1be1a09aa64b7ab833c1207cc116b22cbe45682e5a7fe611abb5eb54f50","prompt_source":"SALY_V015_GATE_REAL_REVIEW_ONLY","compiled_prompt":"Destino visual: Un iPhone 16 Pro con pantalla solicitar SALY\nUna pantalla SALY sin cifras inventadas.\nSolicitar adelanto SALY, iPhone 16 Pro frontal en modo claro.\nCTA verde #008200, montos navy #081631, resto neutro; evitar verde omnipresente.\nDisponible sobre franja menta #EAF9EE integrada al fondo, sin tarjeta adicional.\nDiferenciar monto elegido y monto a recibir por tamaño, etiqueta y posición.\nJerarquía: disponible, selección, resumen y CTA Continuar.\nSelección con borde y marcador funcional; no insinuar recomendación económica.\nConcepto compositivo seleccionado: Franja tonal de disponible, selección agrupada, resumen abierto y CTA final\nTres opciones de monto y entrada manual bajo Cuánto necesitas, sin números ficticios.\nMonto solicitado, Cargos aplicables, Monto a recibir y Fecha de descuento sólo si hay valores respaldados.\nContinuar en CTA verde #008200 con texto blanco; no etiquetar Recomendado sin regla autorizada.\nCabecera: Volver, título Solicitar adelanto y ayuda sobre blanco.\nDisponible: Franja menta integrada, sin contenedor redundante.\nMonto: Tres opciones seleccionables, borde e indicador; entrada manual.\nResumen: Monto a recibir destacado sin tarifas imaginarias.\nContinuar: Un CTA primario Continuar al final.\nNo agregar rayos de explosión, palitos de énfasis, destellos radiales ni líneas cinéticas decorativas alrededor de iconos, montos, botones o ilustraciones. Mantener solamente trazos funcionales de iconografía y separadores estructurales justificados.","render_authorized":false,"intake_semantic_qa":{"verdict":"BLOCKED","intent_class":"OPERATIONAL_PROCESS_INSTRUCTION","source_origin":"PR4648_SOURCE_SEED","source_sha256":"835c6c243a95d651b473527bf92cb742067897916351919e408d3e5f0d868a3a","blocking_reason":"CREATIVE_USER_LITERAL_NOT_RECOVERED","repair_contract":"SALY_CREATIVE_INTAKE_SEMANTIC_REPAIR_V1","compiled_prompt_origin":"ASSISTANT_DERIVED_REVIEW_NOT_USER_LITERAL"},"rendering_authority":false,"intake_source_status":"MISSING_VERIFIED_USER_VISUAL_REQUEST","operational_instruction":"No, pero igual eso causa problema. Lo que debemos demandar es solo un pedido con una, o sea, la pantalla de Ergon que termine la pantalla de home y después haces la otra pantalla. Si no va a haber tendencia al error"}'::jsonb,4,'EXPLORE','{"context_set_id":4,"selected_versions":[{"role":"OFFICIAL","sha256":"f52bd036b0760f64f6222f25d95ebe0c56859cbef34dec923c7af8cd5c09ca52","version_id":7},{"role":"OFFICIAL","sha256":"e0bc5fc47e1f2fa3bdd1d51b34356594a0ee88d39d107562cd7a4a2d1de27b7f","version_id":8},{"role":"EXISTING","sha256":"57822661b02310f97ccd242ce929ed82907251ef22f350f9673d76c56c918a13","version_id":11},{"role":"EXISTING","sha256":"0719a985e5f09e61620906078676ecfe93c63810dca870702b834754d1b7046c","version_id":12},{"role":"EXISTING","sha256":"9a003c868816e05d0858815160d14524fdbd037ac9e92c794261e89a4cc48299","version_id":14}]}'::jsonb),
(9,'SALY_HOME_MIDISPONIBLE_REFINEMENT_20261123','CHAT_USER','BORRADOR','APP_SCREEN_SINGLE','{"screen":"HOME","queue_mode":"SERIAL_V1","review_only":true,"change_scope":"ONLY_MI_DISPONIBLE_AS_VIEW_CALCULATION_LINK","interpretation":"En HOME, el bloque Mi disponible debe mostrar un acceso navegable a Cómo se calcula (chevron), sin un importe monetario. Mantener todo lo demás igual. El valor S/ 800 del mockup no está autorizado.","literal_origin":"USER_MESSAGE_VERBATIM_EXCERPT","literal_sha256":"928dd49fc87a21cd4ac396b1a6a78b7a7b4f89442b45e57bc352ff4f8ff01060","preview_origin":"CHAT_GENERATED_IMAGE_NO_VERIFIED_DB_RUN","schema_version":"SALY_HOME_MIDISPONIBLE_REFINEMENT_DRAFT_V1","blocking_reason":"NOT_COMPILED_NOT_QA_ATTESTED_NOT_RENDER_AUTHORIZED_NO_QUEUE_SLOT","literal_request":"un refinanmiento al perido donde se indica que el mi disonible es un ver para que vea como se calcual.","target_component":"HOME.SUMMARY.MI_DISPONIBLE","render_authorized":false,"intake_semantic_qa":{"verdict":"PENDING","required":true},"single_change_only":true,"source_message_ref":null,"rendering_authority":false,"intake_source_status":"VERBATIM_EXCERPT_PENDING_INDEPENDENT_QA","refinement_of_item_id":10,"refinement_of_order_id":7,"dependency_policy_state":"UNRESOLVED_IMMUTABLE_SUCCESSOR_CHAIN","preview_artifact_sha256":"8854a525b61d5642b3e864d5f35dbd9e3fdaf1bab83754ddeaa884eaf90f52d0","source_verification_status":"USER_EXCERPT_AVAILABLE_MESSAGE_ID_NOT_VERIFIED","no_changes_to_other_components":true}'::jsonb,3,'EXPLORE','{"context_set_id":3,"selected_versions":[{"role":"OFFICIAL","sha256":"f52bd036b0760f64f6222f25d95ebe0c56859cbef34dec923c7af8cd5c09ca52","version_id":7},{"role":"OFFICIAL","sha256":"e0bc5fc47e1f2fa3bdd1d51b34356594a0ee88d39d107562cd7a4a2d1de27b7f","version_id":8},{"role":"EXISTING","sha256":"57822661b02310f97ccd242ce929ed82907251ef22f350f9673d76c56c918a13","version_id":11},{"role":"EXISTING","sha256":"0719a985e5f09e61620906078676ecfe93c63810dca870702b834754d1b7046c","version_id":12},{"role":"EXISTING","sha256":"9a003c868816e05d0858815160d14524fdbd037ac9e92c794261e89a4cc48299","version_id":14},{"role":"EXISTING","sha256":"935bfe20fac036b1ab0a772616d84780171634a84700ef985f06a49a0573dbf2","version_id":18},{"role":"HOME","sha256":"6028d40a3ecbf812fd8bcfb3306c6afc6826535b6a59aa22ef4f4a83cfac9580","version_id":57}]}'::jsonb);
INSERT INTO saly.creative_order_items(id,order_id,code,status,kind,ordinal,required,
 context_json,acceptance_json,qa_receipt,approved_at,approved_by)
VALUES
(11,8,'SOLICITAR_ADELANTO','PENDIENTE','SCREEN',1,true,'{"screen_spec":{"device":"IPHONE16PRO","screen":"SOLICITAR_ADELANTO"}}'::jsonb,'{"qa_required":true,"semantic_qa":{"status":"PENDING"}}'::jsonb,'{}'::jsonb,NULL,NULL),
(13,9,'HOME_MIDISPONIBLE','PENDIENTE','SCREEN',1,true,'{"screen_spec":{"device":"IPHONE16PRO","screen":"HOME"},"parent_item_id":10,"parent_order_id":7,"target_component":"HOME.SUMMARY.MI_DISPONIBLE"}'::jsonb,'{"assertions":["Mi disponible is a navigation entry to Cómo se calcula","Do not render a standalone monetary value in Mi disponible","All other HOME regions and their copy unchanged"],"qa_required":true,"semantic_qa":{"status":"PENDING"}}'::jsonb,'{}'::jsonb,NULL,NULL);
-- Historical rows 5..10 are inserted as immutable baselines without modifying them.
INSERT INTO saly.creative_order_items (id,order_id,code,status,kind,ordinal,required)
VALUES
(5,4,'HISTORICAL_5','TERMINADO','SCREEN',1,true),
(6,4,'HISTORICAL_6','TERMINADO','SCREEN',1,true),
(7,4,'HISTORICAL_7','TERMINADO','SCREEN',1,true),
(8,5,'HISTORICAL_8','TERMINADO','SCREEN',1,true),
(9,5,'HISTORICAL_9','TERMINADO','SCREEN',1,true),
(10,7,'HISTORICAL_10','TERMINADO','SCREEN',1,true);
INSERT INTO saly.identity_elements(id,project_id,code,family)
VALUES
(5,2,'color.action.primary.bg','COLOR'),
(4,2,'color.brand.primary','COLOR'),
(6,2,'candidate.saly_ds_v1.color.brand.green.600','COLOR'),
(7,2,'candidate.saly_ds_v1.color.ink.navy.900','COLOR'),
(8,2,'candidate.saly_ds_v1.color.surface.white','COLOR'),
(9,2,'candidate.saly_ds_v1.color.surface.canvas','COLOR'),
(10,2,'candidate.saly_ds_v1.color.surface.mint','COLOR'),
(11,2,'candidate.saly_ds_v1.color.ink.gray.600','COLOR'),
(12,2,'candidate.saly_ds_v1.color.accent.reward.yellow','COLOR'),
(13,2,'candidate.saly_ds_v1.color.accent.reward.gold.700','COLOR'),
(14,2,'candidate.saly_ds_v1.color.surface.reward','COLOR'),
(15,2,'candidate.saly_ds_v1.color.accent.benefits.purple','COLOR'),
(16,2,'candidate.saly_ds_v1.color.stroke.gray.200','COLOR'),
(17,2,'candidate.saly_ds_v1.semantic.color.action.primary.bg','COLOR'),
(18,2,'candidate.saly_ds_v1.semantic.color.action.primary.text','COLOR'),
(19,2,'candidate.saly_ds_v1.semantic.color.text.primary','COLOR'),
(20,2,'candidate.saly_ds_v1.semantic.color.text.secondary','COLOR'),
(21,2,'candidate.saly_ds_v1.semantic.color.surface.page','COLOR'),
(22,2,'candidate.saly_ds_v1.semantic.color.surface.card','COLOR'),
(23,2,'candidate.saly_ds_v1.semantic.color.surface.subtle','COLOR'),
(24,2,'candidate.saly_ds_v1.semantic.color.border.subtle','COLOR'),
(25,2,'candidate.saly_ds_v1.semantic.color.module.plus.icon','COLOR'),
(26,2,'candidate.saly_ds_v1.semantic.color.module.plus.bg','COLOR'),
(27,2,'candidate.saly_ds_v1.semantic.color.module.rewards.icon','COLOR'),
(28,2,'candidate.saly_ds_v1.semantic.color.module.rewards.bg','COLOR'),
(29,2,'candidate.saly_ds_v1.semantic.color.module.benefits.icon','COLOR'),
(30,2,'candidate.saly_ds_v1.typography.font.family.base','TYPOGRAPHY'),
(31,2,'candidate.saly_ds_v1.typography.font.amount.hero','TYPOGRAPHY'),
(32,2,'candidate.saly_ds_v1.typography.font.heading.card','TYPOGRAPHY'),
(33,2,'candidate.saly_ds_v1.typography.font.heading.section','TYPOGRAPHY'),
(34,2,'candidate.saly_ds_v1.typography.font.body.default','TYPOGRAPHY'),
(35,2,'candidate.saly_ds_v1.typography.font.body.secondary','TYPOGRAPHY'),
(36,2,'candidate.saly_ds_v1.typography.font.caption','TYPOGRAPHY'),
(37,2,'candidate.saly_ds_v1.typography.font.button.primary','TYPOGRAPHY'),
(38,2,'candidate.saly_ds_v1.spacing.space.4','SPACING'),
(39,2,'candidate.saly_ds_v1.spacing.space.8','SPACING'),
(40,2,'candidate.saly_ds_v1.spacing.space.12','SPACING'),
(41,2,'candidate.saly_ds_v1.spacing.space.16','SPACING'),
(42,2,'candidate.saly_ds_v1.spacing.space.24','SPACING'),
(43,2,'candidate.saly_ds_v1.spacing.space.32','SPACING'),
(44,2,'candidate.saly_ds_v1.spacing.space.48','SPACING'),
(45,2,'candidate.saly_ds_v1.radius.radius.card.hero','LAYOUT'),
(46,2,'candidate.saly_ds_v1.radius.radius.card.secondary','LAYOUT'),
(47,2,'candidate.saly_ds_v1.radius.radius.button.primary','LAYOUT'),
(48,2,'candidate.saly_ds_v1.radius.radius.pill','LAYOUT'),
(49,2,'candidate.saly_ds_v1.accessibility.touch_target_min_px','RULE'),
(50,2,'candidate.saly_ds_v1.accessibility.supports_font_scaling','RULE'),
(51,2,'candidate.saly_ds_v1.accessibility.use_color_as_sole_signal','RULE'),
(53,2,'candidate.saly_home_v3.color.surface.benefits','COLOR'),
(54,2,'candidate.saly_home_v3.semantic.color.navigation.active','COLOR'),
(55,2,'candidate.saly_home_v3.semantic.color.navigation.inactive','COLOR'),
(56,2,'candidate.saly_home_v3.semantic.color.navigation.background','COLOR'),
(57,2,'candidate.saly_home_v3.semantic.color.module.benefits.bg','COLOR'),
(58,2,'candidate.saly_home_v3.semantic.color.notification.badge','COLOR'),
(59,2,'candidate.saly_home_v3.elevation.card.hero','LAYOUT');
INSERT INTO saly.identity_versions(id,element_id,approval_status,value_json,metadata)
VALUES
(7,5,'APPROVED','{"usage":"CTA_BACKGROUND_FOR_WHITE_TEXT","value":"#008200","format":"HEX"}'::jsonb,'{"source":"GITHUB:PR3715:SALY_DS_V1_CANDIDATE","white_text_usage":"WCAG_AA_NORMAL_TEXT_CONTRAST_VERIFIED_5_TO_1","approval_authority":"OWNER_EXPLICIT_CHAT_CONFIRMATION","valid_from_meaning":"REGISTRY_ACTIVATION_NOT_RETROACTIVE_DESIGN_APPROVAL","approval_date_local":"2026-11-18"}'::jsonb),
(8,4,'APPROVED','{"usage":"BRAND_ONLY_NOT_WHITE_TEXT_CTA","value":"#00C853","format":"HEX"}'::jsonb,'{"source":"LIBRARY:Identidad de Marca SALY.png","white_text_usage":"NOT_APPROVED_FOR_WHITE_TEXT_CTA","approval_authority":"OWNER_EXPLICIT_CHAT_CONFIRMATION","valid_from_meaning":"REGISTRY_ACTIVATION_NOT_RETROACTIVE_DESIGN_APPROVAL","approval_date_local":"2026-11-18"}'::jsonb),
(10,6,'CANDIDATE','{"value":"#008200"}'::jsonb,'{"source_path":"tokens.color.brand.green.600","conflict_note":"SOURCE_BRAND_008200_CONFLICTS_WITH_APPROVED_BRAND_00C853","not_effective":true,"raw_value_type":"string","source_payload":{"type":"color","usage":"Marca / acción primaria","value":"#008200","status":"candidate"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(11,7,'CANDIDATE','{"value":"#081631"}'::jsonb,'{"source_path":"tokens.color.ink.navy.900","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"type":"color","usage":"Texto principal y cifras","value":"#081631","status":"candidate"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(12,8,'CANDIDATE','{"value":"#FFFFFF"}'::jsonb,'{"source_path":"tokens.color.surface.white","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"type":"color","usage":"Card protagonista y superficies","value":"#FFFFFF","status":"candidate"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(13,9,'CANDIDATE','{"value":"#F5F7F7"}'::jsonb,'{"source_path":"tokens.color.surface.canvas","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"type":"color","usage":"Superficies secundarias","value":"#F5F7F7","status":"candidate"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(14,10,'CANDIDATE','{"value":"#EAF9EE"}'::jsonb,'{"source_path":"tokens.color.surface.mint","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"type":"color","usage":"Fondo de Saly Plus y estados suaves","value":"#EAF9EE","status":"candidate"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(15,11,'CANDIDATE','{"value":"#5C6577"}'::jsonb,'{"source_path":"tokens.color.ink.gray.600","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"type":"color","usage":"Texto secundario","value":"#5C6577","status":"candidate"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(16,12,'CANDIDATE','{"value":"#F6B400"}'::jsonb,'{"source_path":"tokens.color.accent.reward.yellow","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"type":"color","usage":"Acento decorativo Rewards, NO texto/ícono funcional sobre blanco","value":"#F6B400","status":"candidate"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(17,13,'CANDIDATE','{"value":"#9D6800"}'::jsonb,'{"source_path":"tokens.color.accent.reward.gold.700","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"type":"color","usage":"Ícono funcional Rewards contrastado","value":"#9D6800","status":"candidate"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(18,14,'CANDIDATE','{"value":"#FFF9E9"}'::jsonb,'{"source_path":"tokens.color.surface.reward","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"type":"color","usage":"Fondo Rewards","value":"#FFF9E9","status":"candidate"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(19,15,'CANDIDATE','{"value":"#923CF3"}'::jsonb,'{"source_path":"tokens.color.accent.benefits.purple","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"type":"color","usage":"Identidad de Beneficios","value":"#923CF3","status":"candidate"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(20,16,'CANDIDATE','{"value":"#E4E8E8"}'::jsonb,'{"source_path":"tokens.color.stroke.gray.200","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"type":"color","usage":"Bordes y separadores","value":"#E4E8E8","status":"candidate"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(21,17,'CANDIDATE','{"value":"{color.brand.green.600}"}'::jsonb,'{"source_path":"tokens.semantic.color.action.primary.bg","conflict_note":"SEMANTIC_ALIAS_008200_TARGET_COLLIDES_WITH_APPROVED_CTA_TOKEN","not_effective":true,"raw_value_type":"string","source_payload":{"alias":"{color.brand.green.600}","status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(22,18,'CANDIDATE','{"value":"{color.surface.white}"}'::jsonb,'{"source_path":"tokens.semantic.color.action.primary.text","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"alias":"{color.surface.white}","status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(23,19,'CANDIDATE','{"value":"{color.ink.navy.900}"}'::jsonb,'{"source_path":"tokens.semantic.color.text.primary","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"alias":"{color.ink.navy.900}","status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(24,20,'CANDIDATE','{"value":"{color.ink.gray.600}"}'::jsonb,'{"source_path":"tokens.semantic.color.text.secondary","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"alias":"{color.ink.gray.600}","status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(25,21,'CANDIDATE','{"value":"{color.surface.white}"}'::jsonb,'{"source_path":"tokens.semantic.color.surface.page","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"alias":"{color.surface.white}","status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(26,22,'CANDIDATE','{"value":"{color.surface.white}"}'::jsonb,'{"source_path":"tokens.semantic.color.surface.card","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"alias":"{color.surface.white}","status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(27,23,'CANDIDATE','{"value":"{color.surface.canvas}"}'::jsonb,'{"source_path":"tokens.semantic.color.surface.subtle","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"alias":"{color.surface.canvas}","status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(28,24,'CANDIDATE','{"value":"{color.stroke.gray.200}"}'::jsonb,'{"source_path":"tokens.semantic.color.border.subtle","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"alias":"{color.stroke.gray.200}","status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(29,25,'CANDIDATE','{"value":"{color.brand.green.600}"}'::jsonb,'{"source_path":"tokens.semantic.color.module.plus.icon","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"alias":"{color.brand.green.600}","status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(30,26,'CANDIDATE','{"value":"{color.surface.mint}"}'::jsonb,'{"source_path":"tokens.semantic.color.module.plus.bg","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"alias":"{color.surface.mint}","status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(31,27,'CANDIDATE','{"value":"{color.accent.reward.gold.700}"}'::jsonb,'{"source_path":"tokens.semantic.color.module.rewards.icon","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"alias":"{color.accent.reward.gold.700}","status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(32,28,'CANDIDATE','{"value":"{color.surface.reward}"}'::jsonb,'{"source_path":"tokens.semantic.color.module.rewards.bg","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"alias":"{color.surface.reward}","status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(33,29,'CANDIDATE','{"value":"{color.accent.benefits.purple}"}'::jsonb,'{"source_path":"tokens.semantic.color.module.benefits.icon","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"alias":"{color.accent.benefits.purple}","status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(34,30,'CANDIDATE','{"value":"Inter, system-ui, sans-serif"}'::jsonb,'{"source_path":"tokens.typography.font.family.base","conflict_note":"NONE","not_effective":true,"raw_value_type":"string","source_payload":{"value":"Inter, system-ui, sans-serif","status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(35,31,'CANDIDATE','{"value":{"weight":700,"size_px":48,"line_height_px":56}}'::jsonb,'{"source_path":"tokens.typography.font.amount.hero","conflict_note":"NONE","not_effective":true,"raw_value_type":"object","source_payload":{"status":"CANDIDATO","weight":700,"size_px":48,"line_height_px":56},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(36,32,'CANDIDATE','{"value":{"weight":600,"size_px":20,"line_height_px":28}}'::jsonb,'{"source_path":"tokens.typography.font.heading.card","conflict_note":"NONE","not_effective":true,"raw_value_type":"object","source_payload":{"status":"CANDIDATO","weight":600,"size_px":20,"line_height_px":28},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(37,33,'CANDIDATE','{"value":{"weight":700,"size_px":22,"line_height_px":30}}'::jsonb,'{"source_path":"tokens.typography.font.heading.section","conflict_note":"NONE","not_effective":true,"raw_value_type":"object","source_payload":{"status":"CANDIDATO","weight":700,"size_px":22,"line_height_px":30},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(38,34,'CANDIDATE','{"value":{"weight":400,"size_px":16,"line_height_px":24}}'::jsonb,'{"source_path":"tokens.typography.font.body.default","conflict_note":"NONE","not_effective":true,"raw_value_type":"object","source_payload":{"status":"CANDIDATO","weight":400,"size_px":16,"line_height_px":24},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(39,35,'CANDIDATE','{"value":{"weight":400,"size_px":14,"line_height_px":20}}'::jsonb,'{"source_path":"tokens.typography.font.body.secondary","conflict_note":"NONE","not_effective":true,"raw_value_type":"object","source_payload":{"status":"CANDIDATO","weight":400,"size_px":14,"line_height_px":20},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(40,36,'CANDIDATE','{"value":{"weight":400,"size_px":12,"line_height_px":16}}'::jsonb,'{"source_path":"tokens.typography.font.caption","conflict_note":"NONE","not_effective":true,"raw_value_type":"object","source_payload":{"status":"CANDIDATO","weight":400,"size_px":12,"line_height_px":16},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(41,37,'CANDIDATE','{"value":{"weight":600,"size_px":16,"line_height_px":24}}'::jsonb,'{"source_path":"tokens.typography.font.button.primary","conflict_note":"NONE","not_effective":true,"raw_value_type":"object","source_payload":{"status":"CANDIDATO","weight":600,"size_px":16,"line_height_px":24},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(42,38,'CANDIDATE','{"value":4}'::jsonb,'{"source_path":"tokens.spacing.space.4","conflict_note":"NONE","not_effective":true,"raw_value_type":"number","source_payload":{"px":4,"status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(43,39,'CANDIDATE','{"value":8}'::jsonb,'{"source_path":"tokens.spacing.space.8","conflict_note":"NONE","not_effective":true,"raw_value_type":"number","source_payload":{"px":8,"status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(44,40,'CANDIDATE','{"value":12}'::jsonb,'{"source_path":"tokens.spacing.space.12","conflict_note":"NONE","not_effective":true,"raw_value_type":"number","source_payload":{"px":12,"status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(45,41,'CANDIDATE','{"value":16}'::jsonb,'{"source_path":"tokens.spacing.space.16","conflict_note":"NONE","not_effective":true,"raw_value_type":"number","source_payload":{"px":16,"status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(46,42,'CANDIDATE','{"value":24}'::jsonb,'{"source_path":"tokens.spacing.space.24","conflict_note":"NONE","not_effective":true,"raw_value_type":"number","source_payload":{"px":24,"status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(47,43,'CANDIDATE','{"value":32}'::jsonb,'{"source_path":"tokens.spacing.space.32","conflict_note":"NONE","not_effective":true,"raw_value_type":"number","source_payload":{"px":32,"status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(48,44,'CANDIDATE','{"value":48}'::jsonb,'{"source_path":"tokens.spacing.space.48","conflict_note":"NONE","not_effective":true,"raw_value_type":"number","source_payload":{"px":48,"status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(49,45,'CANDIDATE','{"value":24}'::jsonb,'{"source_path":"tokens.radius.radius.card.hero","conflict_note":"NONE","not_effective":true,"raw_value_type":"number","source_payload":{"px":24,"status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(50,46,'CANDIDATE','{"value":16}'::jsonb,'{"source_path":"tokens.radius.radius.card.secondary","conflict_note":"NONE","not_effective":true,"raw_value_type":"number","source_payload":{"px":16,"status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(51,47,'CANDIDATE','{"value":14}'::jsonb,'{"source_path":"tokens.radius.radius.button.primary","conflict_note":"NONE","not_effective":true,"raw_value_type":"number","source_payload":{"px":14,"status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(52,48,'CANDIDATE','{"value":999}'::jsonb,'{"source_path":"tokens.radius.radius.pill","conflict_note":"NONE","not_effective":true,"raw_value_type":"number","source_payload":{"px":999,"status":"CANDIDATO"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(53,49,'CANDIDATE','{"value":44}'::jsonb,'{"source_path":"tokens.accessibility.touch_target_min_px","conflict_note":"NONE","not_effective":true,"raw_value_type":"number","source_payload":44,"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(54,50,'CANDIDATE','{"value":true}'::jsonb,'{"source_path":"tokens.accessibility.supports_font_scaling","conflict_note":"NONE","not_effective":true,"raw_value_type":"boolean","source_payload":true,"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(55,51,'CANDIDATE','{"value":false}'::jsonb,'{"source_path":"tokens.accessibility.use_color_as_sole_signal","conflict_note":"NONE","not_effective":true,"raw_value_type":"boolean","source_payload":false,"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","approval_required_for_activation":true}'::jsonb),
(57,53,'CANDIDATE','{"value":"#F4E7FD"}'::jsonb,'{"kind":"ESTIMATED_COLOR","not_effective":true,"source_file_id":"1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ","alias_target_code":null,"source_file_sha256":"d8dd1a4da97f3ac180e060a4fb23ba4f91d7e37668fe905135c769fd3aa68850","source_pack_sha256":"0571e2de1e5bdb7dd2b9afb06a024abb293beff6a37bacc1e24c33c80e04fbdb","approval_required_for_activation":true}'::jsonb),
(58,54,'CANDIDATE','{"value":"{color.action.primary.bg}"}'::jsonb,'{"kind":"ALIAS","not_effective":true,"source_file_id":"1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ","alias_target_code":"color.action.primary.bg","source_file_sha256":"d8dd1a4da97f3ac180e060a4fb23ba4f91d7e37668fe905135c769fd3aa68850","source_pack_sha256":"0571e2de1e5bdb7dd2b9afb06a024abb293beff6a37bacc1e24c33c80e04fbdb","approval_required_for_activation":true}'::jsonb),
(59,55,'CANDIDATE','{"value":"{color.ink.gray.600}"}'::jsonb,'{"kind":"ALIAS","not_effective":true,"source_file_id":"1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ","alias_target_code":"candidate.saly_ds_v1.color.ink.gray.600","source_file_sha256":"d8dd1a4da97f3ac180e060a4fb23ba4f91d7e37668fe905135c769fd3aa68850","source_pack_sha256":"0571e2de1e5bdb7dd2b9afb06a024abb293beff6a37bacc1e24c33c80e04fbdb","approval_required_for_activation":true}'::jsonb),
(60,56,'CANDIDATE','{"value":"{color.surface.white}"}'::jsonb,'{"kind":"ALIAS","not_effective":true,"source_file_id":"1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ","alias_target_code":"candidate.saly_ds_v1.color.surface.white","source_file_sha256":"d8dd1a4da97f3ac180e060a4fb23ba4f91d7e37668fe905135c769fd3aa68850","source_pack_sha256":"0571e2de1e5bdb7dd2b9afb06a024abb293beff6a37bacc1e24c33c80e04fbdb","approval_required_for_activation":true}'::jsonb),
(61,57,'CANDIDATE','{"value":"{color.surface.benefits}"}'::jsonb,'{"kind":"ALIAS","not_effective":true,"source_file_id":"1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ","alias_target_code":"candidate.saly_home_v3.color.surface.benefits","source_file_sha256":"d8dd1a4da97f3ac180e060a4fb23ba4f91d7e37668fe905135c769fd3aa68850","source_pack_sha256":"0571e2de1e5bdb7dd2b9afb06a024abb293beff6a37bacc1e24c33c80e04fbdb","approval_required_for_activation":true}'::jsonb),
(62,58,'CANDIDATE','{"value":"#E62F40"}'::jsonb,'{"kind":"ESTIMATED_COLOR","not_effective":true,"source_file_id":"1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ","alias_target_code":null,"source_file_sha256":"d8dd1a4da97f3ac180e060a4fb23ba4f91d7e37668fe905135c769fd3aa68850","source_pack_sha256":"0571e2de1e5bdb7dd2b9afb06a024abb293beff6a37bacc1e24c33c80e04fbdb","approval_required_for_activation":true}'::jsonb),
(63,59,'CANDIDATE','{"value":{"blur":16,"color":"#081631","spread":0,"opacity":0.1,"offset_x":0,"offset_y":4}}'::jsonb,'{"not_effective":true,"source_file_id":"1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ","creative_policy":"OPTIONAL","source_pack_sha256":"0571e2de1e5bdb7dd2b9afb06a024abb293beff6a37bacc1e24c33c80e04fbdb","device_coordinate_warning":"FLATTENED_MOCKUP_NOT_NATIVE","approval_required_for_activation":true}'::jsonb);
INSERT INTO saly.creative_context_sets(id,code,state,project_id)
VALUES (3,'SALY_HOME_V015_CONTEXT_20261123','SEALED',2),
(4,'SALY_ADELANTO_V015_CONTEXT_20261123','SEALED',2);
INSERT INTO saly.creative_context_tokens(context_set_id,identity_version_id,role,value_sha256)
VALUES
(4,7,'OFFICIAL','f52bd036b0760f64f6222f25d95ebe0c56859cbef34dec923c7af8cd5c09ca52'),
(4,8,'OFFICIAL','e0bc5fc47e1f2fa3bdd1d51b34356594a0ee88d39d107562cd7a4a2d1de27b7f'),
(4,11,'EXISTING','57822661b02310f97ccd242ce929ed82907251ef22f350f9673d76c56c918a13'),
(4,12,'EXISTING','0719a985e5f09e61620906078676ecfe93c63810dca870702b834754d1b7046c'),
(4,14,'EXISTING','9a003c868816e05d0858815160d14524fdbd037ac9e92c794261e89a4cc48299'),
(3,7,'OFFICIAL','f52bd036b0760f64f6222f25d95ebe0c56859cbef34dec923c7af8cd5c09ca52'),
(3,8,'OFFICIAL','e0bc5fc47e1f2fa3bdd1d51b34356594a0ee88d39d107562cd7a4a2d1de27b7f'),
(3,11,'EXISTING','57822661b02310f97ccd242ce929ed82907251ef22f350f9673d76c56c918a13'),
(3,12,'EXISTING','0719a985e5f09e61620906078676ecfe93c63810dca870702b834754d1b7046c'),
(3,14,'EXISTING','9a003c868816e05d0858815160d14524fdbd037ac9e92c794261e89a4cc48299'),
(3,18,'EXISTING','935bfe20fac036b1ab0a772616d84780171634a84700ef985f06a49a0573dbf2'),
(3,57,'HOME','6028d40a3ecbf812fd8bcfb3306c6afc6826535b6a59aa22ef4f4a83cfac9580');
-- Original source functions copied from live pg_get_functiondef, not reinterpreted.
CREATE OR REPLACE FUNCTION saly.creative_assert_dual_qa_l3c(p_acceptance jsonb, p_receipt jsonb, p_snapshot jsonb, p_output jsonb)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly', 'extensions', 'pg_temp'
AS $function$
DECLARE
 v_sem jsonb:=p_acceptance->'semantic_qa';
 v_visual jsonb:=p_snapshot->'visual_contract';
 v_contract_sha text;
 v_original_sha text;
 v_semantic_sha text;
 v_artifact_sha text;
 v_group text;
 v_expected jsonb;
 v_actual jsonb;
 v_n integer;
BEGIN
 IF jsonb_typeof(p_acceptance) IS DISTINCT FROM 'object'
    OR jsonb_typeof(p_receipt) IS DISTINCT FROM 'object'
    OR jsonb_typeof(p_snapshot) IS DISTINCT FROM 'object'
    OR jsonb_typeof(p_output) IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_INPUT_SHAPE'; END IF;
 IF jsonb_typeof(v_sem) IS DISTINCT FROM 'object'
    OR jsonb_typeof(v_sem->'original_messages') IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_sem->'original_messages')=0
    OR jsonb_typeof(v_sem->'interpretation') IS DISTINCT FROM 'object'
    OR jsonb_typeof(v_sem->'checks') IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_sem->'checks')<>5
 THEN RAISE EXCEPTION 'CREATIVE_SEMANTIC_INPUT_INVALID'; END IF;
 v_original_sha:=encode(extensions.digest(convert_to((v_sem->'original_messages')::text,'UTF8'),'sha256'),'hex');
 v_semantic_sha:=encode(extensions.digest(convert_to(v_sem::text,'UTF8'),'sha256'),'hex');
 IF v_sem->>'original_request_sha256' IS DISTINCT FROM v_original_sha
    OR jsonb_typeof(v_visual) IS DISTINCT FROM 'object'
    OR v_visual->'acceptance_criteria' IS DISTINCT FROM p_acceptance
    OR jsonb_typeof(v_visual->'qa_checks') IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_visual->'qa_checks')<>5
 THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_CONTRACT_MISMATCH'; END IF;
 v_contract_sha:=encode(extensions.digest(convert_to(v_visual::text,'UTF8'),'sha256'),'hex');
 v_artifact_sha:=p_output->>'sha256';

 IF jsonb_typeof(p_snapshot->'visual_contract_sha256') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_receipt->'contract_sha256') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_output->'sha256') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_receipt->'artifact_sha256') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_receipt->'artifact_ref') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_output->'artifact_ref') IS DISTINCT FROM 'string'
    OR p_snapshot->>'visual_contract_sha256' IS DISTINCT FROM v_contract_sha
    OR p_receipt->>'contract_sha256' IS DISTINCT FROM v_contract_sha
    OR v_artifact_sha IS NULL OR v_artifact_sha !~ '^[0-9a-f]{64}$'
    OR p_receipt->>'artifact_sha256' IS DISTINCT FROM v_artifact_sha
    OR p_receipt->>'artifact_ref' IS DISTINCT FROM p_output->>'artifact_ref'
    OR nullif(btrim(p_output->>'artifact_ref'),'') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_ARTIFACT_OR_HASH_MISMATCH'; END IF;

 IF p_receipt#>>'{semantic_qa,original_request_sha256}' IS DISTINCT FROM v_original_sha
    OR p_receipt#>>'{semantic_qa,semantic_contract_sha256}' IS DISTINCT FROM v_semantic_sha
    OR jsonb_typeof(p_receipt#>'{semantic_qa,independent_interpretation}') IS DISTINCT FROM 'string'
    OR nullif(btrim(p_receipt#>>'{semantic_qa,independent_interpretation}'),'') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_SEMANTIC_REVIEW_MISSING'; END IF;

 FOREACH v_group IN ARRAY ARRAY['semantic_qa','technical_qa'] LOOP
   IF p_receipt#>>ARRAY[v_group,'verdict'] IS DISTINCT FROM 'PASS'
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_NOT_PASS'; END IF;
   v_expected:=CASE v_group WHEN 'semantic_qa' THEN v_sem->'checks' ELSE v_visual->'qa_checks' END;
   v_actual:=p_receipt#>ARRAY[v_group,'checks'];
   IF jsonb_typeof(v_actual) IS DISTINCT FROM 'array'
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_CHECKS_MISSING'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_expected) AS x(c)
     WHERE jsonb_typeof(c) IS DISTINCT FROM 'object'
       OR jsonb_typeof(c->'code') IS DISTINCT FROM 'string'
       OR nullif(btrim(c->>'code'),'') IS NULL)
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_INVALID_EXPECTED_CODES'; END IF;
   IF (SELECT count(DISTINCT check_item->>'code') FROM jsonb_array_elements(v_expected) AS t(check_item))<>jsonb_array_length(v_expected)
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_INVALID_EXPECTED_CODES'; END IF;
   IF jsonb_array_length(v_actual)<>jsonb_array_length(v_expected)
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_CHECK_COUNT'; END IF;
   SELECT count(*) INTO v_n
    FROM jsonb_array_elements(v_expected) AS exp(check_item)
    WHERE (SELECT count(*) FROM jsonb_array_elements(v_actual) AS act(check_item)
      WHERE act.check_item->>'code'=exp.check_item->>'code'
       AND act.check_item->>'verdict'='PASS'
       AND jsonb_typeof(act.check_item->'code')='string'
       AND jsonb_typeof(act.check_item->'evidence')='string'
       AND nullif(btrim(act.check_item->>'evidence'),'') IS NOT NULL)=1;
   IF v_n<>jsonb_array_length(v_expected)
   THEN RAISE EXCEPTION 'CREATIVE_DUAL_QA_CHECK_FAILED_OR_MISSING'; END IF;
 END LOOP;
END $function$;

CREATE OR REPLACE FUNCTION saly.creative_queue_advance_run_v1(p_token uuid, p_run_id bigint, p_next_state text, p_output_evidence jsonb DEFAULT '{}'::jsonb, p_error_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE v_claim record; v_run record;
BEGIN
  IF p_token IS NULL OR p_run_id IS NULL
    OR p_next_state NOT IN ('EJECUTANDO','EXITOSO','FALLIDO','BLOQUEADO','CANCELADO')
    OR jsonb_typeof(p_output_evidence) IS DISTINCT FROM 'object'
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_BAD_INPUT'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
  SELECT * INTO v_claim FROM saly.creative_queue_claims_v1
  WHERE claim_token=p_token FOR UPDATE;
  IF NOT FOUND OR v_claim.state<>'ACTIVE' OR v_claim.lease_until<=clock_timestamp()
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_STALE_TOKEN'; END IF;
  SELECT * INTO v_run FROM saly.creative_runs
  WHERE id=p_run_id AND queue_claim_id=v_claim.id
    AND order_id=v_claim.order_id AND item_id=v_claim.item_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_QUEUE_RUN_NOT_BOUND'; END IF;
  IF (p_next_state='EJECUTANDO' AND v_run.state<>'EN_COLA')
     OR (p_next_state IN ('EXITOSO','FALLIDO','BLOQUEADO') AND v_run.state<>'EJECUTANDO')
     OR (p_next_state='CANCELADO' AND v_run.state NOT IN ('EN_COLA','EJECUTANDO'))
  THEN RAISE EXCEPTION 'CREATIVE_QUEUE_RUN_INVALID_TRANSITION'; END IF;
  PERFORM set_config('saly.creative_queue_token',p_token::text,true);
  IF p_next_state='EJECUTANDO' THEN
    UPDATE saly.creative_runs SET state='EJECUTANDO',worker_ref=v_claim.worker_ref,
      updated_at=clock_timestamp() WHERE id=v_run.id;
  ELSE
    UPDATE saly.creative_runs SET state=p_next_state,
      output_evidence=CASE WHEN p_next_state='EXITOSO' THEN p_output_evidence ELSE output_evidence END,
      error_code=p_error_code,updated_at=clock_timestamp()
      WHERE id=v_run.id;
  END IF;
  RETURN jsonb_build_object('run_id',v_run.id,'state',p_next_state,'claim_id',v_claim.id);
END $function$;
-- Exact current single-screen item guard from pg_get_functiondef.
CREATE OR REPLACE FUNCTION saly.creative_single_screen_item_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE kind_of_order text;
BEGIN
 SELECT request_kind INTO kind_of_order FROM saly.creative_orders
 WHERE id=NEW.order_id FOR UPDATE;
 IF kind_of_order IS DISTINCT FROM 'APP_SCREEN_SINGLE' THEN RETURN NEW; END IF;
 IF NEW.kind IS DISTINCT FROM 'SCREEN' OR NEW.ordinal IS DISTINCT FROM 1
 OR NEW.variant_of_item_id IS NOT NULL
 THEN RAISE EXCEPTION 'CREATIVE_SINGLE_SCREEN_ITEM_SHAPE'; END IF;
 IF TG_OP='UPDATE' AND (NEW.id IS DISTINCT FROM OLD.id
  OR NEW.order_id IS DISTINCT FROM OLD.order_id
  OR NEW.code IS DISTINCT FROM OLD.code)
 THEN RAISE EXCEPTION 'CREATIVE_SINGLE_SCREEN_ITEM_BINDING_IMMUTABLE'; END IF;
 IF TG_OP='INSERT' AND EXISTS (SELECT 1 FROM saly.creative_order_items
   WHERE order_id=NEW.order_id)
 THEN RAISE EXCEPTION 'CREATIVE_SINGLE_SCREEN_MULTIPLE_ITEMS'; END IF;
 RETURN NEW;
END $function$;
-- L3B is a fixture-specific adapter: gives a fixed five-check contract for
-- a synthetic QA receipt; NOT the production creative_item_visual_contract_l3b.
CREATE FUNCTION saly.creative_item_visual_contract_l3b(p_item_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $f$
 SELECT jsonb_build_object('contract',jsonb_build_object('qa_checks',
   jsonb_build_array(
     jsonb_build_object('code','CTA_COLOR'),
     jsonb_build_object('code','CTA_TEXT'),
     jsonb_build_object('code','NO_RAYS'),
     jsonb_build_object('code','GEOMETRY'),
     jsonb_build_object('code','NO_FAKE_AMOUNTS'))));
$f$;
DO $assert$ BEGIN
 IF (SELECT count(*) FROM saly.creative_order_items WHERE id IN (11,13))<>2
 OR (SELECT status FROM saly.creative_order_items WHERE id=11)<>'PENDIENTE'
 OR (SELECT status FROM saly.creative_order_items WHERE id=13)<>'PENDIENTE'
 OR (SELECT status FROM saly.creative_orders WHERE id=8)<>'PLANIFICADO'
 OR (SELECT status FROM saly.creative_orders WHERE id=9)<>'BORRADOR'
 OR (SELECT count(*) FROM saly.identity_versions)<>55
 OR (SELECT count(*) FROM saly.creative_order_items WHERE id BETWEEN 5 AND 10)<>6
 THEN RAISE EXCEPTION 'ABC_LIVE_FIXTURE_READBACK_FAILED'; END IF;
END $assert$;
