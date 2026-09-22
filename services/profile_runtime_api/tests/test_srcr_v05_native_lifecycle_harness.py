from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HARNESS_PATH = (
    ROOT
    / "sandbox"
    / "lf_contract_gate_test"
    / "srcr_v05_native_harness"
    / "native_lifecycle_harness.py"
)

spec = importlib.util.spec_from_file_location("srcr_v05_native_harness_tested", HARNESS_PATH)
assert spec and spec.loader
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


def sha(value: str) -> str:
    return "sha256:" + hashlib.sha256(value.encode("utf-8")).hexdigest()


def test_native_harness_reuses_generic_execution_contract_with_read_tools() -> None:
    handoff = harness.build_native_handoff(
        run_id="EXEC-SRCR-V05-NATIVE-HARNESS-TEST-001",
        case_packet={"user_request": "Audit lifecycle read-only."},
        profile_source_sha256=sha("profile-source"),
    )
    contract = handoff["execution_contract"]

    assert handoff["executor_mode"] == "GPT_NATIVE"
    assert handoff["tool_permissions"] == ["READ_GITHUB", "READ_SUPABASE"]
    assert contract["executor_mode"] == "GPT_NATIVE"
    assert set(contract["tool_permissions"]) == {"READ_GITHUB", "READ_SUPABASE"}
    assert "WRITE_SUPABASE" in contract["forbidden_actions"]
    assert "WRITE_GITHUB" in contract["forbidden_actions"]
    assert "SELF_AUTHORIZE_QUALITY" in contract["forbidden_actions"]


def test_query_trace_binds_exactly_to_external_manifest() -> None:
    locator = "sql:select status from public.lf_operation_registry where operation_code=$1"
    digest = sha("query-result")
    trace = [
        {
            "sequence": 1,
            "tool_permission": "READ_SUPABASE",
            "resolver_id": "LF_SUPABASE_READBACK_V1",
            "provider": "SUPABASE",
            "query_locator": locator,
            "request_digest": sha("query-request"),
            "result_digest": digest,
            "observed_at": "2026-09-21T22:00:00-05:00",
            "evidence_id": "EV-LIVE-001",
            "consumer": "$.live_authority_packet",
        }
    ]
    manifest = {
        "manifest_version": "SRCR_EVIDENCE_MANIFEST_V1",
        "bundle_id": "BUNDLE-NATIVE-TEST",
        "bundle_digest": sha("bundle"),
        "observed_at": "2026-09-21T22:00:00-05:00",
        "producer": {
            "kind": "SOURCE_FIRST_RESOLVER",
            "resolver_ref": "supabase://private.lf_evidence_resolver_registry_v1/LF_SUPABASE_READBACK_V1",
        },
        "evidence": [
            {
                "evidence_id": "EV-LIVE-001",
                "subject": "operation lifecycle",
                "evidence_class": "OBSERVED_LIVE",
                "source_locator": locator,
                "revision_or_observed_at": "2026-09-21T22:00:00-05:00",
                "digest": digest,
                "state": "CURRENT",
            }
        ],
    }

    assert harness.validate_query_trace(trace) == []
    assert harness.validate_manifest_trace_binding(manifest, trace) == []


def test_query_trace_rejects_noncanonical_resolver_and_write_permission() -> None:
    trace = [
        {
            "sequence": 1,
            "tool_permission": "WRITE_SUPABASE",
            "resolver_id": "AD_HOC_SQL_READER",
            "provider": "SUPABASE",
            "query_locator": "sql:select 1",
            "request_digest": sha("request"),
            "result_digest": sha("result"),
            "observed_at": "2026-09-21T22:00:00-05:00",
            "evidence_id": "EV-001",
            "consumer": "$.symptom",
        }
    ]
    errors = harness.validate_query_trace(trace)

    assert "trace[0]:TOOL_PERMISSION_INVALID" in errors
    assert "trace[0]:WRITE_TOOL_FORBIDDEN" in errors
    assert "trace[0]:RESOLVER_NOT_CANONICAL" in errors


def test_manifest_trace_rejects_borrowed_locator_or_digest() -> None:
    trace = [
        {
            "sequence": 1,
            "tool_permission": "READ_GITHUB",
            "resolver_id": "LF_GITHUB_SOURCE_READBACK_V1",
            "provider": "GITHUB",
            "query_locator": "github://repo/path@abc",
            "request_digest": sha("request"),
            "result_digest": sha("actual-result"),
            "observed_at": "2026-09-21T22:00:00-05:00",
            "evidence_id": "EV-GH-001",
            "consumer": "$.material_process_graph.nodes[0]",
        }
    ]
    manifest = {
        "evidence": [
            {
                "evidence_id": "EV-GH-001",
                "source_locator": "github://repo/other@abc",
                "digest": sha("other-result"),
            }
        ]
    }

    errors = harness.validate_manifest_trace_binding(manifest, trace)
    assert "trace[0]:EVIDENCE_LOCATOR_MISMATCH" in errors
    assert "trace[0]:EVIDENCE_DIGEST_MISMATCH" in errors


def test_persisted_lifecycle_phase1_trace_and_manifest_are_exactly_bound() -> None:
    base = ROOT / "sandbox" / "lf_contract_gate_test" / "srcr_v05_native_harness"
    trace_payload = json.loads((base / "lifecycle_trace_phase1.json").read_text(encoding="utf-8"))
    manifest = json.loads((base / "lifecycle_evidence_manifest_phase1.json").read_text(encoding="utf-8"))
    trace = trace_payload["trace"]

    assert len(trace) == 15
    assert harness.validate_query_trace(trace) == []
    assert harness.validate_manifest_trace_binding(manifest, trace) == []

    normalized = dict(manifest)
    normalized.pop("bundle_digest", None)
    raw = json.dumps(
        normalized,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    expected_bundle_digest = "sha256:" + hashlib.sha256(raw).hexdigest()
    assert manifest["bundle_digest"] == expected_bundle_digest

    assert [item["finding_id"] for item in trace_payload["findings"]] == [
        "LC-F01",
        "LC-F02",
        "LC-F03",
        "LC-F04",
        "LC-F05",
    ]
