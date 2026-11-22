-- Read only; diagnostic, not authorization. Verified in actual SALY on 2026-11-21.
WITH cfg AS (
 SELECT config_value::text AS raw FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1' AND value_status='REAL' AND valid_from<=now()
 ORDER BY valid_from DESC LIMIT 1
), policy AS (
 SELECT CASE WHEN pg_input_is_valid(raw,'jsonb') THEN raw::jsonb END AS j FROM cfg
), writer AS (
 SELECT p.oid,p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='saly' AND p.oid=to_regprocedure('saly.ventas_sunat_ingesta_core_v1(uuid,text)')
)
SELECT k.source_id,k.habilitada,k.persist_business_data,k.rights_status,k.rights_evidence_ref IS NOT NULL AS rights_evidence_present,
 jsonb_typeof(p.j) AS policy_json_type,(p.j->'enabled') IS NOT DISTINCT FROM 'true'::jsonb AS policy_enabled,
 coalesce(p.j->>'max_rows','') ~ '^[1-9][0-9]{0,8}$' AS max_rows_valid,
 coalesce(p.j->>'max_bytes','') ~ '^[1-9][0-9]{0,8}$' AS max_bytes_valid,
 NOT EXISTS(SELECT FROM unnest(ARRAY['license','attribution','monthly_rights','reduced_rights']) f WHERE nullif(btrim(p.j->>f),'') IS NULL) AS policy_rights_fields_present,
 w.oid IS NOT NULL AS writer_present,w.prosecdef AS writer_security_definer,
 has_function_privilege('service_role',w.oid,'EXECUTE') AS service_exec,
 has_function_privilege('authenticated',w.oid,'EXECUTE') AS authenticated_exec,
 (SELECT count(*) FROM saly.ventas_discovery_ingestas i WHERE i.source_id=k.source_id) AS ingestas,
 (SELECT count(*) FROM saly.ventas_hallazgos h JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id WHERE i.source_id=k.source_id) AS hallazgos
FROM saly.ventas_discovery_catalogo k LEFT JOIN policy p ON true LEFT JOIN writer w ON true WHERE k.source_id='PE-SUNAT-RUC';
