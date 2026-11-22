-- Ejecutar mediante psql ÚNICAMENTE en base PG17 vacía de prueba local.
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
\ir base_candidata.sql
DO $$ DECLARE p bigint; q bigint; a bigint; b bigint; c bigint; o bigint; n integer;
BEGIN
INSERT INTO saly.procesos(codigo) VALUES ('TEST-P') RETURNING id INTO p;
INSERT INTO saly.procesos(codigo) VALUES ('TEST-Q') RETURNING id INTO q;
INSERT INTO saly.procesos_versiones(proceso_id,version,titulo,motivo,origen_ref,creado_por) VALUES (p,1,'Prueba','Inicial','TEST','QA'),(p,2,'Prueba','Agregar paso','TEST','QA'),(p,3,'Prueba','Retirar paso','TEST','QA');
INSERT INTO saly.procesos_pasos(proceso_id,codigo) VALUES (p,'A') RETURNING paso_id INTO a;
INSERT INTO saly.procesos_pasos(proceso_id,codigo) VALUES (p,'B') RETURNING paso_id INTO b;
INSERT INTO saly.procesos_pasos(proceso_id,codigo) VALUES (p,'C') RETURNING paso_id INTO c;
INSERT INTO saly.procesos_pasos(proceso_id,codigo) VALUES (q,'O') RETURNING paso_id INTO o;
INSERT INTO saly.procesos_pasos_versiones VALUES (p,a,1,'Inicio','Entrada'),(p,b,1,'Fin','Salida'),(p,c,1,'Validar','Control'),(q,o,1,'Ajeno','Otro proceso');
INSERT INTO saly.procesos_version_pasos VALUES (p,1,a,1,1,true,false),(p,1,b,1,2,false,true),(p,2,a,1,1,true,false),(p,2,c,1,2,false,false),(p,2,b,1,3,false,true),(p,3,a,1,1,true,false),(p,3,b,1,2,false,true);
INSERT INTO saly.procesos_version_transiciones VALUES (p,1,a,b,'OK'),(p,2,a,c,'OK'),(p,2,c,b,'OK'),(p,3,a,b,'OK');
UPDATE saly.procesos_versiones SET estado='SELLADA' WHERE proceso_id=p AND version IN (1,2,3);
SELECT count(*) INTO n FROM saly.procesos_version_pasos WHERE proceso_id=p AND proceso_version=2; IF n<>3 THEN RAISE EXCEPTION 'Conteo v2 incorrecto'; END IF;
SELECT count(*) INTO n FROM saly.procesos_version_pasos WHERE proceso_id=p AND proceso_version IN (1,3); IF n<>4 THEN RAISE EXCEPTION 'Histórico incorrecto'; END IF;
BEGIN UPDATE saly.procesos_versiones SET titulo='alterado' WHERE proceso_id=p AND version=1; RAISE EXCEPTION 'No bloqueó versión'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
BEGIN DELETE FROM saly.procesos_version_transiciones WHERE proceso_id=p AND proceso_version=1; RAISE EXCEPTION 'No bloqueó transición'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
BEGIN UPDATE saly.procesos_pasos_versiones SET titulo='alterado' WHERE proceso_id=p AND paso_id=a; RAISE EXCEPTION 'No bloqueó paso'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
INSERT INTO saly.procesos_versiones(proceso_id,version,titulo,motivo,origen_ref,creado_por) VALUES (p,4,'Prueba','Negativa','TEST','QA');
BEGIN INSERT INTO saly.procesos_version_pasos VALUES (p,4,o,1,1,true,true); RAISE EXCEPTION 'No bloqueó paso ajeno'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
INSERT INTO saly.procesos_version_pasos VALUES (p,4,a,1,1,true,false),(p,4,b,1,2,false,true);
BEGIN UPDATE saly.procesos_versiones SET estado='SELLADA' WHERE proceso_id=p AND version=4; RAISE EXCEPTION 'No bloqueó flujo desconectado'; EXCEPTION WHEN check_violation THEN NULL; END;
BEGIN INSERT INTO saly.procesos_version_transiciones VALUES (p,4,a,c,'OK'); RAISE EXCEPTION 'No bloqueó transición ajena a versión'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
IF has_table_privilege('authenticated','saly.procesos','INSERT') OR has_table_privilege('anon','saly.procesos','SELECT') THEN RAISE EXCEPTION 'Permisos de cliente incorrectos'; END IF;
RAISE NOTICE 'Pruebas de evolución, histórico, inmutabilidad, referencias y permisos: PASS';
END $$;

-- Ampliacion QA: cuatro -> cinco -> tres pasos; reordenamiento y nueva definicion.
DO $$
DECLARE p bigint; a bigint; b bigint; c bigint; d bigint; e bigint; actual bigint[];
BEGIN
INSERT INTO saly.procesos(codigo) VALUES ('TEST-EVOLUCION-453') RETURNING id INTO p;
INSERT INTO saly.procesos_versiones(proceso_id,version,titulo,motivo,origen_ref,creado_por)
VALUES (p,1,'Evolucion','Inicial','QA-453','QA'),(p,2,'Evolucion','Agregar y reordenar','QA-453','QA'),(p,3,'Evolucion','Retirar pasos','QA-453','QA');
INSERT INTO saly.procesos_pasos(proceso_id,codigo) VALUES(p,'A') RETURNING paso_id INTO a;
INSERT INTO saly.procesos_pasos(proceso_id,codigo) VALUES(p,'B') RETURNING paso_id INTO b;
INSERT INTO saly.procesos_pasos(proceso_id,codigo) VALUES(p,'C') RETURNING paso_id INTO c;
INSERT INTO saly.procesos_pasos(proceso_id,codigo) VALUES(p,'D') RETURNING paso_id INTO d;
INSERT INTO saly.procesos_pasos(proceso_id,codigo) VALUES(p,'E') RETURNING paso_id INTO e;
INSERT INTO saly.procesos_pasos_versiones VALUES(p,a,1,'A','Inicio'),(p,b,1,'B','Validar'),(p,b,2,'B2','Validacion modificada'),(p,c,1,'C','Confirmar'),(p,d,1,'D','Fin'),(p,e,1,'E','Alternativo');
INSERT INTO saly.procesos_version_pasos VALUES
(p,1,a,1,1,true,false),(p,1,b,1,2,false,false),(p,1,c,1,3,false,false),(p,1,d,1,4,false,true),
(p,2,a,1,1,true,false),(p,2,c,1,2,false,false),(p,2,b,2,3,false,false),(p,2,e,1,4,false,false),(p,2,d,1,5,false,true),
(p,3,a,1,1,true,false),(p,3,b,2,2,false,false),(p,3,d,1,3,false,true);
INSERT INTO saly.procesos_version_transiciones VALUES
(p,1,a,b,'OK'),(p,1,b,c,'OK'),(p,1,c,d,'OK'),
(p,2,a,c,'OK'),(p,2,c,b,'OK'),(p,2,b,e,'OK'),(p,2,e,d,'OK'),
(p,3,a,b,'OK'),(p,3,b,d,'OK');
UPDATE saly.procesos_versiones SET estado='SELLADA' WHERE proceso_id=p;
SELECT array_agg(n ORDER BY v) INTO actual FROM (SELECT proceso_version v,count(*) n FROM saly.procesos_version_pasos WHERE proceso_id=p GROUP BY 1)s;
IF actual IS DISTINCT FROM ARRAY[4,5,3]::bigint[] THEN RAISE EXCEPTION 'QA_453_CONTEOS:%',actual; END IF;
IF NOT EXISTS(SELECT 1 FROM saly.procesos_version_pasos WHERE proceso_id=p AND proceso_version=1 AND paso_id=b AND paso_version=1 AND orden=2)
OR NOT EXISTS(SELECT 1 FROM saly.procesos_version_pasos WHERE proceso_id=p AND proceso_version=2 AND paso_id=b AND paso_version=2 AND orden=3)
OR NOT EXISTS(SELECT 1 FROM saly.procesos_version_pasos WHERE proceso_id=p AND proceso_version=3 AND paso_id=b AND paso_version=2 AND orden=2)
THEN RAISE EXCEPTION 'QA_453_IDENTIDAD_VERSION_ORDEN'; END IF;
IF EXISTS(SELECT 1 FROM saly.procesos_version_pasos WHERE proceso_id=p AND proceso_version=3 AND paso_id IN(c,e)) THEN RAISE EXCEPTION 'QA_453_RETIRO'; END IF;
BEGIN INSERT INTO saly.procesos_version_pasos VALUES(p,3,c,1,4,false,false); RAISE EXCEPTION 'QA_453_NO_BLOQUEO_INSERT'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
BEGIN UPDATE saly.procesos_version_pasos SET orden=99 WHERE proceso_id=p AND proceso_version=2 AND paso_id=b; RAISE EXCEPTION 'QA_453_NO_BLOQUEO_REORDEN'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
BEGIN DELETE FROM saly.procesos_version_pasos WHERE proceso_id=p AND proceso_version=1 AND paso_id=c; RAISE EXCEPTION 'QA_453_NO_BLOQUEO_RETIRO'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
RAISE NOTICE 'QA_453: PASS';
END $$;

ROLLBACK;
DO $$ BEGIN IF to_regclass('saly.procesos') IS NOT NULL THEN RAISE EXCEPTION 'Rollback incompleto'; END IF; RAISE NOTICE 'Rollback: PASS'; END $$;
