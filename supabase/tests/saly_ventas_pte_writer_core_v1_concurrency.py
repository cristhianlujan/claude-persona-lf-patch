#!/usr/bin/env python3
"""PG17 two-session qualification. Run on an already provisioned, disposable
test instance with L27/L28 and this writer installed. Never use shared SALY DB.
Requires psql on PATH; target must be local and explicitly named.
Tests the same deployed SQL, not a mocked writer."""
import os
import subprocess
import time
import uuid
import hashlib
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

def psql(sql, *, timeout=30):
    r = subprocess.run(["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-c", sql],
                       check=True, text=True, capture_output=True, timeout=timeout)
    return r.stdout.strip()

def main():
    if os.environ.get("PGHOST") not in ("127.0.0.1", "localhost") or os.environ.get("PGDATABASE") != "saly_pte_writer_ci":
        raise RuntimeError("DISPOSABLE_LOCAL_PG17_ONLY")
    if not psql("SHOW server_version_num").startswith("17"):
        raise RuntimeError("PG17_REQUIRED")
    if psql("SELECT count(*) FROM saly.ventas_discovery_runs") != "0":
        raise RuntimeError("EMPTY_TEST_LEDGER_REQUIRED")
    tag = uuid.uuid4().hex
    run = "RUN-CONCURRENT-" + tag
    cat = "CAT-CONCURRENT-" + tag
    capture = '[{"fila_origen":1,"nombre":"Concurrent A","ruc":"20100000001","ubigeo":"150101"},{"fila_origen":2,"nombre":"Concurrent B","ruc":"20100000001","ubigeo":"110101"}]'
    url = "https://www.datosabiertos.gob.pe/sites/default/files/fixture.csv"
    def lit(s):
        return "'" + s.replace("'", "''") + "'"
    c, r, cap, u = map(lit, (cat, run, capture, url))
    query = str(uuid.uuid4())
    q = lit(query)
    try:
        psql(f"""BEGIN;
INSERT INTO saly.ventas_discovery_catalogo(catalog_version,source_id,connector_id,substep_code,step,familia,nombre,landing_page,rights_status,rights_evidence_ref,rights_checked_at,persist_business_data,habilitada)
VALUES ({c},'PE-PTE','SALY-U07-S13-C03','13.03',13,'ESTADO_TERRITORIAL','Fixture','https://www.datosabiertos.gob.pe/dataset/fixture','PERSISTENCIA_PERMITIDA','fixture://synthetic',now(),true,true);
INSERT INTO saly.ventas_discovery_runs(run_ref,catalog_version,scope,plan_hash,estado)
VALUES ({r},{c},'{{"scope":"LIMA_ICA"}}',repeat('a',64),'EN_EJECUCION');
INSERT INTO saly.ventas_discovery_plan_fuentes(run_id,catalog_version,source_id,connector_id,substep_code,scope_key,seleccion)
SELECT id,{c},'PE-PTE','SALY-U07-S13-C03','13.03','LIMA_ICA','REQUIRED' FROM saly.ventas_discovery_runs WHERE run_ref={r};
INSERT INTO saly.ventas_discovery_plan_batches(run_id,source_id,scope_key,batch_key,query_hash,estado)
SELECT id,'PE-PTE','LIMA_ICA','FIXTURE',repeat('b',64),'FOUND' FROM saly.ventas_discovery_runs WHERE run_ref={r};
INSERT INTO saly.ventas_discovery_ejecuciones(run_id,catalog_version,source_id,connector_id,substep_code,scope_key,estado,evidencia_ref,ultima_consulta_en,total_encontrados)
SELECT id,{c},'PE-PTE','SALY-U07-S13-C03','13.03','LIMA_ICA','FOUND',{u}||'#captura-json-sha256='||encode(sha256(convert_to({cap},'UTF8')),'hex'),now(),2 FROM saly.ventas_discovery_runs WHERE run_ref={r};
INSERT INTO saly.ventas_discovery_consultas(id,ejecucion_id,run_id,run_ref,catalog_version,source_id,connector_id,substep_code,scope_key,batch_key,query_hash,herramienta,inicio,fin,estado,cantidad_hallazgos,evidencia_ref)
SELECT {q}::uuid,e.id,d.id,d.run_ref,{c},'PE-PTE','SALY-U07-S13-C03','13.03','LIMA_ICA','FIXTURE',repeat('b',64),'SYNTHETIC',now(),now(),'FOUND',2,e.evidencia_ref FROM saly.ventas_discovery_ejecuciones e JOIN saly.ventas_discovery_runs d ON d.id=e.run_id WHERE d.run_ref={r};
COMMIT;""")
        call = f"SELECT saly.ventas_pte_ingesta_core_v1({q}::uuid,{cap},'fixture',{u})->>'status';"
        # A keeps its transaction open after the actual writer returns.
        # Only start B after A has returned INSERTED, so B must compete on A's row lock.
        a = subprocess.Popen(["psql","-X","-qAt","-v","ON_ERROR_STOP=1"],
                             stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
        try:
            a.stdin.write("BEGIN;\n" + call + "\n")
            a.stdin.flush()
            with ThreadPoolExecutor(max_workers=1) as pool:
                first = pool.submit(a.stdout.readline).result(timeout=15).strip()
                if first != "INSERTED":
                    raise AssertionError("PTE_CONCURRENT_FIRST_NOT_INSERTED:" + first)
                # A holds the lock; B actually runs the same key on a second backend.
                second = pool.submit(psql, "SET application_name='saly_pte_concurrent_b'; " + call)
                deadline = time.monotonic() + 10
                blocked = False
                while time.monotonic() < deadline:
                    if psql("SELECT count(*) FROM pg_stat_activity WHERE application_name='saly_pte_concurrent_b' AND wait_event_type='Lock'") == "1":
                        blocked = True
                        break
                    time.sleep(0.1)
                if not blocked:
                    raise AssertionError("PTE_CONCURRENT_LOCK_NOT_OBSERVED")
                a.stdin.write("COMMIT;\n")
                a.stdin.flush()
                if second.result(timeout=15) != "REPLAY":
                    raise AssertionError("PTE_CONCURRENT_SECOND_NOT_REPLAY")
            count = psql(f"SELECT count(*)||':'||(SELECT count(*) FROM saly.ventas_hallazgos h JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id WHERE i.consulta_id={q}::uuid) FROM saly.ventas_discovery_ingestas WHERE consulta_id={q}::uuid")
            if count != "1:2":
                raise AssertionError("PTE_CONCURRENT_DUPLICATE_EFFECT:" + count)
            # Read back through the actual SKILL SQL contract, not a fake callback.
            # Positive and negative share the same persisted two-row fixture.
            template = Path("skills/ai_sales_discovery/queries/pte_exact_readback.sql").read_text()
            if template.count("WITH expected AS (") != 1:
                raise AssertionError("SKILL_READBACK_TEMPLATE_MISSING")
            sql_select = template.split("WITH expected AS (", 1)[1].split(";", 1)[0]
            sql_select = "WITH expected AS (" + sql_select
            if sql_select.count("$4::jsonb") != 1 or sql_select.count("$1") != 1:
                raise AssertionError("SKILL_READBACK_TEMPLATE_PARAMS_DRIFT")
            def execute_readback(capture_json):
                statement = ("PREPARE skill_pte_rb(text,text,text,jsonb) AS " +
                             sql_select + "; EXECUTE skill_pte_rb('PE-PTE','fixture','LIMA_ICA'," +
                             lit(capture_json) + "::jsonb);")
                output = psql(statement).split("|")
                if len(output) != 7:
                    raise AssertionError("SKILL_READBACK_RESULT_SHAPE:"+str(output))
                return output
            good = execute_readback(capture)
            expected_hash = hashlib.sha256(capture.encode("utf-8")).hexdigest()
            if good[:3] != ["PE-PTE","fixture","LIMA_ICA"] or \
               good[3] != expected_hash or good[4:6] != ["2","2"] or \
               not good[6].startswith("saly.ventas_discovery_ingestas:"):
                raise AssertionError("SKILL_READBACK_POSITIVE_FAIL:"+str(good))
            changed = capture.replace("Concurrent A","Changed A")
            negative = execute_readback(changed)
            if negative[3] != expected_hash or negative[4:6] != ["2","1"]:
                raise AssertionError("SKILL_READBACK_MUTATION_NOT_DETECTED:"+str(negative))
            print("PASS_AI_SALES_SKILL_PTE_SQL_READBACK_PG17_POSITIVE_NEGATIVE")
            print("PASS_PTE_TWO_SESSIONS_ONE_EFFECT")
        finally:
            if a.poll() is None:
                a.terminate()
            a.communicate(timeout=5)
    finally:
        # Cleanup confined to the synthetic run on the disposable test database.
        psql(f"""BEGIN;
DELETE FROM saly.ventas_hallazgos WHERE ingesta_id IN (SELECT id FROM saly.ventas_discovery_ingestas WHERE run_ref={r});
DELETE FROM saly.ventas_discovery_ingestas WHERE run_ref={r};
DELETE FROM saly.ventas_discovery_consultas WHERE run_ref={r};
DELETE FROM saly.ventas_discovery_ejecuciones WHERE run_id IN (SELECT id FROM saly.ventas_discovery_runs WHERE run_ref={r});
DELETE FROM saly.ventas_discovery_plan_batches WHERE run_id IN (SELECT id FROM saly.ventas_discovery_runs WHERE run_ref={r});
DELETE FROM saly.ventas_discovery_plan_fuentes WHERE run_id IN (SELECT id FROM saly.ventas_discovery_runs WHERE run_ref={r});
DELETE FROM saly.ventas_discovery_runs WHERE run_ref={r};
DELETE FROM saly.ventas_discovery_catalogo WHERE catalog_version={c};
COMMIT;""")
        if psql("SELECT count(*) FROM saly.ventas_discovery_runs") != "0":
            raise AssertionError("PTE_TEST_CLEANUP_FAILED")

if __name__ == "__main__":
    main()
