"""Operation route: deterministic R17 + exact-source preflight for one Supabase Edge target.

No network, mutation, SQL, promotion or runtime deploy in this module.
Caller must fetch canonical evidence from the existing LF Operation authority.
"""
from __future__ import annotations
import json
import re
import sys

SHA = re.compile(r"^[0-9a-f]{40}$")
SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
OPERATION = "DEPLOY_SUPABASE_EDGE_FUNCTION_LF"


def _check(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)


def preflight(p: dict) -> dict:
    _check(isinstance(p, dict), "INVALID_PACKET")
    slug = p.get("function_slug")
    _check(isinstance(slug, str) and bool(SLUG.fullmatch(slug)), "INVALID_TARGET_SLUG")
    _check(p.get("operation_code") == OPERATION, "OPERATION_ROUTE_MISMATCH")
    _check(p.get("target_type") == "SUPABASE_EDGE_FUNCTION", "NON_EDGE_TARGET")
    _check(p.get("target_path") == f"supabase/functions/{slug}", "TARGET_PATH_MISMATCH")

    source, main, rollback = (p.get(x) for x in ("source_sha", "main_sha", "rollback_sha"))
    _check(all(isinstance(x, str) and SHA.fullmatch(x) for x in (source, main, rollback)), "SOURCE_SHA_INVALID")
    _check(source == main, "SOURCE_NOT_EXACT_MAIN")
    _check(source != rollback, "ROLLBACK_EQUALS_SOURCE")
    _check(p.get("rollback_source_equals_deployed") is True, "ROLLBACK_NOT_LIVE_VERIFIED")
    _check(p.get("only_target_function_changed") is True, "OTHER_FUNCTION_DELTA")
    _check(p.get("jwt_mode_preserved") is True, "JWT_MODE_DRIFT")
    _check(p.get("db_write_required") is False, "UNDECLARED_DB_WRITE")
    _check(p.get("no_release_promotion") is True, "RELEASE_PROMOTION_FORBIDDEN")

    requested = p.get("execute") is True
    proof = p.get("r17") or {}
    _check(isinstance(proof, dict), "R17_EVIDENCE_MISSING")
    if requested:
        _check(proof.get("status") == "PASS", "R17_PREFLIGHT_NOT_PASSED")
        _check(isinstance(proof.get("event_id"), (str, int)) and str(proof["event_id"]).strip(), "R17_EVENT_MISSING")
        _check(proof.get("rollback_drill") == "PASS", "R17_ROLLBACK_NOT_VERIFIED")
        _check(proof.get("idempotency") == "PASS", "R17_IDEMPOTENCY_NOT_VERIFIED")
        _check(all(isinstance(proof.get(k), (int, float)) and proof[k] >= 0 for k in ("p50_ms", "p90_ms", "max_ms")), "R17_TIMING_MISSING")
        _check(proof["p50_ms"] <= proof["p90_ms"] <= proof["max_ms"], "R17_TIMING_INCONSISTENT")
        _check(p.get("operation_authority") == "CURRENT_VERIFIED", "OPERATION_AUTHORITY_MISSING")
        _check(p.get("effect_guard") == "RESERVED_EXACT", "EFFECT_GUARD_MISSING")
        _check(p.get("human_runtime_authorization") == "SIGNED_CURRENT", "DEPLOY_NOT_AUTHORIZED")
    return {
        "schema": "LF_EDGE_OPERATION_PREFLIGHT_V1",
        "verdict": "READY_FOR_GOVERNED_DEPLOY" if requested else "DRY_RUN_ONLY",
        "effect_executed": False,
        "operation_code": OPERATION,
        "target": slug,
        "source_sha": source,
        "rollback_sha": rollback,
        "no_release_promotion": True,
    }


if __name__ == "__main__":
    try:
        payload = json.load(sys.stdin)
        print(json.dumps(preflight(payload), sort_keys=True))
    except (ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
        print(json.dumps({"verdict": "BLOCKED", "error": str(exc), "effect_executed": False}))
        sys.exit(2)
