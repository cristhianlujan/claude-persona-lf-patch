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
DO $positive$ DECLARE r jsonb; t text; codes text[]; cx jsonb; BEGIN
 PERFORM pg_temp.assert_true((SELECT count(*)=6 FROM visual.knowledge_module_versions),'six modules');
 PERFORM pg_temp.assert_true((SELECT count(*)=10 FROM saly.evidencias),'ten research references');
 FOR t,codes,cx IN SELECT * FROM (VALUES
 ('NEW_DESIGN',ARRAY['K01','K02','K03','K05','K06'],'{"task":"NEW_DESIGN","dense":false,"related_modules":[]}'::jsonb),
 ('NEW_DENSE',ARRAY['K01','K02','K03','K04','K05','K06'],'{"task":"NEW_DESIGN","dense":true,"related_modules":[]}'::jsonb),
 ('ART_DIRECTION',ARRAY['K01','K02','K03','K05','K06'],'{"task":"ART_DIRECTION","dense":false,"related_modules":[]}'::jsonb),
 ('SPACE_OPTIMIZATION',ARRAY['K03','K04','K05','K06'],'{"task":"SPACE_OPTIMIZATION","dense":true,"related_modules":[]}'::jsonb),
 ('LOCAL_CORRECTION',ARRAY['K05','K06'],'{"task":"LOCAL_CORRECTION","dense":false,"related_modules":[]}'::jsonb),
 ('AUDIT',ARRAY['K03','K04','K06'],'{"task":"AUDIT","dense":true,"related_modules":["K03"]}'::jsonb)
 ) AS x(t,codes,cx) LOOP
  r:=visual.knowledge_select_review_v1('SALY','REVIEW_ONLY',cx,pg_temp.pins(codes));
  PERFORM pg_temp.assert_true(r->>'status'='CANDIDATE_REVIEW_ONLY' AND jsonb_array_length(r->'modules')=cardinality(codes) AND (r->>'production_approved')::boolean=false AND (r->>'render_authorized')::boolean=false AND (r->>'transfer_validated')::boolean=false,t);
  PERFORM pg_temp.assert_true((SELECT array_agg(m->>'module_code' ORDER BY m->>'module_code') FROM jsonb_array_elements(r->'modules') m)=codes,t||' exact modules');
 END LOOP;
END $positive$;
DO $negative$ DECLARE p jsonb:=pg_temp.pins(ARRAY['K05','K06']); cx jsonb:='{"task":"LOCAL_CORRECTION","dense":false,"related_modules":[]}'; bad jsonb; BEGIN
 PERFORM pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','LF','REVIEW_ONLY',cx,p),'KNOWLEDGE_SCOPE_OR_MODE');
 PERFORM pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','SALY','OFFICIAL',cx,p),'KNOWLEDGE_SCOPE_OR_MODE');
 PERFORM pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','SALY','REVIEW_ONLY',cx,'[]'),'KNOWLEDGE_PIN_SET');
 PERFORM pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','SALY','REVIEW_ONLY',cx,jsonb_build_array(p->0,p->0)),'KNOWLEDGE_PIN_SET');
 PERFORM pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','SALY','REVIEW_ONLY',cx,pg_temp.pins(ARRAY['K04','K06'])),'KNOWLEDGE_PIN_SET');
 bad:=jsonb_set(p,'{0,sha256}',to_jsonb(repeat('0',64))); PERFORM pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','SALY','REVIEW_ONLY',cx,bad),'KNOWLEDGE_PIN_NOT_FOUND');
 bad:=jsonb_set(p,'{0,version}','"9.9"'); PERFORM pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','SALY','REVIEW_ONLY',cx,bad),'KNOWLEDGE_PIN_NOT_FOUND');
 PERFORM pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','SALY','REVIEW_ONLY',jsonb_set(cx,'{dense}','true'),p),'KNOWLEDGE_CORRECTION_SCOPE');
 PERFORM pg_temp.expect_error('UPDATE visual.knowledge_module_versions SET state=''APPROVED''','KNOWLEDGE_CANDIDATE_IMMUTABLE');
 PERFORM pg_temp.expect_error('DELETE FROM visual.knowledge_module_versions','KNOWLEDGE_CANDIDATE_IMMUTABLE');
 PERFORM pg_temp.assert_true(NOT has_function_privilege('anon','visual.knowledge_select_review_v1(text,text,jsonb,jsonb)','EXECUTE') AND NOT has_function_privilege('authenticated','visual.knowledge_select_review_v1(text,text,jsonb,jsonb)','EXECUTE'),'no browser execution');
 PERFORM pg_temp.assert_true(has_function_privilege('service_role','visual.knowledge_select_review_v1(text,text,jsonb,jsonb)','EXECUTE') AND NOT has_table_privilege('service_role','visual.knowledge_module_versions','SELECT') AND NOT has_table_privilege('service_role','saly.documentos','SELECT'),'narrow access');
END $negative$;
SAVEPOINT tamper_document;
UPDATE saly.documentos SET contenido=set_byte(contenido,0,0) WHERE codigo='SALY-CREATIVE-K05-V01';
SELECT pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','SALY','REVIEW_ONLY','{"task":"LOCAL_CORRECTION","dense":false,"related_modules":[]}',pg_temp.pins(ARRAY['K05','K06'])),'KNOWLEDGE_DOCUMENT_DRIFT');
ROLLBACK TO tamper_document;
SAVEPOINT tamper_evidence;
UPDATE saly.evidencias SET descripcion=descripcion||' alterado' WHERE codigo='SALY-CREATIVE-RESEARCH-E05-V01';
SELECT pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','SALY','REVIEW_ONLY','{"task":"LOCAL_CORRECTION","dense":false,"related_modules":[]}',pg_temp.pins(ARRAY['K05','K06'])),'KNOWLEDGE_EVIDENCE_DRIFT');
ROLLBACK TO tamper_evidence;
SAVEPOINT remove_link;
DELETE FROM saly.evidencia_documentos WHERE documento_id=(SELECT document_id FROM visual.knowledge_module_versions WHERE module_code='K05');
SELECT pg_temp.expect_error(format('SELECT visual.knowledge_select_review_v1(%L,%L,%L::jsonb,%L::jsonb)','SALY','REVIEW_ONLY','{"task":"LOCAL_CORRECTION","dense":false,"related_modules":[]}',pg_temp.pins(ARRAY['K05','K06'])),'KNOWLEDGE_EVIDENCE_DRIFT');
ROLLBACK TO remove_link;
-- Verify actual role invocation with fixed pins generated by fixture owner.
SELECT pg_temp.pins(ARRAY['K05','K06'])::text AS service_pins \gset
SET LOCAL ROLE service_role;
SELECT visual.knowledge_select_review_v1('SALY','REVIEW_ONLY','{"task":"LOCAL_CORRECTION","dense":false,"related_modules":[]}',:'service_pins'::jsonb)->>'status' AS service_status \gset
RESET ROLE;
SELECT pg_temp.assert_true(:'service_status'='CANDIDATE_REVIEW_ONLY','actual service role read');
ROLLBACK;
DO $rollback$ BEGIN IF to_regnamespace('saly') IS NOT NULL OR to_regnamespace('visual') IS NOT NULL THEN RAISE EXCEPTION 'ROLLBACK_FAILED'; END IF; END $rollback$;
\echo PASS_PG17_KNOWLEDGE_CANDIDATE_ROLLBACK
