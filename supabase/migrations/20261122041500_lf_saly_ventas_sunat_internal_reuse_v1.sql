-- SALY SUNAT internal-use decision only. Keep all runtime and persistence switches OFF.
BEGIN;
DO $sunat_reuse$
DECLARE
 v_exec text;
 v_policy jsonb;
 v_next jsonb;
 v_rights_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch/skills/ai_sales_discovery/contracts/SUNAT_INTERNAL_REUSE_DECISION_V18.md';
 v_n integer;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_saly_ventas_sunat_internal_reuse_v1' AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'SUNAT_REUSE_GOVERNED_TRAIN_REQUIRED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY_DISCOVERY:SUNAT_POLICY_V1',0));
 SELECT config_value::jsonb INTO STRICT v_policy FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1' AND value_status='REAL'
 AND valid_from <= now() ORDER BY valid_from DESC LIMIT 1 FOR SHARE;
 IF v_policy IS DISTINCT FROM '{"qa_run":"44957217395","enabled":false,"source_id":"PE-SUNAT-RUC","monthly_url":"https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip","reduced_url":"https://www2.sunat.gob.pe/padron_reducido_ruc.zip","monthly_license":"ODC-BY","reduced_rights_status":"PENDIENTE_VERIFICAR","rights_review_required":true}'::jsonb
 OR (SELECT count(*) FROM saly.ventas_discovery_catalogo WHERE source_id='PE-SUNAT-RUC')<>1
 OR EXISTS(SELECT 1 FROM saly.ventas_discovery_ingestas WHERE source_id='PE-SUNAT-RUC')
 THEN RAISE EXCEPTION 'SUNAT_REUSE_PRESTATE_DRIFT'; END IF;
 v_next:=v_policy||$decision${"enabled":false,"rights_review_required":false,"reduced_rights_status":"PERSISTENCIA_PERMITIDA","monthly_rights":"ODC-BY","reduced_rights":"INTERNAL_USE_APPROVED_PUBLIC_BUSINESS_FACTS_NOT_EXTERNAL_LICENSE","license":"ODC-BY_MONTHLY_PUBLIC_FACTS_REDUCED_INTERNAL_USE","attribution":"SUNAT — Padrón RUC mensual y Padrón Reducido; fuentes oficiales, conservar URL, periodo y SHA-256","rights_evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/skills/ai_sales_discovery/contracts/SUNAT_INTERNAL_REUSE_DECISION_V18.md","rights_scope":"SALY_B2B_INTERNAL_BUSINESS_FACTS_LIMA_ICA_RUC20","reevaluate_on_material_change":true,"reduced_specific_license_verified":false,"external_legal_opinion_verified":false,"manifest_evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/skills/ai_sales_discovery/tests/evidence/sunat_pinned_batch_plan_20261121.json","manifest_digest_sha256":"3e12083fc487a4d1281e69b0868676fa66f0be42ad3d41966662a610545bd77e"}$decision$::jsonb||jsonb_build_object('rights_decision_execution_id',v_exec);
 UPDATE saly.ventas_discovery_catalogo SET rights_status='PERSISTENCIA_PERMITIDA',
 rights_checked_at=clock_timestamp(), rights_evidence_ref=v_rights_ref
 WHERE catalog_version='PE-SALY-DISCOVERY-2026-11-V0.2' AND source_id='PE-SUNAT-RUC' AND connector_id='SALY-U07-S12-C01' AND substep_code='12.01'
 AND rights_status='PENDIENTE_VERIFICAR' AND rights_checked_at IS NULL AND rights_evidence_ref IS NULL
 AND NOT habilitada AND NOT persist_business_data AND runtime_status='SPEC_ONLY_NOT_CONNECTED';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'SUNAT_REUSE_CATALOG_DRIFT'; END IF;
 INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status,description,valid_from)
 VALUES('SALY_DISCOVERY','SUNAT_POLICY_V1',v_next::text,'JSON','REAL',
 'Decisión de uso B2B interno aprobada; no equivale a licencia del reducido. Runtime deshabilitado; caller y límites pendientes.',clock_timestamp());
 IF NOT EXISTS(SELECT 1 FROM saly.ventas_discovery_catalogo WHERE source_id='PE-SUNAT-RUC'
 AND rights_status='PERSISTENCIA_PERMITIDA' AND rights_evidence_ref=v_rights_ref AND rights_checked_at IS NOT NULL
 AND NOT habilitada AND NOT persist_business_data AND runtime_status='SPEC_ONLY_NOT_CONNECTED')
 OR (SELECT config_value::jsonb FROM public.lf_global_config WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1' AND value_status='REAL' ORDER BY valid_from DESC LIMIT 1) IS DISTINCT FROM v_next
 OR v_next->'enabled' IS DISTINCT FROM 'false'::jsonb
 OR EXISTS(SELECT 1 FROM saly.ventas_discovery_ingestas WHERE source_id='PE-SUNAT-RUC')
 OR has_function_privilege('service_role','saly.ventas_sunat_ingesta_core_v1(uuid,text)','EXECUTE')
 OR has_function_privilege('authenticated','saly.ventas_sunat_ingesta_core_v1(uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'SUNAT_REUSE_POSTSTATE_MISMATCH'; END IF;
END $sunat_reuse$;
COMMIT;
