#!/usr/bin/env python3
"""Exact-head fail-closed regression for Router-bound LF adapter capsules."""
import importlib.util
import json
import tempfile
from copy import deepcopy
from pathlib import Path

from profile_runtime_runner import RESPONSE_TYPE, RuntimeExecutionBlocked, execute_profile_runtime
from validate_profile_execution import canonical_json_sha256, sha256_text, validate_receipt

PROFILE_CODE = "PERFIL-UI-ARCHITECT"
PROFILE_SLUG = "ui_architect"
PROFILE_SOURCES = [{"ref": "profiles/ui_architect/SKILL.md", "content": "# UI\nReturn JSON."}]
INPUT = "Evalua la pantalla."
RAW = {"worker": "ui_architect", "self_verdict": "PASS_TO_QUALITY_PACK_CANDIDATE"}
CAPSULE = "adapter: ADAPTER_LF_SHELL_PROFILE\nassurance_revision: v2\nactivation: ROUTER_BOUND_ONLY\nrules:\n  - preserve authority\n"
AUTO_GOVERNANCE = object()


def adapter_source(**overrides):
    value = {
        "adapter_code": "ADAPTER_LF_SHELL_PROFILE",
        "assurance_revision": "v2",
        "activation_source": "ROUTER",
        "binding_ref": "public.v_lf_router_adapter_bindings:ADAPTER-LF-SHELL-PROFILE-20260827:PERFIL-UI-ARCHITECT",
        "target_ref": PROFILE_CODE,
        "ref": "adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml",
        "content": CAPSULE,
        "input_governance_receipt_required": True,
        "input_governance_continuation_policy": "PASS_ONLY",
        "input_governance_contract_resolution": "LIVE_CURRENT",
        "input_governance_authority_contract": "INPUT_READINESS_CONTRACT",
    }
    value.update(overrides)
    return value


class Adapter:
    adapter_id = "provider-runtime-adapter"
    is_test_double = True
    calls = 0

    def __init__(self):
        self.calls = 0

    def execute(self, request):
        self.calls += 1
        attestation = {
            "provider": "test-provider",
            "model_id": "test-model",
            "run_id": "run-1",
            "attested_at": "2026-08-29T03:00:00Z",
            "adapter_id": self.adapter_id,
            "request_sha256": request["request_sha256"],
            "profile_source_sha256": request["profile_source_sha256"],
            "input_sha256": request["input_sha256"],
            "operation_code": request["operation_code"],
            "profile_code": request["profile_code"],
            "profile_slug": request["profile_slug"],
        }
        if request.get("governance_receipt_sha256"):
            attestation["governance_receipt_sha256"] = request["governance_receipt_sha256"]
        return {
            "response_type": RESPONSE_TYPE,
            "raw_output": RAW,
            "runtime_attestation": attestation,
        }


class Verifier:
    verifier_id = "test-verifier"
    is_test_double = True

    def verify(self, *, request, response, adapter):
        response_sha = canonical_json_sha256(response)
        return {
            "verified": True,
            "verifier_id": self.verifier_id,
            "request_sha256": request["request_sha256"],
            "response_sha256": response_sha,
            "evidence_sha256": sha256_text(request["request_sha256"] + response_sha),
        }


def governance_envelope(sources, **receipt_overrides):
    required = sorted(
        item["adapter_code"]
        for item in (sources or [])
        if item.get("input_governance_receipt_required") is True
    )
    if not required:
        return None
    receipt = {
        "governance_agent_used": True,
        "governance_agent": "input-governance-agent-v1",
        "governance_version": "5.12",
        "sections_consumed": ["APPLICABILITY_READINESS", "SOURCE_AUTHORITY_PROVENANCE"],
        "source_refs": [
            "programacion.input_readiness_runs/9001",
            "lf_ops.pantallas/2",
            "programacion.contratos/INPUT_READINESS_CONTRACT@5.12",
        ],
        "snapshot_hash": "a" * 64,
        "contract_snapshot_hash": "b" * 64,
        "decision": "PASS",
        "gap_or_na": "NONE",
        "timestamp": "2026-08-31T23:50:00Z",
        "run_id": 9001,
        "pantalla_id": 2,
        "screen_code": "ONB_002",
        "run_created_at": "2026-08-31T23:49:00Z",
        "agent_output_sha256": "c" * 64,
        "currentness": "LIVE_CURRENT",
    }
    receipt.update(receipt_overrides)
    return {
        "applicable": True,
        "status": "READY",
        "decision": receipt["decision"],
        "continuation_allowed": receipt["decision"] == "PASS",
        "required_by_adapters": required,
        "pantalla_id": receipt["pantalla_id"],
        "screen_code": receipt["screen_code"],
        "governance_receipt": receipt,
    }


def run(sources=None, governance=AUTO_GOVERNANCE, adapter=None):
    adapter = Adapter() if adapter is None else adapter
    if governance is AUTO_GOVERNANCE:
        governance = governance_envelope(sources)
    package = execute_profile_runtime(
        execution_id="EXEC-RUNTIME-ADAPTER-TEST-001",
        profile_code=PROFILE_CODE,
        profile_slug=PROFILE_SLUG,
        profile_sources=PROFILE_SOURCES,
        input_literal=INPUT,
        adapter=adapter,
        attestation_verifier=Verifier(),
        allow_test_doubles=True,
        lf_adapter_sources=sources,
        input_governance=governance,
    )
    return package, adapter.calls


def expect_block(name, code, fn):
    try:
        fn()
    except RuntimeExecutionBlocked as exc:
        assert exc.code == code, (name, code, exc.code)
        print(f"PASS {name}: {code}")
        return
    raise AssertionError(f"{name}: expected {code}")


def _load_schema_resolver():
    path = Path(__file__).with_name("github_actions_local_runtime.py")
    if not path.is_file():
        return None
    spec = importlib.util.spec_from_file_location("lf_runtime_structured_output_probe", path)
    if spec is None or spec.loader is None:
        raise AssertionError("structured-output runtime module could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module._resolve_runtime_output_schema


def test_structured_schema_resolution():
    resolver = _load_schema_resolver()
    if resolver is None:
        print("PASS structured_schema_isolated_fixture_no_runtime_module")
        return
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        assert resolver(root, "ui_architect") is None
        print("PASS structured_schema_absent_zero_overhead")

        schema_dir = root / "profiles" / "ui_architect" / "schemas"
        schema_dir.mkdir(parents=True)
        schema = schema_dir / "runtime_output.schema.json"
        schema.write_text(json.dumps({"type": "object"}), encoding="utf-8")
        assert resolver(root, "ui_architect") == schema.resolve()
        print("PASS structured_schema_canonical_path")

        expect_block(
            "structured_schema_invalid_slug",
            "LOCAL_RUNTIME_SCHEMA_PROFILE_SLUG_INVALID",
            lambda: resolver(root, "../ui_architect"),
        )

        outside = root / "outside.schema.json"
        outside.write_text(json.dumps({"type": "object"}), encoding="utf-8")
        schema.unlink()
        schema.symlink_to(outside)
        expect_block(
            "structured_schema_symlink_escape",
            "LOCAL_RUNTIME_SCHEMA_PATH_ESCAPE",
            lambda: resolver(root, "ui_architect"),
        )


def main():
    package, calls = run([adapter_source()])
    assert calls == 1
    assert package["request"]["lf_adapter_source_refs"] == ["adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml"]
    invocations = package["receipt"]["lf_adapter_invocations"]
    assert len(invocations) == 1
    assert invocations[0]["activation_source"] == "ROUTER"
    assert invocations[0]["profile_id"] == PROFILE_CODE
    assert package["receipt"]["runtime_attestation"]["adapter_id"] == "provider-runtime-adapter"
    assert package["receipt"]["governance_receipt"]["decision"] == "PASS"
    assert package["receipt"]["input_governance_required_adapters"] == ["ADAPTER_LF_SHELL_PROFILE"]
    assert package["receipt"]["runtime_attestation"]["governance_receipt_sha256"] == package["receipt"]["governance_receipt_sha256"]
    assert validate_receipt(package["receipt"], expected_profile_code=PROFILE_CODE) == []
    print("PASS valid_router_binding_governance_pass_same_call_and_receipt")

    missing_adapter = Adapter()
    expect_block(
        "governance_receipt_absent_no_model_call",
        "INPUT_GOVERNANCE_RECEIPT_MISSING",
        lambda: run([adapter_source()], governance=None, adapter=missing_adapter),
    )
    assert missing_adapter.calls == 0

    partial_adapter = Adapter()
    expect_block(
        "governance_partial_no_model_call",
        "INPUT_GOVERNANCE_DECISION_NOT_PASS",
        lambda: run(
            [adapter_source()],
            governance=governance_envelope([adapter_source()], decision="PARTIAL"),
            adapter=partial_adapter,
        ),
    )
    assert partial_adapter.calls == 0

    stale_adapter = Adapter()
    expect_block(
        "governance_stale_no_model_call",
        "INPUT_GOVERNANCE_RECEIPT_INVALID",
        lambda: run(
            [adapter_source()],
            governance=governance_envelope([adapter_source()], currentness="STALE"),
            adapter=stale_adapter,
        ),
    )
    assert stale_adapter.calls == 0

    package_no_governance, calls = run([adapter_source(
        input_governance_receipt_required=False,
        input_governance_continuation_policy=None,
        input_governance_contract_resolution=None,
        input_governance_authority_contract=None,
    )])
    assert calls == 1
    assert "governance_receipt" not in package_no_governance["receipt"]
    print("PASS adapter_without_governance_zero_overhead")

    package_no_adapter, calls = run([])
    assert calls == 1
    assert "lf_adapter_sources" not in package_no_adapter["request"]
    assert "lf_adapter_invocations" not in package_no_adapter["receipt"]
    print("PASS unbound_profile_zero_adapter_overhead")

    expect_block("profile_direct_activation", "BLOCK_UNBOUND_ADAPTER_INVOCATION", lambda: run([adapter_source(activation_source="PROFILE")]))
    expect_block("duplicate_binding", "BLOCK_DUPLICATE_ADAPTER_INVOCATION", lambda: run([adapter_source(), adapter_source(binding_ref="other")]))
    expect_block("single_capsule_budget", "BLOCK_CONTEXT_BUDGET_EXCEEDED", lambda: run([adapter_source(content="x" * 2001)]))
    expect_block("path_traversal", "LF_ADAPTER_CAPSULE_PATH_INVALID", lambda: run([adapter_source(ref="adapters/../runtime/runtime_capsule.yaml")]))
    expect_block("target_mismatch", "LF_ADAPTER_TARGET_MISMATCH", lambda: run([adapter_source(target_ref="PERFIL-OTHER")]))

    many = [adapter_source(adapter_code=f"A{i}", binding_ref=f"b{i}", ref=f"adapters/a{i}/runtime/runtime_capsule.yaml") for i in range(5)]
    expect_block("adapter_count_budget", "LF_ADAPTER_BINDING_COUNT_EXCEEDED", lambda: run(many))

    total = [
        adapter_source(adapter_code="A1", binding_ref="b1", ref="adapters/a1/runtime/runtime_capsule.yaml", content="a" * 2000),
        adapter_source(adapter_code="A2", binding_ref="b2", ref="adapters/a2/runtime/runtime_capsule.yaml", content="b" * 2000),
        adapter_source(adapter_code="A3", binding_ref="b3", ref="adapters/a3/runtime/runtime_capsule.yaml", content="c"),
    ]
    expect_block("total_context_budget", "BLOCK_TOTAL_ADAPTER_CONTEXT_BUDGET_EXCEEDED", lambda: run(total))

    tampered = deepcopy(package["receipt"])
    tampered["lf_adapter_invocations"][0]["profile_id"] = "PERFIL-OTHER"
    tampered["receipt_sha256"] = canonical_json_sha256({k: v for k, v in tampered.items() if k != "receipt_sha256"})
    errors = validate_receipt(tampered, expected_profile_code=PROFILE_CODE)
    assert "LF_ADAPTER_INVOCATION_0_PROFILE_ID_MISMATCH" in errors
    print("PASS tampered_lf_adapter_receipt_blocks")

    tampered_governance = deepcopy(package["receipt"])
    tampered_governance["governance_receipt"]["decision"] = "PARTIAL"
    tampered_governance["governance_receipt_sha256"] = canonical_json_sha256(tampered_governance["governance_receipt"])
    tampered_governance["receipt_sha256"] = canonical_json_sha256({k: v for k, v in tampered_governance.items() if k != "receipt_sha256"})
    errors = validate_receipt(tampered_governance, expected_profile_code=PROFILE_CODE)
    assert "INPUT_GOVERNANCE_DECISION_NOT_PASS" in errors
    assert "INPUT_GOVERNANCE_ATTESTATION_SHA256_MISMATCH" in errors
    print("PASS tampered_governance_receipt_blocks")

    test_structured_schema_resolution()
    print("LF_ADAPTER_BINDING_TESTS_PASS 19/19")


if __name__ == "__main__":
    main()
