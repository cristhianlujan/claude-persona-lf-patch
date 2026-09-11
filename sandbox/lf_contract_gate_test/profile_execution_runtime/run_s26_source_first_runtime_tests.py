#!/usr/bin/env python3
from copy import deepcopy

from profile_execution_contract import build_execution_contract, build_source_fidelity_contract, canonical_json_sha256
from profile_runtime_runner import RESPONSE_TYPE, RuntimeExecutionBlocked
from s26_source_first_runtime import build_governed_build_plan, build_source_model, execute_s26_source_first_profile_runtime
from semantic_binding_validator import SCHEMA as SEMANTIC_BINDING_SCHEMA, canonical_sha as semantic_canonical_sha, validate as validate_semantic_binding
from validate_profile_execution import canonical_json_sha256 as receipt_json_sha256, sha256_text

PROFILE_SOURCES = [
    {"ref": "profiles/ui_architect/SKILL.md", "content": "# UI Architect\nUse governed contract."},
]
INPUT = "Remedia B2B-CARGA-001 desde autoridad source-first."
CONTEXT_SHA = "a" * 64
CARD_SHA = "b" * 64


def make_fidelity():
    return build_source_fidelity_contract(
        source_ref="screens/B2B-CARGA-001",
        source_sha256="c" * 64,
        authority_kind="VISUAL_ONLY",
        extraction_confidence=1.0,
        critical_ambiguity=False,
        immutable_entities=[
            {
                "entity_id": "table.header.lote",
                "kind": "TABLE_COLUMN",
                "semantic_signature": {"label": "Lote", "position": 1},
            },
            {
                "entity_id": "table.header.nombre",
                "kind": "TABLE_COLUMN",
                "semantic_signature": {"label": "Nombre", "position": 2},
            },
        ],
        mutable_dimensions=["layout", "overflow_strategy", "spacing"],
    )


def make_contract(fidelity):
    return build_execution_contract(
        run_id="EXEC-S26-SOURCE-FIRST-TEST-001",
        profile_code="PERFIL-UI-ARCHITECT",
        profile_version="v1",
        objective="Remediate from bound source authority.",
        authorized_scope=["screen:B2B-CARGA-001"],
        current_gate="S26_SOURCE_FIRST_GOLDEN",
        allowed_actions=["READ_INPUT", "EVALUATE_UI", "EMIT_FINDINGS"],
        forbidden_actions=["MODIFY_PRODUCTION", "MERGE_MAIN", "ACQUIRE_MODEL_WEIGHTS"],
        required_checks=["ROUTER", "INPUT_GOVERNANCE", "SOURCE_FIDELITY", "PROFILE_CONTRACT"],
        required_evidence=["router", "input_governance", "source_fidelity", "profile_execution"],
        closure_conditions=["NO_P0_OPEN", "EVIDENCE_PERSISTED", "READBACK_PASS"],
        input_governance_ref="programacion.input_readiness_runs/221",
        card_refs_and_hashes=[{"ref": "decision_product_experience", "sha256": CARD_SHA}],
        adapter_ref="ADAPTER-LF-SHELL-PROFILE-20260827",
        context_fingerprint=CONTEXT_SHA,
        tool_permissions=["READ_GITHUB", "READ_SUPABASE"],
        executor_mode="GPT_NATIVE",
        source_fidelity_contract_ref=fidelity["source_ref"],
        source_fidelity_contract_sha256=fidelity["contract_sha256"],
    )


def make_package():
    fidelity = make_fidelity()
    model = build_source_model(
        run_id="EXEC-S26-SOURCE-FIRST-TEST-001",
        source_fidelity_contract=fidelity,
        observed_samples=[
            {
                "sample_id": "visual.selected_page.1",
                "source_ref": fidelity["source_ref"],
                "value_sha256": sha256_text("1"),
            }
        ],
        runtime_bindings=[
            {
                "binding_id": "pagination.current_page",
                "target": "current_page",
                "authority_ref": "LIVE_CURRENT_PAGE_OR_NOT_PREBOUND",
            },
            {
                "binding_id": "pagination.record_count",
                "target": "record_count",
                "authority_ref": "LIVE_FILTERED_RESULT_COUNT",
            },
        ],
    )
    plan = build_governed_build_plan(
        run_id="EXEC-S26-SOURCE-FIRST-TEST-001",
        source_model=model,
        source_fidelity_contract=fidelity,
    )
    return fidelity, model, plan


def make_semantic_binding(fidelity, artifact):
    binding = {
        "schema": SEMANTIC_BINDING_SCHEMA,
        "artifact_canonical_sha256": semantic_canonical_sha(artifact),
        "source_fidelity_contract_sha256": fidelity["contract_sha256"],
        "bindings": [
            {
                "entity_id": "table.header.lote",
                "artifact_pointer": "/composer_payload/headers/0",
                "signature_key": "label",
                "comparison": "EXACT",
            },
            {
                "entity_id": "table.header.nombre",
                "artifact_pointer": "/composer_payload/headers/1",
                "signature_key": "label",
                "comparison": "EXACT",
            },
        ],
        "dynamic_bindings": [
            {
                "binding_id": "record_count",
                "artifact_pointer": "/composer_payload/state/record_count_binding",
                "expected_binding": "LIVE_FILTERED_RESULT_COUNT",
            }
        ],
        "forbidden_render_literals": [
            {
                "literal_id": "record_count_literal",
                "artifact_pointer": "/composer_payload/state/record_count",
                "must_be_absent": True,
            }
        ],
    }
    binding["binding_sha256"] = semantic_canonical_sha(binding)
    return binding


class NativeAdapter:
    adapter_id = "chatgpt-native-current-context-v1"
    is_test_double = True

    def __init__(self):
        self.calls = 0

    def execute(self, request):
        self.calls += 1
        assert request["source_first_mode"] == "S26_SOURCE_FIRST_V1"
        assert request["source_model"]["observed_samples"][0]["classification"] == "OBSERVED_SAMPLE_ONLY"
        assert "value" not in request["source_model"]["observed_samples"][0]
        assert len(request["governed_build_plan"]["semantic_bindings"]) == 2
        assert request["governed_build_plan"]["observed_sample_policy"] == "NON_BINDING_EVIDENCE_ONLY"
        semantic_labels = [
            item["semantic_signature"]["label"]
            for item in request["source_fidelity_contract"]["immutable_entities"]
        ]
        return {
            "response_type": RESPONSE_TYPE,
            "raw_output": {
                "worker": "ui_architect",
                "output_type": "PRODUCTION_UI_SPEC",
                "deliverable_created": {"screen_definition": {"task_mode": "REMEDIATE_EXISTING"}},
                "composer_payload": {
                    "headers": semantic_labels,
                    "state": {"record_count_binding": "LIVE_FILTERED_RESULT_COUNT"},
                },
            },
            "runtime_attestation": {
                "provider": "OPENAI_CHATGPT_NATIVE",
                "model_id": "gpt-native-source-first-test",
                "run_id": "native-run-source-first-001",
                "attested_at": "2026-09-09T20:00:00+00:00",
                "adapter_id": self.adapter_id,
                "executor_mode": request["executor_mode"],
                "request_sha256": request["request_sha256"],
                "profile_source_sha256": request["profile_source_sha256"],
                "input_sha256": request["input_sha256"],
                "operation_code": request["operation_code"],
                "profile_code": request["profile_code"],
                "profile_slug": request["profile_slug"],
            },
        }


class NativeVerifier:
    verifier_id = "native-source-first-test-verifier"
    is_test_double = True

    def verify(self, *, request, response, adapter):
        response_sha = receipt_json_sha256(response)
        return {
            "verified": True,
            "verifier_id": self.verifier_id,
            "request_sha256": request["request_sha256"],
            "response_sha256": response_sha,
            "evidence_sha256": sha256_text(f"{request['request_sha256']}:{response_sha}"),
        }


def execute(fidelity, model, plan, contract=None, adapter=None):
    contract = make_contract(fidelity) if contract is None else contract
    adapter = NativeAdapter() if adapter is None else adapter
    result = execute_s26_source_first_profile_runtime(
        execution_contract=contract,
        source_fidelity_contract=fidelity,
        source_model=model,
        governed_build_plan=plan,
        execution_id=contract["run_id"],
        profile_code=contract["profile_code"],
        profile_slug="ui_architect",
        profile_sources=PROFILE_SOURCES,
        input_literal=INPUT,
        adapter=adapter,
        attestation_verifier=NativeVerifier(),
        allow_test_doubles=True,
    )
    return result, adapter


def reseal(payload, field):
    payload[field] = canonical_json_sha256({k: v for k, v in payload.items() if k != field})
    return payload


def expect_block(code, fn):
    try:
        fn()
    except RuntimeExecutionBlocked as exc:
        assert exc.code == code, (code, exc.code, exc.detail)
    else:
        raise AssertionError(f"expected block {code}")


def main():
    passed = 0
    fidelity, model, plan = make_package()
    result, adapter = execute(fidelity, model, plan)
    assert adapter.calls == 1
    assert result["source_first_mode"] == "S26_SOURCE_FIRST_V1"
    assert result["request"]["source_model_sha256"] == model["source_model_sha256"]
    assert result["request"]["governed_build_plan_sha256"] == plan["governed_build_plan_sha256"]
    passed += 1

    # Integration proof: semantic authority must survive the complete source-first
    # path into concrete render-facing artifact locations, not merely ride along as
    # request metadata.
    artifact = result["raw_output"]
    semantic_binding = make_semantic_binding(fidelity, artifact)
    assert validate_semantic_binding(fidelity, artifact, semantic_binding) == []
    passed += 1

    # A producer may recompute the artifact hash after mutating output, but it
    # still cannot manufacture semantic fidelity: the entity binding must fail.
    mutated_artifact = deepcopy(artifact)
    mutated_artifact["composer_payload"]["headers"][0] = "Código"
    mutated_binding = deepcopy(semantic_binding)
    mutated_binding["artifact_canonical_sha256"] = semantic_canonical_sha(mutated_artifact)
    mutated_binding["binding_sha256"] = semantic_canonical_sha(
        {k: v for k, v in mutated_binding.items() if k != "binding_sha256"}
    )
    mutation_errors = validate_semantic_binding(fidelity, mutated_artifact, mutated_binding)
    assert "SEMANTIC_BINDING_MISMATCH:table.header.lote" in mutation_errors, mutation_errors
    passed += 1

    broken_model = deepcopy(model)
    broken_model["protected_semantics"] = broken_model["protected_semantics"][:-1]
    reseal(broken_model, "source_model_sha256")
    adapter = NativeAdapter()
    expect_block("SOURCE_MODEL_INVALID", lambda: execute(fidelity, broken_model, plan, adapter=adapter))
    assert adapter.calls == 0
    passed += 1

    leaking_model = deepcopy(model)
    leaking_model["observed_samples"][0]["value"] = 1
    reseal(leaking_model, "source_model_sha256")
    adapter = NativeAdapter()
    expect_block("SOURCE_MODEL_INVALID", lambda: execute(fidelity, leaking_model, plan, adapter=adapter))
    assert adapter.calls == 0
    passed += 1

    broken_plan = deepcopy(plan)
    broken_plan["semantic_bindings"] = broken_plan["semantic_bindings"][:-1]
    reseal(broken_plan, "governed_build_plan_sha256")
    adapter = NativeAdapter()
    expect_block("GOVERNED_BUILD_PLAN_INVALID", lambda: execute(fidelity, model, broken_plan, adapter=adapter))
    assert adapter.calls == 0
    passed += 1

    # Freeze the original execution contract first; then mutate the supplied
    # authority. This proves the runtime rejects authority drift before any
    # adapter/model call instead of silently regenerating trust around it.
    original_contract = make_contract(fidelity)
    wrong_fidelity = deepcopy(fidelity)
    wrong_fidelity["source_ref"] = "screens/OTHER"
    reseal(wrong_fidelity, "contract_sha256")
    adapter = NativeAdapter()
    expect_block(
        "SOURCE_FIRST_SOURCE_FIDELITY_SHA_MISMATCH",
        lambda: execute(wrong_fidelity, model, plan, contract=original_contract, adapter=adapter),
    )
    assert adapter.calls == 0
    passed += 1

    wrong_run_model = deepcopy(model)
    wrong_run_model["run_id"] = "OTHER-RUN"
    reseal(wrong_run_model, "source_model_sha256")
    adapter = NativeAdapter()
    expect_block("SOURCE_MODEL_INVALID", lambda: execute(fidelity, wrong_run_model, plan, adapter=adapter))
    assert adapter.calls == 0
    passed += 1

    print(f"S26_SOURCE_FIRST_RUNTIME_TESTS_PASS {passed}/8")


if __name__ == "__main__":
    main()
