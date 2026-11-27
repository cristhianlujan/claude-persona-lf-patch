-- S22-BC: Claude approved exact mapping; draft PG17 rollback only.
BEGIN;
CREATE TEMP TABLE s22bc_mapping(codigo text PRIMARY KEY,capa text CHECK(capa IN ('BACKEND','FRONTEND','AMBOS'))) ON COMMIT DROP;
INSERT INTO s22bc_mapping VALUES
('S12-C01','BACKEND'),
('S12-C02','BACKEND'),
('S12-C03','BACKEND'),
('S12-C04','BACKEND'),
('S12-C05','BACKEND'),
('S12-C13','BACKEND'),
('S12-C15','BACKEND'),
('S12-C16','BACKEND'),
('S13-C11','BACKEND'),
('S13-C15','BACKEND'),
('S13-C17','BACKEND'),
('S19-C09','BACKEND'),
('S19-C10','BACKEND'),
('S19-C11','BACKEND'),
('S21-C02','BACKEND'),
('S21-C07','BACKEND'),
('S22A-C01','BACKEND'),
('S22A-C02','BACKEND'),
('S22AB-C06','BACKEND'),
('S22AD-C08','BACKEND'),
('S22AO-422-1','BACKEND'),
('S22B-C06','BACKEND'),
('S22C-C04','BACKEND'),
('S22D-C01','BACKEND'),
('S22E-C01','BACKEND'),
('S22J-C04','BACKEND'),
('S22K-C02','BACKEND'),
('S22K-C03','BACKEND'),
('S22K-C05','BACKEND'),
('S22Q-C05','BACKEND'),
('S22Q-C06','BACKEND'),
('S22Q-C07','BACKEND'),
('S22V-C09','BACKEND'),
('S22W-C01','BACKEND'),
('S22W-C02','BACKEND'),
('S22W-C04','BACKEND'),
('S22W-C06','BACKEND'),
('S22W-C08','BACKEND'),
('S22X-C08','BACKEND'),
('S22Y-C01','BACKEND'),
('S22Y-C03','BACKEND'),
('S22Y-C05','BACKEND'),
('S22Y-C06','BACKEND'),
('S22Z-C01','BACKEND'),
('S22Z-C08','BACKEND'),
('M4C-C06','FRONTEND'),
('M4C-C07','FRONTEND'),
('M4C-C08','FRONTEND'),
('S11-C03','FRONTEND'),
('S11-C20','FRONTEND'),
('S11-C21','FRONTEND'),
('S11-C22','FRONTEND'),
('S11-C23','FRONTEND'),
('S11-C24','FRONTEND'),
('S11-C25','FRONTEND'),
('S12-C09','FRONTEND'),
('S12-C10','FRONTEND'),
('S13-C01','FRONTEND'),
('S13-C04','FRONTEND'),
('S13-C10','FRONTEND'),
('S13-C14','FRONTEND'),
('S16-C03','FRONTEND'),
('S19-C01','FRONTEND'),
('S20-C01','FRONTEND'),
('S21-C01','FRONTEND'),
('S22AA-C03','FRONTEND'),
('S22AA-C04','FRONTEND'),
('S22AB-C02','FRONTEND'),
('S22C-C03','FRONTEND'),
('S22K-C04','FRONTEND'),
('S22L-C04','FRONTEND'),
('S22V-C04','FRONTEND'),
('S22V-C06','FRONTEND'),
('S22V-C07','FRONTEND'),
('S22X-C06','FRONTEND'),
('S22Z-C06','FRONTEND'),
('S7-C11','FRONTEND'),
('S8-C03','FRONTEND'),
('S8-C04','FRONTEND'),
('S8-C05','FRONTEND'),
('S8-C06','FRONTEND'),
('S8-C23','FRONTEND'),
('S8-C24','FRONTEND'),
('M3-C04','AMBOS'),
('S12-C06','AMBOS'),
('S12-C07','AMBOS'),
('S12-C12','AMBOS'),
('S13-C09','AMBOS'),
('S13-C12','AMBOS'),
('S13-C13','AMBOS'),
('S16-C04','AMBOS'),
('S17-C01','AMBOS'),
('S19-C12','AMBOS'),
('S22AA-C06','AMBOS'),
('S22AA-C07','AMBOS'),
('S22AB-C01','AMBOS'),
('S22AB-C03','AMBOS'),
('S22AB-C04','AMBOS'),
('S22AF-C03','AMBOS'),
('S22AO-13139-1','AMBOS'),
('S22AO-617-1','AMBOS'),
('S22AO-617-2','AMBOS'),
('S22AO-620-1','AMBOS'),
('S22B-C05','AMBOS'),
('S22BA-448-1','AMBOS'),
('S22C-C01','AMBOS'),
('S22C-C02','AMBOS'),
('S22E-C05','AMBOS'),
('S22K-C01','AMBOS'),
('S22Q-C04','AMBOS'),
('S22Q-C08','AMBOS'),
('S22V-C01','AMBOS'),
('S22V-C02','AMBOS'),
('S22V-C03','AMBOS'),
('S22V-C08','AMBOS'),
('S22W-C03','AMBOS'),
('S22W-C05','AMBOS'),
('S22W-C07','AMBOS'),
('S22W-C09','AMBOS'),
('S22X-C01','AMBOS'),
('S22X-C02','AMBOS'),
('S22X-C03','AMBOS'),
('S22X-C04','AMBOS'),
('S22X-C05','AMBOS'),
('S22X-C07','AMBOS'),
('S22X-C09','AMBOS'),
('S22Y-C02','AMBOS'),
('S22Y-C04','AMBOS'),
('S22Y-C07','AMBOS'),
('S22Y-C08','AMBOS'),
('S22Z-C02','AMBOS'),
('S22Z-C03','AMBOS'),
('S22Z-C04','AMBOS'),
('S22Z-C05','AMBOS'),
('S22Z-C07','AMBOS'),
('S5-C23','AMBOS'),
('S7-C02','AMBOS'),
('S7-C08','AMBOS'),
('S12-C08',NULL::text),
('S12-C11',NULL::text),
('S12-C14',NULL::text),
('S12-C17',NULL::text),
('S12-C18',NULL::text),
('S13-C08',NULL::text),
('S21-C08',NULL::text),
('S22AB-C05',NULL::text),
('S22J-C03',NULL::text),
('S22L-C03',NULL::text),
('S22L-C05',NULL::text),
('S22M-C01',NULL::text),
('S22M-C02',NULL::text),
('S22S-C02',NULL::text),
('S22S-C03',NULL::text),
('S22S-C04',NULL::text),
('S22V-C05',NULL::text);
DO $bc$
DECLARE
 before_data jsonb; after_data jsonb; before_layers jsonb; after_layers jsonb;
 before_counts jsonb; after_counts jsonb; changed jsonb; expected jsonb;
 cov_before bigint; cov_after bigint; digest_before text; digest_after text;
 t record; verdict text; suite text:='';
BEGIN
 IF (SELECT count(*) FROM s22bc_mapping)<>155 OR (SELECT count(*) FROM s22bc_mapping WHERE capa IS NOT NULL)<>138 THEN RAISE EXCEPTION 'S22BC_MAPPING_COUNT'; END IF;
 IF EXISTS(SELECT codigo FROM lf_ops.nucleo_reglas WHERE capa_ejecucion IS NULL EXCEPT SELECT codigo FROM s22bc_mapping) OR EXISTS(SELECT codigo FROM s22bc_mapping EXCEPT SELECT codigo FROM lf_ops.nucleo_reglas WHERE capa_ejecucion IS NULL) THEN RAISE EXCEPTION 'S22BC_SOURCE_SET_DRIFT'; END IF;
 SELECT jsonb_build_object('lf_rules',(SELECT coalesce(jsonb_agg(to_jsonb(x)-'capa_ejecucion' ORDER BY codigo),'[]'::jsonb) FROM lf_ops.nucleo_reglas x),'lf_versions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version),'[]'::jsonb) FROM lf_ops.nucleo_regla_versiones x),'lf_coverage',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY legacy_id,nucleo_codigo,version_nucleo),'[]'::jsonb) FROM lf_ops.lf_nucleo_cobertura_legada x),'lf_apps',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,nodo),'[]'::jsonb) FROM lf_ops.nucleo_aplicaciones x),'lf_tests',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version,n),'[]'::jsonb) FROM lf_ops.nucleo_regla_pruebas x),'saly_rules',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY codigo),'[]'::jsonb) FROM saly.nucleo_reglas x),'saly_versions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version),'[]'::jsonb) FROM saly.nucleo_regla_versiones x),'saly_apps',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,nodo),'[]'::jsonb) FROM saly.nucleo_aplicaciones x),'saly_tests',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version,n),'[]'::jsonb) FROM saly.nucleo_regla_pruebas x)) INTO before_data;
 SELECT jsonb_object_agg(codigo,capa_ejecucion) INTO before_layers FROM lf_ops.nucleo_reglas;
 SELECT jsonb_build_object('BACKEND',count(*) FILTER(WHERE capa_ejecucion='BACKEND'),'FRONTEND',count(*) FILTER(WHERE capa_ejecucion='FRONTEND'),'AMBOS',count(*) FILTER(WHERE capa_ejecucion='AMBOS'),'NULL',count(*) FILTER(WHERE capa_ejecucion IS NULL)) INTO before_counts FROM lf_ops.nucleo_reglas;
 SELECT count(DISTINCT legacy_id) INTO cov_before FROM lf_ops.lf_nucleo_cobertura_legada WHERE estado_cobertura='REEMPLAZADA';
 SELECT encode(sha256(convert_to(before_data::text,'UTF8')),'hex') INTO digest_before;
 WITH u AS (UPDATE lf_ops.nucleo_reglas r SET capa_ejecucion=m.capa FROM s22bc_mapping m WHERE r.codigo=m.codigo AND r.capa_ejecucion IS NULL AND m.capa IS NOT NULL RETURNING r.codigo,r.capa_ejecucion)
 SELECT jsonb_object_agg(codigo,capa_ejecucion) INTO changed FROM u;
 SELECT jsonb_object_agg(codigo,capa) INTO expected FROM s22bc_mapping WHERE capa IS NOT NULL;
 IF changed IS DISTINCT FROM expected THEN RAISE EXCEPTION 'S22BC_UPDATED_SET_DRIFT'; END IF;
 SELECT jsonb_object_agg(codigo,capa_ejecucion) INTO after_layers FROM lf_ops.nucleo_reglas;
 IF after_layers IS DISTINCT FROM before_layers||expected THEN RAISE EXCEPTION 'S22BC_LAYER_DRIFT'; END IF;
 IF EXISTS(SELECT codigo FROM lf_ops.nucleo_reglas WHERE capa_ejecucion IS NULL EXCEPT SELECT codigo FROM s22bc_mapping WHERE capa IS NULL) OR EXISTS(SELECT codigo FROM s22bc_mapping WHERE capa IS NULL EXCEPT SELECT codigo FROM lf_ops.nucleo_reglas WHERE capa_ejecucion IS NULL) THEN RAISE EXCEPTION 'S22BC_NULL_SET_DRIFT'; END IF;
 SELECT jsonb_build_object('BACKEND',count(*) FILTER(WHERE capa_ejecucion='BACKEND'),'FRONTEND',count(*) FILTER(WHERE capa_ejecucion='FRONTEND'),'AMBOS',count(*) FILTER(WHERE capa_ejecucion='AMBOS'),'NULL',count(*) FILTER(WHERE capa_ejecucion IS NULL)) INTO after_counts FROM lf_ops.nucleo_reglas;
 IF after_counts IS DISTINCT FROM jsonb_build_object('BACKEND',234,'FRONTEND',389,'AMBOS',77,'NULL',17) THEN RAISE EXCEPTION 'S22BC_COUNTS_DRIFT %',after_counts; END IF;
 FOR t IN SELECT * FROM (VALUES ('lf_ops','puerta','PUERTA 26/26'),('lf_ops','evaluacion','EVALUACION 23/23'),('lf_ops','cambio','CAMBIO 16/16'),('lf_ops','contrato','CONTRATO 4/4 (12 casos)'),('lf_ops','calculo','CALCULO 36/36'),('lf_ops','profundidad','PROFUNDIDAD 13/13'),('lf_ops','alcance_inverso','ALCANCE_INVERSO 10/10'),('saly','puerta','PUERTA 26/26'),('saly','evaluacion','EVALUACION 23/23'),('saly','cambio','CAMBIO 16/16'),('saly','contrato','CONTRATO 4/4 (12 casos)'),('saly','calculo','CALCULO 36/36'),('saly','profundidad','PROFUNDIDAD 13/13'),('saly','alcance_inverso','ALCANCE_INVERSO 10/10')) x(esquema,nombre,esperado) LOOP
 EXECUTE format('SELECT %I.%I()',t.esquema,'nucleo_autotest_'||t.nombre||'_v1') INTO verdict;
 IF verdict IS DISTINCT FROM t.esperado THEN RAISE EXCEPTION 'S22BC_AUTOTEST_FAIL %.% %',t.esquema,t.nombre,verdict; END IF;
 suite:=concat_ws(';',suite,t.esquema||'.'||verdict);
 END LOOP;
 IF public.lf_nucleo_autotest_conjunto_v1() IS DISTINCT FROM 'CONJUNTO 5/5' OR lf_ops.lf_puente_autotest_v1() IS DISTINCT FROM 'PUENTE 8/8' OR lf_ops.lf_puente2_autotest_v1() IS DISTINCT FROM 'PUENTE2 6/6' THEN RAISE EXCEPTION 'S22BC_CONJUNTO_OR_PUENTE_FAIL'; END IF;
 SELECT jsonb_build_object('lf_rules',(SELECT coalesce(jsonb_agg(to_jsonb(x)-'capa_ejecucion' ORDER BY codigo),'[]'::jsonb) FROM lf_ops.nucleo_reglas x),'lf_versions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version),'[]'::jsonb) FROM lf_ops.nucleo_regla_versiones x),'lf_coverage',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY legacy_id,nucleo_codigo,version_nucleo),'[]'::jsonb) FROM lf_ops.lf_nucleo_cobertura_legada x),'lf_apps',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,nodo),'[]'::jsonb) FROM lf_ops.nucleo_aplicaciones x),'lf_tests',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version,n),'[]'::jsonb) FROM lf_ops.nucleo_regla_pruebas x),'saly_rules',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY codigo),'[]'::jsonb) FROM saly.nucleo_reglas x),'saly_versions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version),'[]'::jsonb) FROM saly.nucleo_regla_versiones x),'saly_apps',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,nodo),'[]'::jsonb) FROM saly.nucleo_aplicaciones x),'saly_tests',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version,n),'[]'::jsonb) FROM saly.nucleo_regla_pruebas x)) INTO after_data;
 SELECT encode(sha256(convert_to(after_data::text,'UTF8')),'hex') INTO digest_after;
 IF before_data IS DISTINCT FROM after_data OR digest_before IS DISTINCT FROM digest_after THEN RAISE EXCEPTION 'S22BC_CONTENT_DRIFT'; END IF;
 IF (SELECT jsonb_object_agg(codigo,capa_ejecucion) FROM lf_ops.nucleo_reglas) IS DISTINCT FROM after_layers THEN RAISE EXCEPTION 'S22BC_AUTOTEST_LAYER_RESIDUE'; END IF;
 SELECT count(DISTINCT legacy_id) INTO cov_after FROM lf_ops.lf_nucleo_cobertura_legada WHERE estado_cobertura='REEMPLAZADA';
 IF cov_before<>cov_after THEN RAISE EXCEPTION 'S22BC_COVERAGE_DRIFT'; END IF;
 IF jsonb_array_length(lf_ops.lf_nucleo_lectura_transicion_v1(36,'INPUT_GOVERNANCE','DIRECTAS')->'nativas') IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'S22BC_DPIG03'; END IF;
 RAISE NOTICE 'S22BC_PROOF PG=% before=% after=% updated=138 null=17 coverage_before=% coverage_after=% digest_before=% digest_after=% SALY_UNCHANGED J2_CONJUNTO_5/5 PUENTE_8/8 PUENTE2_6/6 suite=% mapping=%',current_setting('server_version_num'),before_counts,after_counts,cov_before,cov_after,digest_before,digest_after,suite,changed;
END $bc$;
ROLLBACK;
DO $rollback$
BEGIN
 IF (SELECT count(*) FROM lf_ops.nucleo_reglas WHERE capa_ejecucion IS NULL)<>155 OR to_regclass('pg_temp.s22bc_mapping') IS NOT NULL THEN RAISE EXCEPTION 'S22BC_ROLLBACK_RESIDUE'; END IF;
 RAISE EXCEPTION 'S22BC_HASH_ALL ROLLBACK_OK; see S22BC_PROOF';
END $rollback$;
