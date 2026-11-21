"""PG17 disposable qualification on the existing SALY schema and real competing sessions."""
import json
import os
import subprocess
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT / "supabase/tests"))
sys.path.insert(0,str(ROOT / "skills/ai_sales_discovery/adapters"))
from saly_ventas_pte_crossrun_pg17_concurrency import psql, lit
from sunat_company_v1 import company, batches, MONTHLY_FIELDS


def main():
    assert os.getenv("PGHOST") == "127.0.0.1" and os.getenv("PGDATABASE") == "saly_pte_writer_ci"
    assert psql("SHOW server_version_num").startswith("17")
    psql("CREATE TABLE public.lf_global_config(scope text, config_key text, config_value text, value_status text, valid_from timestamptz)")
    psql((Path(__file__).with_name("sunat_writer_candidate_v1.sql")).read_text())
    monthly_url, reduced_url = "https://example.org/monthly", "https://example.org/reduced"
    rows = []
    for i in (1,2):
        m = dict.fromkeys(MONTHLY_FIELDS,"")
        m.update(RUC=str(20000000000+i), Estado="ACTIVO", UBIGEO="150101",NroTrab="-")
        d = dict(RUC=m["RUC"], nombre="Compañía "+str(i), estado="ACTIVO", condicion="", ubigeo="150101")
        e = dict(url=monthly_url, ordinal=i,zip_sha256="a"*64,header_sha256="c"*64)
        rows.append(company(m,d,e,dict(e,url=reduced_url,zip_sha256="b"*64)))
    payload, = batches(rows,2,10000)
    policy = dict(enabled=True,source_id="TEST-SUNAT", monthly_url=monthly_url, reduced_url=reduced_url,
                  max_rows=2,max_bytes=10000,license="fixture",attribution="fixture",
                  monthly_rights="fixture:monthly",reduced_rights="fixture:reduced")
    psql("INSERT INTO public.lf_global_config VALUES ('SALY_DISCOVERY','SUNAT_POLICY_V1',"+
         lit(json.dumps(policy))+",'REAL',now())")
    c, a, b, u, cap = map(lit,("CAT-SUNAT-TEST","RUN-SUNAT-A","RUN-SUNAT-B",monthly_url,payload.decode()))
    runrefs = a+","+b
    query_a, query_b = str(uuid.uuid4()), str(uuid.uuid4())
    psql(f"""BEGIN;
INSERT INTO saly.ventas_discovery_catalogo(
 catalog_version,source_id,connector_id,substep_code,step,familia,nombre,
 landing_page,rights_status,rights_evidence_ref,rights_checked_at,
 persist_business_data,habilitada)
VALUES ({c},'TEST-SUNAT','TEST-CONNECTOR','13.03',13,'ESTADO_TERRITORIAL','Synthetic company source',
'https://www.datosabiertos.gob.pe/dataset/fixture',
'PERSISTENCIA_PERMITIDA','fixture://crossrun',now(),true,true);

INSERT INTO saly.ventas_discovery_runs(run_ref,catalog_version,scope,plan_hash,estado)
VALUES ({a},{c},'{{"scope":"LIMA_ICA"}}',repeat('a',64),'EN_EJECUCION'),
       ({b},{c},'{{"scope":"LIMA_ICA"}}',repeat('b',64),'EN_EJECUCION');

INSERT INTO saly.ventas_discovery_plan_fuentes(
 run_id,catalog_version,source_id,connector_id,substep_code,scope_key,seleccion,estado)
SELECT id,{c},'TEST-SUNAT','TEST-CONNECTOR','13.03','LIMA_ICA','REQUIRED','EN_EJECUCION'
FROM saly.ventas_discovery_runs WHERE run_ref IN ({runrefs});

INSERT INTO saly.ventas_discovery_plan_batches(run_id,source_id,scope_key,batch_key,query_hash,estado)
SELECT id,'TEST-SUNAT','LIMA_ICA','FIXTURE',repeat('c',64),'FOUND'
FROM saly.ventas_discovery_runs WHERE run_ref IN ({runrefs});

INSERT INTO saly.ventas_discovery_ejecuciones(
 run_id,catalog_version,source_id,connector_id,substep_code,scope_key,estado,
 evidencia_ref,ultima_consulta_en,total_encontrados)
SELECT id,{c},'TEST-SUNAT','TEST-CONNECTOR','13.03','LIMA_ICA','FOUND',
{u}||'#captura-json-sha256='||encode(sha256(convert_to({cap},'UTF8')),'hex'),now(),2
FROM saly.ventas_discovery_runs WHERE run_ref IN ({runrefs});

INSERT INTO saly.ventas_discovery_consultas(
 id,ejecucion_id,run_id,run_ref,catalog_version,source_id,connector_id,
 substep_code,scope_key,batch_key,query_hash,herramienta,inicio,fin,estado,
 cantidad_hallazgos,evidencia_ref)
SELECT CASE d.run_ref WHEN {a} THEN {lit(query_a)}::uuid ELSE {lit(query_b)}::uuid END,
e.id,d.id,d.run_ref,{c},'TEST-SUNAT','TEST-CONNECTOR','13.03',
'LIMA_ICA','FIXTURE',repeat('c',64),'SYNTHETIC_PG17_CONCURRENT',
now(),now(),'FOUND',2,e.evidencia_ref
FROM saly.ventas_discovery_ejecuciones e
JOIN saly.ventas_discovery_runs d ON d.id=e.run_id
WHERE d.run_ref IN ({runrefs});
COMMIT;""")
    def call(q):
        return f"SELECT saly.ventas_sunat_ingesta_core_v1({lit(q)}::uuid,{cap});"
    psql("BEGIN;"+call(query_a)+"ROLLBACK;")
    assert psql("SELECT count(*) FROM saly.ventas_discovery_ingestas")=="0"
    try:
        psql(call(str(uuid.uuid4())))
    except subprocess.CalledProcessError as exc:
        assert "SUNAT_QUERY_OR_RIGHTS" in exc.stderr, exc.stderr
    else:
        raise AssertionError("missing consultation accepted")
    with subprocess.Popen(["psql","-X","-qAt","-v","ON_ERROR_STOP=1"],stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE,text=True,bufsize=1) as first:
        try:
            first.stdin.write("BEGIN;\n"+call(query_a)+"\n")
            first.stdin.flush()
            with ThreadPoolExecutor(max_workers=2) as pool:
                received = pool.submit(first.stdout.readline).result(timeout=12).strip()
                uuid.UUID(received)
                second = pool.submit(psql,call(query_b),app="sunat_ci_competing",timeout=20)
                deadline=time.monotonic()+8
                waiting=False
                while time.monotonic()<deadline and not second.done():
                    waiting = psql("SELECT EXISTS(SELECT FROM pg_stat_activity WHERE application_name='sunat_ci_competing' AND wait_event_type='Lock')")=="t"
                    if waiting: break
                    time.sleep(.1)
                first.stdin.write("COMMIT;\n")
                first.stdin.flush()
                assert waiting and second.result(timeout=12)==received
        finally:
            first.stdin.close()
            first.wait(timeout=10)
    assert psql(call(query_a)) == received
    assert psql("SELECT count(*) FROM saly.ventas_discovery_ingestas")=="1"
    assert psql("SELECT count(*) FROM saly.ventas_hallazgos WHERE captura_empresarial IS NOT NULL")=="2"
    # Different scheduled batch for the same source snapshot tries the same RUCs.
    d_id = str(uuid.uuid4())
    psql(f"""BEGIN;
    INSERT INTO saly.ventas_discovery_plan_batches(run_id,source_id,scope_key,batch_key,query_hash,estado)
    SELECT run_id,source_id,scope_key,'OVERLAP',query_hash,estado FROM saly.ventas_discovery_plan_batches
    WHERE run_id=(SELECT run_id FROM saly.ventas_discovery_consultas WHERE id={lit(query_b)}::uuid);
    INSERT INTO saly.ventas_discovery_consultas(id,ejecucion_id,run_id,run_ref,catalog_version,source_id,connector_id,
    substep_code,scope_key,batch_key,query_hash,herramienta,inicio,fin,estado,cantidad_hallazgos,evidencia_ref)
    SELECT {lit(d_id)}::uuid,ejecucion_id,run_id,run_ref,catalog_version,source_id,connector_id,substep_code,scope_key,
    'OVERLAP',query_hash,herramienta,inicio,fin,estado,cantidad_hallazgos,evidencia_ref FROM saly.ventas_discovery_consultas
    WHERE id={lit(query_b)}::uuid; COMMIT;""")
    try:
        psql(call(d_id))
    except subprocess.CalledProcessError as exc:
        assert "SUNAT_OVERLAPPING_BATCH" in exc.stderr, exc.stderr
    else:
        raise AssertionError("overlapping batch accepted")
    assert psql("SELECT count(*) FROM saly.ventas_discovery_ingestas")=="1"
    print("PASS_SUNAT_PG17_ROLLBACK_NEGATIVE_CROSS_RUN_LOCK_REPLAY_1_BATCH_2_COMPANIES")


if __name__ == "__main__":
    main()

