-- Frozen Step10 source specification 12.01_PE-SUNAT-RUC.json
-- SHA256 32b1d98b2c0c0d2d493799c229b8563a93e1222e8509fff529df3cf47ed79c5f.
BEGIN;
DO $register$
DECLARE
 v_catalog constant text := 'PE-SALY-DISCOVERY-2026-11-V0.2';
 v_source constant text := 'PE-SUNAT-RUC';
 v_policy jsonb := jsonb_build_object('enabled',false,'source_id',v_source,
 'monthly_url','https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip',
 'reduced_url','https://www2.sunat.gob.pe/padron_reducido_ruc.zip',
 'monthly_license','ODC-BY','reduced_rights_status','PENDIENTE_VERIFICAR',
 'qa_run','44957217395','rights_review_required',true);
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY_DISCOVERY.SUNAT_POLICY_V1',0));
 INSERT INTO saly.ventas_discovery_catalogo(catalog_version,source_id,connector_id,substep_code,step,
 familia,nombre,landing_page,rights_status,persist_business_data,habilitada,runtime_status)
 VALUES(v_catalog,v_source,'SALY-U07-S12-C01','12.01',12,'ESTADO_NACIONAL','SUNAT padrón RUC y anexos',
 'https://www.sunat.gob.pe/descargaPRR/mrc137_padron_reducido.html','PENDIENTE_VERIFICAR',false,false,'SPEC_ONLY_NOT_CONNECTED')
 ON CONFLICT (catalog_version,source_id) DO NOTHING;
 IF NOT EXISTS(SELECT FROM saly.ventas_discovery_catalogo WHERE catalog_version=v_catalog AND source_id=v_source
 AND connector_id='SALY-U07-S12-C01' AND substep_code='12.01' AND familia='ESTADO_NACIONAL'
 AND rights_status='PENDIENTE_VERIFICAR' AND NOT habilitada AND NOT persist_business_data)
 THEN RAISE EXCEPTION 'SUNAT_CATALOG_REGISTRATION_DRIFT'; END IF;
 IF NOT EXISTS (SELECT FROM public.lf_global_config WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1')
 THEN INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status,description)
 VALUES('SALY_DISCOVERY','SUNAT_POLICY_V1',v_policy::text,'JSON','REAL','Registro de fuente SUNAT; activación y límites del escritor pendientes.');
 END IF;
 IF (SELECT count(*) FROM public.lf_global_config WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1')<>1
 OR NOT EXISTS(SELECT FROM public.lf_global_config WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
 AND config_value::jsonb=v_policy AND value_status='REAL')
 THEN RAISE EXCEPTION 'SUNAT_POLICY_REGISTRATION_DRIFT'; END IF;
END $register$;
COMMIT;
