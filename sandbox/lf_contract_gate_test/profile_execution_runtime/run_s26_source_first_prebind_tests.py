#!/usr/bin/env python3
from copy import deepcopy
import json
from pathlib import Path
import tempfile

from profile_execution_contract import build_execution_contract, build_source_fidelity_contract, canonical_json_sha256
from s26_source_first_prebind import SourceFirstPrebindError, validate_prebind
from s26_source_first_runtime import build_governed_build_plan, build_source_model

RUN_ID = "EXEC-S26-SOURCE-FIRST-PREBIND-TEST-001"


def build_binding_plan(fidelity, model, plan):
    source_entities = {item["entity_id"]: item for item in model["protected_semantics"]}
    binding_plan = {
        "schema": "S26_SEMANTIC_BINDING_PLAN_V1",
        "mode": "S26_SOURCE_FIRST_V1",
        "run_id": RUN_ID,
        "source_fidelity_contract_sha256": fidelity["contract_sha256"],
        "source_model_sha256": model["source_model_sha256"],
        "governed_build_plan_sha256": plan["governed_build_plan_sha256"],
        "observed_sample_policy": "NON_BINDING_EVIDENCE_ONLY",
        "bindings": [
            {
                "entity_id": "table.header.lote",
                "source_entity_sha256": source_entities["table.header.lote"]["source_entity_sha256"],
                "artifact_pointer": "/composer_payload/headers/0",
                "signature_key": "label",
                "comparison": "EXACT",
            },
            {
                "entity_id": "table.header.nombre",
                "source_entity_sha256": source_entities["table.header.nombre"]["source_entity_sha256"],
                "artifact_pointer": "/composer_payload/headers/1",
                "signature_key": "label",
                "comparison": "EXACT",
            },
        ],
        "dynamic_bindings": [
            {
                "binding_id": "pagination.record_count",
                "artifact_pointer": "/composer_payload/state/record_count_binding",
                "expected_binding": "LIVE_FILTERED_RESULT_COUNT",
                "forbidden_literal_pointer": "/composer_payload/state/record_count",
            }
        ],
    }
    binding_plan["semantic_binding_plan_sha256"] = canonical_json_sha256(binding_plan)
    return binding_plan


def build_package():
    fidelity = build_source_fidelity_contract(
        source_ref="screens/B2B-CARGA-001",
        source_sha256="c" * 64,
        authority_kind="VISUAL_ONLY",
        extraction_confidence=1.0,
        critical_ambiguity=False,
        immutable_entities=[
            {"entity_id":"table.header.lote","kind":"TABLE_COLUMN","semantic_signature":{"label":"Lote","position":1}},
            {"entity_id":"table.header.nombre","kind":"TABLE_COLUMN","semantic_signature":{"label":"Nombre","position":2}},
        ],
        mutable_dimensions=["layout","overflow_strategy","spacing"],
    )
    contract = build_execution_contract(
        run_id=RUN_ID,
        profile_code="PERFIL-UI-ARCHITECT",
        profile_version="v1",
        objective="Fresh source-first prebind test.",
        authorized_scope=["screen:B2B-CARGA-001"],
        current_gate="S26_SOURCE_FIRST_GOLDEN",
        allowed_actions=["READ_INPUT","EVALUATE_UI","EMIT_FINDINGS"],
        forbidden_actions=["MODIFY_PRODUCTION","MERGE_MAIN","ACQUIRE_MODEL_WEIGHTS"],
        required_checks=["ROUTER","INPUT_GOVERNANCE","SOURCE_FIDELITY","PROFILE_CONTRACT"],
        required_evidence=["router","input_governance","source_fidelity","profile_execution"],
        closure_conditions=["NO_P0_OPEN","EVIDENCE_PERSISTED","READBACK_PASS"],
        input_governance_ref="programacion.input_readiness_runs/221",
        card_refs_and_hashes=[],
        card_resolution={
            "mode":"GENERIC_SAFE",
            "critical_authority_missing":False,
            "unresolved_capabilities":[],
            "core_policy_ref":"profiles/ui_architect/SKILL.md",
            "core_policy_sha256":"d"*64,
            "fallback_reason":"No specialized Card required for prebind fixture.",
        },
        adapter_ref="ADAPTER-LF-SHELL-PROFILE-20260827",
        context_fingerprint="a"*64,
        tool_permissions=["READ_GITHUB","READ_SUPABASE"],
        executor_mode="GPT_NATIVE",
        source_fidelity_contract_ref=fidelity["source_ref"],
        source_fidelity_contract_sha256=fidelity["contract_sha256"],
    )
    model = build_source_model(
        run_id=RUN_ID,
        source_fidelity_contract=fidelity,
        observed_samples=[],
        runtime_bindings=[
            {"binding_id":"pagination.record_count","target":"record_count","authority_ref":"LIVE_FILTERED_RESULT_COUNT"}
        ],
    )
    plan = build_governed_build_plan(
        run_id=RUN_ID,
        source_model=model,
        source_fidelity_contract=fidelity,
    )
    binding_plan = build_binding_plan(fidelity, model, plan)
    return contract, fidelity, model, plan, binding_plan


def write_package(root: Path, contract, fidelity, model, plan, binding_plan):
    for name, value in (
        ("execution_contract.json", contract),
        ("source_fidelity_contract.json", fidelity),
        ("source_model.json", model),
        ("governed_build_plan.json", plan),
        ("semantic_binding_plan.json", binding_plan),
    ):
        (root/name).write_text(json.dumps(value, ensure_ascii=False, sort_keys=True), encoding="utf-8")


def reseal(payload, field):
    payload[field] = canonical_json_sha256({k:v for k,v in payload.items() if k != field})


def expect(code, fn):
    try:
        fn()
    except SourceFirstPrebindError as exc:
        assert exc.code == code, (code, exc.code, exc.detail)
    else:
        raise AssertionError(f"expected {code}")


def main():
    passed=0
    contract,fidelity,model,plan,binding_plan=build_package()

    with tempfile.TemporaryDirectory() as td:
        root=Path(td);write_package(root,contract,fidelity,model,plan,binding_plan)
        receipt=validate_prebind(root)
        assert receipt["material_output_absent"] is True
        assert receipt["next_phase"] == "MATERIAL_BUILD"
        assert receipt["golden_declared"] is False
        assert receipt["promotion_authorized"] is False
        assert receipt["semantic_binding_plan_sha256"] == binding_plan["semantic_binding_plan_sha256"]
        passed+=1

    with tempfile.TemporaryDirectory() as td:
        root=Path(td);write_package(root,contract,fidelity,model,plan,binding_plan);(root/"raw_output.json").write_text("{}",encoding="utf-8")
        expect("PREBIND_MATERIAL_OUTPUT_ALREADY_PRESENT",lambda:validate_prebind(root));passed+=1

    with tempfile.TemporaryDirectory() as td:
        root=Path(td);write_package(root,contract,fidelity,model,plan,binding_plan);(root/"source_model.json").unlink()
        expect("PREBIND_REQUIRED_FILE_MISSING",lambda:validate_prebind(root));passed+=1

    with tempfile.TemporaryDirectory() as td:
        root=Path(td);bad=deepcopy(model);bad["protected_semantics"]=bad["protected_semantics"][:-1];reseal(bad,"source_model_sha256");write_package(root,contract,fidelity,bad,plan,binding_plan)
        expect("PREBIND_SOURCE_MODEL_INVALID",lambda:validate_prebind(root));passed+=1

    with tempfile.TemporaryDirectory() as td:
        root=Path(td);bad=deepcopy(plan);bad["semantic_bindings"]=bad["semantic_bindings"][:-1];reseal(bad,"governed_build_plan_sha256");write_package(root,contract,fidelity,model,bad,binding_plan)
        expect("PREBIND_GOVERNED_BUILD_PLAN_INVALID",lambda:validate_prebind(root));passed+=1

    with tempfile.TemporaryDirectory() as td:
        root=Path(td);bad=deepcopy(contract);bad["source_fidelity_contract_sha256"]="e"*64;reseal(bad,"contract_sha256");write_package(root,bad,fidelity,model,plan,binding_plan)
        expect("PREBIND_SOURCE_FIDELITY_SHA_MISMATCH",lambda:validate_prebind(root));passed+=1

    with tempfile.TemporaryDirectory() as td:
        root=Path(td);write_package(root,contract,fidelity,model,plan,binding_plan);(root/"semantic_binding_plan.json").unlink()
        expect("PREBIND_REQUIRED_FILE_MISSING",lambda:validate_prebind(root));passed+=1

    with tempfile.TemporaryDirectory() as td:
        root=Path(td);bad=deepcopy(binding_plan);bad["bindings"]=bad["bindings"][:-1];reseal(bad,"semantic_binding_plan_sha256");write_package(root,contract,fidelity,model,plan,bad)
        expect("PREBIND_SEMANTIC_BINDING_PLAN_INVALID",lambda:validate_prebind(root));passed+=1

    with tempfile.TemporaryDirectory() as td:
        root=Path(td);bad=deepcopy(binding_plan);bad["dynamic_bindings"][0]["expected_binding"]="STATIC_6";reseal(bad,"semantic_binding_plan_sha256");write_package(root,contract,fidelity,model,plan,bad)
        expect("PREBIND_SEMANTIC_BINDING_PLAN_INVALID",lambda:validate_prebind(root));passed+=1

    with tempfile.TemporaryDirectory() as td:
        root=Path(td);bad=deepcopy(binding_plan);bad["observed_sample_policy"]="RENDER_AS_STATIC";reseal(bad,"semantic_binding_plan_sha256");write_package(root,contract,fidelity,model,plan,bad)
        expect("PREBIND_SEMANTIC_BINDING_PLAN_INVALID",lambda:validate_prebind(root));passed+=1

    print(f"S26_SOURCE_FIRST_PREBIND_TESTS_PASS {passed}/10")


if __name__ == "__main__":
    main()
