"""Read-only explanation of SUNAT commercial rejections over SHA-verified data.

Only aggregate diagnostics are emitted. No business identifiers, SQL, writes,
secrets, uploads or persisted raw source data.
"""
import json
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "adapters"))
from sunat_commercial_gate_v1 import commercially_admissible

REASON_ORDER = (
    "SIN_DATO_EMPLEADOS",
    "MENOS_50_EMPLEADOS",
    "ESTADO_MENSUAL_NO_ACTIVO",
    "ESTADO_REDUCIDO_NO_ACTIVO",
    "CONDICION_MENSUAL_NO_HABIDO",
    "CONDICION_REDUCIDA_NO_HABIDO",
    "CAPTURA_INVALIDA",
)


def rejection_reasons(record, *, min_workers):
    """Return *all* failing predicates in stable priority order.

    The existing production gate remains the authority, and parity is checked
    for each record. The first reason is the exclusive reason for totals.
    """
    if type(min_workers) is not int or min_workers < 1:
        raise ValueError("AUDIT_POLICY_REQUIRED")
    if not isinstance(record, dict) or not isinstance(record.get("capture"), dict):
        return ("CAPTURA_INVALIDA",)
    c = record["capture"]
    if c.get("version") != "sunat.company.v1" or c.get("source") != "SUNAT":
        return ("CAPTURA_INVALIDA",)
    norm = c.get("normalized")
    obs = c.get("observations")
    if not isinstance(norm, dict) or not isinstance(obs, dict):
        return ("CAPTURA_INVALIDA",)
    monthly = obs.get("monthly")
    reduced = obs.get("reduced")
    if not isinstance(monthly, dict) or not isinstance(reduced, dict):
        return ("CAPTURA_INVALIDA",)
    m, d = monthly.get("raw"), reduced.get("raw")
    if not isinstance(m, dict) or not isinstance(d, dict):
        return ("CAPTURA_INVALIDA",)
    n = norm.get("workers_integer_literal")
    bad = []
    if type(n) is not int:
        bad.append("SIN_DATO_EMPLEADOS")
    elif n < min_workers:
        bad.append("MENOS_50_EMPLEADOS")
    for obj, key, expected, code in (
        (m, "Estado", "ACTIVO", "ESTADO_MENSUAL_NO_ACTIVO"),
        (d, "estado", "ACTIVO", "ESTADO_REDUCIDO_NO_ACTIVO"),
        (m, "Condicion", "HABIDO", "CONDICION_MENSUAL_NO_HABIDO"),
        (d, "condicion", "HABIDO", "CONDICION_REDUCIDA_NO_HABIDO"),
    ):
        val = obj.get(key)
        if not isinstance(val, str) or val.strip().upper() != expected:
            bad.append(code)
    return tuple(bad)


def aggregate_reasons(verified, *, historical_batches, min_workers):
    """Inspect verified canonical rows in-memory; log only aggregate counters."""
    if type(historical_batches) is not int or historical_batches < 0:
        raise ValueError("AUDIT_HISTORICAL_PREFIX")
    primary, overlap = Counter(), Counter()
    scanned = skipped = eligible = multiple = batches = 0
    for entry, payload in verified:
        batches += 1
        if entry.get("ordinal") != batches:
            raise ValueError("AUDIT_BATCH_ORDER")
        rows = json.loads(payload)
        if not isinstance(rows, list) or len(rows) != entry.get("rows"):
            raise ValueError("AUDIT_BATCH_ROWS")
        if batches <= historical_batches:
            skipped += len(rows)
            continue
        for item in rows:
            scanned += 1
            reasons = rejection_reasons(item, min_workers=min_workers)
            admitted = commercially_admissible(item, min_workers=min_workers)
            if bool(reasons) == admitted:
                raise ValueError("AUDIT_GATE_PARITY")
            if reasons:
                primary[reasons[0]] += 1
                overlap.update(reasons)
                if len(reasons) > 1:
                    multiple += 1
            else:
                eligible += 1
    return dict(
        historical_batches=historical_batches,
        historical_rows_skipped=skipped,
        remaining_batches=batches - historical_batches,
        scanned_remaining_rows=scanned,
        excluded_by_commercial_policy=sum(primary.values()),
        eligible_before_existing_ruc_dedupe=eligible,
        multiple_causes=multiple,
        primary_reasons={k: primary[k] for k in REASON_ORDER},
        overlapping_reasons={k: overlap[k] for k in REASON_ORDER},
    )


def run():
    from sunat_first_governed_batch_v22 import expected, request_for
    from sunat_verified_delivery_v1 import verified_candidate_payloads
    exact, prior = expected()
    if (exact["rows"], exact["batches"]) != (478657, 479):
        raise ValueError("AUDIT_PINNED_SOURCE_TOTAL")
    # Historical witness only: current SALY public.lf_global_config was read
    # separately as SALY_DISCOVERY/SUNAT_COMMERCIAL_MIN_WORKERS_V1 = 50.
    # This cannot alter the operational commercial minimum.
    min_workers = 50
    with verified_candidate_payloads(request_for(prior), expected_manifest=exact) as (_, verified):
        result = aggregate_reasons(verified, historical_batches=136,
                                   min_workers=min_workers)
    if (result["historical_rows_skipped"], result["remaining_batches"],
        result["scanned_remaining_rows"], result["excluded_by_commercial_policy"],
        result["eligible_before_existing_ruc_dedupe"]) != (
            136000, 343, 342657, 340390, 2267):
        raise ValueError("AUDIT_REFERENCE_RECONCILIATION")
    if sum(result["primary_reasons"].values()) != 340390:
        raise ValueError("AUDIT_PRIMARY_REASON_TOTAL")
    safe = dict(result, source_id="PE-SUNAT-RUC", scope="LIMA_ICA",
                min_workers=min_workers, source_sha256=exact["source_sha256"],
                historical_manifest_sha256=exact["manifest_digest_sha256"],
                db_read=False, db_write=False, data_persisted=False)
    print("SALY_SUNAT_REASON_AUDIT_PASS " +
          json.dumps(safe, sort_keys=True), flush=True)


if __name__ == "__main__":
    try:
        run()
    except Exception as exc:
        # Never print upstream error text (it might include source content).
        print("SALY_SUNAT_REASON_AUDIT_BLOCKED " + type(exc).__name__, flush=True)
        raise SystemExit(1)
