#!/usr/bin/env python3
"""One-shot metadata-only resnapshot of official SUNAT ZIPs after mutable reduced source drift.
Reuse pinned downloader, dual parser and deterministic planner. No SALY DB access or writes.
Archive bytes remain in an ephemeral temp directory; output contains no company names/RUCs.
"""
import json
import re
import sys
import tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"adapters"))
from sunat_integrated_real_probe import build_request
from sunat_download_v1 import acquire
from sunat_dual_stream_v1 import candidate_receipt
from sunat_batch_plan_v1 import canonical,sha

def measure():
    request=build_request()
    limits=request["limits"]; transport=request["transport"]
    with tempfile.TemporaryDirectory(prefix="saly-sunat-rebaseline-") as directory:
        source={}; meta={}
        for kind in ("monthly","reduced"):
            pinned=request["sources"][kind]
            path=Path(directory)/(kind+".zip")
            observed=acquire(pinned["url"],path,allowed_urls={pinned["url"]},
                max_bytes=limits["zip_bytes"],attempts=transport["attempts"],
                socket_timeout=transport["socket_timeout"],
                deadline_seconds=transport["deadline_seconds"],
                backoff_seconds=transport["backoff_seconds"],expected_sha=None)
            meta[kind]=dict(sha256=observed["sha256"],bytes=observed["bytes"],
                last_modified=observed["http_last_modified"],
                changed_from_reviewed=observed["sha256"]!=pinned["zip_sha256"])
            source[kind]=dict(pinned,path=str(path),zip_sha256=observed["sha256"])
        print("SUNAT_CURRENT_ARCHIVE_HASHES "+json.dumps(meta,sort_keys=True),flush=True)
        first=candidate_receipt(source["monthly"],source["reduced"],departments=["11","15"],
            limits=limits,directory=directory)
        if first["rows"]<=0 or first["batches"]<=0:
            raise ValueError("CURRENT_EMPTY_SCOPE")
        expected=dict(first,qa_baseline_match=True)
        plan_limits=dict(max_rows=limits["max_batch_rows"],max_bytes=limits["max_batch_bytes"],
            max_batches=first["batches"],
            max_total_bytes=first["batches"]*limits["max_batch_bytes"])
        second=candidate_receipt(source["monthly"],source["reduced"],departments=["11","15"],
            limits=limits,directory=directory,
            batch_plan=dict(expected=expected,limits=plan_limits))
        plan=second["batch_plan"]; entries=plan["plan"]
        if (second["rows"]!=first["rows"] or second["batches"]!=first["batches"]
                or second["batch_digest_sha256"]!=first["batch_digest_sha256"]
                or second["stats"]!=first["stats"]
                or len({e["batch_key"] for e in entries})!=len(entries)):
            raise ValueError("CURRENT_RECONCILIATION_MISMATCH")
        report=dict(state="CURRENT_OFFICIAL_SNAPSHOT_MEASURED_ONLY",scope=["11","15"],
            source_id="PE-SUNAT-RUC",source_sha256=plan["snapshot_sha256"],
            rows=plan["rows"],batches=plan["batches"],
            total_bytes=plan["total_bytes"],stats=second["stats"],
            batch_digest_sha256=plan["batch_digest_sha256"],
            manifest_digest_sha256=sha(canonical(entries)),
            unique_batch_keys=len(entries),sources=meta,
            rights_review_required=False,runtime_authorized=False,db_write_confirmed=False)
        print("SUNAT_CURRENT_SNAPSHOT_QA "+json.dumps(report,sort_keys=True),flush=True)

if __name__=="__main__":
    try:
        measure()
    except Exception as exc:
        reason=str(exc) if type(exc) is ValueError and re.fullmatch("[A-Z_]+",str(exc)) else type(exc).__name__
        print("SUNAT_CURRENT_SNAPSHOT_BLOCKED "+reason,flush=True)
        raise SystemExit(1)
