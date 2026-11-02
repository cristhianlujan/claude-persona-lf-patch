"""One-process PG01-C4 to PG02 smoke. Explicitly NOT an admission authority.

A candidate frame is never a substitute for trusted PG01 readback. This
isolated runner checks data-shape interoperability and preserves provenance
flags; it cannot cause a programming run or issue a trusted receipt.
"""
from pg02_c4_evidence_adapter_v1 import validate_c4_evidence
from pg02_classifier_v1 import PG02Blocked, classify


def run_isolated_smoke(snapshot, catalog, pg01_c4_readback):
    """Only process a candidate frame; reject missing/negative readback."""
    if not isinstance(pg01_c4_readback, dict):
        raise PG02Blocked("PG01_C4_READBACK_REQUIRED")
    if pg01_c4_readback.get("verified") is not False:
        # A caller's verified=True is NOT independent authentication.
        raise PG02Blocked("PG01_C4_TRUSTED_AUTHORITY_UNAVAILABLE")
    if pg01_c4_readback.get("reason") != "ISOLATED_TEST_FIXTURE_ONLY":
        raise PG02Blocked("PG01_C4_REAL_READBACK_NOT_ADMITTED")
    candidate = pg01_c4_readback.get("candidate_frame")
    binding = validate_c4_evidence(candidate)
    result = classify(snapshot, catalog, pg01_binding=binding)
    if result.get("status") != "CANDIDATE_NOT_ADMITTED":
        raise PG02Blocked("PG02_UNEXPECTED_AUTHORITY_PROMOTION")
    return {"integration":"PG01_C4_TO_PG02_LOCAL_CANDIDATE_ONLY",
            "authorized":False,"deploy_allowed":False,
            "pg01_authority":binding["authority_state"],"pg02":result}
