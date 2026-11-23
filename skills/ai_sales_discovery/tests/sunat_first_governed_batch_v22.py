#!/usr/bin/env python3
"""One-time SALY pilot: exactly one pinned SUNAT batch through the deployed native operation.

Runs only from trusted main after Merge Train; no direct hallazgos inserts,
no source data in logs/artifacts, no installation/migration, no alternative DB.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / ""))
sys.path.insert(0, str(HERE.parent / "adapters"))

from sunat_batch_plan_v1 import canonical, sha
from sunat_integrated_real_probe import build_request
from sunat_verified_delivery_v1 import verified_candidate_payloads

EVIDENCE = HERE / "evidence" / "sunat_current_20261122.json"
PRIOR = EVIDENCE
EXEC = "EXEC-SALY-SUNAT-PILOT-20261122-001"
OWNER = "SALY-SUNAT-FIRST-BATCH-V22"
SCOPE = "LIMA_ICA"
SOURCE = "PE-SUNAT-RUC"
DBHOST = "aws-1-us-east-1.pooler.supabase.com"
DBUSER = "postgres.mhwmirqcgxxukpctffuv"
DBNAME = "postgres"

def sql_literal(s):
    if not isinstance(s, str) or "\x00" in s:
        raise ValueError("SQL_LITERAL_INVALID")
    return "'" + s.replace("'", "''") + "'"

def psql(query, *, timeout=120):
    env = os.environ.copy()
    if not env.get("PGPASSWORD"):
        raise ValueError("DB_CREDENTIAL_UNAVAILABLE")
    if (env.get("PGHOST"), env.get("PGUSER"), env.get("PGDATABASE")) != (DBHOST, DBUSER, DBNAME):
        raise ValueError("WRONG_DB_TARGET")
    proc = subprocess.run(
        ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=terse",
         "-v", "ECHO=none"],
        input=query, text=True, capture_output=True, env=env, timeout=timeout,
        check=False)
    if proc.returncode:
        # No raw stderr, SQL, names, identifiers or payloads in logs.
        raise ValueError("GOVERNED_DB_CALL_REJECTED")
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        raise ValueError("DB_RESPONSE_SHAPE")
    try:
        return json.loads(lines[0])
    except (ValueError, TypeError):
        raise ValueError("DB_RESPONSE_NOT_JSON") from None

def expected():
    exact = json.loads(EVIDENCE.read_text(encoding="utf-8"))["receipt"]
    prior = json.loads(PRIOR.read_text(encoding="utf-8"))["prior"]
    if (exact["rows"], exact["batches"], exact["manifest_digest_sha256"]) != (
        478657, 479, "23350466e89c654e7736de01f1f0d630fec7874713d7ba101a907da08fb27d00"):
        raise ValueError("PINNED_MANIFEST_CHANGED")
    if any(exact[k] != prior[k] for k in ("rows", "batches", "stats",
                                         "source_sha256", "batch_digest_sha256")):
        raise ValueError("PINNED_RECEIPT_MISMATCH")
    return exact, prior

def request_for(prior):
    request = build_request()
    request["sources"]["reduced"]["zip_sha256"] = prior["source_sha256"][1]
    request["expected"] = prior["qa_baseline"]
    request["evidence_ref"] = prior["qa_evidence_ref"]
    request["batch_plan"] = {
        "expected": prior,
        "limits": {
            "max_rows": request["limits"]["max_batch_rows"],
            "max_bytes": request["limits"]["max_batch_bytes"],
            "max_batches": prior["batches"],
            "max_total_bytes": prior["batches"] * request["limits"]["max_batch_bytes"],
        },
    }
    return request

def preflight(exact):
    sql = """SELECT jsonb_build_object(
    'configured', coalesce((SELECT (config_value::jsonb->>'enabled')::boolean
      FROM public.lf_global_config WHERE scope='SALY_DISCOVERY'
      AND config_key='SUNAT_POLICY_V1' AND value_status='REAL'
      ORDER BY valid_from DESC LIMIT 1),false),
    'catalog', coalesce((SELECT habilitada AND persist_business_data
      AND rights_status='PERSISTENCIA_PERMITIDA' AND rights_evidence_ref IS NOT NULL
      FROM saly.ventas_discovery_catalogo WHERE source_id='PE-SUNAT-RUC'),false),
    'operation', coalesce((SELECT status='SANDBOX_ACTIVE'
      FROM public.lf_operation_registry WHERE operation_code='INGESTA_EMPRESARIAL_SALY'),false),
    'manifest', (SELECT config_value::jsonb->>'manifest_digest_sha256'
      FROM public.lf_global_config WHERE scope='SALY_DISCOVERY'
      AND config_key='SUNAT_POLICY_V1' ORDER BY valid_from DESC LIMIT 1),
    'snapshots', (SELECT config_value::jsonb->'snapshot_sha256'
      FROM public.lf_global_config WHERE scope='SALY_DISCOVERY'
      AND config_key='SUNAT_POLICY_V1' ORDER BY valid_from DESC LIMIT 1),
    'existing', (SELECT count(*) FROM saly.ventas_discovery_ingestas
      WHERE source_id='PE-SUNAT-RUC'))::text;"""
    got = psql(sql, timeout=30)
    if not (got.get("configured") is True and got.get("catalog") is True
            and got.get("operation") is True
            and got.get("manifest") == exact["manifest_digest_sha256"]
            and got.get("snapshots") == exact["source_sha256"]
            and got.get("existing") in (0, 1)):
        raise ValueError("DB_FIRST_BATCH_NOT_ADMITTED")

def build_transaction(entry, payload, entries, exact):
    if (entry != entries[0] or entry.get("ordinal") != 1
            or len(payload) != entry["bytes"] or sha(payload) != entry["capture_sha256"]):
        raise ValueError("FIRST_BATCH_PAYLOAD_DRIFT")
    if len(entries) != exact["batches"] or sha(canonical(entries)) != exact["manifest_digest_sha256"]:
        raise ValueError("FIRST_BATCH_PLAN_DRIFT")
    text = payload.decode("utf-8", errors="strict")
    if "$sunat_first_v22$" in text:
        raise ValueError("FIRST_BATCH_DELIMITER")
    req = dict(business="SALY", source_id=SOURCE, scope_key=SCOPE,
               snapshot_sha256=exact["source_sha256"],
               manifest_digest_sha256=exact["manifest_digest_sha256"])
    request_digest = sha(canonical(req))
    qexec, qowner, qbatch = [sql_literal(s) for s in (EXEC, OWNER, entry["batch_key"])]
    qdigest = sql_literal(request_digest)
    qmanifest = sql_literal(json.dumps({"sunat_plan": req}, separators=(",", ":"), ensure_ascii=False))
    qplan = sql_literal(canonical(entries).decode("utf-8"))
    qpayload = sql_literal(text)
    qsrc = sql_literal(SOURCE)
    qhash = sql_literal(entry["capture_sha256"])
    qrows = str(entry["rows"])
    # Single DB transaction: native execution, leased effect reservation,
    # canonical writer, row/hash readback, all-or-nothing. No side-channel writes.
    return f"""BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='240s';
DO $sunat_first_v22$
DECLARE
 v_execution jsonb; v_lease jsonb; v_run uuid; v_receipt jsonb; v_fence bigint;
BEGIN
 v_execution:=public.fn_lf_operation_reserve_execution_v1(
   {qexec},'INGESTA_EMPRESARIAL_SALY','DISCOVERY_SOURCE',{qsrc},
   {qexec},{qdigest},{qexec},NULL,NULL,{qmanifest}::jsonb);
 IF v_execution->>'result' NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION')
 THEN RAISE EXCEPTION 'SUNAT_FIRST_RESERVATION'; END IF;
 v_lease:=public.fn_lf_operation_acquire_lease_v1({qexec},{qowner},600,{qexec});
 IF v_lease->>'result'<>'LEASE_ACQUIRED' THEN RAISE EXCEPTION 'SUNAT_FIRST_LEASE'; END IF;
 v_fence:=(v_lease->>'lease_fence')::bigint;
 v_run:=saly.ventas_sunat_plan_prepare_v1({qexec},{qowner},v_fence,{qplan}::jsonb);
 v_receipt:=saly.ventas_sunat_batch_execute_v1({qexec},{qowner},v_fence,{qbatch},{qpayload});
 IF v_receipt->>'capture_sha256' IS DISTINCT FROM {qhash}
 OR v_receipt->>'batch_key' IS DISTINCT FROM {qbatch}
 OR (v_receipt->>'rows')::integer<>{qrows}
 OR NOT EXISTS(SELECT 1 FROM saly.ventas_discovery_ingestas
     WHERE id=(v_receipt->>'ingesta_id')::uuid AND source_id={qsrc}
     AND archivo_sha256={qhash} AND filas_reportadas={qrows})
 OR (SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE source_id={qsrc})<>1
 OR (SELECT count(*) FROM saly.ventas_hallazgos
     WHERE ingesta_id=(v_receipt->>'ingesta_id')::uuid)<>{qrows}
 THEN RAISE EXCEPTION 'SUNAT_FIRST_READBACK'; END IF;
END $sunat_first_v22$;
SELECT jsonb_build_object(
 'ingestas',(SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE source_id={qsrc}),
 'empresas',(SELECT count(*) FROM saly.ventas_hallazgos h
     JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
     WHERE i.source_id={qsrc}),
 'batch_key',{qbatch},'capture_sha256',{qhash},
 'run_ref',{qexec})::text;
COMMIT;
"""

def run():
    exact, prior = expected()
    preflight(exact)
    request = request_for(prior)
    # Entire pinned join and capture reconciliation, in one pass that also
    # produces payloads. No extra QA download and no archive retained.
    with verified_candidate_payloads(request, expected_manifest=exact) as (_, stream):
        first_entry, first_payload = next(stream)
        # The verified context guarantees exact full-manifest checks before delivery.
        full_plan = _.get("batch_plan", {}).get("plan", [])
        sql = build_transaction(first_entry, first_payload, full_plan, exact)
        receipt = psql(sql, timeout=360)
        if (receipt.get("ingestas"), receipt.get("empresas"),
            receipt.get("batch_key"), receipt.get("capture_sha256")) != (
                1, first_entry["rows"], first_entry["batch_key"], first_entry["capture_sha256"]):
            raise ValueError("FIRST_BATCH_TERMINAL_READBACK_MISMATCH")
        print("SUNAT_FIRST_BATCH_SUCCESS " + json.dumps({
            "ingestas": 1, "empresas": receipt["empresas"], "ordinal": 1,
            "batch_key": receipt["batch_key"], "capture_sha256": receipt["capture_sha256"],
            "source_id": SOURCE, "db_write_confirmed": True,
        }, sort_keys=True), flush=True)

if __name__ == "__main__":
    try:
        run()
    except Exception as exc:
        reason = str(exc) if type(exc) is ValueError and re.fullmatch("[A-Z_]+", str(exc)) else type(exc).__name__
        print("SUNAT_FIRST_BATCH_BLOCKED " + reason, flush=True)
        raise SystemExit(1)
