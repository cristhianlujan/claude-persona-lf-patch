"""Read-only PG-00 catalog admission adapter. No database writes, no synthetic authority."""
import hashlib
import json
from pg02_classifier_v1 import PG02Blocked, classify

EXPECTED_ADRS = tuple(f"ADR-PROG-STD-{i:03}" for i in range(1, 18))

def classify_with_pg00(snapshot, decision_rows, mapping_release, *, expected_release_sha256):
    """Fails closed unless exactly 17 active decisions and separately authorized mapping."""
    if not isinstance(decision_rows, list) or len(decision_rows) != 17:
        raise PG02Blocked("PG00_DECISIONS_INCOMPLETE")
    index = {}
    for row in decision_rows:
        if not isinstance(row, dict) or row.get("adr") in index:
            raise PG02Blocked("PG00_DECISIONS_DUPLICATE")
        index[row.get("adr")] = row
    if tuple(sorted(index)) != EXPECTED_ADRS:
        raise PG02Blocked("PG00_DECISIONS_MISMATCH")
    if any(str(index[k].get("estado","")).lower() != "vigente" for k in EXPECTED_ADRS):
        raise PG02Blocked("PG00_DECISION_NOT_VIGENTE")
    # Existence of ADRs cannot authorize front -> domain classification.
    if not isinstance(mapping_release,dict) or mapping_release.get("state") != "PG00_RELEASED":
        raise PG02Blocked("PG00_MAPPING_NOT_RELEASED")
    if not mapping_release.get("release_ref") or not mapping_release.get("release_sha256"):
        raise PG02Blocked("PG00_MAPPING_RELEASE_PROVENANCE_MISSING")
    payload = mapping_release.get("mapping")
    if not isinstance(payload,dict):
        raise PG02Blocked("PG00_MAPPING_MISSING")
    release_digest = hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",",":"),ensure_ascii=False).encode()).hexdigest()
    if release_digest != mapping_release["release_sha256"] or release_digest != expected_release_sha256:
        raise PG02Blocked("PG00_MAPPING_DIGEST_MISMATCH")
    # The existing classifier only accepts SOURCE_ONLY_CANDIDATE and explicitly marks
    # its output NOT_ADMITTED; no authorized execution can emerge from this bridge.
    candidate = dict(payload)
    candidate["state"] = "SOURCE_ONLY_CANDIDATE"
    result = classify(snapshot, candidate)
    result["pg00_decision_codes"] = list(EXPECTED_ADRS)
    result["pg00_mapping_release_ref"] = mapping_release["release_ref"]
    result["pg00_release_state"] = "SOURCE_BOUND_CANDIDATE_NOT_ADMITTED"
    return result
