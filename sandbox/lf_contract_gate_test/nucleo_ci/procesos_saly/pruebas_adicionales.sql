-- Pruebas adicionales (Claude): ramas, convergencia, ciclos, inicios y ACL. PG17 aislado, ROLLBACK.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
IF current_setting('server_version_num')::int / 10000 <> 17 OR current_database() NOT LIKE 'saly_test_%' OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN
RAISE EXCEPTION 'Solo PG17 local aislado, base saly_test_* y TCP 127.0.0.1'; END IF;
END $$;
CREATE SCHEMA saly;
DO $$ BEGIN
IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $$;
\ir stub_nucleo_nodos.sql
\ir base_candidata.sql
DO $$ DECLARE p bigint; a bigint; b bigint; c bigint; f bigint;
BEGIN
INSERT INTO saly.procesos(codigo,nodo_codigo) VALUES ('X','MOD-TEST') RETURNING id INTO p;
INSERT INTO saly.procesos_pasos(proceso_id,codigo) VALUES(p,'A') RETURNING paso_id INTO a;
INSERT INTO saly.procesos_pasos(proceso_id,codigo) VALUES(p,'B') RETURNING paso_id INTO b;
INSERT INTO saly.procesos_pasos(proceso_id,codigo) VALUES(p,'C') RETURNING paso_id INTO c;
INSERT INTO saly.procesos_pasos(proceso_id,codigo) VALUES(p,'F') RETURNING paso_id INTO f;
INSERT INTO saly.procesos_pasos_versiones VALUES(p,a,1,'A','x'),(p,b,1,'B','x'),(p,c,1,'C','x'),(p,f,1,'F','x');
INSERT INTO saly.procesos_versiones(proceso_id,version,titulo,motivo,origen_ref,creado_por) VALUES(p,1,'t','m','o','c'),(p,2,'t','m','o','c'),(p,3,'t','m','o','c');
-- v1: bifurcacion + convergencia + ciclo con salida
INSERT INTO saly.procesos_version_pasos VALUES(p,1,a,1,1,true,false),(p,1,b,1,2,false,false),(p,1,c,1,3,false,false),(p,1,f,1,4,false,true);
INSERT INTO saly.procesos_version_transiciones VALUES(p,1,a,b,'OK'),(p,1,a,c,'ALT'),(p,1,b,a,'VOLVER'),(p,1,b,f,'OK'),(p,1,c,f,'OK');
UPDATE saly.procesos_versiones SET estado='SELLADA' WHERE proceso_id=p AND version=1;
-- v2: ciclo sin salida al fin
INSERT INTO saly.procesos_version_pasos VALUES(p,2,a,1,1,true,false),(p,2,b,1,2,false,false),(p,2,c,1,3,false,false),(p,2,f,1,4,false,true);
INSERT INTO saly.procesos_version_transiciones VALUES(p,2,a,b,'OK'),(p,2,b,c,'OK'),(p,2,c,b,'OK'),(p,2,a,f,'ALT');
BEGIN UPDATE saly.procesos_versiones SET estado='SELLADA' WHERE proceso_id=p AND version=2; RAISE EXCEPTION 'EXTRA_CICLO_SIN_SALIDA_SELLO'; EXCEPTION WHEN check_violation THEN NULL; END;
-- v3: dos inicios
INSERT INTO saly.procesos_version_pasos VALUES(p,3,a,1,1,true,false);
BEGIN INSERT INTO saly.procesos_version_pasos VALUES(p,3,b,1,2,true,false); RAISE EXCEPTION 'EXTRA_DOS_INICIOS'; EXCEPTION WHEN unique_violation THEN NULL; END;
-- autotransicion permitida dentro de la misma version
INSERT INTO saly.procesos_version_transiciones VALUES(p,3,a,a,'LOOP');
-- nodo: inexistente, de nivel no MODULO e inmutabilidad
BEGIN INSERT INTO saly.procesos(codigo,nodo_codigo) VALUES ('N1','NO-EXISTE'); RAISE EXCEPTION 'EXTRA_NODO_INEXISTENTE'; EXCEPTION WHEN check_violation THEN NULL; END;
BEGIN INSERT INTO saly.procesos(codigo,nodo_codigo) VALUES ('N2','PANTALLA-7'); RAISE EXCEPTION 'EXTRA_NODO_NO_MODULO'; EXCEPTION WHEN check_violation THEN NULL; END;
BEGIN UPDATE saly.procesos SET nodo_codigo='G' WHERE id=p; RAISE EXCEPTION 'EXTRA_NODO_MUTABLE'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
-- ACL
IF has_table_privilege('authenticated','saly.procesos','TRUNCATE') OR has_sequence_privilege('authenticated','saly.procesos_pasos_paso_id_seq','USAGE') THEN RAISE EXCEPTION 'EXTRA_ACL'; END IF;
RAISE NOTICE 'PROCESOS_EXTRA_PASS';
END $$;
ROLLBACK;
DO $$ BEGIN IF to_regclass('saly.procesos') IS NOT NULL THEN RAISE EXCEPTION 'Rollback incompleto'; END IF; RAISE NOTICE 'EXTRA_ROLLBACK_PASS'; END $$;
