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


def main() -> int:
    runtime = load(RUNTIME, "runtime_schema_autobind_v3")

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        product = runtime._materialize_runtime_output_schema("product_director_lf", REPO, work)
        assert product is not None and product.is_file()
        product_payload = json.loads(product.read_text(encoding="utf-8"))
        product_sources = product_payload.get("x-lf-runtime-schema-source")
        assert product_sources == ["product_direction_spec.schema.json", "product_missing_input.schema.json"], product_sources
        assert len(product_payload.get("anyOf", [])) == 2

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        ui = runtime._materialize_runtime_output_schema("ui_architect", REPO, work)
        assert ui is not None and ui.is_file()
        ui_payload = json.loads(ui.read_text(encoding="utf-8"))
        ui_sources = ui_payload.get("x-lf-runtime-schema-source")
        assert ui_sources == [
            "ui_focused_decision.schema.json",
            "ui_missing_input.schema.json",
            "ui_production_spec.schema.json",
        ], ui_sources
        assert len(ui_payload.get("anyOf", [])) == 3

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        quality = runtime._materialize_runtime_output_schema("quality_pack", REPO, work)
        assert quality is not None and quality.is_file()
        canonical = REPO / "profiles/quality_pack/schemas/runtime_output.schema.json"
        assert quality.read_bytes() == canonical.read_bytes(), "explicit runtime schema bytes must remain unchanged"

    with tempfile.TemporaryDirectory() as td:
        fake_repo = Path(td) / "repo"
        schemas = fake_repo / "profiles" / "p" / "schemas"
        schemas.mkdir(parents=True)
        (schemas / "a.schema.json").write_text('{"type":"object"}', encoding="utf-8")
        (schemas / "b.schema.json").write_text('{"type":"object","required":["x"]}', encoding="utf-8")
        work = Path(td) / "work"
        synthesized = runtime._materialize_runtime_output_schema("p", fake_repo, work)
        assert synthesized is not None
        payload = json.loads(synthesized.read_text(encoding="utf-8"))
        assert payload["x-lf-runtime-schema-source"] == ["a.schema.json", "b.schema.json"]
        assert len(payload["anyOf"]) == 2

    print("RUNTIME_SCHEMA_AUTOBIND_V3_PASS product=2 ui=3 explicit_quality_preserved=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
