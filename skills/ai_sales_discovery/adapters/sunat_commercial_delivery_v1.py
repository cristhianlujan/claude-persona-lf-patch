"""SUNAT commercial-only candidate manifest from fully verified historical source bytes.

Boundary:
- upstream MUST be verified_candidate_payloads (both full ZIP/source hashes checked);
- this module performs no database writes, downloads, grants or runtime admission;
- the historical 479-batch manifest is immutable and never reused for writing;
- all new row payloads are staged privately, checked and released only after EOF;
- downstream *governed* operation must separately authenticate new policy/manifest.
"""
import hashlib
import json
import re
import tempfile
from contextlib import contextmanager

from sunat_batch_plan_v1 import canonical, require, sha
from sunat_company_v1 import batches
from sunat_commercial_gate_v1 import commercially_admissible
from sunat_verified_delivery_v1 import _Staging

SOURCE = "PE-SUNAT-RUC"
SCOPE = "LIMA_ICA"
HEX = re.compile(r"[0-9a-f]{64}")
RUC = re.compile(r"20[0-9]{9}")
ENTRY_KEYS = frozenset(
    ("batch_key", "ordinal", "rows", "bytes", "capture_sha256",
     "consulta_evidencia_ref")
)


@contextmanager
def commercial_payloads_from_verified(
    verified_raw_pairs, *, original_manifest_sha256, snapshot_sha256,
    original_batches, historical_found_batches, existing_rucs, min_workers,
    max_rows, max_bytes, max_batches, max_total_bytes, monthly_url,
    directory=None
):
    """Rebatch only new, eligible RUC after full historical-manifest verification.

    Caller must obtain historical_found_batches and existing_rucs from one
    trusted SALY readback, and the minimum from lf_global_config. No default
    is inferred. All 479 historical batches are verified by the upstream
    delivery before this function is entered.

    Returns (manifest metadata without RUC/name, iterator of exact UTF-8
    canonical batches). The temporary payloads never leave this context.
    """
    require(isinstance(original_manifest_sha256,str) and
            HEX.fullmatch(original_manifest_sha256) is not None,
            "COMMERCIAL_PRIOR_DIGEST")
    require(type(snapshot_sha256) is list and len(snapshot_sha256)==2 and
            all(isinstance(s,str) and HEX.fullmatch(s) for s in snapshot_sha256)
            and snapshot_sha256[0] != snapshot_sha256[1], "COMMERCIAL_SNAPSHOTS")
    require(type(original_batches) is int and original_batches>0 and
            type(historical_found_batches) is int and
            0<=historical_found_batches<original_batches,
            "COMMERCIAL_COMPLETED_PREFIX")
    require(type(existing_rucs) in (set,frozenset) and
            all(type(r) is str and RUC.fullmatch(r) for r in existing_rucs),
            "COMMERCIAL_EXISTING_ROSTER")
    require(type(min_workers) is int and min_workers>0,"COMMERCIAL_MIN_WORKERS")
    require(all(type(v) is int and v>0 for v in
                (max_rows,max_bytes,max_batches,max_total_bytes)),
            "COMMERCIAL_LIMITS")
    require(isinstance(monthly_url,str) and re.fullmatch(
        r"https://www\\.datosabiertos\\.gob\\.pe/sites/default/files/PadronRUC_[0-9]{6}\\.zip",
        monthly_url), "COMMERCIAL_SOURCE_URL")

    with tempfile.TemporaryDirectory(prefix="sunat-commercial-",dir=directory) as work:
        staged = _Staging(work,dict(max_bytes=max_bytes,max_batches=max_batches,
                                    max_total_bytes=max_total_bytes))
        found = 0
        scanned = 0
        skipped_old = 0
        skipped_present = 0
        excluded = 0
        source_previous = ""
        selected_rucs = set()
        original_rows = 0

        def eligible_rows():
            nonlocal found,scanned,skipped_old,skipped_present,excluded
            nonlocal source_previous,original_rows
            for entry,payload in verified_raw_pairs:
                found+=1
                require(type(entry) is dict and
                        isinstance(entry.get("ordinal"),int) and
                        entry["ordinal"]==found and found<=original_batches and
                        entry.get("capture_sha256")==sha(payload) and
                        len(payload)==entry.get("bytes"),"COMMERCIAL_PRIOR_BATCH")
                require(type(payload) is bytes and canonical(json.loads(payload))==payload,
                        "COMMERCIAL_PRIOR_CANONICAL")
                rows=json.loads(payload)
                require(type(rows) is list and len(rows)==entry.get("rows"),
                        "COMMERCIAL_PRIOR_ROWS")
                for item in rows:
                    original_rows+=1
                    require(type(item) is dict and set(item)=={"capture","capture_sha256"}
                            and type(item["capture"]) is dict and
                            sha(canonical(item["capture"]))==item["capture_sha256"],
                            "COMMERCIAL_PRIOR_ROW_HASH")
                    ruc=item["capture"].get("normalized",{}).get("ruc")
                    require(type(ruc) is str and RUC.fullmatch(ruc) and
                            ruc>source_previous,"COMMERCIAL_RUC_SORTED_UNIQUE")
                    source_previous=ruc
                    if found<=historical_found_batches:
                        skipped_old+=1
                        continue
                    scanned+=1
                    if not commercially_admissible(item,min_workers=min_workers):
                        excluded+=1
                        continue
                    if ruc in existing_rucs:
                        skipped_present+=1
                        continue
                    require(ruc not in selected_rucs,"COMMERCIAL_REPEATED_SELECTED_RUC")
                    selected_rucs.add(ruc)
                    yield item

        chain=hashlib.sha256()
        plan=[]
        total_bytes=0
        expected_rows=0
        try:
            for payload in batches(eligible_rows(),max_rows,max_bytes):
                idx=len(plan)+1
                require(idx<=max_batches,"COMMERCIAL_BATCH_LIMIT")
                total_bytes+=len(payload)
                require(total_bytes<=max_total_bytes,"COMMERCIAL_TOTAL_BYTES")
                rows=json.loads(payload)
                n=len(rows)
                expected_rows+=n
                payload_hash=sha(payload)
                chain.update(bytes.fromhex(payload_hash))
                batch_key=sha(canonical([SOURCE,snapshot_sha256,SCOPE,idx]))
                plan.append(dict(batch_key=batch_key,ordinal=idx,rows=n,
                                 bytes=len(payload),capture_sha256=payload_hash,
                                 consulta_evidencia_ref=monthly_url+
                                     "#captura-json-sha256="+payload_hash))
                staged.append(payload)
            require(found==original_batches,"COMMERCIAL_PRIOR_INCOMPLETE")
            require(original_rows==scanned+skipped_old,"COMMERCIAL_SOURCE_ACCOUNTING")
            require(scanned==excluded+skipped_present+expected_rows,
                    "COMMERCIAL_SELECTION_ACCOUNTING")
            require(expected_rows>0 and len(plan)>0,"COMMERCIAL_NO_NEW_ELIGIBLE")
            require(len(selected_rucs)==expected_rows,
                    "COMMERCIAL_DISTINCT_RUCS")
            require(len({item["batch_key"] for item in plan})==len(plan),
                    "COMMERCIAL_BATCH_KEY_COLLISION")
            receipt=dict(
                state="CANDIDATE_PLAN_ONLY",source_id=SOURCE,scope_key=SCOPE,
                policy_ref="SALY_DISCOVERY/SUNAT_COMMERCIAL_MIN_WORKERS_V1",
                min_workers=min_workers,source_sha256=list(snapshot_sha256),
                original_manifest_digest_sha256=original_manifest_sha256,
                historical_found_batches=historical_found_batches,
                original_batches=original_batches,
                skipped_historical_rows=skipped_old,
                scanned_remaining_rows=scanned,
                excluded_by_commercial_policy=excluded,
                skipped_already_registered=skipped_present,
                rows=expected_rows,batches=len(plan),total_bytes=total_bytes,
                batch_digest_sha256=chain.hexdigest(),
                manifest_digest_sha256=sha(canonical(plan)),
                prior_existing_ruc_count=len(existing_rucs),
                prior_existing_rucs_sha256=sha(canonical(sorted(existing_rucs))),
                plan=plan,runtime_authorized=False,db_write_confirmed=False
            )
            # _Staging performs an independent digest + shape + file-set check
            # before any candidate payload can be handed to a caller.
            seal_receipt=dict(batch_plan=dict(
                plan=plan,rows=expected_rows,batches=len(plan),
                total_bytes=total_bytes,batch_digest_sha256=chain.hexdigest(),
                snapshot_sha256=snapshot_sha256),
                stats={},qa_baseline_match=True,
                runtime_authorized=False,db_write_confirmed=False,
                rights_verified=False)
            seal_expected=dict(rows=expected_rows,batches=len(plan),
                               total_bytes=total_bytes,
                               batch_digest_sha256=chain.hexdigest(),
                               manifest_digest_sha256=receipt["manifest_digest_sha256"],
                               source_sha256=snapshot_sha256,stats={})
            staged.seal(seal_receipt,seal_expected)
            yield receipt,staged.iter_verified()
        finally:
            pass
