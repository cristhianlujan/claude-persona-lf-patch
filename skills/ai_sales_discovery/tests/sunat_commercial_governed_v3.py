#!/usr/bin/env python3
"""SALY SUNAT commercial-only real importer via existing native governed writer.

TRUSTED MAIN ONLY. Executed only by approved GitHub Actions environment after
ACTUALIZACION_DB_LF Merge Train installs the exact manifest, approved policy
and reserves an INGESTA_EMPRESARIAL_SALY operation.

No direct INSERT, no raw business data in logs or repository, no reusing
the immutable historical 479-batch plan, and no parallel writers.
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/"adapters"))
from sunat_batch_plan_v1 import sha,canonical
from sunat_first_governed_batch_v22 import expected,request_for,psql,sql_literal
from sunat_verified_delivery_v1 import verified_candidate_payloads
from sunat_commercial_delivery_v1 import commercial_payloads_from_verified

SOURCE="PE-SUNAT-RUC"
RUN="EXEC-SALY-SUNAT-COMMERCIAL-20261123-001"
OLD="EXEC-SALY-SUNAT-PILOT-20261122-001"
OWNER="SALY-SUNAT-COMMERCIAL-V3"
MONTHLY_URL="https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip"
SCOPE="LIMA_ICA"
HEX=re.compile(r"[0-9a-f]{64}\Z")


def validate_policy_and_roster(raw, exact):
    """Only trusted DB source may authorize a run. No fallback/default values."""
    if type(raw) is not dict or type(raw.get("policy")) is not dict:
        raise ValueError("COMMERCIAL_DB_POLICY_MISSING")
    pol=raw["policy"]
    if not (raw.get("old_run")=="HOLD" and raw.get("old_batches")==136
            and raw.get("old_hist_rows")==136000
            and raw.get("operation") in (None,"IN_PROGRESS")
            and (raw.get("operation")=="IN_PROGRESS" or raw.get("new_run") is None)
            and raw.get("new_run") in (None,"EN_EJECUCION","PARTIAL")
            and raw.get("trigger_active") is True
            and pol.get("enabled") is True and pol.get("commercial_mode") is True
            and pol.get("commercial_run_ref")==RUN
            and pol.get("old_manifest_replay_allowed") is False
            and pol.get("source_id")==SOURCE
            and pol.get("rights_scope")=="SALY_B2B_INTERNAL_BUSINESS_FACTS_LIMA_ICA_RUC20"
            and pol.get("reduced_rights_status")=="PERSISTENCIA_PERMITIDA"
            and pol.get("snapshot_sha256")==exact["source_sha256"]
            and pol.get("original_manifest_digest_sha256")==exact["manifest_digest_sha256"]
            and pol.get("historical_found_batches")==136
            and type(raw.get("min_workers")) is int and raw["min_workers"]==50
            and type(pol.get("expected_rows")) is int and pol["expected_rows"]>0
            and type(pol.get("expected_batches")) is int and pol["expected_batches"] in (1,2,3)
            and type(pol.get("max_rows")) is int and pol["max_rows"]==1000
            and type(pol.get("max_bytes")) is int and pol["max_bytes"]==4194304
            and type(pol.get("max_total_bytes")) is int and pol["max_total_bytes"]>=pol["max_bytes"]
            and type(pol.get("manifest_digest_sha256")) is str
            and HEX.fullmatch(pol["manifest_digest_sha256"])
            and type(pol.get("batch_digest_sha256")) is str
            and HEX.fullmatch(pol["batch_digest_sha256"])
            and type(pol.get("existing_rucs_sha256")) is str
            and HEX.fullmatch(pol["existing_rucs_sha256"])):
        raise ValueError("COMMERCIAL_DB_POLICY_NOT_ADMITTED")
    roster=raw.get("existing_rucs")
    if not (type(roster) is list and all(type(x) is str and re.fullmatch(r"20[0-9]{9}",x) for x in roster)
            and len(set(roster))==len(roster) and roster==sorted(roster)
            and sha(canonical(roster))==pol["existing_rucs_sha256"]):
        raise ValueError("COMMERCIAL_DB_ROSTER_CHANGED")
    return pol,set(roster)


def db_preflight():
    qrun=sql_literal(RUN)
    qold=sql_literal(OLD)
    return psql(f"""WITH prior AS (
    SELECT DISTINCT h.ruc_candidato AS ruc
    FROM saly.ventas_hallazgos h
    JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
    WHERE i.run_ref IS DISTINCT FROM {qrun}
      AND h.ruc_candidato ~ '^20[0-9]{{9}}$'
)
SELECT jsonb_build_object(
 'policy',(SELECT config_value::jsonb FROM public.lf_global_config
           WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
           AND value_type='JSON' AND value_status='REAL'
           ORDER BY valid_from DESC LIMIT 1),
 'min_workers',(SELECT config_value::integer FROM public.lf_global_config
            WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_COMMERCIAL_MIN_WORKERS_V1'
              AND value_type='INTEGER' AND value_status='REAL'
            ORDER BY valid_from DESC LIMIT 1),
 'operation',(SELECT status FROM public.lf_operation_execution WHERE execution_id={qrun}
           AND operation_code='INGESTA_EMPRESARIAL_SALY'
           AND target_type='DISCOVERY_SOURCE' AND target_code='PE-SUNAT-RUC'),
 'new_run',(SELECT estado FROM saly.ventas_discovery_runs WHERE run_ref={qrun}),
 'old_run',(SELECT estado FROM saly.ventas_discovery_runs WHERE run_ref={qold}),
 'old_batches',(SELECT count(*) FROM saly.ventas_discovery_ingestas
          WHERE run_ref={qold} AND source_id='PE-SUNAT-RUC'),
 'old_hist_rows',(SELECT coalesce(sum(filas_reportadas),0) FROM saly.ventas_discovery_ingestas
          WHERE run_ref={qold} AND source_id='PE-SUNAT-RUC'),
 'trigger_active',EXISTS(SELECT 1 FROM pg_trigger
    WHERE tgrelid='saly.ventas_hallazgos'::regclass
      AND tgname='trg_saly_sunat_commercial_admission_v1' AND tgenabled='O'),
 'existing_rucs',(SELECT coalesce(jsonb_agg(ruc ORDER BY ruc),'[]'::jsonb) FROM prior)
)::text;""",timeout=80)


def verify_manifest(receipt, pol):
    fields=("rows","batches","total_bytes","manifest_digest_sha256",
            "batch_digest_sha256","prior_existing_rucs_sha256")
    required=(
        receipt["rows"]==pol["expected_rows"]
        and receipt["batches"]==pol["expected_batches"]
        and receipt["total_bytes"]<=pol["max_total_bytes"]
        and receipt["manifest_digest_sha256"]==pol["manifest_digest_sha256"]
        and receipt["batch_digest_sha256"]==pol["batch_digest_sha256"]
        and receipt["prior_existing_rucs_sha256"]==pol["existing_rucs_sha256"]
        and receipt["historical_found_batches"]==136
        and receipt["scanned_remaining_rows"]==
             receipt["excluded_by_commercial_policy"]+
             receipt["skipped_already_registered"]+receipt["rows"]
        and receipt["runtime_authorized"] is False
        and receipt["db_write_confirmed"] is False
    )
    if not required:
        raise ValueError("COMMERCIAL_VERIFIED_MANIFEST_MISMATCH")
    return {k:receipt.get(k) for k in fields}


def plan_sql(entries,source_sha256):
    # Client cannot supply an unverified manifest: only the sealed source stream.
    plan_json=canonical(entries).decode("utf8")
    if "$saly_commercial_plan$" in plan_json:
        raise ValueError("COMMERCIAL_PLAN_DELIMITER")
    if not (type(source_sha256) is list and len(source_sha256)==2 and
            all(type(x) is str and HEX.fullmatch(x) for x in source_sha256)):
        raise ValueError("COMMERCIAL_SOURCE_PINS_INVALID")
    source_req=dict(business="SALY",source_id=SOURCE,scope_key=SCOPE,
                    snapshot_sha256=source_sha256,
                    manifest_digest_sha256=sha(canonical(entries)))
    request_digest=sha(canonical(source_req))
    qrun,qowner,qplan=map(sql_literal,(RUN,OWNER,plan_json))
    qdigest=sql_literal(request_digest)
    qmanifest=sql_literal(json.dumps({"sunat_plan":source_req},
                                    ensure_ascii=False,separators=(",",":")))
    return f"""BEGIN;
SET LOCAL lock_timeout='20s';
SET LOCAL statement_timeout='150s';
DO $saly_commercial_plan$
DECLARE v_lease jsonb; v_execution jsonb; v_run uuid;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY:PE-SUNAT-RUC:SEQUENTIAL',0));
 v_execution:=public.fn_lf_operation_reserve_execution_v1(
    {qrun},'INGESTA_EMPRESARIAL_SALY','DISCOVERY_SOURCE','PE-SUNAT-RUC',
    {qrun},{qdigest},{qrun},NULL,NULL,{qmanifest}::jsonb);
 IF v_execution->>'result' NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION')
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_RUN_RESERVATION'; END IF;
 v_lease:=public.fn_lf_operation_acquire_lease_v1({qrun},{qowner},3600,{qrun});
 IF v_lease->>'result' IS DISTINCT FROM 'LEASE_ACQUIRED'
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_LEASE_NOT_ACQUIRED'; END IF;
 v_run:=saly.ventas_sunat_plan_prepare_v1(
    {qrun},{qowner},(v_lease->>'lease_fence')::bigint,{qplan}::jsonb);
 IF v_run IS NULL THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_NO_RUN'; END IF;
END $saly_commercial_plan$;
SELECT jsonb_build_object('run_ref',{qrun},'planned',
 (SELECT count(*) FROM saly.ventas_discovery_plan_batches b
 JOIN saly.ventas_discovery_runs r ON r.id=b.run_id
 WHERE r.run_ref={qrun} AND b.source_id='PE-SUNAT-RUC'))::text;
COMMIT;"""


def batch_sql(entry,payload,ordinal,cumulative):
    if (type(payload) is not bytes or sha(payload)!=entry["capture_sha256"]
            or len(payload)!=entry["bytes"] or entry["ordinal"]!=ordinal
            or len(payload)>4194304 or entry["rows"]>1000):
        raise ValueError("COMMERCIAL_BATCH_SOURCE_DRIFT")
    raw=payload.decode("utf8",errors="strict")
    if "$saly_commercial_batch$" in raw:
        raise ValueError("COMMERCIAL_BATCH_DELIMITER")
    qrun,qowner,qkey,qhash,qraw=map(sql_literal,
                                    (RUN,OWNER,entry["batch_key"],entry["capture_sha256"],raw))
    return f"""BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='240s';
DO $saly_commercial_batch$
DECLARE v_lease jsonb; v_receipt jsonb; v_found integer; v_rows integer;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY:PE-SUNAT-RUC:SEQUENTIAL',0));
 v_lease:=public.fn_lf_operation_acquire_lease_v1({qrun},{qowner},3600,{qrun});
 IF v_lease->>'result' IS DISTINCT FROM 'LEASE_ACQUIRED'
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_LEASE_NOT_ACQUIRED'; END IF;
 v_receipt:=saly.ventas_sunat_batch_execute_v1(
    {qrun},{qowner},(v_lease->>'lease_fence')::bigint,{qkey},{qraw});
 IF v_receipt->>'batch_key' IS DISTINCT FROM {qkey}
 OR v_receipt->>'capture_sha256' IS DISTINCT FROM {qhash}
 OR (v_receipt->>'rows')::int<>{entry["rows"]}
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_BATCH_RECEIPT'; END IF;
 SELECT count(*) INTO v_found FROM saly.ventas_discovery_plan_batches b
 JOIN saly.ventas_discovery_runs r ON r.id=b.run_id
 WHERE r.run_ref={qrun} AND b.source_id='PE-SUNAT-RUC' AND b.estado='FOUND';
 SELECT count(*) INTO v_rows FROM saly.ventas_hallazgos h
 JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
 WHERE i.run_ref={qrun} AND i.source_id='PE-SUNAT-RUC';
 IF v_found<>{ordinal} OR v_rows<>{cumulative}
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_BATCH_READBACK'; END IF;
END $saly_commercial_batch$;
SELECT jsonb_build_object('ordinal',{ordinal},'rows',
 (SELECT count(*) FROM saly.ventas_hallazgos h JOIN saly.ventas_discovery_ingestas i
  ON i.id=h.ingesta_id WHERE i.run_ref={qrun} AND i.source_id='PE-SUNAT-RUC'),
 'batch_count',(SELECT count(*) FROM saly.ventas_discovery_ingestas
  WHERE run_ref={qrun} AND source_id='PE-SUNAT-RUC'))::text;
COMMIT;"""


def final_readback(expected_rows, expected_batches):
    qrun=sql_literal(RUN)
    got=psql(f"""SELECT jsonb_build_object(
 'new_rows',(SELECT count(*) FROM saly.ventas_hallazgos h
             JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
             WHERE i.run_ref={qrun} AND i.source_id='PE-SUNAT-RUC'),
 'new_batches',(SELECT count(*) FROM saly.ventas_discovery_ingestas
             WHERE run_ref={qrun} AND source_id='PE-SUNAT-RUC'),
 'ineligible',(SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1
             WHERE run_ref={qrun} AND clasificacion_comercial<>'ELEGIBLE'),
 'old_run',(SELECT estado FROM saly.ventas_discovery_runs
             WHERE run_ref={sql_literal(OLD)}),
 'total_sunat',(SELECT count(*) FROM saly.ventas_hallazgos h
             JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
             WHERE i.source_id='PE-SUNAT-RUC')
)::text;""",timeout=90)
    if not (got.get("new_rows")==expected_rows
            and got.get("new_batches")==expected_batches
            and got.get("ineligible")==0 and got.get("old_run")=="HOLD"):
        raise ValueError("SUNAT_COMMERCIAL_TERMINAL_READBACK_FAILED")
    return got


def run():
    exact,prior=expected()
    db=db_preflight()
    pol,roster=validate_policy_and_roster(db,exact)
    print("SUNAT_COMMERCIAL_VERIFIED_SOURCE_START "+json.dumps(
        dict(source=SOURCE,run_ref=RUN,policy_threshold=db["min_workers"],
             old_batches=136,source_batches=exact["batches"],
             roster_count=len(roster),planned_new_rows=pol["expected_rows"]),
        sort_keys=True),flush=True)
    with verified_candidate_payloads(request_for(prior),expected_manifest=exact) as (_,source):
        with commercial_payloads_from_verified(
            source,original_manifest_sha256=exact["manifest_digest_sha256"],
            snapshot_sha256=exact["source_sha256"],
            original_batches=exact["batches"],
            historical_found_batches=136,
            existing_rucs=roster,min_workers=db["min_workers"],
            max_rows=pol["max_rows"],max_bytes=pol["max_bytes"],
            max_batches=pol["expected_batches"],
            max_total_bytes=pol["max_total_bytes"],
            monthly_url=MONTHLY_URL
        ) as (candidate,verified):
            metadata=verify_manifest(candidate,pol)
            entries=candidate["plan"]
            prep=psql(plan_sql(entries,pol["snapshot_sha256"]),timeout=180)
            if prep.get("planned")!=len(entries) or prep.get("run_ref")!=RUN:
                raise ValueError("SUNAT_COMMERCIAL_PLAN_READBACK_FAILED")
            count=0
            for ordinal,(entry,payload) in enumerate(verified,1):
                count+=entry["rows"]
                receipt=psql(batch_sql(entry,payload,ordinal,count),timeout=310)
                if (receipt.get("ordinal"),receipt.get("rows"),
                    receipt.get("batch_count"))!=(ordinal,count,ordinal):
                    raise ValueError("SUNAT_COMMERCIAL_BATCH_RESPONSE_DRIFT")
                print("SUNAT_COMMERCIAL_BATCH_COMMITTED "+json.dumps(
                    dict(ordinal=ordinal,total_batches=len(entries),rows=count),
                    sort_keys=True),flush=True)
            if count!=pol["expected_rows"]:
                raise ValueError("SUNAT_COMMERCIAL_TERMINAL_COUNT_MISMATCH")
    after=final_readback(pol["expected_rows"],pol["expected_batches"])
    print("PASS_SUNAT_COMMERCIAL_GOVERNED_INSERT "+json.dumps(
        dict(run_ref=RUN,added=after["new_rows"],batches=after["new_batches"],
             total_sunat=after["total_sunat"],ineligible_remaining=0,
             db_write_confirmed=True),sort_keys=True),flush=True)


if __name__=="__main__":
    try:
        run()
    except Exception as exc:
        reason=str(exc) if type(exc) is ValueError and re.fullmatch(r"[A-Z_]+",str(exc)) else type(exc).__name__
        print("SUNAT_COMMERCIAL_INSERT_BLOCKED "+reason,flush=True)
        raise SystemExit(1)
