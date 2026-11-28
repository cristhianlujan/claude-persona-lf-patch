\set ON_ERROR_STOP on
-- Static CI-only fixtures. No claim_token, no user data, no production writes.
INSERT INTO saly.config_global SELECT * FROM jsonb_populate_record(NULL::saly.config_global,'{"scope":"CREATIVE_FACTORY","config_key":"LEASE_SECONDS","created_at":"2026-11-23T01:15:23.887709+00:00","valid_from":"2026-11-23T01:15:23.887709+00:00","value_type":"INTEGER","description":"Inicial: 10 minutos de lease de worker; no es SLA ni permiso de generación. Decisión técnica PR #4616.","config_value":"600","value_status":"REAL"}'::jsonb);
INSERT INTO saly.config_global SELECT * FROM jsonb_populate_record(NULL::saly.config_global,'{"scope":"CREATIVE_FACTORY","config_key":"QUEUE_TIMEOUT_SECONDS","created_at":"2026-11-23T01:15:23.887709+00:00","valid_from":"2026-11-23T01:15:23.887709+00:00","value_type":"INTEGER","description":"Inicial: 15 minutos de espera máxima para RUN EN_COLA; calibrar con evidencia. Decisión técnica PR #4616.","config_value":"900","value_status":"REAL"}'::jsonb);
INSERT INTO saly.config_global SELECT * FROM jsonb_populate_record(NULL::saly.config_global,'{"scope":"CREATIVE_FACTORY","config_key":"MAX_ATTEMPTS","created_at":"2026-11-23T01:15:23.887709+00:00","valid_from":"2026-11-23T01:15:23.887709+00:00","value_type":"INTEGER","description":"Inicial: intento original y un reintento; no repetir sin límite. Decisión técnica PR #4616.","config_value":"2","value_status":"REAL"}'::jsonb);
INSERT INTO saly.config_global SELECT * FROM jsonb_populate_record(NULL::saly.config_global,'{"scope":"CREATIVE_FACTORY","config_key":"QUEUE_MAX","created_at":"2026-11-23T01:15:23.887709+00:00","valid_from":"2026-11-23T01:15:23.887709+00:00","value_type":"INTEGER","description":"Inicial: una admisión RUN en cola; ejecución serial. Decisión técnica PR #4616, no dato medido.","config_value":"1","value_status":"REAL"}'::jsonb);
INSERT INTO public.lf_decisiones_gov SELECT * FROM jsonb_populate_record(NULL::public.lf_decisiones_gov,'{"fecha":"2026-06-29","impacto":"Toda operación visual debe consultar lf_design.v_color_tokens_operativos y referenciar el token semántico. Los valores literales quedan permitidos únicamente en la fuente canónica de tokens.","contexto":"Se elimina la duplicación de valores de color fuera de la fuente canónica para evitar contradicciones y regresiones entre agentes, documentos e implementaciones.","decision":"Los colores oficiales de Libertad Financiera se resuelven exclusivamente por token_name desde lf_design.v_color_tokens_operativos. Ningún prompt, handoff, spec, documento, decisión o implementación debe almacenar valores literales de color.","created_at":"2026-06-30T04:41:29.70244+00:00","updated_at":"2026-07-21T01:20:10.342621+00:00","id_decision":"DEC-COLOR-001","raw_payload":{"applies_to":["prompts","handoffs","specs","documents","decisions","implementation"],"lookup_key":"token_name","resolution_source":"lf_design.v_color_tokens_operativos","hardcoded_color_literals_allowed":false},"observaciones":"Fuente única ejecutable: lf_design.v_color_tokens_operativos. Resolver por token_name. No copiar valores desde memoria, imágenes, decisiones históricas ni documentos.","decision_number":54,"estado_original":"CANDIDATO","source_sheet_name":"MANUAL_CLAUDE_SESSION","estado_normalizado":"VIGENTE","migration_batch_id":"f46b3d3c-c078-4615-a71f-04898a7203d0","documento_relacionado":"DOC_01_02_COLOR_SYSTEM_V2_CANDIDATO_CORREGIDO (ACT-0019) + DOC_PALETA_VISUAL_MASTER_MARKETPLACE","created_by_execution_id":"UNKNOWN","updated_by_execution_id":null}'::jsonb);
INSERT INTO lf_design.brand_assets SELECT * FROM jsonb_populate_record(NULL::lf_design.brand_assets,'{"status":"VIGENTE","version":"v1","filename":"LF_BRAND_LOGO_1L_LIGHT_TRANSPARENT.png","metadata":{"width_px":2027,"height_px":364,"line_count":1,"text_color":"navy_core","source_kind":"DERIVED_FROM_OFFICIAL_1L_ASSET","drive_file_id":"197I1Gx7KTpEe_ZvCvvAWl9hUc-D5YSZa","target_surface":"LIGHT","brand_green_hex":"#109044","brand_green_token":"green_action","canonical_filename":"LF_BRAND_LOGO_1L_LIGHT_TRANSPARENT.png","visual_decision_id":21,"drive_upload_status":"UPLOADED","drive_parent_folder_id":"1g9Yig1uagfFNXabAJnMbhanOG_-s4x50"},"mime_type":"image/png","asset_code":"LF_BRAND_LOGO_1L_LIGHT_TRANSPARENT","asset_kind":"LOGO","asset_name":"LF Logo 1 línea — fondo claro","created_at":"2026-08-15T06:20:51.551243+00:00","is_current":true,"updated_at":"2026-08-16T18:20:59.600568+00:00","access_level":"PRIVATE","asset_variant":"LIGHT_1L_TRANSPARENT","brand_asset_id":5,"storage_bucket":"1g9Yig1uagfFNXabAJnMbhanOG_-s4x50","checksum_sha256":"898bd5f50ee588919ed0ccace4cfc4c0d7741efc178248bff2303c1893cabd81","storage_provider":"GOOGLE_DRIVE","source_decision_id":"DEC-COLOR-001","storage_object_path":"197I1Gx7KTpEe_ZvCvvAWl9hUc-D5YSZa","source_decision_number":54}'::jsonb);
INSERT INTO saly.identity_elements SELECT * FROM jsonb_populate_record(NULL::saly.identity_elements,'{"id":68,"code":"lf.source.colors.green_action","name":"lf.source.colors.green_action","family":"COLOR","status":"ACTIVE","metadata":{"source":"lf_design","source_status":"VIGENTE"},"created_at":"2026-11-26T07:05:42.852029+00:00","project_id":3,"updated_at":"2026-11-26T07:05:42.852029+00:00","value_type":"JSON","decision_id":null,"description":null,"is_required":false,"is_protected":false}'::jsonb);
INSERT INTO saly.identity_versions SELECT * FROM jsonb_populate_record(NULL::saly.identity_versions,'{"id":125,"metadata":{},"valid_to":null,"created_at":"2026-11-26T07:05:42.852029+00:00","element_id":68,"updated_at":"2026-11-26T07:05:42.852029+00:00","valid_from":"2026-11-26T07:05:42.852029+00:00","value_json":{"value":{"notes":"Unico verde oficial LF.","status":"VIGENTE","hex_value":"#109044","rgb_value":"rgb(16,144,68)","created_at":"2026-06-30T15:29:59.535141+00:00","token_name":"green_action","updated_at":"2026-07-02T03:32:42.115248+00:00","requires_qa":true,"token_group":"green","allowed_usage":"Logo, CTA principal, badges activos, checks, montos positivos, avance y solucion","blocked_usage":"Crear verdes alternativos por pantalla","semantic_role":"Accion principal, progreso y solucion","color_token_id":16,"design_system_id":1,"propagation_scope":["web","mobile","prompts_visuales","handoff_dev","fixtures"],"design_system_code":"LF_DS_V1","source_decision_id":"DEC-COLOR-001","affected_components":["logo","cta_primary","badge_active","check_icon","positive_amount","progress"],"source_decision_number":54}},"decision_id":null,"channel_code":"GLOBAL","audience_code":"ALL","change_reason":null,"version_number":1,"approval_status":"APPROVED","approval_reference":"LF source VIGENTE; owner authorized factory test"}'::jsonb);
INSERT INTO saly.proyecto OVERRIDING SYSTEM VALUE SELECT * FROM jsonb_populate_record(NULL::saly.proyecto,'{"id":2,"fase":"IDEACION","codigo":"SALY-001","estado":"ACTIVO","nombre":"Saly","objetivo":"Fintech de adelantos de sueldo y prestamos, con capacidad de operar empresas autofondeadas o con fondeo externo y modalidades White Label o app compartida.","created_at":"2026-08-07T23:43:23.120011+00:00","updated_at":"2026-08-07T23:43:23.120011+00:00","significado_nombre":"Derivado de salario"}'::jsonb);
INSERT INTO saly.proyecto OVERRIDING SYSTEM VALUE SELECT * FROM jsonb_populate_record(NULL::saly.proyecto,'{"id":3,"fase":"IDEACION","codigo":"LF","estado":"ACTIVO","nombre":"Libertad Financiera","objetivo":"Plataforma peruana de negociación de deuda castigada.","created_at":"2026-11-26T03:35:54.082785+00:00","updated_at":"2026-11-26T03:35:54.082785+00:00","significado_nombre":null}'::jsonb);
INSERT INTO saly.identity_elements SELECT * FROM jsonb_populate_record(NULL::saly.identity_elements,'{"id":8,"code":"candidate.saly_ds_v1.color.surface.white","name":"surface.white","family":"COLOR","status":"ACTIVE","metadata":{"source_path":"tokens.color.surface.white","original_key":"surface.white","source_group":"color","conflict_note":"NONE","import_status":"CANDIDATE_ONLY","source_artifact":"SALY_DS_V1","source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","source_revision":"1.0.0-candidate.1","original_payload":{"type":"color","usage":"Card protagonista y superficies","value":"#FFFFFF","status":"candidate"},"source_pr_number":3715,"canonical_binding":"NOT_MAPPED_TO_APPROVED_KEYS","source_git_commit":"ccb1ce125f21f85a3fe163d5839e4f0fedaaa0ac"},"created_at":"2026-11-19T04:42:16.338081+00:00","project_id":2,"updated_at":"2026-11-24T19:10:06.829817+00:00","value_type":"COLOR","decision_id":null,"description":"Imported candidate from SALY_DS_V1; not effective or approved","is_required":false,"is_protected":false}'::jsonb);
INSERT INTO saly.identity_elements SELECT * FROM jsonb_populate_record(NULL::saly.identity_elements,'{"id":5,"code":"color.action.primary.bg","name":"Saly Primary Action Green","family":"COLOR","status":"ACTIVE","metadata":{"approval_authority":"OWNER_EXPLICIT_CHAT_CONFIRMATION","approval_date_local":"2026-11-18","protected_semantics":"REQUIRES_GOVERNED_CHANGE","base_variants_source":"SALY brand identity Library and SALY_DS_V1 candidate","approval_conversation_scope":"SALY_GREEN_BRAND_AND_CTA_ONLY"},"created_at":"2026-11-19T04:14:05.647965+00:00","project_id":2,"updated_at":"2026-11-19T04:14:05.647965+00:00","value_type":"COLOR","decision_id":null,"description":"Approved darker SALY green for primary buttons and white functional text.","is_required":true,"is_protected":true}'::jsonb);
INSERT INTO saly.identity_elements SELECT * FROM jsonb_populate_record(NULL::saly.identity_elements,'{"id":4,"code":"color.brand.primary","name":"Saly Primary Green","family":"COLOR","status":"ACTIVE","metadata":{"approval_authority":"OWNER_EXPLICIT_CHAT_CONFIRMATION","approval_date_local":"2026-11-18","protected_semantics":"REQUIRES_GOVERNED_CHANGE","base_variants_source":"SALY brand identity Library and SALY_DS_V1 candidate","approval_conversation_scope":"SALY_GREEN_BRAND_AND_CTA_ONLY"},"created_at":"2026-11-19T04:14:05.647965+00:00","project_id":2,"updated_at":"2026-11-19T04:14:05.647965+00:00","value_type":"COLOR","decision_id":null,"description":"Approved SALY brand/identity green. Accent and branding only; not white-text button.","is_required":true,"is_protected":true}'::jsonb);
INSERT INTO saly.identity_versions SELECT * FROM jsonb_populate_record(NULL::saly.identity_versions,'{"id":68,"metadata":{"applies_to":["PROTOTIPO_APP"],"token_role":"SUPERFICIE_BASE","source_path":"tokens.color.surface.white","conflict_note":"NONE","raw_value_type":"string","source_payload":{"type":"color","usage":"Card protagonista y superficies","value":"#FFFFFF","status":"candidate"},"source_git_blob":"551469ed451f60af43e874c4688451a210a82dc1","medium_provenance":"SALY_DS_V1_APP_CONFIRMED_ONLY","approval_authority":"OWNER_EXPLICIT_CHAT_CONFIRMATION","valid_from_meaning":"REGISTRY_ACTIVATION_NOT_RETROACTIVE_DESIGN_APPROVAL","applies_to_proposed":["REDES_SOCIALES","IMPRESION","PAPEL"],"approval_date_local":"2026-11-24","derived_from_version_id":12},"valid_to":null,"created_at":"2026-11-24T19:10:06.829817+00:00","element_id":8,"updated_at":"2026-11-24T19:10:06.829817+00:00","valid_from":"2026-11-24T19:10:06.829817+00:00","value_json":{"value":"#FFFFFF"},"decision_id":null,"channel_code":"GLOBAL","audience_code":"ALL","change_reason":"Owner approved existing candidate design system; original version preserved.","version_number":2,"approval_status":"APPROVED","approval_reference":"OWNER_CHAT_APPROVAL:2026-11-24T13:56-05:00:SALY_DESIGN_SYSTEM"}'::jsonb);
INSERT INTO saly.identity_versions SELECT * FROM jsonb_populate_record(NULL::saly.identity_versions,'{"id":8,"metadata":{"source":"LIBRARY:Identidad de Marca SALY.png","applies_to":["PROTOTIPO_APP"],"token_role":"MARCA","white_text_usage":"NOT_APPROVED_FOR_WHITE_TEXT_CTA","medium_provenance":"SALY_DS_V1_APP_CONFIRMED_ONLY","approval_authority":"OWNER_EXPLICIT_CHAT_CONFIRMATION","valid_from_meaning":"REGISTRY_ACTIVATION_NOT_RETROACTIVE_DESIGN_APPROVAL","applies_to_proposed":["REDES_SOCIALES","IMPRESION","PAPEL"],"approval_date_local":"2026-11-18"},"valid_to":null,"created_at":"2026-11-19T04:14:05.647965+00:00","element_id":4,"updated_at":"2026-11-19T04:14:05.647965+00:00","valid_from":"2026-11-19T04:14:05.647965+00:00","value_json":{"usage":"BRAND_ONLY_NOT_WHITE_TEXT_CTA","value":"#00C853","format":"HEX"},"decision_id":null,"channel_code":"GLOBAL","audience_code":"ALL","change_reason":"Owner selected #00C853 identity and #008200 CTA; other proposed SALY tokens not approved here.","version_number":1,"approval_status":"APPROVED","approval_reference":"OWNER_CHAT_APPROVAL:2026-11-18:SALY_GREEN_BRAND_CTA"}'::jsonb);
INSERT INTO saly.identity_versions SELECT * FROM jsonb_populate_record(NULL::saly.identity_versions,'{"id":7,"metadata":{"source":"GITHUB:PR3715:SALY_DS_V1_CANDIDATE","applies_to":["PROTOTIPO_APP"],"token_role":"CTA","white_text_usage":"WCAG_AA_NORMAL_TEXT_CONTRAST_VERIFIED_5_TO_1","medium_provenance":"SALY_DS_V1_APP_CONFIRMED_ONLY","approval_authority":"OWNER_EXPLICIT_CHAT_CONFIRMATION","valid_from_meaning":"REGISTRY_ACTIVATION_NOT_RETROACTIVE_DESIGN_APPROVAL","applies_to_proposed":[],"approval_date_local":"2026-11-18"},"valid_to":null,"created_at":"2026-11-19T04:14:05.647965+00:00","element_id":5,"updated_at":"2026-11-19T04:14:05.647965+00:00","valid_from":"2026-11-19T04:14:05.647965+00:00","value_json":{"usage":"CTA_BACKGROUND_FOR_WHITE_TEXT","value":"#008200","format":"HEX"},"decision_id":null,"channel_code":"GLOBAL","audience_code":"ALL","change_reason":"Owner selected #00C853 identity and #008200 CTA; other proposed SALY tokens not approved here.","version_number":1,"approval_status":"APPROVED","approval_reference":"OWNER_CHAT_APPROVAL:2026-11-18:SALY_GREEN_BRAND_CTA"}'::jsonb);
INSERT INTO visual.source_assets OVERRIDING SYSTEM VALUE SELECT * FROM jsonb_populate_record(NULL::visual.source_assets,'{"id":1,"file_ref":"1YXWAS8McVi0Y91FEtMbCW6M57-6D9em9","metadata":{"width_px":1086,"byte_size":1343036,"folder_id":"1qhQwIhuJJ-EvKFRDxEVf-R265_gGh-65","height_px":1448,"mime_type":"image/png","source_url":"https://drive.google.com/file/d/1YXWAS8McVi0Y91FEtMbCW6M57-6D9em9/view?usp=drivesdk","status_note":"CANDIDATE_ONLY_REQUIRES_APPROVAL_RECEIPT","verified_date":"2026-11-20","source_filename":"SALY_HOME_IPHONE16PRO_v1.1.png","byte_verification_method":"GOOGLE_DRIVE_AUTHENTICATED_RAW_DOWNLOAD_PYTHON_SHA256"},"provider":"GOOGLE_DRIVE","asset_code":"SALY_HOME_IPHONE16PRO","brand_code":"SALY","created_at":"2026-11-20T14:28:54.946554+00:00","source_kind":"SCREEN","approval_ref":null,"source_sha256":"3d80592dc94938ea6e4d34727a99a0aec242b43838e2815820b72e87d649d33e","version_number":1,"approval_status":"CANDIDATE","independent_sha_verified":true}'::jsonb);

-- LF fixture: synthetic order 25; intentionally distinct from protected order 23.
INSERT INTO saly.creative_context_sets(id,project_id,code,version_label,mode,state,sealed_at,provenance)
OVERRIDING SYSTEM VALUE VALUES
(9001,3,'LF_F1_CI_CTX','CI_V1','EXPLORE','SEALED',clock_timestamp(),
 '{"assets":[{"asset_code":"LF_BRAND_LOGO_1L_LIGHT_TRANSPARENT","filename":"LF_BRAND_LOGO_1L_LIGHT_TRANSPARENT.png","mime_type":"image/png","checksum_sha256":"898bd5f50ee588919ed0ccace4cfc4c0d7741efc178248bff2303c1893cabd81","storage_provider":"GOOGLE_DRIVE","storage_object_path":"197I1Gx7KTpEe_ZvCvvAWl9hUc-D5YSZa","brand_asset_id":5}]}'::text);
INSERT INTO saly.creative_context_tokens(context_set_id,identity_version_id,role,value_sha256)
VALUES (9001,125,'OFFICIAL','afc1a69dc102317aeb0a51f5cff57bf4e54930d67b00e384f552c4b3ed8b240c');

INSERT INTO saly.creative_orders(id,project_id,code,request_key,title,request_kind,design_mode,requested_by,scope_json,identity_snapshot,status,context_set_id)
OVERRIDING SYSTEM VALUE VALUES
(25,3,'LF_F1_CI_ORDER','lf-f1-ci-order-25','LF F1 CI synthetic','APP_SCREEN_SINGLE','EXPLORE','CI_F1',
 jsonb_build_object('queue_mode','SERIAL_V1','review_only',false,'render_authorized',true,'rendering_authority',true,
                    'original_literal_request','CI LF F1 synthetic request'),
 '{}'::jsonb,'PLANIFICADO',9001);

WITH m AS (
 SELECT jsonb_build_array(jsonb_build_object('speaker','USER','text','CI LF F1 synthetic request')) msgs
), s AS (
 SELECT jsonb_build_object(
   'schema_version','SALY_SEMANTIC_QA_L3C_V1','scope','SCREEN','source_type','OWNER_LITERAL',
   'require_artifact_evidence',true,'require_independent_interpretation',true,
   'original_messages',msgs,
   'original_request_sha256',encode(extensions.digest(convert_to(msgs::text,'UTF8'),'sha256'),'hex'),
   'interpretation',jsonb_build_object(
      'change',jsonb_build_array('CI change'),'creative_freedom','CI constrained',
      'evaluation_basis','CI exact contract','excluded',jsonb_build_array('No production'),
      'interpretation_origin','ASSISTANT_INTERPRETATION_SEPARATE_FROM_USER_LITERAL',
      'objective','Exercise F1 gates','preserve',jsonb_build_array('Governed context'),'screens',jsonb_build_array('CI screen')),
   'checks',jsonb_build_array(
      jsonb_build_object('code','LF_SEM_LITERAL','expected','MATCH','severity','BLOCK'),
      jsonb_build_object('code','LF_SEM_ASSET','expected','VERIFIED','severity','BLOCK'),
      jsonb_build_object('code','LF_SEM_CONTEXT','expected','SEALED','severity','BLOCK'),
      jsonb_build_object('code','LF_SEM_SNAPSHOT','expected','CANONICAL','severity','BLOCK'),
      jsonb_build_object('code','LF_SEM_QA','expected','INDEPENDENT','severity','BLOCK'))
 ) sem FROM m
)
INSERT INTO saly.creative_order_items(id,order_id,code,ordinal,kind,title,required,acceptance_json,context_json,status)
OVERRIDING SYSTEM VALUE
SELECT 2501,25,'LF_F1_SCREEN',1,'SCREEN','LF F1 synthetic screen',true,
       jsonb_build_object('qa_required',true,'semantic_qa',sem),
       jsonb_build_object('token_codes',jsonb_build_array('lf.source.colors.green_action'),
          'asset_codes',jsonb_build_array('LF_BRAND_LOGO_1L_LIGHT_TRANSPARENT'),
          'screen_spec',jsonb_build_object('device','IPHONE16PRO','screen','CI_LF')),
       'PENDIENTE'
FROM s;

-- SALY control fixture: three minimal canonical identity tokens + one verified visual source.
INSERT INTO saly.creative_context_sets(id,project_id,code,version_label,mode,state,sealed_at,provenance)
OVERRIDING SYSTEM VALUE VALUES
(9100,2,'SALY_F1_CI_CTX','CI_V1','EXPLORE','SEALED',clock_timestamp(),'CI_F1_STATIC');
INSERT INTO saly.creative_context_tokens(context_set_id,identity_version_id,role,value_sha256) VALUES
(9100,7,'OFFICIAL','f52bd036b0760f64f6222f25d95ebe0c56859cbef34dec923c7af8cd5c09ca52'),
(9100,8,'OFFICIAL','e0bc5fc47e1f2fa3bdd1d51b34356594a0ee88d39d107562cd7a4a2d1de27b7f'),
(9100,68,'EXISTING','0719a985e5f09e61620906078676ecfe93c63810dca870702b834754d1b7046c');

INSERT INTO saly.creative_orders(id,project_id,code,request_key,title,request_kind,design_mode,requested_by,scope_json,identity_snapshot,status,context_set_id)
OVERRIDING SYSTEM VALUE VALUES
(9100,2,'SALY_F1_CI_ORDER','saly-f1-ci-order','SALY F1 CI control','APP_SCREEN_SINGLE','EXPLORE','CI_F1',
 jsonb_build_object('queue_mode','SERIAL_V1','review_only',false,'render_authorized',true,'rendering_authority',true),
 '{}'::jsonb,'PLANIFICADO',9100);

WITH base AS (
 SELECT jsonb_build_object(
  'art','CI frontal app screen','cta','CI CTA','free','[]'::jsonb,'mode','PLAN_ONLY','brand','SALY',
  'guided',jsonb_build_array('Preserve canonical tokens'),'intent','CI parity control',
  'output',jsonb_build_object('count',1,'format','PNG','dimensions',jsonb_build_array(1086,1448)),
  'bindings',jsonb_build_object('CTA fondo','color.action.primary.bg','CTA texto','candidate.saly_ds_v1.color.surface.white','Identidad','color.brand.primary'),
  'hierarchy',jsonb_build_array('Header','Main CTA'),
  'copy_locked',jsonb_build_object('base','CI only','overrides','[]'::jsonb),
  'layout_lock','CI deterministic layout','visual_lock','CI deterministic visual lock',
  'restrictions',jsonb_build_array('No production'),
  'reference_sha256','3d80592dc94938ea6e4d34727a99a0aec242b43838e2815820b72e87d649d33e'
 ) b
), locked AS (
 SELECT b, jsonb_build_object('LOCK',
      jsonb_build_object('cta',b->'cta','output',b->'output','bindings',b->'bindings','hierarchy',b->'hierarchy',
        'copy_locked',b->'copy_locked','layout_lock',b->'layout_lock','visual_lock',b->'visual_lock',
        'restrictions',b->'restrictions','reference_sha256',b->'reference_sha256'),
      'GUIDED',b->'guided','FREE',b->'free') dl FROM base
), bp AS (
 SELECT b||jsonb_build_object('schema_version','CREATIVE_VISUAL_BLUEPRINT_V1','design_lock',dl,
   'design_lock_sha256',encode(extensions.digest(convert_to(dl::text,'UTF8'),'sha256'),'hex')) blueprint FROM locked
)
INSERT INTO saly.creative_order_items(id,order_id,code,ordinal,kind,title,required,acceptance_json,context_json,status)
OVERRIDING SYSTEM VALUE
SELECT 9101,9100,'SALY_F1_SCREEN',1,'SCREEN','SALY F1 parity screen',true,
 jsonb_build_object('qa_required',true,'visual_rules',jsonb_build_object('scope','SALY_F1_CI_ORDER','no_decorative_rays',true)),
 jsonb_build_object('screen_spec',jsonb_build_object('device','IPHONE16PRO','screen','CI_SALY','visual_blueprint',blueprint)),
 'PENDIENTE'
FROM bp;
INSERT INTO saly.creative_item_sources(id,order_id,item_id,source_asset_id,purpose,source_sha256)
OVERRIDING SYSTEM VALUE VALUES
(9101,9100,9101,1,'VISUAL_REFERENCE','3d80592dc94938ea6e4d34727a99a0aec242b43838e2815820b72e87d649d33e');
