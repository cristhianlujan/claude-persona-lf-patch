-- OECE Socios 195 candidates: PostgreSQL 17 isolated post-import positive/negative.
\set ON_ERROR_STOP on
DO $pre$
BEGIN
 IF current_database()<>'saly_vinculos_ci'
 OR current_setting('server_version_num')::int / 10000 <> 17
 THEN RAISE EXCEPTION 'OECE_IMPORT_UNSAFE_TEST_TARGET'; END IF;
 IF (SELECT count(*) FROM saly.ventas_vinculos_empresariales_v1
 WHERE fuente_id='PE-OECE-RNP-SOCIOS' AND fuente_version='att106893232:v1:2021-11-11')<>195
 THEN RAISE EXCEPTION 'OECE_IMPORT_EXPECTED_195_MISSING'; END IF;
 IF (SELECT count(DISTINCT empresa_ruc) FROM saly.ventas_vinculos_empresariales_v1
 WHERE fuente_id='PE-OECE-RNP-SOCIOS')<>161
 OR (SELECT count(DISTINCT vinculada_ruc) FROM saly.ventas_vinculos_empresariales_v1
 WHERE fuente_id='PE-OECE-RNP-SOCIOS')<>75
 THEN RAISE EXCEPTION 'OECE_IMPORT_CANDIDATES_COUNT_MISMATCH'; END IF;
 IF (SELECT count(*) FROM saly.ventas_vinculos_evidencias_v1)<>195
 OR (SELECT count(*) FROM saly.ventas_vinculos_empresariales_v1)<>195
 THEN RAISE EXCEPTION 'OECE_IMPORT_EVIDENCE_COUNT_MISMATCH'; END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='saly' AND c.relname IN
  ('ventas_vinculos_empresariales_v1','ventas_vinculos_evidencias_v1')
 AND c.relrowsecurity AND c.relforcerowsecurity)<>2
 THEN RAISE EXCEPTION 'OECE_IMPORT_RLS_NOT_FORCED'; END IF;
 IF has_table_privilege('anon','saly.ventas_vinculos_empresariales_v1','SELECT')
 OR has_table_privilege('authenticated','saly.ventas_vinculos_evidencias_v1','INSERT')
 THEN RAISE EXCEPTION 'OECE_IMPORT_UNEXPECTED_CLIENT_GRANT'; END IF;
 IF EXISTS(SELECT 1 FROM saly.ventas_vinculos_empresariales_v1 v
 LEFT JOIN saly.ventas_vinculos_evidencias_v1 e ON e.vinculo_id=v.id
 WHERE e.id IS NULL)
 THEN RAISE EXCEPTION 'OECE_IMPORT_LINK_WITHOUT_EVIDENCE'; END IF;
 RAISE NOTICE 'PASS_OECE_SOCIOS_195_161_75_WITH_RLS_AND_EVIDENCE';
END $pre$;
BEGIN;
DO $negative$
DECLARE v_failed boolean; v_id uuid;
BEGIN
 v_failed:=false;
 BEGIN
 INSERT INTO saly.ventas_vinculos_empresariales_v1
  (empresa_ruc,vinculada_ruc,tipo_relacion,estado,fuente_id,fuente_version,fuente_corte)
 SELECT empresa_ruc,vinculada_ruc,tipo_relacion,estado,fuente_id,fuente_version,fuente_corte
 FROM saly.ventas_vinculos_empresariales_v1 LIMIT 1;
 EXCEPTION WHEN unique_violation THEN v_failed:=true; END;
 IF NOT v_failed THEN RAISE EXCEPTION 'OECE_DUPLICATE_LINK_NOT_REJECTED'; END IF;
 v_failed:=false;
 BEGIN
 INSERT INTO saly.ventas_vinculos_empresariales_v1
 (empresa_ruc,vinculada_ruc,tipo_relacion,estado,fuente_id,fuente_version,fuente_corte)
 VALUES ('20100000001','20100000002','CONTROL_ACCIONARIO','CONTROL_VERIFICADO',
 'FIXTURE','TEST','2021-11-11');
 EXCEPTION WHEN check_violation THEN v_failed:=true; END;
 IF NOT v_failed THEN RAISE EXCEPTION 'OECE_UNPROVEN_CONTROL_NOT_REJECTED'; END IF;
 v_failed:=false;
 BEGIN
 INSERT INTO saly.ventas_vinculos_empresariales_v1
 (empresa_ruc,vinculada_ruc,tipo_relacion,estado,fuente_id,fuente_version,fuente_corte)
 VALUES ('20100000001','10100000002','SOCIO_DECLARADO','CANDIDATO',
 'FIXTURE','TEST','2021-11-11');
 EXCEPTION WHEN check_violation THEN v_failed:=true; END;
 IF NOT v_failed THEN RAISE EXCEPTION 'OECE_NON_JURIDICAL_OWNER_NOT_REJECTED'; END IF;
 SELECT id INTO v_id FROM saly.ventas_vinculos_empresariales_v1
 WHERE fuente_id='PE-OECE-RNP-SOCIOS' LIMIT 1;
 v_failed:=false;
 BEGIN
 INSERT INTO saly.ventas_vinculos_evidencias_v1
 (vinculo_id,evidencia_ref,url_fuente,clase_evidencia,derechos_estado)
 SELECT vinculo_id,evidencia_ref,url_fuente,clase_evidencia,derechos_estado
 FROM saly.ventas_vinculos_evidencias_v1 WHERE vinculo_id=v_id LIMIT 1;
 EXCEPTION WHEN unique_violation THEN v_failed:=true; END;
 IF NOT v_failed THEN RAISE EXCEPTION 'OECE_DUPLICATE_EVIDENCE_NOT_REJECTED'; END IF;
 RAISE NOTICE 'PASS_OECE_SOCIOS_NEGATIVE_CONSTRAINTS';
END $negative$;
ROLLBACK;
DO $post$
BEGIN
 IF (SELECT count(*) FROM saly.ventas_vinculos_empresariales_v1)<>195
 OR (SELECT count(*) FROM saly.ventas_vinculos_evidencias_v1)<>195
 THEN RAISE EXCEPTION 'OECE_SOCIOS_ROLLBACK_COUNT_CHANGED'; END IF;
 RAISE NOTICE 'PASS_OECE_SOCIOS_PG17_NEGATIVE_ROLLBACK_CLEAN';
END $post$;
