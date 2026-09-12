from __future__ import annotations

from dataclasses import dataclass

HEX_A = "a" * 40
HEX_B = "b" * 40
HEX_X = "c" * 40

@dataclass(frozen=True)
class Case:
    name: str
    baseline: str | None
    current: str | None
    blob: str | None
    bound: object | None
    execution_bound: bool = True
    reread: bool = False
    rebind: bool = False
    rebound_from: str | None = None
    caller_claims_trusted: bool = False
    expected: str = ""


def revision_sha(value: object | None) -> str:
    if not isinstance(value, dict):
        return ""
    sha = value.get("revision_sha")
    return sha if isinstance(sha, str) and len(sha) == 40 and all(c in "0123456789abcdef" for c in sha) else ""


def evaluate(case: Case) -> str:
    # Model the intended trusted runtime authority. Caller trust flags are intentionally ignored.
    if not case.baseline:
        return "PROFILE_UPDATE_BASELINE_OBSERVATION_REQUIRED"
    if len(case.baseline) != 40:
        return "PROFILE_UPDATE_BASELINE_REVISION_INVALID"
    if not case.current:
        return "PROFILE_UPDATE_CURRENT_REVISION_UNRESOLVED"
    if not case.blob:
        return "PROFILE_UPDATE_CURRENT_TARGET_BLOB_UNRESOLVED"
    bound_sha = revision_sha(case.bound)
    if not bound_sha:
        return "PROFILE_UPDATE_BOUND_REVISION_STRUCTURED_REQUIRED"
    if case.execution_bound is not True:
        return "PROFILE_UPDATE_EXECUTION_BINDING_REQUIRED"

    stale = case.baseline != case.current
    if stale:
        if case.reread is not True:
            return "PROFILE_UPDATE_STALE_REREAD_REQUIRED"
        if case.rebind is not True:
            return "PROFILE_UPDATE_STALE_REBIND_REQUIRED"
        if case.rebound_from != case.baseline:
            return "PROFILE_UPDATE_REBOUND_FROM_REVISION_MISMATCH"
    if bound_sha != case.current:
        return "PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH"
    return "STALE_REBOUND_CURRENT" if stale else "CURRENT_BOUND"


CASES = [
    Case("POS_CURRENT_BOUND", HEX_A, HEX_A, HEX_X, {"revision_sha": HEX_A}, expected="CURRENT_BOUND"),
    Case("POS_STALE_REBOUND_CURRENT", HEX_A, HEX_B, HEX_X, {"revision_sha": HEX_B}, reread=True, rebind=True, rebound_from=HEX_A, expected="STALE_REBOUND_CURRENT"),
    Case("NEG_MISSING_BASELINE", None, HEX_A, HEX_X, {"revision_sha": HEX_A}, expected="PROFILE_UPDATE_BASELINE_OBSERVATION_REQUIRED"),
    Case("NEG_INVALID_BASELINE", "bad", HEX_A, HEX_X, {"revision_sha": HEX_A}, expected="PROFILE_UPDATE_BASELINE_REVISION_INVALID"),
    Case("NEG_MISSING_CURRENT", HEX_A, None, HEX_X, {"revision_sha": HEX_A}, expected="PROFILE_UPDATE_CURRENT_REVISION_UNRESOLVED"),
    Case("NEG_TARGET_BLOB_UNRESOLVED", HEX_A, HEX_A, None, {"revision_sha": HEX_A}, expected="PROFILE_UPDATE_CURRENT_TARGET_BLOB_UNRESOLVED"),
    Case("NEG_BOUND_UNSTRUCTURED", HEX_A, HEX_A, HEX_X, HEX_A, expected="PROFILE_UPDATE_BOUND_REVISION_STRUCTURED_REQUIRED"),
    Case("NEG_EXECUTION_NOT_BOUND", HEX_A, HEX_A, HEX_X, {"revision_sha": HEX_A}, execution_bound=False, expected="PROFILE_UPDATE_EXECUTION_BINDING_REQUIRED"),
    Case("NEG_STALE_NO_REREAD", HEX_A, HEX_B, HEX_X, {"revision_sha": HEX_B}, expected="PROFILE_UPDATE_STALE_REREAD_REQUIRED"),
    Case("NEG_STALE_NO_REBIND", HEX_A, HEX_B, HEX_X, {"revision_sha": HEX_B}, reread=True, expected="PROFILE_UPDATE_STALE_REBIND_REQUIRED"),
    Case("NEG_REBOUND_FROM_WRONG_REV", HEX_A, HEX_B, HEX_X, {"revision_sha": HEX_B}, reread=True, rebind=True, rebound_from=HEX_X, expected="PROFILE_UPDATE_REBOUND_FROM_REVISION_MISMATCH"),
    Case("NEG_BOUND_NOT_CURRENT", HEX_A, HEX_B, HEX_X, {"revision_sha": HEX_A}, reread=True, rebind=True, rebound_from=HEX_A, expected="PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH"),
    Case("NEG_CALLER_TRUST_FLAGS_CANNOT_OVERRIDE", HEX_A, HEX_B, HEX_X, {"revision_sha": HEX_A}, reread=True, rebind=True, rebound_from=HEX_A, caller_claims_trusted=True, expected="PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH"),
]

failed = []
for case in CASES:
    actual = evaluate(case)
    if actual != case.expected:
        failed.append(f"{case.name}: expected={case.expected} actual={actual}")

# Invariant: changing only caller trust assertion cannot alter deterministic result.
base = Case("BASE", HEX_A, HEX_B, HEX_X, {"revision_sha": HEX_A}, reread=True, rebind=True, rebound_from=HEX_A, caller_claims_trusted=False)
spoof = Case("SPOOF", HEX_A, HEX_B, HEX_X, {"revision_sha": HEX_A}, reread=True, rebind=True, rebound_from=HEX_A, caller_claims_trusted=True)
if evaluate(base) != evaluate(spoof):
    failed.append("CALLER_TRUST_FLAG_CHANGED_RESULT")

if failed:
    raise SystemExit("FAIL_UPDATE_SERVER_TRUST_BEHAVIOR:" + ";".join(failed))

print(f"PASS_UPDATE_SERVER_TRUST_BEHAVIOR={len(CASES)}/{len(CASES)}")
print("CALLER_TRUST_FLAG_INFLUENCE=false")
print("SERVER_DERIVED_DECISION_MODEL=true")
print("UPDATE_WRITE_ENABLED=false")
