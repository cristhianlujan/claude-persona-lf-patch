"""PE10 E2 decision rule S2 validator.

Deterministic evidence classifier only. It does not discover dependencies, attest
historical runtime, deploy Edge functions, or prove a defect by itself.
"""
from __future__ import annotations

from typing import Any

DECISIONS = frozenset({
    "MEASURE_FIRST",
    "CLEAR_NO_ACTION",
    "VERIFY_MINOR",
    "VERIFY_CRITICAL",
    "REPAIR_REQUIRED",
})
EXPOSURE_CLASSES = frozenset({"cron", "trigger", "edge", "security_definer"})


def _require_nonnegative_int(value: Any, name: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ValueError(f"{name} must be a nonnegative integer")
    return value


def _require_query_ids(item: dict[str, Any], prefix: str) -> list[str]:
    query_ids = item.get("query_ids")
    if not isinstance(query_ids, list) or not query_ids or any(
        not isinstance(q, str) or not q.strip() for q in query_ids
    ):
        raise ValueError(f"{prefix} requires nonempty query_ids")
    return query_ids


def validate_hash_reconciliation(hash_evidence: dict[str, Any]) -> dict[str, int]:
    if not isinstance(hash_evidence, dict):
        raise ValueError("hash_evidence must be an object")
    total = _require_nonnegative_int(hash_evidence.get("total"), "hash total")
    equal = _require_nonnegative_int(hash_evidence.get("equal"), "hash equal")
    modified = _require_nonnegative_int(hash_evidence.get("modified"), "hash modified")
    null = _require_nonnegative_int(hash_evidence.get("null"), "hash null")
    missing = _require_nonnegative_int(hash_evidence.get("missing"), "hash missing")
    valid_len32 = _require_nonnegative_int(hash_evidence.get("valid_len32"), "hash valid_len32")
    if equal + modified + null + missing != total:
        raise ValueError("hash reconciliation does not sum to total")
    if valid_len32 + null != total:
        raise ValueError("32-char hash validation does not reconcile with nulls")
    return {"total":total,"equal":equal,"modified":modified,"null":null,"missing":missing,"valid_len32":valid_len32}


def _critical_exposure(item: dict[str, Any]) -> bool:
    if not isinstance(item, dict):
        raise ValueError("exposure evidence entries must be objects")
    cls = item.get("class")
    if cls not in EXPOSURE_CLASSES:
        raise ValueError("unknown exposure class")
    _require_query_ids(item, f"{cls} exposure")
    if item.get("route_reaches_subject") is not True:
        return False
    if cls in {"cron", "trigger"}:
        return item.get("active") is True
    if cls == "edge":
        return item.get("source_inspected") is True and item.get("deployment_attested") is True
    if cls == "security_definer":
        return item.get("security_definer") is True and item.get("effective_callable") is True
    return False


def classify_decision(evidence: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(evidence, dict):
        raise ValueError("evidence must be an object")

    if evidence.get("defect_proven") is True:
        refs = evidence.get("defect_evidence_refs")
        if not isinstance(refs, list) or not refs or any(
            not isinstance(ref, str) or len(ref.strip()) < 4 for ref in refs
        ):
            raise ValueError("REPAIR_REQUIRED needs concrete defect evidence refs")
        return {"decision":"REPAIR_REQUIRED","reason":"concrete defect or regression demonstrated","critical_exposures":0}

    if evidence.get("hashes_measured") is not True or evidence.get("census_measured") is not True:
        return {"decision":"MEASURE_FIRST","reason":"both hash comparison and reverse consumer census are mandatory","critical_exposures":0}

    hashes = validate_hash_reconciliation(evidence.get("hash_evidence", {}))
    material_drift_count = _require_nonnegative_int(evidence.get("material_drift_count"), "material_drift_count")
    outside_consumer_count = _require_nonnegative_int(evidence.get("outside_consumer_count"), "outside_consumer_count")

    exposures = evidence.get("exposures", [])
    if not isinstance(exposures, list):
        raise ValueError("exposures must be a list")
    critical = [item for item in exposures if _critical_exposure(item)]
    if critical:
        return {"decision":"VERIFY_CRITICAL","reason":"at least one measured reachable exposure path reaches the subject","critical_exposures":len(critical)}

    all_hashes_equal = (
        hashes["equal"] == hashes["total"]
        and hashes["modified"] == 0
        and hashes["null"] == 0
        and hashes["missing"] == 0
    )
    if all_hashes_equal and material_drift_count == 0 and outside_consumer_count == 0:
        return {"decision":"CLEAR_NO_ACTION","reason":"measured inventory is current and no extra material consumer was found","critical_exposures":0}

    return {"decision":"VERIFY_MINOR","reason":"drift or extra consumers exist without a measured critical reachable path","critical_exposures":0}
