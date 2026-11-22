\set ON_ERROR_STOP on
-- Run only on an EMPTY disposable local PG17 database named saly_knowledge_test.
-- psql -X -h 127.0.0.1 -d saly_knowledge_test -f pruebas_pg17.sql
BEGIN;
DO $guard$ BEGIN
 IF current_database()<>'saly_knowledge_test' OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet OR current_setting('server_version_num')::int NOT BETWEEN 170000 AND 179999 OR to_regnamespace('saly') IS NOT NULL OR to_regnamespace('visual') IS NOT NULL THEN RAISE EXCEPTION 'TEST_LOCAL_EMPTY_PG17_ONLY'; END IF;
END $guard$;
-- Minimal fixtures of observed column types and constraints, not a copy of live schema.
CREATE SCHEMA saly;
CREATE SCHEMA visual;
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto SCHEMA extensions;
DO $roles$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;
GRANT USAGE ON SCHEMA visual TO service_role;
CREATE TABLE saly.proyecto(codigo text PRIMARY KEY,estado text NOT NULL);
INSERT INTO saly.proyecto VALUES('SALY-001','ACTIVO');
CREATE TABLE saly.documentos(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,codigo text NOT NULL UNIQUE,nombre_archivo text NOT NULL,mime_type text NOT NULL,tamano_bytes bigint NOT NULL CHECK(tamano_bytes>=0),sha256 text NOT NULL UNIQUE CHECK(sha256 ~ '^[0-9a-f]{64}$'),origen text NOT NULL,tipo text NOT NULL CHECK(tipo IN ('FUENTE_USUARIO','DERIVADO','OTRO')),contenido bytea,metadata jsonb NOT NULL DEFAULT '{}',binario_persistido boolean NOT NULL DEFAULT false,estado_persistencia text NOT NULL DEFAULT 'METADATA_ONLY' CHECK(estado_persistencia IN ('BINARIO_VERIFICADO','CONTENIDO_LOGICO_COMPLETO','METADATA_ONLY')),CHECK(contenido IS NULL OR octet_length(contenido)=tamano_bytes));
CREATE TABLE saly.evidencias(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,codigo text NOT NULL UNIQUE,tipo text NOT NULL,titulo text NOT NULL,descripcion text NOT NULL,referencia text,fecha_evidencia date,hechos jsonb NOT NULL DEFAULT '{}',estado text NOT NULL DEFAULT 'VIGENTE' CHECK(estado IN ('VIGENTE','SUPERADA','REFERENCIAL')));
CREATE TABLE saly.evidencia_documentos(evidencia_id bigint REFERENCES saly.evidencias(id),documento_id bigint REFERENCES saly.documentos(id),relacion text NOT NULL DEFAULT 'RESPALDA',PRIMARY KEY(evidencia_id,documento_id));
\ir repositorio_selector_candidato.sql
CREATE FUNCTION pg_temp.assert_true(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'ASSERT:%',label; END IF; END $$;
CREATE FUNCTION pg_temp.expect_error(stmt text,expected text) RETURNS void LANGUAGE plpgsql AS $$ DECLARE caught text; BEGIN
 BEGIN EXECUTE stmt; EXCEPTION WHEN OTHERS THEN caught:=SQLERRM; END;
 IF caught IS DISTINCT FROM expected THEN RAISE EXCEPTION 'EXPECTED %, GOT %',expected,caught; END IF;
END $$;
CREATE FUNCTION pg_temp.pins(codes text[]) RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_agg(jsonb_build_object('module_code',module_code,'version',version,'sha256',document_sha256) ORDER BY module_code) FROM visual.knowledge_module_versions WHERE module_code=ANY(codes) $$;
CREATE TEMP TABLE baseline_versions AS SELECT * FROM visual.knowledge_module_versions;
\ir depth_candidate.sql
CREATE FUNCTION pg_temp.pins_v(codes text[],ver text) RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_agg(jsonb_build_object('module_code',module_code,'version',version,'sha256',document_sha256) ORDER BY module_code) FROM visual.knowledge_module_versions WHERE module_code=ANY(codes) AND version=ver $$;
DO $positive$ DECLARE r jsonb; v text; t text; codes text[]; cx jsonb; BEGIN
 PERFORM pg_temp.assert_true((SELECT count(*)=12 FROM visual.knowledge_module_versions),'12 versions');
 PERFORM pg_temp.assert_true((SELECT count(*)=17 FROM saly.evidencias),'17 unique sources');
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT * FROM baseline_versions EXCEPT SELECT * FROM visual.knowledge_module_versions),'baseline unchanged');
 PERFORM pg_temp.assert_true((SELECT count(*)=6 FROM visual.knowledge_module_versions n JOIN baseline_versions b ON b.id=n.parent_id AND b.module_code=n.module_code WHERE n.version='0.2'),'6 parent bindings');
 FOREACH v IN ARRAY ARRAY['0.1','0.2'] LOOP
 FOR t,codes,cx IN SELECT * FROM (VALUES
 ('NEW_DESIGN',ARRAY['K01','K02','K03','K05','K06'],'{"task":"NEW_DESIGN","dense":false,"related_modules":[]}'::jsonb),
 ('NEW_DENSE',ARRAY['K01','K02','K03','K04','K05','K06'],'{"task":"NEW_DESIGN","dense":true,"related_modules":[]}'::jsonb),
 ('ART_DIRECTION',ARRAY['K01','K02','K03','K05','K06'],'{"task":"ART_DIRECTION","dense":false,"related_modules":[]}'::jsonb),
 ('SPACE_OPTIMIZATION',ARRAY['K03','K04','K05','K06'],'{"task":"SPACE_OPTIMIZATION","dense":true,"related_modules":[]}'::jsonb),
 ('LOCAL_CORRECTION',ARRAY['K05','K06'],'{"task":"LOCAL_CORRECTION","dense":false,"related_modules":[]}'::jsonb),
 ('AUDIT',ARRAY['K03','K04','K06'],'{"task":"AUDIT","dense":true,"related_modules":["K03"]}'::jsonb)) AS x(t,codes,cx) LOOP
 r:=visual.knowledge_select_review_v1('SALY','REVIEW_ONLY',cx,pg_temp.pins_v(codes,v));
 PERFORM pg_temp.assert_true(r->>'status'='CANDIDATE_REVIEW_ONLY' AND jsonb_array_length(r->'modules')=cardinality(codes) AND r->>'production_approved'='false' AND r->>'render_authorized'='false' AND r->>'transfer_validated'='false',v||t);
 PERFORM pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'modules') m WHERE m->>'version'<>v OR (v='0.2' AND position('Ampliación v0.2' in m->>'content')=0)),v||' exact versions');
 END LOOP;
 END LOOP;
END $positive$;
DO $negative$ DECLARE p jsonb:=pg_temp.pins_v(ARRAY['K05','K06'],'0.2'); cx jsonb:='{"task":"LOCAL_CORRECTION","dense":false,"related_modules":[]}'; BEGIN
 PERFORM pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','SALY','OFFICIAL',cx,p),'KNOWLEDGE_SCOPE_OR_MODE');
 PERFORM pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','LF','REVIEW_ONLY',cx,p),'KNOWLEDGE_SCOPE_OR_MODE');
 PERFORM pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','SALY','REVIEW_ONLY',cx,jsonb_set(p,'{0,sha256}',to_jsonb(repeat('0',64)))),'KNOWLEDGE_PIN_NOT_FOUND');
 PERFORM pg_temp.expect_error('UPDATE visual.knowledge_module_versions SET state=''APPROVED'' WHERE version=''0.2''','KNOWLEDGE_CANDIDATE_IMMUTABLE');
END $negative$;
SAVEPOINT mutate;
UPDATE saly.documentos SET contenido=set_byte(contenido,0,0) WHERE codigo='SALY-CREATIVE-K05-V02';
SELECT pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','SALY','REVIEW_ONLY','{"task":"LOCAL_CORRECTION","dense":false,"related_modules":[]}',pg_temp.pins_v(ARRAY['K05','K06'],'0.2')),'KNOWLEDGE_DOCUMENT_DRIFT');
ROLLBACK TO mutate;
SAVEPOINT evmut;
UPDATE saly.evidencias SET descripcion=descripcion||' alterado' WHERE codigo='SALY-CREATIVE-RESEARCH-E14-V02';
SELECT pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','SALY','REVIEW_ONLY','{"task":"LOCAL_CORRECTION","dense":false,"related_modules":[]}',pg_temp.pins_v(ARRAY['K05','K06'],'0.2')),'KNOWLEDGE_EVIDENCE_DRIFT');
ROLLBACK TO evmut;
ROLLBACK;
DO $$ BEGIN IF to_regnamespace('saly') IS NOT NULL OR to_regnamespace('visual') IS NOT NULL THEN RAISE EXCEPTION 'ROLLBACK_FAILED'; END IF; END $$;
\echo PASS_KNOWLEDGE_DEPTH_V02_PG17_ROLLBACK
