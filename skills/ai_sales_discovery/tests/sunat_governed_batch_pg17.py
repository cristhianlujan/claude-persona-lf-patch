"""Disposable PG17: actual SALY schema/writer and native reserve/lease/effect functions.
Synthetic operation registration, approved policy and payloads only. No production authority test.
Runs after sunat_writer_pg17.py in the existing workflow.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'supabase/tests'))
sys.path.insert(0,str(ROOT/'skills/ai_sales_discovery/adapters'))
from saly_ventas_pte_crossrun_pg17_concurrency import psql, lit
from sunat_company_v1 import company, batches, MONTHLY_FIELDS
from sunat_batch_plan_v1 import canonical, sha

GEN=ROOT/'supabase/migrations/20260911025454_s30_c05_generic_execution_reliability_v1.sql'
AUTH=ROOT/'supabase/migrations/20260917224500_s30_router_downstream_authority_enforcement_v1.sql'

def function(source,name):
    pattern=r'create or replace function public\.'+re.escape(name)+r'\(.*?\$function\$;'
    found=re.findall(pattern,source.read_text(),flags=re.I|re.S)
    assert len(found)==1,name
    return found[0]

def main():
    assert os.getenv('PGHOST')=='127.0.0.1' and os.getenv('PGDATABASE')=='saly_pte_writer_ci'
    assert psql('SHOW server_version_num').startswith('17')
    psql("""CREATE TABLE public.lf_operation_registry(operation_code text PRIMARY KEY,status text NOT NULL);
CREATE TABLE public.lf_operation_contracts(operation_code text,contract_code text,status text);
CREATE TABLE public.lf_activos(codigo_activo text,metadata jsonb,archived_at timestamptz,estado_operativo text);
INSERT INTO public.lf_activos VALUES('ROUTER_DOWNSTREAM_AUTHORITY','{"transversal_inventory":{"consumers_known":["ACTUALIZACION_DB_LF"]}}',NULL,'ACTIVO');
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,operation_code text REFERENCES public.lf_operation_registry(operation_code),
 target_type text,target_code text,target_repo text,target_path text,status text NOT NULL DEFAULT 'IN_PROGRESS',
 manifest jsonb NOT NULL DEFAULT '{}',created_by_execution_id text,updated_by_execution_id text,
 idempotency_key text,request_sha256 text,lease_owner text,lease_expires_at timestamptz,lease_fence bigint NOT NULL DEFAULT 0);
CREATE UNIQUE INDEX fixture_operation_idempotency ON public.lf_operation_execution(operation_code,idempotency_key) WHERE idempotency_key IS NOT NULL;""")
    source=GEN.read_text()
    start=source.index('create table if not exists public.lf_operation_effect_guard')
    end=source.index('alter table public.lf_operation_effect_guard enable row level security',start)
    psql(source[start:end])
    for file,name in [(GEN,'fn_lf_operation_reserve_execution_v1'),(GEN,'fn_lf_operation_acquire_lease_v1'),
                      (GEN,'fn_lf_operation_mark_effect_succeeded_v1'),
                      (AUTH,'lf_router_downstream_authority_consumer_v1'),(AUTH,'lf_router_downstream_authority_validate_v1'),
                      (AUTH,'fn_lf_operation_reserve_effect_v1')]:
        psql(function(file,name))
    psql(Path(__file__).with_name('sunat_governed_batch_candidate_v1.sql').read_text())
    monthly='https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip'
    reduced='https://www2.sunat.gob.pe/padron_reducido_ruc.zip'
    snapshots=['d'*64,'e'*64]
    captures=[]
    for i in (1,2):
        m=dict.fromkeys(MONTHLY_FIELDS,''); m.update(RUC=str(20000002000+i),Estado='ACTIVO',Condicion='HABIDO',UBIGEO='110101',NroTrab=('50' if i==1 else '49'))
        d=dict(RUC=m['RUC'],nombre='Fixture jurídica '+str(i),estado='ACTIVO',condicion='HABIDO',ubigeo='110101')
        ev=dict(url=monthly,ordinal=i,zip_sha256=snapshots[0],header_sha256='c'*64)
        captures.append(company(m,d,ev,dict(ev,url=reduced,zip_sha256=snapshots[1])))
    payloads=list(batches(captures,1,10000))
    plan=[]
    for i,p in enumerate(payloads,1):
        h=sha(p)
        plan.append(dict(batch_key=sha(canonical(['PE-SUNAT-RUC',snapshots,'LIMA_ICA',i])),ordinal=i,rows=1,
                         bytes=len(p),capture_sha256=h,consulta_evidencia_ref=monthly+'#captura-json-sha256='+h))
    digest=sha(canonical(plan))
    rights='fixture://sunat-internal-reuse'
    policy=dict(enabled=True,source_id='PE-SUNAT-RUC',monthly_url=monthly,reduced_url=reduced,
        max_rows=1,max_bytes=10000,max_total_bytes=20000,expected_rows=2,expected_batches=2,
        rights_scope='SALY_B2B_INTERNAL_BUSINESS_FACTS_LIMA_ICA_RUC20',reduced_rights_status='PERSISTENCIA_PERMITIDA',
        rights_evidence_ref=rights,manifest_digest_sha256=digest,snapshot_sha256=snapshots,license='fixture',
        attribution='fixture',monthly_rights='fixture',reduced_rights='fixture')
    req=dict(business='SALY',source_id='PE-SUNAT-RUC',scope_key='LIMA_ICA',snapshot_sha256=snapshots,manifest_digest_sha256=digest)
    psql("""INSERT INTO saly.ventas_discovery_catalogo(catalog_version,source_id,connector_id,substep_code,step,familia,nombre,landing_page,rights_status,rights_evidence_ref,rights_checked_at,persist_business_data,habilitada)
VALUES('CAT-SUNAT-GOV-TEST','PE-SUNAT-RUC','SALY-U07-S12-C01','12.01',12,'ESTADO_NACIONAL','Synthetic official source','https://www.sunat.gob.pe/descargaPRR/mrc137_padron_reducido.html','PERSISTENCIA_PERMITIDA','fixture://sunat-internal-reuse',now(),true,true);
INSERT INTO public.lf_operation_registry VALUES('INGESTA_EMPRESARIAL_SALY','SANDBOX_ACTIVE');
INSERT INTO public.lf_operation_contracts VALUES('INGESTA_EMPRESARIAL_SALY','SALY_BUSINESS_INGESTION_V1','ACTIVE_ENFORCEMENT');""")
    def set_policy(p):
        psql("INSERT INTO public.lf_global_config VALUES('SALY_DISCOVERY','SUNAT_POLICY_V1',"+lit(json.dumps(p))+",'REAL',clock_timestamp())")
    set_policy(policy)
    def reserve(exec_id,request):
        return psql("SELECT public.fn_lf_operation_reserve_execution_v1("+",".join(map(lit,[
            exec_id,'INGESTA_EMPRESARIAL_SALY','DISCOVERY_SOURCE','PE-SUNAT-RUC',exec_id,sha(canonical(request)),exec_id]))+
            ",NULL,NULL,"+lit(json.dumps({'sunat_plan':request}))+"::jsonb)")
    ex='EXEC-SUNAT-FIXTURE'; reserve(ex,req)
    lease=json.loads(psql("SELECT public.fn_lf_operation_acquire_lease_v1("+lit(ex)+",'fixture-worker',60,"+lit(ex)+")"))
    fence=lease['lease_fence']
    def prepare(p=plan,execution=ex,f=fence):
        return "SELECT saly.ventas_sunat_plan_prepare_v1("+lit(execution)+",'fixture-worker',"+str(f)+","+lit(json.dumps(p,ensure_ascii=False))+"::jsonb);"
    def execute(i=0,p=None,f=fence):
        return "SELECT saly.ventas_sunat_batch_execute_v1("+lit(ex)+",'fixture-worker',"+str(f)+","+lit(plan[i]['batch_key'])+","+lit((p if p is not None else payloads[i]).decode())+");"
    def fail(sql,expected):
        try: psql(sql)
        except subprocess.CalledProcessError as err: assert expected in err.stderr,err.stderr
        else: raise AssertionError('accepted: '+expected)
    def counts():
        return psql("""SELECT count(*)::text||':'||(SELECT count(*) FROM saly.ventas_discovery_consultas WHERE source_id='PE-SUNAT-RUC')::text||':'||
(SELECT count(*) FROM public.lf_operation_effect_guard WHERE execution_id='EXEC-SUNAT-FIXTURE')::text FROM saly.ventas_discovery_ingestas WHERE source_id='PE-SUNAT-RUC'""")
    fail(prepare(execution='no-such-exec'),'SUNAT_OPERATION_REQUIRED')
    fail(prepare(f=fence+1),'SUNAT_STALE_LEASE')
    set_policy(dict(policy,enabled=False)); fail(prepare(),'SUNAT_CALL_POLICY'); set_policy(policy)
    fail(prepare([dict(plan[0],rows=2),plan[1]]),'SUNAT_PLAN_DIGEST')
    run=psql(prepare()); assert psql(prepare())==run
    fail(execute(p=payloads[0]+b' '),'SUNAT_BATCH_HASH')
    assert counts()=='0:0:0'
    # Positive exact full transaction, prove no mutation survives rollback.
    psql('BEGIN;'+execute()+'ROLLBACK;'); assert counts()=='0:0:0'
    # Real writer failure after reservation and consultation rolls back both, no orphan.
    set_policy(dict(policy,license='')); fail(execute(),'SUNAT_POLICY_INVALID'); assert counts()=='0:0:0'; set_policy(policy)
    # Catalog permission failure must also leave zero effects.
    psql("UPDATE saly.ventas_discovery_catalogo SET habilitada=false,persist_business_data=false WHERE source_id='PE-SUNAT-RUC'")
    fail(execute(),'SUNAT_CALL_CATALOG')
    psql("UPDATE saly.ventas_discovery_catalogo SET habilitada=true,persist_business_data=true WHERE source_id='PE-SUNAT-RUC'")
    assert counts()=='0:0:0'
    first=psql(execute()); assert counts()=='1:1:1'; assert psql(execute())==first
    second=psql(execute(1)); assert first!=second and counts()=='2:2:2'
    assert psql("SELECT count(*) FROM saly.ventas_hallazgos h JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id WHERE i.source_id='PE-SUNAT-RUC'")=='2'
    assert psql("SELECT count(*) FROM public.lf_operation_effect_guard WHERE execution_id='EXEC-SUNAT-FIXTURE' AND state='SUCCEEDED'")=='2'
    assert psql("SELECT count(*) FROM saly.ventas_discovery_plan_batches WHERE run_id="+lit(run)+"::uuid AND estado='FOUND'")=='2'
    # PG17 positive + negative against the exact commercial-view DDL carried by this PR.
    # The SUNAT writer and signed payloads are unchanged; the view filters at ingestion-read time.
    matches=list((ROOT/'supabase/migrations').glob('*_lf_saly_sunat_commercial_filter_v1.sql'))
    assert len(matches)==1
    migration=matches[0].read_text()
    ddl=migration[migration.index('CREATE VIEW saly.ventas_sunat_elegibilidad_v1'):
                  migration.index('DO $post
    fail(execute(f=fence+1),'SUNAT_STALE_LEASE')
    psql("UPDATE saly.ventas_hallazgos SET captura_empresarial='{}'::jsonb WHERE ingesta_id="+lit(json.loads(first)['ingesta_id'])+"::uuid")
    fail(execute(),'SUNAT_BATCH_READBACK')
    assert counts()=='2:2:2'
    # No public client execution paths.
    assert psql("SELECT has_function_privilege('service_role','saly.ventas_sunat_batch_execute_v1(text,text,bigint,text,text)','EXECUTE')")=='f'
    print('PASS_SUNAT_NATIVE_PLAN_BATCH_ATOMIC_ROLLBACK_READBACK_REPLAY_LEASE_2_BATCHES_2_COMPANIES')
if __name__=='__main__': main()
,migration.index('CREATE VIEW saly.ventas_sunat_elegibilidad_v1'))]
    psql(ddl)
    assert psql("SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1")=='2'
    assert psql("SELECT count(*) FROM saly.ventas_sunat_comercial_v1")=='1'
    assert psql("SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1 WHERE clasificacion_comercial='EXCLUIDA_MENOS_50_EMPLEADOS'")=='1'
    assert psql("SELECT count(*) FROM saly.ventas_sunat_comercial_v1 WHERE nrotrab=50")=='1'
    assert psql("SELECT count(*) FROM saly.ventas_sunat_comercial_v1 WHERE nrotrab<50")=='0'
    # Test missing NroTrab: fail closed and never leak into commercial projection.
    small='20000002002'
    raw_small=psql("SELECT captura_empresarial::text FROM saly.ventas_hallazgos WHERE ruc_candidato="+lit(small))
    psql("UPDATE saly.ventas_hallazgos SET captura_empresarial=jsonb_set(captura_empresarial,"+
         "'{capture,normalized,workers_integer_literal}','null'::jsonb) WHERE ruc_candidato="+lit(small))
    assert psql("SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1 WHERE clasificacion_comercial='EXCLUIDA_SIN_DATO_EMPLEADOS'")=='1'
    psql("UPDATE saly.ventas_hallazgos SET captura_empresarial="+lit(raw_small)+"::jsonb WHERE ruc_candidato="+lit(small))
    # Test non-HABIDO at the 50-worker inclusive boundary.
    candidate='20000002001'
    raw_candidate=psql("SELECT captura_empresarial::text FROM saly.ventas_hallazgos WHERE ruc_candidato="+lit(candidate))
    psql("UPDATE saly.ventas_hallazgos SET captura_empresarial=jsonb_set(captura_empresarial,"+
         "'{capture,observations,reduced,raw,condicion}',"+lit(json.dumps('NO HABIDO'))+"::jsonb) WHERE ruc_candidato="+lit(candidate))
    assert psql("SELECT count(*) FROM saly.ventas_sunat_comercial_v1")=='0'
    assert psql("SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1 WHERE clasificacion_comercial='EXCLUIDA_CONDICION'")=='1'
    psql("UPDATE saly.ventas_hallazgos SET captura_empresarial="+lit(raw_candidate)+"::jsonb WHERE ruc_candidato="+lit(candidate))
    assert psql("SELECT count(*) FROM saly.ventas_sunat_comercial_v1")=='1'
    assert psql("SELECT count(*) FROM saly.ventas_hallazgos h JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id WHERE i.source_id='PE-SUNAT-RUC'")=='2'
    assert psql("SELECT has_table_privilege('authenticated','saly.ventas_sunat_comercial_v1','SELECT')")=='f'
    # Contradictory BAJA in reduced while monthly remains ACTIVO: fail closed.
    ruc='20000002001'
    original=psql("SELECT captura_empresarial::text FROM saly.ventas_hallazgos WHERE ruc_candidato="+lit(ruc))
    psql("UPDATE saly.ventas_hallazgos SET captura_empresarial=jsonb_set(captura_empresarial,"+
         "'{capture,observations,reduced,raw,estado}',"+lit(json.dumps('BAJA DE OFICIO'))+"::jsonb) WHERE ruc_candidato="+lit(ruc))
    assert psql("SELECT count(*) FROM saly.ventas_sunat_comercial_v1")=='0'
    assert psql("SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1 WHERE clasificacion_comercial='EXCLUIDA_ESTADO'")=='1'
    psql("UPDATE saly.ventas_hallazgos SET captura_empresarial="+lit(original)+"::jsonb WHERE ruc_candidato="+lit(ruc))
    assert psql("SELECT count(*) FROM saly.ventas_sunat_comercial_v1")=='1'
    print('PASS_SALY_SUNAT_COMMERCIAL_PG17_50_INCLUDED_49_EXCLUDED_NULL_NO_HABIDO_BAJA_RESTORED_RAW_PRESERVED')
    # A stale worker cannot continue. A mutated persisted row cannot be reported as replay success.
    fail(execute(f=fence+1),'SUNAT_STALE_LEASE')
    psql("UPDATE saly.ventas_hallazgos SET captura_empresarial='{}'::jsonb WHERE ingesta_id="+lit(json.loads(first)['ingesta_id'])+"::uuid")
    fail(execute(),'SUNAT_BATCH_READBACK')
    assert counts()=='2:2:2'
    # No public client execution paths.
    assert psql("SELECT has_function_privilege('service_role','saly.ventas_sunat_batch_execute_v1(text,text,bigint,text,text)','EXECUTE')")=='f'
    print('PASS_SUNAT_NATIVE_PLAN_BATCH_ATOMIC_ROLLBACK_READBACK_REPLAY_LEASE_2_BATCHES_2_COMPANIES')
if __name__=='__main__': main()
