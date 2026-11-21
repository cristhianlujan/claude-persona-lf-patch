#!/usr/bin/env python3
"""B7: real simultaneous source-version collision in two PostgreSQL 17 sessions.

Disposable database ONLY; never use shared SALY or a connected Supabase role.
The deployed PTE writer SQL and the index DDL are loaded by CI before running.
The negative must fail on saly_pte_source_batch_once_v1 specifically.
"""
import os
import subprocess
import time
import uuid
from concurrent.futures import ThreadPoolExecutor


def psql(sql, *, app=None, timeout=30):
    env = os.environ.copy()
    if app:
        env["PGAPPNAME"] = app
    r = subprocess.run(
        ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-c", sql],
        text=True, capture_output=True, env=env, timeout=timeout, check=True
    )
    return r.stdout.strip()


def lit(v):
    return "'" + v.replace("'", "''") + "'"


def main():
    if os.environ.get("PGHOST") not in ("127.0.0.1", "localhost"):
        raise RuntimeError("PG17_LOCAL_DISPOSABLE_ONLY")
    if os.environ.get("PGDATABASE") != "saly_pte_writer_ci":
        raise RuntimeError("PG17_LOCAL_DISPOSABLE_ONLY")
    if not psql("SHOW server_version_num").startswith("17"):
        raise RuntimeError("PG17_REQUIRED")
    if psql("SELECT count(*) FROM saly.ventas_discovery_runs") != "0":
        raise RuntimeError("PG17_FIXTURE_BASELINE_NOT_EMPTY")
    if psql("SELECT count(*) FROM pg_indexes WHERE schemaname='saly' AND indexname='saly_pte_source_batch_once_v1'") != "1":
        raise RuntimeError("PG17_SOURCE_INDEX_NOT_APPLIED")

    tag = uuid.uuid4().hex
    category = "CAT-CROSSRUN-" + tag
    run_a, run_b = "RUN-CROSSRUN-" + tag + "-A", "RUN-CROSSRUN-" + tag + "-B"
    query_a, query_b = str(uuid.uuid4()), str(uuid.uuid4())
    resource = "https://www.datosabiertos.gob.pe/sites/default/files/fixture.csv"
    capture = '[{"fila_origen":1,"nombre":"Concurrent institution A","ruc":"20100000001","ubigeo":"150101"},{"fila_origen":2,"nombre":"Concurrent institution B","ruc":null,"ubigeo":"110101"}]'
    c, a, b, u, cap = map(lit, (category, run_a, run_b, resource, capture))
    runrefs = a + "," + b
    fixture_count = "SELECT count(*) FROM saly.ventas_discovery_runs WHERE run_ref IN (" + runrefs + ")"
    sessions = []

    try:
        psql(f"""BEGIN;
INSERT INTO saly.ventas_discovery_catalogo(
 catalog_version,source_id,connector_id,substep_code,step,familia,nombre,
 landing_page,rights_status,rights_evidence_ref,rights_checked_at,
 persist_business_data,habilitada)
VALUES ({c},'PE-PTE','SALY-U07-S13-C03','13.03',13,'ESTADO_TERRITORIAL','Synthetic PTE source',
'https://www.datosabiertos.gob.pe/dataset/fixture',
'PERSISTENCIA_PERMITIDA','fixture://crossrun',now(),true,true);

INSERT INTO saly.ventas_discovery_runs(run_ref,catalog_version,scope,plan_hash,estado)
VALUES ({a},{c},'{{"scope":"LIMA_ICA"}}',repeat('a',64),'EN_EJECUCION'),
       ({b},{c},'{{"scope":"LIMA_ICA"}}',repeat('b',64),'EN_EJECUCION');

INSERT INTO saly.ventas_discovery_plan_fuentes(
 run_id,catalog_version,source_id,connector_id,substep_code,scope_key,seleccion,estado)
SELECT id,{c},'PE-PTE','SALY-U07-S13-C03','13.03','LIMA_ICA','REQUIRED','EN_EJECUCION'
FROM saly.ventas_discovery_runs WHERE run_ref IN ({runrefs});

INSERT INTO saly.ventas_discovery_plan_batches(run_id,source_id,scope_key,batch_key,query_hash,estado)
SELECT id,'PE-PTE','LIMA_ICA','FIXTURE',repeat('c',64),'FOUND'
FROM saly.ventas_discovery_runs WHERE run_ref IN ({runrefs});

INSERT INTO saly.ventas_discovery_ejecuciones(
 run_id,catalog_version,source_id,connector_id,substep_code,scope_key,estado,
 evidencia_ref,ultima_consulta_en,total_encontrados)
SELECT id,{c},'PE-PTE','SALY-U07-S13-C03','13.03','LIMA_ICA','FOUND',
{u}||'#captura-json-sha256='||encode(sha256(convert_to({cap},'UTF8')),'hex'),now(),2
FROM saly.ventas_discovery_runs WHERE run_ref IN ({runrefs});

INSERT INTO saly.ventas_discovery_consultas(
 id,ejecucion_id,run_id,run_ref,catalog_version,source_id,connector_id,
 substep_code,scope_key,batch_key,query_hash,herramienta,inicio,fin,estado,
 cantidad_hallazgos,evidencia_ref)
SELECT CASE d.run_ref WHEN {a} THEN {lit(query_a)}::uuid ELSE {lit(query_b)}::uuid END,
e.id,d.id,d.run_ref,{c},'PE-PTE','SALY-U07-S13-C03','13.03',
'LIMA_ICA','FIXTURE',repeat('c',64),'SYNTHETIC_PG17_CONCURRENT',
now(),now(),'FOUND',2,e.evidencia_ref
FROM saly.ventas_discovery_ejecuciones e
JOIN saly.ventas_discovery_runs d ON d.id=e.run_id
WHERE d.run_ref IN ({runrefs});
COMMIT;""")

        one = f"SELECT saly.ventas_pte_ingesta_core_v1({lit(query_a)}::uuid,{cap},'fixture',{u})->>'status';"
        two = f"SELECT saly.ventas_pte_ingesta_core_v1({lit(query_b)}::uuid,{cap},'fixture',{u})->>'status';"
        process_a = subprocess.Popen(
            ["psql","-X","-qAt","-v","ON_ERROR_STOP=1"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1, env={**os.environ,"PGAPPNAME":"saly_pte_crossrun_a"}
        )
        sessions.append(process_a)
        process_a.stdin.write("BEGIN;\n" + one + "\n")
        process_a.stdin.flush()

        with ThreadPoolExecutor(max_workers=2) as pool:
            first = pool.submit(process_a.stdout.readline).result(timeout=15).strip()
            if first != "INSERTED":
                raise AssertionError("CROSSRUN_A_NOT_INSERTED:" + first)
            second = pool.submit(psql,two,app="saly_pte_crossrun_b",timeout=20)
            deadline = time.monotonic()+10
            actually_waiting = False
            while time.monotonic()<deadline:
                if psql("SELECT count(*) FROM pg_stat_activity WHERE application_name='saly_pte_crossrun_b' AND wait_event_type='Lock'") == "1":
                    actually_waiting=True
                    break
                if second.done():
                    break
                time.sleep(0.1)
            if not actually_waiting:
                raise AssertionError("CROSSRUN_B_LOCK_COMPETITION_NOT_OBSERVED")
            process_a.stdin.write("COMMIT;\n")
            process_a.stdin.flush()
            try:
                output = second.result(timeout=15)
            except subprocess.CalledProcessError as exc:
                if "saly_pte_source_batch_once_v1" not in exc.stderr or "duplicate key value violates unique constraint" not in exc.stderr:
                    raise AssertionError("CROSSRUN_WRONG_NEGATIVE_CONTROL:" + exc.stderr[-800:]) from exc
            else:
                raise AssertionError("CROSSRUN_DUPLICATE_ACCEPTED:" + output)

        verified = psql(f"""SELECT
 (SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE run_ref IN ({runrefs}))::text||':'||
 (SELECT count(*) FROM saly.ventas_hallazgos h JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id WHERE i.run_ref IN ({runrefs}))::text;""")
        if verified != "1:2":
            raise AssertionError("CROSSRUN_EFFECT_NOT_EXACT_ONCE:"+verified)
        print("PASS_PTE_TWO_RUNS_ONE_SNAPSHOT_ONE_EFFECT_REAL_PG17")
        print("PASS_PTE_SECOND_SESSION_TARGET_CONSTRAINT_saly_pte_source_batch_once_v1")
    finally:
        for proc in sessions:
            if proc.poll() is None:
                proc.terminate()
            proc.communicate(timeout=5)
        # Do not silently mask failure; CI will report any cleanup failure too.
        psql(f"""BEGIN;
DELETE FROM saly.ventas_hallazgos WHERE ingesta_id IN (
 SELECT id FROM saly.ventas_discovery_ingestas WHERE run_ref IN ({runrefs}));
DELETE FROM saly.ventas_discovery_ingestas WHERE run_ref IN ({runrefs});
DELETE FROM saly.ventas_discovery_consultas WHERE run_ref IN ({runrefs});
DELETE FROM saly.ventas_discovery_ejecuciones WHERE run_id IN (
 SELECT id FROM saly.ventas_discovery_runs WHERE run_ref IN ({runrefs}));
DELETE FROM saly.ventas_discovery_plan_batches WHERE run_id IN (
 SELECT id FROM saly.ventas_discovery_runs WHERE run_ref IN ({runrefs}));
DELETE FROM saly.ventas_discovery_plan_fuentes WHERE run_id IN (
 SELECT id FROM saly.ventas_discovery_runs WHERE run_ref IN ({runrefs}));
DELETE FROM saly.ventas_discovery_runs WHERE run_ref IN ({runrefs});
DELETE FROM saly.ventas_discovery_catalogo WHERE catalog_version={c};
COMMIT;""")
        if psql(fixture_count)!="0" or psql("SELECT count(*) FROM saly.ventas_hallazgos")!="0" or psql("SELECT count(*) FROM saly.ventas_discovery_ingestas")!="0":
            raise AssertionError("CROSSRUN_FIXTURE_CLEANUP_FAILED")

if __name__=="__main__":
    main()
