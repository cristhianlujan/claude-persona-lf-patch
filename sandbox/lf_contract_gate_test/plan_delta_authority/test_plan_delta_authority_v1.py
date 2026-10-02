#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("plan_delta_authority_v1", ROOT / "plan_delta_authority_v1.py")
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

PLAN = "LF_SUPER_ADMIN_POST_PASE_ARCHITECTURE_V1"
PREV = "9b234da6cdec56c141cc452e3997650c93cdf3a27f64d9b5858bea311476c648"
NEXT = "1" * 64


def event() -> dict:
    return {
        "id": 20001,
        "evento_tipo": "DECISION_ESTRATEGICA",
        "entidad_tipo": "PROGRAM_PLAN",
        "entidad_codigo": PLAN,
        "payload": {
            "authority": "LF_GOVERNANCE",
            "authorizes": ["PLAN_DELTA_AUTHORITY"],
            "authorization_scope": "PLAN_DELTA_AUTHORITY",
            "plan_id": PLAN,
            "previous_plan_digest": PREV,
            "next_plan_digest": NEXT,
            "self_authorization": False,
        },
    }


def call(e: dict) -> dict:
    return mod.produce_plan_delta_authority(
        event=e,
        plan_id=PLAN,
        previous_plan_digest=PREV,
        next_plan_digest=NEXT,
    )


checks = 0

ok = call(event())
assert ok["decision"] == "AUTHORIZED_PLAN_DELTA" and ok["ready"] is True; checks += 1
assert ok["authority"] == "PLAN_AUTHORITY" and ok["schema_version"] == "LF_PLAN_DELTA_AUTHORITY_READBACK_V1"; checks += 1
assert ok["receipt_digest"] == mod.canonical_sha256({k: v for k, v in ok.items() if k != "receipt_digest"}); checks += 1

for field, value, reason in [
    ("evento_tipo", "HANDOFF_DEEP_CONTEXT", "AUTHORIZATION_EVENT_TYPE_MISMATCH"),
    ("entidad_tipo", "PULL_REQUEST", "AUTHORIZATION_ENTITY_TYPE_MISMATCH"),
    ("entidad_codigo", "OTHER_PLAN", "AUTHORIZATION_PLAN_ENTITY_MISMATCH"),
]:
    e = event(); e[field] = value
    out = call(e)
    assert out["decision"] == "PLAN_DELTA_NOT_AUTHORIZED" and out["reason"] == reason; checks += 1

payload_cases = [
    ("authority", "OTHER_AUTHORITY", "AUTHORIZATION_AUTHORITY_MISMATCH"),
    ("authorization_scope", "OTHER_SCOPE", "AUTHORIZATION_SCOPE_MISMATCH"),
    ("previous_plan_digest", "2" * 64, "AUTHORIZATION_PREVIOUS_DIGEST_MISMATCH"),
    ("next_plan_digest", "3" * 64, "AUTHORIZATION_NEXT_DIGEST_MISMATCH"),
    ("self_authorization", True, "SELF_AUTHORIZATION_NOT_EXPLICITLY_FORBIDDEN"),
]
for field, value, reason in payload_cases:
    e = event(); e["payload"][field] = value
    out = call(e)
    assert out["decision"] == "PLAN_DELTA_NOT_AUTHORIZED" and out["reason"] == reason; checks += 1

e = event(); e["payload"]["authorizes"] = ["OTHER_SCOPE"]
out = call(e)
assert out["decision"] == "PLAN_DELTA_NOT_AUTHORIZED" and out["reason"] == "AUTHORIZATION_TOKEN_MISSING"; checks += 1

assert checks == 12, checks
print(f"PASS_PLAN_DELTA_AUTHORITY_V1 checks={checks}")
