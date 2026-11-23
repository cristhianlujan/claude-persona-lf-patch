#!/bin/bash
# Concurrencia sobre datos confirmados, solo PG17 aislado (base saly_test_conc, TCP 127.0.0.1, sin red externa).
set -u
Q="psql -X -q -h 127.0.0.1 -U postgres -d saly_test_conc -At -v ON_ERROR_STOP=1"
V=$($Q -c "SHOW server_version_num")
case "$V" in 17*) ;; *) echo "CONC_FAIL no PG17 $V"; exit 1;; esac
[ "$($Q -c 'select current_database()')" = "saly_test_conc" ] || { echo "CONC_FAIL base"; exit 1; }
$Q -c "CREATE SCHEMA saly; DO \$\$ BEGIN CREATE ROLE anon NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END \$\$; DO \$\$ BEGIN CREATE ROLE authenticated NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END \$\$; DO \$\$ BEGIN CREATE ROLE service_role NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END \$\$;" || exit 1
$Q -f stub_nucleo_nodos.sql || exit 1
$Q -f base_candidata.sql || exit 1
$Q -c "INSERT INTO saly.procesos(codigo,nodo_codigo) VALUES ('C','MOD-TEST'); SELECT saly.procesos_version_crear_v1(1,'t','m','o','c');
INSERT INTO saly.procesos_pasos(proceso_id,codigo) VALUES (1,'A'),(1,'B'),(1,'Z');
INSERT INTO saly.procesos_pasos_versiones VALUES (1,1,1,'A','x'),(1,2,1,'B','x'),(1,3,1,'Z','x');
INSERT INTO saly.procesos_version_pasos VALUES (1,1,1,1,1,true,false),(1,1,2,1,2,false,true);
INSERT INTO saly.procesos_version_transiciones VALUES (1,1,1,2,'OK');" >/dev/null || exit 1
# A) dos creaciones concurrentes de versión: números distintos y consecutivos
for i in 1 2; do ( $Q -c "BEGIN; SELECT saly.procesos_version_crear_v1(1,'t','m','o','c$i'); SELECT pg_sleep(1); COMMIT;" >/tmp/conc_a$i 2>&1 ) & done; wait
[ "$($Q -c "select string_agg(version::text,',' order by version) from saly.procesos_versiones where proceso_id=1")" = "1,2,3" ] || { echo "CONC_FAIL versiones"; exit 1; }
# B) sellar retiene el candado; la edición concurrente espera y luego es rechazada
( $Q -c "BEGIN; UPDATE saly.procesos_versiones SET estado='SELLADA' WHERE proceso_id=1 AND version=1; SELECT pg_sleep(2); COMMIT;" >/tmp/conc_b1 2>&1 ) &
sleep 0.7
$Q -c "INSERT INTO saly.procesos_version_pasos VALUES (1,1,3,1,3,false,false);" >/tmp/conc_b2 2>&1; wait
grep -q SALY_PROCESO_NO_EDITABLE /tmp/conc_b2 || { echo "CONC_FAIL edicion tras sellado"; cat /tmp/conc_b2; exit 1; }
[ "$($Q -c "select estado||':'||(select count(*) from saly.procesos_version_pasos where proceso_id=1 and proceso_version=1) from saly.procesos_versiones where proceso_id=1 and version=1")" = "SELLADA:2" ] || { echo "CONC_FAIL estado sellada"; exit 1; }
# C) la edición retiene el candado; el sellado espera y evalúa la composición NUEVA (flujo incompleto debe rechazarse)
$Q -c "INSERT INTO saly.procesos_version_pasos VALUES (1,2,1,1,1,true,false),(1,2,2,1,2,false,true); INSERT INTO saly.procesos_version_transiciones VALUES (1,2,1,2,'OK');" >/dev/null || exit 1
( $Q -c "BEGIN; INSERT INTO saly.procesos_version_pasos VALUES (1,2,3,1,3,false,false); SELECT pg_sleep(2); COMMIT;" >/tmp/conc_c1 2>&1 ) &
sleep 0.7
$Q -c "UPDATE saly.procesos_versiones SET estado='SELLADA' WHERE proceso_id=1 AND version=2;" >/tmp/conc_c2 2>&1; wait
grep -q SALY_PROCESO_FLUJO_INCOMPLETO /tmp/conc_c2 || { echo "CONC_FAIL sellado ciego a la composicion nueva"; cat /tmp/conc_c2; exit 1; }
[ "$($Q -c "select estado from saly.procesos_versiones where proceso_id=1 and version=2")" = "BORRADOR" ] || { echo "CONC_FAIL estado v2"; exit 1; }
echo "PROCESOS_CONC_PASS"
