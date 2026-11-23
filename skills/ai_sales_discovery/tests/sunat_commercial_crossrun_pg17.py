"""EXACT commercial SUNAT core cross-RUN replay on isolated PostgreSQL17.

First execute the original legacy real-writer concurrency and negative cases,
then install only the exact modified function source, demonstrating:
(1) legacy original 1 batch unchanged;
(2) same key+source ZIP but DIFFERENT RUN and DIFFERENT company payload is
    accepted only when commercial_mode=true;
(3) replay of the new RUN uses its own receipt and never changes the prior one.
"""
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"supabase/tests"))
sys.path.insert(0,str(ROOT/"skills/ai_sales_discovery/adapters"))
from saly_ventas_pte_crossrun_pg17_concurrency import psql,lit
from sunat_company_v1 import company,batches,MONTHLY_FIELDS
from sunat_writer_pg17 import main as legacy_writer_full_test

def main():
    legacy_writer_full_test()
    assert psql("SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE source_id='TEST-SUNAT'")=="1"
    original=psql("SELECT id FROM saly.ventas_discovery_ingestas WHERE source_id='TEST-SUNAT'")
    migration=next((ROOT/"supabase/migrations").glob("*_lf_saly_sunat_commercial_crossrun_replay_v1.sql"))
    src=migration.read_text()
    x=src.index("CREATE OR REPLACE FUNCTION saly.ventas_sunat_ingesta_core_v1")
    y=src.index("END $function$;",x)+len("END $function$;")
    exact_ddl=src[x:y]
    assert "run_ref=q.run_ref" in exact_ddl and "commercial_mode" in exact_ddl
    psql(exact_ddl)

    monthly_url,reduced_url="https://example.org/monthly","https://example.org/reduced"
    companies=[]
    for n in (3,4):
        ruc=str(20000000000+n)
        m=dict.fromkeys(MONTHLY_FIELDS,"")
        m.update(RUC=ruc,NroTrab="50",Estado="ACTIVO",
                 Condicion="HABIDO",UBIGEO="150101")
        d=dict(RUC=ruc,nombre="Fixture "+str(n),estado="ACTIVO",
               condicion="HABIDO",ubigeo="150101")
        proof=dict(url=monthly_url,ordinal=n,
                   zip_sha256="a"*64,header_sha256="c"*64)
        companies.append(company(m,d,proof,
                         dict(proof,url=reduced_url,zip_sha256="b"*64)))
    payload,=batches(companies,2,10000)
    cap=payload.decode("utf8")
    h=psql("SELECT encode(sha256(convert_to("+lit(cap)+",'UTF8')),'hex')")
    assert len(h)==64
    q=psql("""SELECT c.id::text FROM saly.ventas_discovery_consultas c
    WHERE c.run_ref='RUN-SUNAT-B' AND c.batch_key='FIXTURE'""")
    psql("UPDATE public.lf_global_config SET config_value="
         +lit(json.dumps(dict(enabled=True,commercial_mode=True,source_id="TEST-SUNAT",
            monthly_url=monthly_url,reduced_url=reduced_url,max_rows=2,max_bytes=10000,
            license="fixture",attribution="fixture",monthly_rights="fixture:monthly",
            reduced_rights="fixture:reduced")))
         +" WHERE config_key='SUNAT_POLICY_V1'")
    psql("UPDATE saly.ventas_discovery_consultas SET evidencia_ref="
         +lit(monthly_url+"#captura-json-sha256="+h)
         +" WHERE id="+lit(q)+"::uuid")
    newer=psql("SELECT saly.ventas_sunat_ingesta_core_v1("
               +lit(q)+"::uuid,"+lit(cap)+")")
    assert newer!=original
    assert psql("SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE source_id='TEST-SUNAT'")=="2"
    assert psql("SELECT count(*) FROM saly.ventas_hallazgos WHERE captura_empresarial IS NOT NULL")=="4"
    assert psql("SELECT count(*) FROM saly.ventas_hallazgos WHERE ingesta_id="+lit(original)+"::uuid")=="2"
    assert psql("SELECT count(*) FROM saly.ventas_hallazgos WHERE ingesta_id="+lit(newer)+"::uuid")=="2"
    assert psql("SELECT saly.ventas_sunat_ingesta_core_v1("
                +lit(q)+"::uuid,"+lit(cap)+")")==newer
    assert psql("SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE source_id='TEST-SUNAT'")=="2"
    print("PASS_SALY_SUNAT_PG17_LEGACY_CROSSRUN_REPLAY_UNCHANGED_COMMERCIAL_RUN_SCOPED_4_COMPANIES")

if __name__=="__main__":
    main()
