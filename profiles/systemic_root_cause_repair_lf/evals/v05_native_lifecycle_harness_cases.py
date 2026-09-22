#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HARNESS = Path(__file__).with_name("v05_native_lifecycle_harness.py")

spec = importlib.util.spec_from_file_location("srcr_v05_native_harness_cases_target", HARNESS)
assert spec and spec.loader
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)

passed = 0


def check(name: str, condition: bool, detail=None) -> None:
    global passed
    if not condition:
        raise AssertionError(f"{name}: {detail}")
    passed += 1
    print(f"PASS {name}")


def sha(value: str) -> str:
    return "sha256:" + hashlib.sha256(value.encode("utf-8")).hexdigest()


handoff = h.build_native_handoff(
    run_id="EXEC-SRCR-V05-NATIVE-HARNESS-EVAL-001",
    case_packet={"user_request": "Audit lifecycle read-only."},
    profile_source_sha256=sha("profile-source"),
)
contract = handoff["execution_contract"]

check("NATIVE_EXECUTOR_MODE", handoff["executor_mode"] == "GPT_NATIVE")
check("READ_ONLY_TOOLS", handoff["tool_permissions"] == ["READ_GITHUB", "READ_SUPABASE"])
check("GENERIC_EXECUTION_CONTRACT_REUSED", contract["schema"] == "PROFILE_EXECUTION_CONTRACT_V1")
check("NO_SELF_QUALITY", "SELF_AUTHORIZE_QUALITY" in contract["forbidden_actions"])
check("NO_RUNTIME_ACTIVATION", "ACTIVATE_RUNTIME" in contract["forbidden_actions"])

locator = "sql:select status from public.lf_operation_registry where operation_code=$1"
digest = sha("result")
trace = [{
    "sequence": 1,
    "tool_permission": "READ_SUPABASE",
    "resolver_id": "LF_SUPABASE_READBACK_V1",
    "provider": "SUPABASE",
    "query_locator": locator,
    "request_digest": sha("request"),
    "result_digest": digest,
    "observed_at": "2026-09-21T22:00:00-05:00",
    "evidence_id": "EV-001",
    "consumer": "$.live_authority_packet",
}]
manifest = {
    "manifest_version": "SRCR_EVIDENCE_MANIFEST_V1",
    "bundle_id": "BUNDLE-001",
    "bundle_digest": sha("bundle"),
    "observed_at": "2026-09-21T22:00:00-05:00",
    "producer": {
        "kind": "SOURCE_FIRST_RESOLVER",
        "resolver_ref": "supabase://private.lf_evidence_resolver_registry_v1/LF_SUPABASE_READBACK_V1",
    },
    "evidence": [{
        "evidence_id": "EV-001",
        "subject": "operation lifecycle",
        "evidence_class": "OBSERVED_LIVE",
        "source_locator": locator,
        "revision_or_observed_at": "2026-09-21T22:00:00-05:00",
        "digest": digest,
        "state": "CURRENT",
    }],
}

check("QUERY_TRACE_VALID", h.validate_query_trace(trace) == [], h.validate_query_trace(trace))
check(
    "MANIFEST_TRACE_EXACT_BINDING",
    h.validate_manifest_trace_binding(manifest, trace) == [],
    h.validate_manifest_trace_binding(manifest, trace),
)

bad = [dict(trace[0], tool_permission="WRITE_SUPABASE", resolver_id="AD_HOC_READER")]
bad_errors = h.validate_query_trace(bad)
check("WRITE_TOOL_REJECTED", "trace[0]:TOOL_PERMISSION_INVALID" in bad_errors, bad_errors)
check("AD_HOC_RESOLVER_REJECTED", "trace[0]:RESOLVER_NOT_CANONICAL" in bad_errors, bad_errors)

borrowed = {
    "evidence": [{
        "evidence_id": "EV-001",
        "source_locator": "sql:select something_else",
        "digest": sha("other"),
    }]
}
borrow_errors = h.validate_manifest_trace_binding(borrowed, trace)
check("BORROWED_LOCATOR_REJECTED", "trace[0]:EVIDENCE_LOCATOR_MISMATCH" in borrow_errors, borrow_errors)
check("BORROWED_DIGEST_REJECTED", "trace[0]:EVIDENCE_DIGEST_MISMATCH" in borrow_errors, borrow_errors)

print(f"V05_NATIVE_LIFECYCLE_HARNESS_CASES_PASS {passed}/11")
