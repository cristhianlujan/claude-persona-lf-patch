"""OFFLINE-ONLY SALY visual skill transport probe. Never a production handler."""
from __future__ import annotations

import hashlib
import json
from typing import Any

BUSINESS = "SALY"
PROFILE = "PERFIL-UI-ARCHITECT"
SKILL = "SALY_APP_VISUAL_PROBE"
MODE = "OFFLINE_CONTRACT_TEST"
SENSITIVE = frozenset(("token", "password", "secret", "authorization", "credential",
                       "api_key", "access_token", "refresh_token", "jwt", "cookie"))


def _redact(value: Any, depth: int = 0) -> Any:
    if depth > 12:
        return "[TRUNCATED_DEPTH]"
    if isinstance(value, dict):
        return {str(key): "[REDACTED]" if any(s in str(key).lower() for s in SENSITIVE)
                else _redact(item, depth + 1)
                for key, item in value.items()}
    if isinstance(value, list):
        return [_redact(item, depth + 1) for item in value]
    return value


def hello_world(payload: dict[str, Any]) -> dict[str, Any]:
    base = {"schema_version": "SALY_APP_VISUAL_PROBE_V0_1",
            "runtime_invoked": False, "simulated": True,
            "effect_authority": False, "write_performed": False}
    def block(reason: str) -> dict[str, Any]:
        return {**base, "status": "BLOCKED", "blocking_code": reason}

    if not isinstance(payload, dict) or payload.get("pilot_mode") != MODE:
        return block("OFFLINE_CONTRACT_TEST_ONLY")
    transport = payload.get("transport")
    if not isinstance(transport, dict):
        return block("MISSING_TRANSPORT")
    try:
        if len(json.dumps(transport, ensure_ascii=False)) > 24000:
            return block("TRANSPORT_TOO_LARGE")
        stage = transport["stage1_payload"]
        route = transport["route_result"]
        semantic = transport["semantic_result"]
        handoff = transport["router_profile_handoff"]
        selection = transport["skill_selection"]
        gate2 = transport["gate2_derivation"]
        if any(not isinstance(x, dict) for x in (stage, route, semantic, handoff, selection, gate2)):
            return block("INVALID_TRANSPORT_TYPES")
        if stage.get("schema_version") != "LF_ROUTER_STAGE1_V2":
            return block("INVALID_STAGE1_SCHEMA")
        if stage.get("negocio_codigo") != BUSINESS or route.get("negocio_codigo") != BUSINESS:
            return block("CROSS_BUSINESS_OR_UNKNOWN")
        if route.get("paso") == "NEGOCIO_NO_HABILITADO":
            return block("BUSINESS_NOT_ENABLED")
        if transport.get("fixture_only") is not True or route.get("mock_route") is not True:
            return block("REAL_ROUTER_RECEIPT_REQUIRED")
        if semantic.get("selected_profile_code") != PROFILE or handoff.get("profile_code") != PROFILE:
            return block("WRONG_PROFILE")
        if selection.get("skill_code") != SKILL or selection.get("selection_mode") != "SEMANTIC_OPTIONAL":
            return block("WRONG_SKILL_SELECTION")
        if any(obj.get("effect_authority") is not False for obj in (route, gate2, handoff)):
            return block("UNAUTHORIZED_EFFECT")
        raw = json.dumps(transport, sort_keys=True, ensure_ascii=False,
                         separators=(",", ":")).encode("utf-8")
        return {**base, "status": "HELLO_WORLD_OFFLINE",
                "mensaje": "Hola mundo, ya llegué.",
                "transport_sha256": hashlib.sha256(raw).hexdigest(),
                "transporte_recibido": _redact(transport)}
    except (KeyError, TypeError, ValueError, OverflowError, RecursionError):
        return block("TRANSPORT_INCOMPLETE_OR_INVALID")


if __name__ == "__main__":
    import sys
    try:
        request = json.load(sys.stdin)
        result = hello_world(request)
    except (ValueError, TypeError, RecursionError):
        result = {"status": "BLOCKED", "blocking_code": "INVALID_JSON_INPUT",
                  "effect_authority": False, "runtime_invoked": False}
    print(json.dumps(result, ensure_ascii=False, indent=2))
