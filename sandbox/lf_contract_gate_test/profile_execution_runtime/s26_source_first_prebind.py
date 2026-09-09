#!/usr/bin/env python3
"""Fail-closed prebind gate for fresh S26 source-first executions.

A fresh S26 material run is not allowed to produce raw/composer/artifact output until
its execution contract, source-fidelity contract, source model, governed build plan,
and semantic binding plan are mutually bound and valid.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from profile_execution_contract import (
    canonical_json_sha256,
    validate_execution_contract,
    validate_source_fidelity_contract,
)
from s26_source_first_runtime import (
    SOURCE_FIRST_MODE,
    validate_governed_build_plan,
    validate_source_model,
)

PREBIND_SCHEMA = "S26_SOURCE_FIRST_PREBIND_RECEIPT_V1"
SEMANTIC_BINDING_PLAN_SCHEMA = "S26_SEMANTIC_BINDING_PLAN_V1"
SEMANTIC_BINDING_COMPARISONS = {"EXACT", "LIST_EXACT", "LIST_CONTAINS", "DICT_SUBSET"}
REQUIRED_JSON_FILES = {
    "execution_contract": "execution_contract.json",
    "source_fidelity_contract": "source_fidelity_contract.json",
    "source_model": "source_model.json",
    "governed_build_plan": "governed_build_plan.json",
    "semantic_binding_plan": "semantic_binding_plan.json",
}
MATERIAL_OUTPUT_FILENAMES = (
    "raw_output.json",
    "artifact_payload.json",
    "composer_payload.json",
)


class SourceFirstPrebindError(ValueError):
    def __init__(self, code: str, detail: str = "") -> None:
        self.code = code
        self.detail = detail
        super().__init__(code if not detail else f"{code}:{detail}")


def _load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SourceFirstPrebindError("PREBIND_REQUIRED_FILE_MISSING", path.name) from exc
    except json.JSONDecodeError as exc:
        raise SourceFirstPrebindError("PREBIND_JSON_INVALID", f"{path.name}:{exc.msg}") from exc


def _file_sha256(path: Path) -> str:
    import hashlib

    return hashlib.sha256(path.read_bytes()).hexdigest()


def _nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _json_pointer(value: Any) -> bool:
    return isinstance(value, str) and value.startswith("/") and len(value) > 1


def _validate_semantic_binding_plan(
    plan: Any,
    *,
    run_id: str,
    fidelity: dict[str, Any],
    source_model: dict[str, Any],
    build_plan: dict[str, Any],
) -> list[str]:
    if not isinstance(plan, dict):
        return ["SEMANTIC_BINDING_PLAN_NOT_OBJECT"]

    errors: list[str] = []
    if plan.get("schema") != SEMANTIC_BINDING_PLAN_SCHEMA:
        errors.append("SEMANTIC_BINDING_PLAN_SCHEMA_INVALID")
    if plan.get("mode") != SOURCE_FIRST_MODE:
        errors.append("SEMANTIC_BINDING_PLAN_MODE_INVALID")
    if plan.get("run_id") != run_id:
        errors.append("SEMANTIC_BINDING_PLAN_RUN_ID_MISMATCH")
    if plan.get("source_fidelity_contract_sha256") != fidelity.get("contract_sha256"):
        errors.append("SEMANTIC_BINDING_PLAN_SOURCE_FIDELITY_SHA_MISMATCH")
    if plan.get("source_model_sha256") != source_model.get("source_model_sha256"):
        errors.append("SEMANTIC_BINDING_PLAN_SOURCE_MODEL_SHA_MISMATCH")
    if plan.get("governed_build_plan_sha256") != build_plan.get("governed_build_plan_sha256"):
        errors.append("SEMANTIC_BINDING_PLAN_BUILD_PLAN_SHA_MISMATCH")
    if plan.get("observed_sample_policy") != build_plan.get("observed_sample_policy"):
        errors.append("SEMANTIC_BINDING_PLAN_OBSERVED_SAMPLE_POLICY_MISMATCH")

    protected = source_model.get("protected_semantics", [])
    protected_by_id = {
        item.get("entity_id"): item
        for item in protected
        if isinstance(item, dict) and _nonempty_string(item.get("entity_id"))
    }
    fidelity_by_id = {
        item.get("entity_id"): item
        for item in fidelity.get("immutable_entities", [])
        if isinstance(item, dict) and _nonempty_string(item.get("entity_id"))
    }
    expected_entity_ids = set(protected_by_id)

    bindings = plan.get("bindings")
    seen_entities: set[str] = set()
    if not isinstance(bindings, list) or not bindings:
        errors.append("SEMANTIC_BINDING_PLAN_BINDINGS_INVALID")
    else:
        for index, item in enumerate(bindings):
            prefix = f"SEMANTIC_BINDING_PLAN_BINDING_{index}"
            if not isinstance(item, dict):
                errors.append(prefix + "_NOT_OBJECT")
                continue
            entity_id = item.get("entity_id")
            if not _nonempty_string(entity_id):
                errors.append(prefix + "_ENTITY_ID_INVALID")
                continue
            if entity_id in seen_entities:
                errors.append("SEMANTIC_BINDING_PLAN_ENTITY_DUPLICATE:" + entity_id)
            seen_entities.add(entity_id)
            protected_item = protected_by_id.get(entity_id)
            fidelity_item = fidelity_by_id.get(entity_id)
            if protected_item is None or fidelity_item is None:
                errors.append("SEMANTIC_BINDING_PLAN_ENTITY_NOT_SOURCE_AUTHORIZED:" + entity_id)
                continue
            if item.get("source_entity_sha256") != protected_item.get("source_entity_sha256"):
                errors.append("SEMANTIC_BINDING_PLAN_ENTITY_SHA_MISMATCH:" + entity_id)
            if not _json_pointer(item.get("artifact_pointer")):
                errors.append("SEMANTIC_BINDING_PLAN_POINTER_INVALID:" + entity_id)
            signature_key = item.get("signature_key")
            signature = fidelity_item.get("semantic_signature")
            if not isinstance(signature, dict) or not _nonempty_string(signature_key) or signature_key not in signature:
                errors.append("SEMANTIC_BINDING_PLAN_SIGNATURE_KEY_INVALID:" + entity_id)
            if item.get("comparison") not in SEMANTIC_BINDING_COMPARISONS:
                errors.append("SEMANTIC_BINDING_PLAN_COMPARISON_INVALID:" + entity_id)

    missing_entities = sorted(expected_entity_ids - seen_entities)
    invented_entities = sorted(seen_entities - expected_entity_ids)
    for entity_id in missing_entities:
        errors.append("SEMANTIC_BINDING_PLAN_ENTITY_MISSING:" + entity_id)
    for entity_id in invented_entities:
        errors.append("SEMANTIC_BINDING_PLAN_ENTITY_INVENTED:" + entity_id)

    runtime_bindings = source_model.get("runtime_bindings", [])
    runtime_by_id = {
        item.get("binding_id"): item
        for item in runtime_bindings
        if isinstance(item, dict) and _nonempty_string(item.get("binding_id"))
    }
    expected_dynamic_ids = set(runtime_by_id)
    dynamic = plan.get("dynamic_bindings")
    seen_dynamic: set[str] = set()
    if not isinstance(dynamic, list):
        errors.append("SEMANTIC_BINDING_PLAN_DYNAMIC_BINDINGS_INVALID")
    else:
        for index, item in enumerate(dynamic):
            prefix = f"SEMANTIC_BINDING_PLAN_DYNAMIC_{index}"
            if not isinstance(item, dict):
                errors.append(prefix + "_NOT_OBJECT")
                continue
            binding_id = item.get("binding_id")
            if not _nonempty_string(binding_id):
                errors.append(prefix + "_ID_INVALID")
                continue
            if binding_id in seen_dynamic:
                errors.append("SEMANTIC_BINDING_PLAN_DYNAMIC_DUPLICATE:" + binding_id)
            seen_dynamic.add(binding_id)
            source_binding = runtime_by_id.get(binding_id)
            if source_binding is None:
                errors.append("SEMANTIC_BINDING_PLAN_DYNAMIC_INVENTED:" + binding_id)
                continue
            if item.get("expected_binding") != source_binding.get("authority_ref"):
                errors.append("SEMANTIC_BINDING_PLAN_DYNAMIC_AUTHORITY_MISMATCH:" + binding_id)
            if not _json_pointer(item.get("artifact_pointer")):
                errors.append("SEMANTIC_BINDING_PLAN_DYNAMIC_POINTER_INVALID:" + binding_id)
            if not _json_pointer(item.get("forbidden_literal_pointer")):
                errors.append("SEMANTIC_BINDING_PLAN_FORBIDDEN_POINTER_INVALID:" + binding_id)
            if item.get("artifact_pointer") == item.get("forbidden_literal_pointer"):
                errors.append("SEMANTIC_BINDING_PLAN_DYNAMIC_POINTER_COLLISION:" + binding_id)

    for binding_id in sorted(expected_dynamic_ids - seen_dynamic):
        errors.append("SEMANTIC_BINDING_PLAN_DYNAMIC_MISSING:" + binding_id)
    for binding_id in sorted(seen_dynamic - expected_dynamic_ids):
        errors.append("SEMANTIC_BINDING_PLAN_DYNAMIC_INVENTED:" + binding_id)

    claimed_sha = plan.get("semantic_binding_plan_sha256")
    if not _nonempty_string(claimed_sha):
        errors.append("SEMANTIC_BINDING_PLAN_SHA256_INVALID")
    else:
        expected_sha = canonical_json_sha256(
            {key: value for key, value in plan.items() if key != "semantic_binding_plan_sha256"}
        )
        if claimed_sha != expected_sha:
            errors.append("SEMANTIC_BINDING_PLAN_SHA256_MISMATCH")
    return sorted(set(errors))


def validate_prebind(evidence_dir: Path) -> dict[str, Any]:
    evidence_dir = evidence_dir.resolve()
    if not evidence_dir.is_dir():
        raise SourceFirstPrebindError("PREBIND_EVIDENCE_DIR_MISSING", str(evidence_dir))

    material_present = [name for name in MATERIAL_OUTPUT_FILENAMES if (evidence_dir / name).exists()]
    if material_present:
        raise SourceFirstPrebindError(
            "PREBIND_MATERIAL_OUTPUT_ALREADY_PRESENT",
            ",".join(sorted(material_present)),
        )

    paths = {key: evidence_dir / name for key, name in REQUIRED_JSON_FILES.items()}
    payloads = {key: _load_json(path) for key, path in paths.items()}

    execution_contract = payloads["execution_contract"]
    fidelity = payloads["source_fidelity_contract"]
    source_model = payloads["source_model"]
    build_plan = payloads["governed_build_plan"]
    semantic_binding_plan = payloads["semantic_binding_plan"]

    contract_errors = validate_execution_contract(execution_contract)
    if contract_errors:
        raise SourceFirstPrebindError("PREBIND_EXECUTION_CONTRACT_INVALID", ",".join(contract_errors))

    fidelity_errors = validate_source_fidelity_contract(fidelity)
    if fidelity_errors:
        raise SourceFirstPrebindError("PREBIND_SOURCE_FIDELITY_INVALID", ",".join(fidelity_errors))

    run_id = execution_contract["run_id"]
    if execution_contract.get("source_fidelity_contract_ref") != fidelity.get("source_ref"):
        raise SourceFirstPrebindError("PREBIND_SOURCE_FIDELITY_REF_MISMATCH")
    if execution_contract.get("source_fidelity_contract_sha256") != fidelity.get("contract_sha256"):
        raise SourceFirstPrebindError("PREBIND_SOURCE_FIDELITY_SHA_MISMATCH")

    source_model_errors = validate_source_model(
        source_model,
        run_id=run_id,
        source_fidelity_contract=fidelity,
    )
    if source_model_errors:
        raise SourceFirstPrebindError("PREBIND_SOURCE_MODEL_INVALID", ",".join(source_model_errors))

    plan_errors = validate_governed_build_plan(
        build_plan,
        run_id=run_id,
        source_model=source_model,
        source_fidelity_contract=fidelity,
    )
    if plan_errors:
        raise SourceFirstPrebindError("PREBIND_GOVERNED_BUILD_PLAN_INVALID", ",".join(plan_errors))

    semantic_plan_errors = _validate_semantic_binding_plan(
        semantic_binding_plan,
        run_id=run_id,
        fidelity=fidelity,
        source_model=source_model,
        build_plan=build_plan,
    )
    if semantic_plan_errors:
        raise SourceFirstPrebindError("PREBIND_SEMANTIC_BINDING_PLAN_INVALID", ",".join(semantic_plan_errors))

    receipt: dict[str, Any] = {
        "schema": PREBIND_SCHEMA,
        "mode": SOURCE_FIRST_MODE,
        "run_id": run_id,
        "profile_code": execution_contract["profile_code"],
        "execution_contract_sha256": execution_contract["contract_sha256"],
        "source_fidelity_contract_sha256": fidelity["contract_sha256"],
        "source_model_sha256": source_model["source_model_sha256"],
        "governed_build_plan_sha256": build_plan["governed_build_plan_sha256"],
        "semantic_binding_plan_sha256": semantic_binding_plan["semantic_binding_plan_sha256"],
        "input_file_sha256": {key: _file_sha256(path) for key, path in sorted(paths.items())},
        "material_output_absent": True,
        "next_phase": "MATERIAL_BUILD",
        "golden_declared": False,
        "promotion_authorized": False,
    }
    receipt["prebind_receipt_sha256"] = canonical_json_sha256(receipt)
    return receipt


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("evidence_dir", type=Path)
    args = parser.parse_args()
    try:
        receipt = validate_prebind(args.evidence_dir)
    except SourceFirstPrebindError as exc:
        print(json.dumps({"valid": False, "code": exc.code, "detail": exc.detail}, ensure_ascii=False))
        return 1
    print(json.dumps({"valid": True, "receipt": receipt}, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
