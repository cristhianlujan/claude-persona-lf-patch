"""PG17 disposable: reproduce real SUNAT batch-9 Unicode name rejection, then prove minimal guard fix."""
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"supabase/tests"))
sys.path.insert(0,str(ROOT/"skills/ai_sales_discovery/adapters"))
from saly_ventas_pte_crossrun_pg17_concurrency import psql,lit
from sunat_company_v1 import company,batches,MONTHLY_FIELDS


def main():
    assert os.getenv('PGHOST')=='127.0.0.1' and os.getenv('PGDATABASE')=='saly_pte_writer_ci'
    assert psql('SHOW server_version_num').startswith('17')
    assert psql("SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE source_id='TEST-SUNAT'")=='1'
    ms=dict.fromkeys(MONTHLY_FIELDS,'')
    ms.update(RUC='20000000003',Estado='ACTIVO',UBIGEO='150101',NroTrab='3')
    # Real failure: Python strip normalizes NBSP, original PG btrim does not.
    name='\u00a0Empresa Ejemplo\u00a0'
    red=dict(RUC=ms['RUC'],nombre=name,estado='ACTIVO',condicion='',ubigeo='150101')
    ev=dict(url='https://example.org/monthly',ordinal=3,zip_sha256='a'*64,header_sha256='c'*64)
    item=company(ms,red,ev,dict(ev,url='https://example.org/reduced',zip_sha256='b'*64))
    assert item['capture']['normalized']['razon_social']=='Empresa Ejemplo'
    payload,=batches([item],2,10000)
    capture=lit(payload.decode())
    qid=str(uuid.uuid4())
    psql("""INSERT INTO saly.ventas_discovery_plan_batches(run_id,source_id,scope_key,batch_key,query_hash,estado)
SELECT id,'TEST-SUNAT','LIMA_ICA','UNICODE_NAME',repeat('d',64),'FOUND'
FROM saly.ventas_discovery_runs WHERE run_ref='RUN-SUNAT-A';""")
    psql("""INSERT INTO saly.ventas_discovery_consultas(
id,ejecucion_id,run_id,run_ref,catalog_version,source_id,connector_id,substep_code,
scope_key,batch_key,query_hash,herramienta,inicio,fin,estado,cantidad_hallazgos,evidencia_ref)
SELECT """+lit(qid)+"""::uuid,e.id,d.id,d.run_ref,d.catalog_version,
'TEST-SUNAT','TEST-CONNECTOR','13.03','LIMA_ICA','UNICODE_NAME',repeat('d',64),
'PG17_UNICODE_TRIM',now(),now(),'FOUND',1,
'https://example.org/monthly#captura-json-sha256='||
encode(sha256(convert_to("""+capture+""",'UTF8')),'hex')
FROM saly.ventas_discovery_ejecuciones e
JOIN saly.ventas_discovery_runs d ON d.id=e.run_id
WHERE d.run_ref='RUN-SUNAT-A';""")
    call="SELECT saly.ventas_sunat_ingesta_core_v1("+lit(qid)+"::uuid,"+capture+");"
    try:
        psql(call)
    except subprocess.CalledProcessError as exc:
        assert 'SUNAT_CAPTURE_INVALID' in exc.stderr,'ORIGINAL_WRITER_REJECTION_CHANGED'
    else:
        raise AssertionError('ORIGINAL_WRITER_FALSELY_ACCEPTED_UNICODE')
    assert psql("SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE source_id='TEST-SUNAT'")=='1'
    migration=list((ROOT/'supabase/migrations').glob('*_lf_saly_sunat_name_whitespace_v1.sql'))
    assert len(migration)==1
    text=migration[0].read_text()
    start=text.index('CREATE OR REPLACE FUNCTION saly.ventas_sunat_ingesta_core_v1(')
    end=text.index('DO $post$',start)
    ddl=text[start:end].strip()
    assert ddl.endswith(';') and ddl.count("chr(160)")==2
    psql(ddl)
    result=psql(call)
    uuid.UUID(result)
    assert psql("SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE source_id='TEST-SUNAT'")=='2'
    assert psql("SELECT count(*) FROM saly.ventas_hallazgos WHERE captura_empresarial IS NOT NULL")=='3'
    raw_name_json=psql("SELECT to_json(captura_empresarial#>>'{capture,observations,reduced,raw,nombre}')::text FROM saly.ventas_hallazgos WHERE ruc_candidato='20000000003'")
    assert json.loads(raw_name_json)==name,'RAW_NAME_NOT_PRESERVED'
    assert psql("SELECT captura_empresarial#>>'{capture,normalized,razon_social}' FROM saly.ventas_hallazgos WHERE ruc_candidato='20000000003'")=='Empresa Ejemplo'
    print('PASS_SUNAT_UNICODE_NAME_PG17_NEGATIVE_BEFORE_POSITIVE_AFTER_EXACT_RAW_PRESERVED')


if __name__=='__main__':
    main()
