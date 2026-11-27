-- S22-BD: owner-approved internal controls; exact 17 BACKEND assignments; V3 PG17 proof approved.
BEGIN;
CREATE TEMP TABLE s22bd_mapping(codigo text PRIMARY KEY,capa text CHECK(capa IN ('BACKEND','FRONTEND','AMBOS'))) ON COMMIT DROP;
INSERT INTO s22bd_mapping VALUES
('S12-C08','BACKEND'),
('S12-C11','BACKEND'),
('S12-C14','BACKEND'),
('S12-C17','BACKEND'),
('S12-C18','BACKEND'),
('S13-C08','BACKEND'),
('S21-C08','BACKEND'),
('S22AB-C05','BACKEND'),
('S22J-C03','BACKEND'),
('S22L-C03','BACKEND'),
('S22L-C05','BACKEND'),
('S22M-C01','BACKEND'),
('S22M-C02','BACKEND'),
('S22S-C02','BACKEND'),
('S22S-C03','BACKEND'),
('S22S-C04','BACKEND'),
('S22V-C05','BACKEND');
DO $bd$
DECLARE
 before_data jsonb; after_data jsonb; before_layers jsonb; after_layers jsonb;
 before_counts jsonb; after_counts jsonb; changed jsonb; expected jsonb;
 cov_before bigint; cov_after bigint; digest_before text; digest_after text;
 t record; verdict text; suite text:='';
BEGIN
 IF (SELECT count(*) FROM s22bd_mapping)<>17 OR (SELECT count(*) FROM s22bd_mapping WHERE capa IS NOT NULL)<>17 THEN RAISE EXCEPTION 'S22BD_MAPPING_COUNT'; END IF;
 IF EXISTS(SELECT codigo FROM lf_ops.nucleo_reglas WHERE capa_ejecucion IS NULL EXCEPT SELECT codigo FROM s22bd_mapping) OR EXISTS(SELECT codigo FROM s22bd_mapping EXCEPT SELECT codigo FROM lf_ops.nucleo_reglas WHERE capa_ejecucion IS NULL) THEN RAISE EXCEPTION 'S22BD_SOURCE_SET_DRIFT'; END IF;
 SELECT jsonb_build_object('lf_rules',(SELECT coalesce(jsonb_agg(to_jsonb(x)-'capa_ejecucion' ORDER BY codigo),'[]'::jsonb) FROM lf_ops.nucleo_reglas x),'lf_versions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version),'[]'::jsonb) FROM lf_ops.nucleo_regla_versiones x),'lf_coverage',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY legacy_id,nucleo_codigo,version_nucleo),'[]'::jsonb) FROM lf_ops.lf_nucleo_cobertura_legada x),'lf_apps',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,nodo),'[]'::jsonb) FROM lf_ops.nucleo_aplicaciones x),'lf_tests',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version,n),'[]'::jsonb) FROM lf_ops.nucleo_regla_pruebas x),'saly_rules',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY codigo),'[]'::jsonb) FROM saly.nucleo_reglas x),'saly_versions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version),'[]'::jsonb) FROM saly.nucleo_regla_versiones x),'saly_apps',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,nodo),'[]'::jsonb) FROM saly.nucleo_aplicaciones x),'saly_tests',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version,n),'[]'::jsonb) FROM saly.nucleo_regla_pruebas x)) INTO before_data;
 SELECT jsonb_object_agg(codigo,capa_ejecucion) INTO before_layers FROM lf_ops.nucleo_reglas;
 SELECT jsonb_build_object('BACKEND',count(*) FILTER(WHERE capa_ejecucion='BACKEND'),'FRONTEND',count(*) FILTER(WHERE capa_ejecucion='FRONTEND'),'AMBOS',count(*) FILTER(WHERE capa_ejecucion='AMBOS'),'NULL',count(*) FILTER(WHERE capa_ejecucion IS NULL)) INTO before_counts FROM lf_ops.nucleo_reglas;
 SELECT count(DISTINCT legacy_id) INTO cov_before FROM lf_ops.lf_nucleo_cobertura_legada WHERE estado_cobertura='REEMPLAZADA';
 SELECT encode(sha256(convert_to(before_data::text,'UTF8')),'hex') INTO digest_before;
 WITH u AS (UPDATE lf_ops.nucleo_reglas r SET capa_ejecucion=m.capa FROM s22bd_mapping m WHERE r.codigo=m.codigo AND r.capa_ejecucion IS NULL AND m.capa IS NOT NULL RETURNING r.codigo,r.capa_ejecucion)
 SELECT jsonb_object_agg(codigo,capa_ejecucion) INTO changed FROM u;
 SELECT jsonb_object_agg(codigo,capa) INTO expected FROM s22bd_mapping WHERE capa IS NOT NULL;
 IF changed IS DISTINCT FROM expected THEN RAISE EXCEPTION 'S22BD_UPDATED_SET_DRIFT'; END IF;
 SELECT jsonb_object_agg(codigo,capa_ejecucion) INTO after_layers FROM lf_ops.nucleo_reglas;
 IF after_layers IS DISTINCT FROM before_layers||expected THEN RAISE EXCEPTION 'S22BD_LAYER_DRIFT'; END IF;
 IF EXISTS(SELECT codigo FROM lf_ops.nucleo_reglas WHERE capa_ejecucion IS NULL EXCEPT SELECT codigo FROM s22bd_mapping WHERE capa IS NULL) OR EXISTS(SELECT codigo FROM s22bd_mapping WHERE capa IS NULL EXCEPT SELECT codigo FROM lf_ops.nucleo_reglas WHERE capa_ejecucion IS NULL) THEN RAISE EXCEPTION 'S22BD_NULL_SET_DRIFT'; END IF;
 SELECT jsonb_build_object('BACKEND',count(*) FILTER(WHERE capa_ejecucion='BACKEND'),'FRONTEND',count(*) FILTER(WHERE capa_ejecucion='FRONTEND'),'AMBOS',count(*) FILTER(WHERE capa_ejecucion='AMBOS'),'NULL',count(*) FILTER(WHERE capa_ejecucion IS NULL)) INTO after_counts FROM lf_ops.nucleo_reglas;
 IF after_counts IS DISTINCT FROM jsonb_build_object('BACKEND',251,'FRONTEND',389,'AMBOS',77,'NULL',0) THEN RAISE EXCEPTION 'S22BD_COUNTS_DRIFT %',after_counts; END IF;
 FOR t IN SELECT * FROM (VALUES ('lf_ops','puerta','PUERTA 26/26'),('lf_ops','evaluacion','EVALUACION 23/23'),('lf_ops','cambio','CAMBIO 16/16'),('lf_ops','contrato','CONTRATO 4/4 (12 casos)'),('lf_ops','calculo','CALCULO 36/36'),('lf_ops','profundidad','PROFUNDIDAD 13/13'),('lf_ops','alcance_inverso','ALCANCE_INVERSO 10/10'),('saly','puerta','PUERTA 26/26'),('saly','evaluacion','EVALUACION 23/23'),('saly','cambio','CAMBIO 16/16'),('saly','contrato','CONTRATO 4/4 (12 casos)'),('saly','calculo','CALCULO 36/36'),('saly','profundidad','PROFUNDIDAD 13/13'),('saly','alcance_inverso','ALCANCE_INVERSO 10/10')) x(esquema,nombre,esperado) LOOP
 EXECUTE format('SELECT %I.%I()',t.esquema,'nucleo_autotest_'||t.nombre||'_v1') INTO verdict;
 IF verdict IS DISTINCT FROM t.esperado THEN RAISE EXCEPTION 'S22BD_AUTOTEST_FAIL %.% %',t.esquema,t.nombre,verdict; END IF;
 suite:=concat_ws(';',suite,t.esquema||'.'||verdict);
 END LOOP;
 IF public.lf_nucleo_autotest_conjunto_v1() IS DISTINCT FROM 'CONJUNTO 5/5' OR lf_ops.lf_puente_autotest_v1() IS DISTINCT FROM 'PUENTE 8/8' OR lf_ops.lf_puente2_autotest_v1() IS DISTINCT FROM 'PUENTE2 6/6' THEN RAISE EXCEPTION 'S22BD_CONJUNTO_OR_PUENTE_FAIL'; END IF;
 SELECT jsonb_build_object('lf_rules',(SELECT coalesce(jsonb_agg(to_jsonb(x)-'capa_ejecucion' ORDER BY codigo),'[]'::jsonb) FROM lf_ops.nucleo_reglas x),'lf_versions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version),'[]'::jsonb) FROM lf_ops.nucleo_regla_versiones x),'lf_coverage',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY legacy_id,nucleo_codigo,version_nucleo),'[]'::jsonb) FROM lf_ops.lf_nucleo_cobertura_legada x),'lf_apps',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,nodo),'[]'::jsonb) FROM lf_ops.nucleo_aplicaciones x),'lf_tests',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version,n),'[]'::jsonb) FROM lf_ops.nucleo_regla_pruebas x),'saly_rules',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY codigo),'[]'::jsonb) FROM saly.nucleo_reglas x),'saly_versions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version),'[]'::jsonb) FROM saly.nucleo_regla_versiones x),'saly_apps',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,nodo),'[]'::jsonb) FROM saly.nucleo_aplicaciones x),'saly_tests',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY regla,version,n),'[]'::jsonb) FROM saly.nucleo_regla_pruebas x)) INTO after_data;
 SELECT encode(sha256(convert_to(after_data::text,'UTF8')),'hex') INTO digest_after;
 IF before_data IS DISTINCT FROM after_data OR digest_before IS DISTINCT FROM digest_after THEN RAISE EXCEPTION 'S22BD_CONTENT_DRIFT'; END IF;
 IF (SELECT jsonb_object_agg(codigo,capa_ejecucion) FROM lf_ops.nucleo_reglas) IS DISTINCT FROM after_layers THEN RAISE EXCEPTION 'S22BD_AUTOTEST_LAYER_RESIDUE'; END IF;
 SELECT count(DISTINCT legacy_id) INTO cov_after FROM lf_ops.lf_nucleo_cobertura_legada WHERE estado_cobertura='REEMPLAZADA';
 IF cov_before<>cov_after THEN RAISE EXCEPTION 'S22BD_COVERAGE_DRIFT'; END IF;
 IF jsonb_array_length(lf_ops.lf_nucleo_lectura_transicion_v1(36,'INPUT_GOVERNANCE','DIRECTAS')->'nativas') IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'S22BD_DPIG03'; END IF;
 RAISE NOTICE 'S22BD_PROOF PG=% before=% after=% updated=17 null=0 coverage_before=% coverage_after=% digest_before=% digest_after=% SALY_UNCHANGED J2_CONJUNTO_5/5 PUENTE_8/8 PUENTE2_6/6 suite=% mapping=%',current_setting('server_version_num'),before_counts,after_counts,cov_before,cov_after,digest_before,digest_after,suite,changed;
 IF (SELECT count(*) FROM jsonb_object_keys(changed))<>17 OR changed IS DISTINCT FROM expected THEN RAISE EXCEPTION 'S22BD_FINAL_UPDATED_SET_DRIFT'; END IF;
 IF (SELECT jsonb_build_object('BACKEND',count(*) FILTER(WHERE capa_ejecucion='BACKEND'),'FRONTEND',count(*) FILTER(WHERE capa_ejecucion='FRONTEND'),'AMBOS',count(*) FILTER(WHERE capa_ejecucion='AMBOS'),'NULL',count(*) FILTER(WHERE capa_ejecucion IS NULL)) FROM lf_ops.nucleo_reglas) IS DISTINCT FROM after_counts THEN RAISE EXCEPTION 'S22BD_FINAL_COUNTS_DRIFT'; END IF;
 RAISE NOTICE 'S22BD_FINAL_PASS counts=% updated=% coverage=%',after_counts,(SELECT count(*) FROM jsonb_object_keys(changed)),cov_after;
END $bd$;
COMMIT;
