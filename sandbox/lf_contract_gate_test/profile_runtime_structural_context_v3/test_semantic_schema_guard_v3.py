#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
RUNTIME_DIR = REPO / "sandbox/lf_contract_gate_test/profile_execution_runtime"
RUNTIME = RUNTIME_DIR / "run_zero_cost_profile_request.py"
if str(RUNTIME_DIR) not in sys.path:
    sys.path.insert(0, str(RUNTIME_DIR))


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def output_types(schema: dict) -> set[str]:
    arms = schema.get("anyOf") if isinstance(schema.get("anyOf"), list) else [schema]
    result: set[str] = set()
    for arm in arms:
        assert isinstance(arm, dict)
        assert arm.get("type") == "object", "runtime schema must forbid bare scalar output"
        props = arm.get("properties") or {}
        output = props.get("output_type") or {}
        value = output.get("const")
        if isinstance(value, str):
            result.add(value)
    return result


def main() -> int:
    runtime = load(RUNTIME, "semantic_schema_guard_v3")

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        product_path = runtime._materialize_runtime_output_schema("product_director_lf", REPO, work)
        assert product_path is not None
        product = json.loads(product_path.read_text(encoding="utf-8"))
        assert product.get("x-lf-runtime-schema-source") == [
            "product_direction_spec.schema.json",
            "product_missing_input.schema.json",
        ]
        assert output_types(product) == {"PRODUCT_DIRECTION_SPEC", "PRODUCT_MISSING_INPUT_STATE"}
        product_arms = product["anyOf"]
        direction = next(
            arm for arm in product_arms
            if ((arm.get("properties") or {}).get("output_type") or {}).get("const") == "PRODUCT_DIRECTION_SPEC"
        )
        assert "deliverable_created" in direction.get("required", [])
        deliverable = (direction.get("properties") or {}).get("deliverable_created") or {}
        assert deliverable.get("type") == "object"
        assert "product_decision" in deliverable.get("required", [])
        assert "acceptance_criteria" in deliverable.get("required", [])
        assert "decision_lineage" in deliverable.get("required", [])

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        ui_path = runtime._materialize_runtime_output_schema("ui_architect", REPO, work)
        assert ui_path is not None
        ui = json.loads(ui_path.read_text(encoding="utf-8"))
        assert ui.get("x-lf-runtime-schema-source") == [
            "ui_focused_decision.schema.json",
            "ui_missing_input.schema.json",
            "ui_production_spec.schema.json",
        ]
        ui_types = output_types(ui)
        assert len(ui_types) == 3, ui_types

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        quality_path = runtime._materialize_runtime_output_schema("quality_pack", REPO, work)
        assert quality_path is not None
        quality = json.loads(quality_path.read_text(encoding="utf-8"))
        assert quality.get("type") == "object"
        assert isinstance(quality.get("required"), list) and quality["required"]

    print(
        "SEMANTIC_SCHEMA_GUARD_V3_PASS "
        "bare_scalar_forbidden=true product_substantive_required=true ui_object_union=true quality_object=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
