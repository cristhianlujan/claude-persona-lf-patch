"""PG17 disposable regression: historical dispatch collision then commercial RUN isolation.

Use official migrated native writer as fixture. Never connects to SALY production,
never reads credentials and uses only synthetic company records. Tests:
  1. Without patch, two distinct RUNs sharing key fail on global dispatch uniqueness.
  2. After EXACT patch DDL, new RUN gets unique dispatch and 1 real stored company.
  3. Replay is idempotent and old historical effect dispatch remains unchanged.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"supabase/tests"))
sys.path.insert(0,str(ROOT/"skills/ai_sales_discovery/adapters"))
from saly_ventas_pte_crossrun_pg17_concurrency import psql,lit
from sunat_company_v1 import company,batches,MONTHLY_FIELDS
from sunat_batch_plan_v1 import sha,canonical
from sunat_governed_batch_pg17 import main as native_historical_fixture

NEW_RUN="EXEC-SUNAT-COMMERCIAL-PG17"
HIST_RUN="EXEC-SUNAT-FIXTURE"
MONTHLY="https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip"
REDUCED="https://www2.sunat.gob.pe/padron_reducido_ruc.zip"
SNAP=["d"*64,"e"*64]
MIGRATION=ROOT/"supabase/migrations/20261123050000_lf_saly_sunat_commercial_dispatch_key_v1.sql"
CORE=ROOT/"supabase/migrations/20261123024000_lf_saly_sunat_commercial_crossrun_replay_v1.sql"


def extract_function(path, begins):
    content=path.read_text(encoding="utf8")
    start=content.index(begins)
    end=content.index("END $function$;",start)+len("END $function$;")
    return content[start:end]


def sql_fail(statement,needle):
    try:
        psql(statement)
    except subprocess.CalledProcessError as exc:
        if needle not in (exc.stderr or ""):
            raise AssertionError("WRONG_EXPECTED_FAILURE") from None
    else:
        raise AssertionError("NEGATIVE_SHOULD_REJECT")


def main():
    if os.getenv("PGHOST")!="127.0.0.1" or os.getenv("PGDATABASE")!="saly_pte_writer_ci":
        raise ValueError("PG17_DISPOSABLE_ONLY")
    if not psql("SHOW server_version_num").startswith("17"):
        raise ValueError("PG17_REQUIRED")

    # Build historical native effects, two successful batches and legacy guard.
    native_historical_fixture()
    assert psql("SELECT count(*) FROM public.lf_operation_effect_guard WHERE execution_id="+lit(HIST_RUN))=="2"
    assert psql("SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE source_id='PE-SUNAT-RUC'")=="2"

    # The previous governed patch is required for commercial run-scoped ingesta replay.
    core=extract_function(CORE,"CREATE OR REPLACE FUNCTION saly.ventas_sunat_ingesta_core_v1")
    psql(core)

    m=dict.fromkeys(MONTHLY_FIELDS,"")
    m.update(RUC="20000002003",Estado="ACTIVO",Condicion="HABIDO",
             UBIGEO="110101",NroTrab="50")
    d=dict(RUC=m["RUC"],nombre="Fixture comercial 3",estado="ACTIVO",
           condicion="HABIDO",ubigeo="110101")
    proof=dict(url=MONTHLY,ordinal=3,zip_sha256=SNAP[0],header_sha256="c"*64)
    reduced=dict(proof,url=REDUCED,zip_sha256=SNAP[1])
    payload,=batches([company(m,d,proof,reduced)],1,10000)
    key=sha(canonical(["PE-SUNAT-RUC",SNAP,"LIMA_ICA",1]))
    digest=sha(payload)
    entry=dict(batch_key=key,ordinal=1,rows=1,bytes=len(payload),
               capture_sha256=digest,
               consulta_evidencia_ref=MONTHLY+"#captura-json-sha256="+digest)
    plan=[entry]
    manifest=sha(canonical(plan))
    assert psql("SELECT count(*) FROM public.lf_operation_effect_guard WHERE dispatch_key="+lit("SUNAT:"+key))=="1"

    policy=dict(enabled=True,commercial_mode=True,commercial_run_ref=NEW_RUN,
        source_id="PE-SUNAT-RUC",monthly_url=MONTHLY,reduced_url=REDUCED,
        max_rows=1,max_bytes=10000,max_total_bytes=20000,expected_rows=1,
        expected_batches=1,manifest_digest_sha256=manifest,
        snapshot_sha256=SNAP,rights_scope="SALY_B2B_INTERNAL_BUSINESS_FACTS_LIMA_ICA_RUC20",
        reduced_rights_status="PERSISTENCIA_PERMITIDA",
        rights_evidence_ref="fixture://sunat-internal-reuse",
        license="fixture",attribution="fixture",monthly_rights="fixture",
        reduced_rights="fixture",old_manifest_replay_allowed=False)
    psql("INSERT INTO public.lf_global_config(scope,config_key,config_value,value_status,valid_from) VALUES "+
         "('SALY_DISCOVERY','SUNAT_POLICY_V1',"+lit(json.dumps(policy))+",'REAL',now()+interval '1 second')")
    # Existing context selector uses valid_from<=now(). Move value into the past.
    psql("UPDATE public.lf_global_config SET valid_from=now()-interval '1 second' WHERE config_key='SUNAT_POLICY_V1' AND config_value="+lit(json.dumps(policy)))

    request=dict(business="SALY",source_id="PE-SUNAT-RUC",scope_key="LIMA_ICA",
                 snapshot_sha256=SNAP,manifest_digest_sha256=manifest)
    req_hash=sha(canonical(request))
    args=",".join(map(lit,[NEW_RUN,"INGESTA_EMPRESARIAL_SALY","DISCOVERY_SOURCE",
                         "PE-SUNAT-RUC",NEW_RUN,req_hash,NEW_RUN]))
    psql("SELECT public.fn_lf_operation_reserve_execution_v1("+args+
         ",NULL,NULL,"+lit(json.dumps({"sunat_plan":request}))+"::jsonb)")
    lease=json.loads(psql("SELECT public.fn_lf_operation_acquire_lease_v1("+
                 lit(NEW_RUN)+",'fixture-worker',3600,"+lit(NEW_RUN)+")"))
    assert lease["result"]=="LEASE_ACQUIRED"
    fence=int(lease["lease_fence"])
    prepare="SELECT saly.ventas_sunat_plan_prepare_v1("+lit(NEW_RUN)+",'fixture-worker',"+str(fence)+","+lit(json.dumps(plan))+"::jsonb)"
    run_id=psql(prepare)
    assert run_id

    execute="SELECT saly.ventas_sunat_batch_execute_v1("+lit(NEW_RUN)+",'fixture-worker',"+str(fence)+","+lit(key)+","+lit(payload.decode("utf8"))+")"
    sql_fail(execute,"lf_operation_effect_guard_dispatch_key_key")
    assert psql("SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE run_ref="+lit(NEW_RUN))=="0"
    assert psql("SELECT count(*) FROM public.lf_operation_effect_guard WHERE execution_id="+lit(NEW_RUN))=="0"
    print("PASS_PG17_COLLISION_REPRODUCED_23505",flush=True)

    patched=extract_function(MIGRATION,"CREATE OR REPLACE FUNCTION saly.ventas_sunat_batch_execute_v1")
    assert "'SUNAT:'||p_exec||':'||p_batch" in patched
    assert "CASE WHEN pol->'commercial_mode'='true'::jsonb" in patched
    psql(patched)
    result=psql(execute)
    receipt=json.loads(result)
    assert receipt["rows"]==1
    assert psql(execute)==result
    assert psql("SELECT count(*) FROM public.lf_operation_effect_guard WHERE execution_id="+lit(NEW_RUN)+" AND dispatch_key="+lit("SUNAT:"+NEW_RUN+":"+key)+" AND state='SUCCEEDED'")=="1"
    assert psql("SELECT count(*) FROM public.lf_operation_effect_guard WHERE execution_id="+lit(HIST_RUN)+" AND dispatch_key="+lit("SUNAT:"+key)+" AND state='SUCCEEDED'")=="1"
    assert psql("SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE run_ref="+lit(NEW_RUN))=="1"
    assert psql("SELECT count(*) FROM saly.ventas_hallazgos h JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id WHERE i.run_ref="+lit(NEW_RUN))=="1"
    assert psql("SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE source_id='PE-SUNAT-RUC'")=="3"

    # Negative: disabled commercial mode causes historical dispatch key collision,
    # maintaining strict unchanged legacy behavior.
    psql("UPDATE public.lf_global_config SET config_value="+lit(json.dumps(dict(policy,commercial_mode=False)))+
         " WHERE config_key='SUNAT_POLICY_V1' AND config_value="+lit(json.dumps(policy)))
    # Retrospective replay is forbidden if caller changes the policy.
    sql_fail(execute,"EFFECT_SCOPE_REUSED_WITH_DIFFERENT_REQUEST")
    print("PASS_PG17_NEW_RUN_SCOPED_DISPATCH_REPLAY_OLD_EFFECT_UNCHANGED",flush=True)


if __name__=="__main__":
    main()
