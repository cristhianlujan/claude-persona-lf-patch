from __future__ import annotations

import hashlib
import inspect
import ast
import base64
import gzip
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HARNESS_PATH = (
    ROOT
    / "sandbox"
    / "lf_contract_gate_test"
    / "srcr_v06_native_harness"
    / "native_lifecycle_harness.py"
)

spec = importlib.util.spec_from_file_location("srcr_v06_native_harness_tested", HARNESS_PATH)
assert spec and spec.loader
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)

BUILDER_PATH = (
    ROOT
    / "sandbox"
    / "lf_contract_gate_test"
    / "srcr_v06_native_harness"
    / "build_candidate_from_v05.py"
)
builder_spec = importlib.util.spec_from_file_location("srcr_v06_builder_tested", BUILDER_PATH)
assert builder_spec and builder_spec.loader
builder = importlib.util.module_from_spec(builder_spec)
builder_spec.loader.exec_module(builder)

V05_EVAL = (
    ROOT
    / "profiles"
    / "systemic_root_cause_repair_lf"
    / "evals"
    / "v05_producer_depth_cases.py"
)
v05_fixture = __import__("runpy").run_path(str(V05_EVAL), run_name="srcr_v06_builder_fixture")


def sha(value: str) -> str:
    return "sha256:" + hashlib.sha256(value.encode("utf-8")).hexdigest()


def test_native_harness_reuses_generic_execution_contract_with_read_tools() -> None:
    handoff = harness.build_native_handoff(
        run_id="EXEC-SRCR-V06-NATIVE-HARNESS-TEST-001",
        case_packet={"user_request": "Audit lifecycle read-only."},
        profile_source_sha256=sha("profile-source"),
    )
    contract = handoff["execution_contract"]

    assert handoff["executor_mode"] == "GPT_NATIVE"
    assert handoff["tool_permissions"] == ["READ_GITHUB", "READ_SUPABASE", "READ_WEB"]
    assert contract["executor_mode"] == "GPT_NATIVE"
    assert set(contract["tool_permissions"]) == {"READ_GITHUB", "READ_SUPABASE", "READ_WEB"}
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


def test_web_research_trace_binds_exact_https_evidence() -> None:
    locator = "https://slsa.dev/spec/v1.2/provenance"
    digest = sha("web-result")
    trace = [{
        "sequence": 1,
        "tool_permission": "READ_WEB",
        "resolver_id": "LF_WEB_RESEARCH_READBACK_V1",
        "provider": "WEB",
        "query_locator": locator,
        "request_digest": sha("web-request"),
        "result_digest": digest,
        "observed_at": "2026-09-22T14:28:56Z",
        "evidence_id": "EV-WEB-001",
        "consumer": "$.research_assurance",
        "result_status": "FOUND",
        "result_count": 1,
        "claim_support": "CONTENT",
    }]
    manifest = {"evidence": [{
        "evidence_id": "EV-WEB-001",
        "source_locator": locator,
        "digest": digest,
    }]}
    assert harness.validate_query_trace(trace) == []
    assert harness.validate_manifest_trace_binding(manifest, trace) == []


def test_web_research_trace_rejects_virtual_web_locator() -> None:
    digest = sha("web-result")
    trace = [{
        "sequence": 1,
        "tool_permission": "READ_WEB",
        "resolver_id": "LF_WEB_RESEARCH_READBACK_V1",
        "provider": "WEB",
        "query_locator": "web://slsa.dev/spec/v1.2/provenance",
        "request_digest": sha("web-request"),
        "result_digest": digest,
        "observed_at": "2026-09-22T14:28:56Z",
        "evidence_id": "EV-WEB-001",
        "consumer": "$.research_assurance",
        "result_status": "FOUND",
        "result_count": 1,
        "claim_support": "CONTENT",
    }]
    manifest = {"evidence": [{
        "evidence_id": "EV-WEB-001",
        "source_locator": "web://slsa.dev/spec/v1.2/provenance",
        "digest": digest,
    }]}
    assert "trace[0]:WEB_LOCATOR_CLASS_MISMATCH" in harness.validate_manifest_trace_binding(manifest, trace)


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
    base = ROOT / "sandbox" / "lf_contract_gate_test" / "srcr_v06_native_harness"
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


def test_persisted_lifecycle_phase2_trace_and_manifest_are_exactly_bound() -> None:
    base = ROOT / "sandbox" / "lf_contract_gate_test" / "srcr_v06_native_harness"
    trace_payload = json.loads((base / "lifecycle_trace_phase2.json").read_text(encoding="utf-8"))
    manifest = json.loads((base / "lifecycle_evidence_manifest_phase2.json").read_text(encoding="utf-8"))
    trace = trace_payload["trace"]

    assert len(trace) == 10
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

    findings = {item["finding_id"]: item for item in trace_payload["findings"]}
    assert findings["LC-F01"]["status"] == "CONFIRMED_STRENGTHENED"
    assert findings["LC-F03"]["status"] == "CONFIRMED_STRENGTHENED"
    assert findings["LC-F05"]["status"] == "ROOT_CAUSE_CONFIRMED"


def test_persisted_lifecycle_phase3_trace_and_manifest_are_exactly_bound() -> None:
    base = ROOT / "sandbox" / "lf_contract_gate_test" / "srcr_v06_native_harness"
    trace_payload = json.loads((base / "lifecycle_trace_phase3.json").read_text(encoding="utf-8"))
    manifest = json.loads((base / "lifecycle_evidence_manifest_phase3.json").read_text(encoding="utf-8"))
    trace = trace_payload["trace"]

    assert len(trace) == 11
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

    findings = {item["finding_id"]: item for item in trace_payload["findings"]}
    assert findings["LC-F06"]["status"] == "ROOT_CAUSE_CONFIRMED"
    assert findings["LC-F07"]["status"] == "ROOT_CAUSE_CONFIRMED"
    assert findings["LC-F08"]["status"] == "ROOT_CAUSE_CONFIRMED"
    assert findings["LC-F09"]["status"] == "CONFIRMED_CONSEQUENCE"
    assert findings["LC-F10"]["status"] == "CONFIRMED_CONSEQUENCE"


def test_persisted_lifecycle_phase4_trace_and_manifest_are_exactly_bound() -> None:
    base = ROOT / "sandbox" / "lf_contract_gate_test" / "srcr_v06_native_harness"
    trace_payload = json.loads((base / "lifecycle_trace_phase4.json").read_text(encoding="utf-8"))
    manifest = json.loads((base / "lifecycle_evidence_manifest_phase4.json").read_text(encoding="utf-8"))
    trace = trace_payload["trace"]

    assert len(trace) == 8
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

    findings = {item["finding_id"]: item for item in trace_payload["findings"]}
    assert findings["LC-F11"]["status"] == "ROOT_CAUSE_CONFIRMED"
    assert findings["LC-F12"]["status"] == "ROOT_CAUSE_CONFIRMED"


def test_zero_result_evidence_cannot_support_positive_claim() -> None:
    base = {
        "sequence": 1,
        "tool_permission": "READ_SUPABASE",
        "resolver_id": "LF_SUPABASE_READBACK_V1",
        "provider": "SUPABASE",
        "query_locator": "sql:Q-zero-row",
        "request_digest": sha("request"),
        "result_digest": sha("empty-result"),
        "observed_at": "2026-09-22T00:00:00Z",
        "evidence_id": "EV-ZERO",
        "consumer": "$.live_authority_packet",
        "result_status": "EMPTY",
        "result_count": 0,
    }
    positive = dict(base, claim_support="PRESENCE")
    assert "trace[0]:ZERO_RESULT_REQUIRES_ABSENCE_SUPPORT" in harness.validate_query_trace([positive])

    absence = dict(base, claim_support="ABSENCE")
    assert harness.validate_query_trace([absence]) == []


def test_runtime_research_bundle_requires_result_semantics_for_every_live_query() -> None:
    digest = sha("result")
    locator = "sql:select * from public.example where id=$1"
    manifest = {
        "evidence": [{
            "evidence_id": "EV-1",
            "source_locator": locator,
            "digest": digest,
        }],
        "query_trace": [{
            "sequence": 1,
            "tool_permission": "READ_SUPABASE",
            "resolver_id": "LF_SUPABASE_READBACK_V1",
            "provider": "SUPABASE",
            "query_locator": locator,
            "request_digest": sha("request"),
            "result_digest": digest,
            "observed_at": "2026-09-22T00:00:00Z",
            "evidence_id": "EV-1",
            "consumer": "$.live_authority_packet",
        }],
    }
    manifest_sha = "sha256:" + harness.canonical_sha256(manifest)
    result = harness.research_trace.validate_runtime_research_bundle(
        manifest,
        resolved_authority_context={"EV-1": {"fact": "x"}},
        expected_manifest_sha256=manifest_sha,
    )
    assert result["status"] == "FAIL"
    assert "trace[0]:RESULT_STATUS_REQUIRED_AT_RUNTIME" in result["blocking_codes"]
    assert "trace[0]:RESULT_COUNT_REQUIRED_AT_RUNTIME" in result["blocking_codes"]
    assert "trace[0]:CLAIM_SUPPORT_REQUIRED_AT_RUNTIME" in result["blocking_codes"]

    manifest["query_trace"][0].update({
        "result_status": "EMPTY",
        "result_count": 0,
        "claim_support": "PRESENCE",
    })
    manifest_sha = "sha256:" + harness.canonical_sha256(manifest)
    positive_zero = harness.research_trace.validate_runtime_research_bundle(
        manifest,
        resolved_authority_context={"EV-1": {"fact": "x"}},
        expected_manifest_sha256=manifest_sha,
    )
    assert positive_zero["status"] == "FAIL"
    assert any(
        code.endswith("ZERO_RESULT_REQUIRES_ABSENCE_SUPPORT")
        for code in positive_zero["blocking_codes"]
    )

    manifest["query_trace"][0]["claim_support"] = "ABSENCE"
    manifest_sha = "sha256:" + harness.canonical_sha256(manifest)
    absence = harness.research_trace.validate_runtime_research_bundle(
        manifest,
        resolved_authority_context={"EV-1": {"fact": "x"}},
        expected_manifest_sha256=manifest_sha,
    )
    assert absence["status"] == "PASS", absence


def test_current_uncertainty_without_evidence_map_is_rejected() -> None:
    candidate_path = (
        ROOT
        / "sandbox"
        / "lf_contract_gate_test"
        / "srcr_v06_candidate_20260922"
        / "candidate_v06.json.gz.b64"
    )
    manifest_path = (
        ROOT
        / "sandbox"
        / "lf_contract_gate_test"
        / "srcr_v06_candidate_20260922"
        / "evidence_manifest_v06_merged.json"
    )
    candidate = json.loads(
        gzip.decompress(base64.b64decode(candidate_path.read_bytes())).decode("utf-8")
    )
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    assert candidate.get("current_uncertainties")
    candidate["evidence_map"] = [
        row
        for row in candidate.get("evidence_map", [])
        if row.get("claim_path") != "$.current_uncertainties"
        and not str(row.get("claim_path") or "").startswith("$.current_uncertainties[")
    ]
    result = harness.runtime_validate.validate(candidate, manifest)
    assert "CURRENT_UNCERTAINTY_EVIDENCE_MAP_REQUIRED" in result["blocking_codes"]


def _emitted_codes(path: Path) -> set[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    result: set[str] = set()
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id == "_error" and node.args:
            arg = node.args[0]
            if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                result.add(arg.value)
        if isinstance(node.func, ast.Attribute) and node.func.attr == "append" and node.args:
            arg = node.args[0]
            if isinstance(arg, ast.Constant) and isinstance(arg.value, str) and arg.value.isupper():
                result.add(arg.value)
    return result


def test_rule_ownership_catalog_has_zero_structural_utility_code_overlap() -> None:
    catalog_path = (
        ROOT / "profiles" / "systemic_root_cause_repair_lf" / "contracts" / "rule_ownership.v1.json"
    )
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    structural = ROOT / catalog["owners"]["STRUCTURAL"]["path"]
    utility = ROOT / catalog["owners"]["SEMANTIC_UTILITY"]["path"]
    structural_codes = _emitted_codes(structural)
    utility_codes = _emitted_codes(utility)
    assert structural_codes
    assert utility_codes
    assert structural_codes.isdisjoint(utility_codes)
    assert catalog["static_test"]["structural_utility_overlap_expected"] == 0


def test_runtime_and_native_harness_delegate_research_trace_to_single_owner() -> None:
    engine_path = ROOT / "services" / "profile_runtime_api" / "profile_runtime_api" / "engine.py"
    engine_source = engine_path.read_text(encoding="utf-8")
    harness_source = HARNESS_PATH.read_text(encoding="utf-8")
    assert "load_research_trace_validator" in engine_source
    assert "research_trace.validate_query_trace(trace)" in inspect.getsource(harness.validate_query_trace)
    assert "research_trace.validate_manifest_trace_binding(manifest, trace)" in inspect.getsource(harness.validate_manifest_trace_binding)
    assert "research_trace.validate_query_trace(trace)" in harness_source
    assert "research_trace.validate_manifest_trace_binding(manifest, trace)" in harness_source


def test_prefreeze_rejects_malformed_test_protocol_before_candidate_receipt() -> None:
    candidate_path = (
        ROOT
        / "sandbox"
        / "lf_contract_gate_test"
        / "srcr_v06_candidate_20260922"
        / "candidate_v06.json.gz.b64"
    )
    manifest_path = (
        ROOT
        / "sandbox"
        / "lf_contract_gate_test"
        / "srcr_v06_candidate_20260922"
        / "evidence_manifest_v06_merged.json"
    )
    trace_path = (
        ROOT
        / "sandbox"
        / "lf_contract_gate_test"
        / "srcr_v06_candidate_20260922"
        / "lifecycle_trace_v06_resequenced.json"
    )
    candidate = json.loads(
        gzip.decompress(base64.b64decode(candidate_path.read_bytes())).decode("utf-8")
    )
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    trace = json.loads(trace_path.read_text(encoding="utf-8"))["trace"]
    candidate["planned_regressions"][0]["test_protocol"]["setup"] = "invalid-string"
    try:
        harness.materialize_prequality_freeze(
            candidate=candidate,
            evidence_manifest=manifest,
            query_trace=trace,
        )
    except RuntimeError as exc:
        assert str(exc).startswith("PREFREEZE_VALIDATION_NOT_CLEAN:OUTPUT_SCHEMA")
    else:
        raise AssertionError("schema-invalid candidate must never materialize a freeze receipt")


def test_repaired_v06_candidate_passes_governed_prequality_freeze() -> None:
    candidate_path = (
        ROOT / "sandbox" / "lf_contract_gate_test"
        / "srcr_v06_candidate_repaired_20260922" / "candidate_v06_repaired.json"
    )
    manifest_path = (
        ROOT / "sandbox" / "lf_contract_gate_test"
        / "srcr_v06_candidate_20260922" / "evidence_manifest_v06_merged.json"
    )
    trace_path = (
        ROOT / "sandbox" / "lf_contract_gate_test"
        / "srcr_v06_candidate_repaired_20260922" / "query_trace_prefreeze.json"
    )
    candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    trace_doc = json.loads(trace_path.read_text(encoding="utf-8"))
    query_trace = trace_doc["trace"]

    validation = harness.post_producer_validation(
        candidate=candidate,
        evidence_manifest=manifest,
        query_trace=query_trace,
    )
    runtime_gate = validation.get("runtime_validate")
    assert isinstance(runtime_gate, dict), validation
    assert runtime_gate.get("blocking_codes") == [], runtime_gate.get("blocking_codes")
    assert validation.get("manifest_trace_binding_errors") == [], validation.get("manifest_trace_binding_errors")
    assert validation["status"] == "PASS_PRE_QUALITY", validation
    receipt = harness.materialize_prequality_freeze(
        candidate=candidate,
        evidence_manifest=manifest,
        query_trace=query_trace,
    )
    assert receipt["pre_quality_status"] == "PASS_PRE_QUALITY", receipt
    assert receipt["schema_error_count"] == 0, receipt
    assert receipt["output_schema_path"] == "profiles/systemic_root_cause_repair_lf/schemas/output.schema.json"
    assert receipt["output_schema_file_sha256"] == hashlib.sha256(
        (ROOT / receipt["output_schema_path"]).read_bytes()
    ).hexdigest()
    assert receipt["validation_sha256"] == harness.canonical_sha256(validation)
    assert receipt["deterministic_status"] == "PASS", receipt
    assert receipt["semantic_utility_status"] == "PASS", receipt
    assert receipt["independent_quality"] == "PENDING_INDEPENDENT_REVIEW", receipt
    assert receipt["canonical_quality_accepted"] is False
    assert receipt["candidate_sha256"] == (
        "126ca5dd7be63f582536fa0662dd1dde488e3b908dfa5dbbafb3ccd50f588e01"
    )


def test_v06_builder_declares_canary_consumer_and_queue_terminal_bridge() -> None:
    base_candidate, _ = v05_fixture["v05_pair"]("ARCHITECTURE_AUDIT")
    candidate = builder.build_candidate(base_candidate)

    edges = {
        item["edge_id"]: item
        for item in candidate["material_process_graph"]["edges"]
    }
    refresh = edges["EDGE-REFRESH-VERIFY"]
    terminal = edges["EDGE-EXECUTE-TERMINAL-READBACK"]

    assert refresh["next_gate"] == "PROFILE_RUNTIME_CANARY_REQUIRED"
    assert (
        refresh["proposed_next_gate_consumer_ref"]
        == "proposed://GESTION_RELEASE_PERFIL_LF/runtime_canary_consumer"
    )
    assert terminal["proposed_change_ref"] == (
        "proposed://EJECUCION_PERFIL_LF/queue_terminal_bridge"
    )

    targets = {
        row["target"]
        for row in candidate["implementation_delta"]
        if isinstance(row, dict)
    }
    assert (
        "supabase://proposed/GESTION_RELEASE_PERFIL_LF/runtime_canary_consumer"
        in targets
    )
    assert (
        "supabase://proposed/EJECUCION_PERFIL_LF/queue_terminal_bridge"
        in targets
    )

    selected_errors = harness.runtime_validate._v06_selected_change_errors(candidate)
    assert not any(
        item["code"] == "V06_SELECTED_REPAIR_CHANGE_UNDECLARED"
        for item in selected_errors
    ), selected_errors

    deliverables = {
        row["artifact_ref"]
        for row in candidate["implementation_package"]["deliverables"]
        if isinstance(row, dict)
    }
    assert "proposed://GESTION_RELEASE_PERFIL_LF/runtime_canary_consumer" in deliverables
    assert "proposed://EJECUCION_PERFIL_LF/queue_terminal_bridge" in deliverables


def test_v06_implementable_edge_change_must_be_declared_in_delta() -> None:
    payload = {
        "profile_pack_id": "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6",
        "status": "SYSTEMIC_REPAIR_SPEC",
        "implementation_delta": [
            {
                "target": "supabase://proposed/PROFILE_RELEASE_CONTRACT_V1",
                "action": "create",
                "rationale": "x",
                "evidence_refs": ["evidence://x"],
            }
        ],
        "material_process_graph": {
            "edges": [
                {
                    "disposition": "IMPLEMENTABLE",
                    "proposed_change_ref": "proposed://EJECUCION_PERFIL_LF/queue_terminal_bridge",
                }
            ]
        },
    }
    errors = harness.runtime_validate._v06_selected_change_errors(payload)
    assert any(
        item["code"] == "V06_SELECTED_REPAIR_CHANGE_UNDECLARED"
        for item in errors
    )

    payload["implementation_delta"].append(
        {
            "target": "supabase://proposed/EJECUCION_PERFIL_LF/queue_terminal_bridge",
            "action": "declare exact queue terminal bridge",
            "rationale": "close canonical terminality",
            "evidence_refs": ["evidence://terminality"],
        }
    )
    errors = harness.runtime_validate._v06_selected_change_errors(payload)
    assert not any(
        item["code"] == "V06_SELECTED_REPAIR_CHANGE_UNDECLARED"
        for item in errors
    )
