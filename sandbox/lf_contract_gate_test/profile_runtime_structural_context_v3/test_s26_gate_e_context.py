#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import json
import tempfile
from pathlib import Path

from s26_hp001.bootstrap_context import evaluate_bootstrap
from s26_hp001.gate_d_authority import evaluate_authority_resolution
from s26_hp001.gate_e_context import (
    GateETypedContextBlocked,
    _load_resolver,
    _validate_payload,
    evaluate_typed_context,
)

HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "s26_hp001"
OUTPUT = FIXTURE / "gate_e_output.json"


def load_payload() -> dict:
    value = json.loads(OUTPUT.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError("GATE_E_FIXTURE_NOT_OBJECT")
    return value


def expect_block(name: str, payload: dict, gate_d: dict, bootstrap: dict, contains: str) -> str:
    try:
        _validate_payload(payload, gate_d, bootstrap)
    except GateETypedContextBlocked as exc:
        text = str(exc)
        if contains not in text:
            raise RuntimeError(f"GATE_E_NEGATIVE_WRONG_BLOCK:{name}:{text}")
        return text
    raise RuntimeError(f"GATE_E_NEGATIVE_FALSE_PASS:{name}")


def expect_adapter_block(name: str, fn, expected: str) -> str:
    resolver = _load_resolver()
    try:
        fn(resolver)
    except resolver.RuntimeContextBlocked as exc:
        if exc.code != expected:
            raise RuntimeError(f"GATE_E_ADAPTER_WRONG_BLOCK:{name}:{exc.code}")
        return exc.code
    raise RuntimeError(f"GATE_E_ADAPTER_FALSE_PASS:{name}")


def adapter_matrix() -> dict:
    resolver = _load_resolver()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        rel = "adapters/_s26_gate_e_fixture/runtime_capsule.yaml"
        path = root / rel
        path.parent.mkdir(parents=True)
        raw = b"adapter: S26_GATE_E_LOCAL_FIXTURE\nactivation: TEST_ONLY\n"
        path.write_bytes(raw)
        sha = hashlib.sha256(raw).hexdigest()
        code = "ADAPTER-S26-GATE-E-TEST"
        binding = {
            "canonical_adapter_id": code,
            "current_path": rel,
            "binding_ref": "local-fixture://s26-gate-e/adapter-binding",
            "sha256": sha,
        }
        context = {"required_adapter_codes": [code]}
        request = {"lf_adapter_bindings": [binding]}
        resolved = resolver._resolve_adapters(context, request, root)
        if resolved != [{
            "adapter_code": code,
            "current_path": rel,
            "sha256": sha,
            "binding_ref": binding["binding_ref"],
        }]:
            raise RuntimeError("GATE_E_ADAPTER_POSITIVE_DIVERGENCE")

        missing = expect_adapter_block(
            "required_missing",
            lambda module: module._resolve_adapters(context, {"lf_adapter_bindings": []}, root),
            "RUNTIME_ADAPTER_MISSING",
        )
        wrong_sha_binding = dict(binding)
        wrong_sha_binding["sha256"] = "0" * 64
        wrong_sha = expect_adapter_block(
            "wrong_sha",
            lambda module: module._resolve_adapters(context, {"lf_adapter_bindings": [wrong_sha_binding]}, root),
            "RUNTIME_CONTEXT_PROVENANCE_SHA_MISMATCH",
        )
        duplicate = expect_adapter_block(
            "duplicate",
            lambda module: module._resolve_adapters(context, {"lf_adapter_bindings": [binding, dict(binding)]}, root),
            "RUNTIME_ADAPTER_AMBIGUOUS",
        )
        outside = dict(binding)
        outside["current_path"] = "sandbox/not-an-adapter.yaml"
        out_of_scope = expect_adapter_block(
            "out_of_scope",
            lambda module: module._resolve_adapters(context, {"lf_adapter_bindings": [outside]}, root),
            "RUNTIME_CONTEXT_REF_OUT_OF_SCOPE",
        )
        return {
            "positive_cardinality": len(resolved),
            "positive_adapter_code": resolved[0]["adapter_code"],
            "positive_sha256": resolved[0]["sha256"],
            "required_missing": missing,
            "wrong_sha": wrong_sha,
            "duplicate": duplicate,
            "out_of_scope": out_of_scope,
            "fixture_mode": "LOCAL_FIXTURE",
            "governed_adapters_namespace_mutated": False,
            "production_effect": False,
        }


def main() -> int:
    bootstrap = evaluate_bootstrap()
    gate_d = evaluate_authority_resolution()
    positive = evaluate_typed_context(gate_d, bootstrap)
    if positive["output"]["status"] != "PASS":
        raise RuntimeError("GATE_E_POSITIVE_NOT_PASS")
    if positive["adapter_binding_count"] != 0:
        raise RuntimeError("GATE_E_HP001_ADAPTER_COUNT_INVALID")
    if positive["authority_count"] != 4:
        raise RuntimeError("GATE_E_POSITIVE_AUTHORITY_COUNT_INVALID")
    if positive["bootstrap_context_sha256"] != bootstrap["output_sha256"]:
        raise RuntimeError("GATE_E_POSITIVE_BOOTSTRAP_DRIFT")

    base = load_payload()
    negatives = {}

    x = copy.deepcopy(base)
    x["bootstrap_context"]["source_sha256"] = "0" * 64
    negatives["bootstrap_sha_drift"] = expect_block("bootstrap_sha_drift", x, gate_d, bootstrap, "GATE_E_BOOTSTRAP_BINDING_MISMATCH")

    x = copy.deepcopy(base)
    x["bootstrap_context"]["execution_mode"] = "PROD_CONTROLLED"
    negatives["bootstrap_mode_drift"] = expect_block("bootstrap_mode_drift", x, gate_d, bootstrap, "GATE_E_BOOTSTRAP_BINDING_MISMATCH")

    x = copy.deepcopy(base)
    x["upstream"]["source_output_sha256"] = "0" * 64
    negatives["wrong_d_sha"] = expect_block("wrong_d_sha", x, gate_d, bootstrap, "GATE_E_UPSTREAM_OUTPUT_SHA_MISMATCH")

    x = copy.deepcopy(base)
    x["run_id"] = "S26-HP-WRONG"
    negatives["run_mismatch"] = expect_block("run_mismatch", x, gate_d, bootstrap, "GATE_E_IDENTITY_INVALID")

    x = copy.deepcopy(base)
    x["typed_context"]["schema"] = "LF_RUNTIME_TYPED_CONTEXT_WRONG"
    negatives["typed_schema"] = expect_block("typed_schema", x, gate_d, bootstrap, "GATE_E_TYPED_CONTEXT_NOT_RESOLVER_EXACT")

    x = copy.deepcopy(base)
    x["resolver_input"]["runtime_context"]["input_fields"]["profile_slug"] = "wrong_profile"
    negatives["profile_slug"] = expect_block("profile_slug", x, gate_d, bootstrap, "GATE_E_RUNTIME_CONTEXT_DIVERGENCE")

    x = copy.deepcopy(base)
    x["resolver_input"]["runtime_context"]["input_fields"]["output_contract_version"] = "WRONG"
    negatives["output_contract"] = expect_block("output_contract", x, gate_d, bootstrap, "GATE_E_RUNTIME_CONTEXT_DIVERGENCE")

    x = copy.deepcopy(base)
    x["resolver_input"]["runtime_context"]["required_adapter_codes"] = ["ADAPTER_REQUIRED_TEST"]
    negatives["required_adapter_missing_in_hp001"] = expect_block("required_adapter_missing_in_hp001", x, gate_d, bootstrap, "GATE_E_RUNTIME_CONTEXT_DIVERGENCE")

    x = copy.deepcopy(base)
    x["policy"]["paid_fallback_allowed"] = True
    negatives["paid_fallback"] = expect_block("paid_fallback", x, gate_d, bootstrap, "GATE_E_POLICY_BOUNDARY_INVALID")

    x = copy.deepcopy(base)
    x["next_gate"] = "WRONG"
    negatives["wrong_next_gate"] = expect_block("wrong_next_gate", x, gate_d, bootstrap, "GATE_E_TRANSITION_INVALID")

    adapters = adapter_matrix()

    print(json.dumps({
        "gate": "S26_HP001_GATE_E_TYPED_CONTEXT_MATRIX_V2",
        "result": "PASS",
        "execution_mode": bootstrap["execution_mode"],
        "distribution_mode": bootstrap["distribution_mode"],
        "policy_snapshot_sha256": bootstrap["policy_snapshot_sha256"],
        "bootstrap_context_sha256": bootstrap["output_sha256"],
        "hp001_positive": {
            "output_sha256": positive["output_sha256"],
            "typed_context_sha256": positive["typed_context_sha256"],
            "adapter_binding_count": positive["adapter_binding_count"],
            "authority_count": positive["authority_count"],
            "next_gate": positive["output"]["next_gate"],
        },
        "adapter_development_matrix": adapters,
        "negative_controls": negatives,
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
