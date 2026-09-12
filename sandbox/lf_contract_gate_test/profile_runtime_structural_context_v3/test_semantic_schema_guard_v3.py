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


def schema_arms(schema: dict) -> list[dict]:
    arms = schema.get("anyOf") if isinstance(schema.get("anyOf"), list) else [schema]
    assert arms
    for arm in arms:
        assert isinstance(arm, dict)
        assert arm.get("type") == "object", "runtime schema must forbid bare scalar output"
        required = arm.get("required")
        assert isinstance(required, list) and required, "runtime schema arm must require substantive fields"
    return arms


def product_output_types(schema: dict) -> set[str]:
    result: set[str] = set()
    for arm in schema_arms(schema):
        props = arm.get("properties") or {}
        output = props.get("output_type") or {}
        value = output.get("const")
        if isinstance(value, str):
            result.add(value)
    return result


def expect_ambiguous(runtime, profile_slug: str, work: Path) -> None:
    try:
        runtime._materialize_runtime_output_schema(profile_slug, REPO, work)
    except runtime.RuntimeExecutionBlocked as exc:
        assert exc.code == "QUEUE_RUNTIME_SCHEMA_AMBIGUOUS", (exc.code, exc.detail)
        return
    raise AssertionError(f"expected fail-closed ambiguous schema block for {profile_slug}")


def read_canonical(profile_slug: str, filename: str) -> dict:
    path = REPO / "profiles" / profile_slug / "schemas" / filename
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    runtime = load(RUNTIME, "semantic_schema_guard_v3")

    # Multiple canonical schemas remain individually substantive, but AUTO must
    # never synthesize them into a new runtime contract. Selection must be explicit.
    with tempfile.TemporaryDirectory() as td:
        expect_ambiguous(runtime, "product_director_lf", Path(td))
    product_direction = read_canonical("product_director_lf", "product_direction_spec.schema.json")
    product_missing = read_canonical("product_director_lf", "product_missing_input.schema.json")
    assert product_output_types(product_direction) == {"PRODUCT_DIRECTION_SPEC"}
    assert product_output_types(product_missing) == {"PRODUCT_MISSING_INPUT_STATE"}
    direction = schema_arms(product_direction)[0]
    assert "deliverable_created" in direction.get("required", [])
    deliverable = (direction.get("properties") or {}).get("deliverable_created") or {}
    assert deliverable.get("type") == "object"
    assert "product_decision" in deliverable.get("required", [])
    assert "acceptance_criteria" in deliverable.get("required", [])
    assert "decision_lineage" in deliverable.get("required", [])

    with tempfile.TemporaryDirectory() as td:
        expect_ambiguous(runtime, "ui_architect", Path(td))
    ui_files = [
        "ui_focused_decision.schema.json",
        "ui_missing_input.schema.json",
        "ui_production_spec.schema.json",
    ]
    ui_arms = []
    for filename in ui_files:
        ui_arms.extend(schema_arms(read_canonical("ui_architect", filename)))
    assert len(ui_arms) == 3
    assert all(len(arm.get("required", [])) >= 2 for arm in ui_arms)
    assert max(len(arm.get("required", [])) for arm in ui_arms) >= 10

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        quality_path = runtime._materialize_runtime_output_schema("quality_pack", REPO, work)
        assert quality_path is not None
        quality = json.loads(quality_path.read_text(encoding="utf-8"))
        quality_arms = schema_arms(quality)
        assert len(quality_arms) == 1

    print(
        "SEMANTIC_SCHEMA_GUARD_V3_PASS "
        "bare_scalar_forbidden=true product_substantive_required=true "
        "ui_substantive_schemas=true ambiguous_auto_blocked=true quality_object=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
