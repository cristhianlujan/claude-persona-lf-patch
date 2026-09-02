#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
RUNTIME = REPO / "sandbox/lf_contract_gate_test/profile_execution_runtime/run_zero_cost_profile_request.py"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    runtime = load(RUNTIME, "runtime_schema_binding_v3")
    canonical = REPO / "profiles/quality_pack/schemas/quality_review.schema.json"
    runtime_alias = REPO / "profiles/quality_pack/schemas/runtime_output.schema.json"
    assert canonical.is_file() and runtime_alias.is_file()
    assert sha(canonical) == sha(runtime_alias), "runtime schema must remain byte-identical to canonical quality_review"
    with tempfile.TemporaryDirectory() as td:
        copied = runtime._materialize_runtime_output_schema("quality_pack", REPO, Path(td))
        assert copied is not None and copied.is_file()
        assert sha(copied) == sha(canonical)
    print("QUALITY_RUNTIME_SCHEMA_BINDING_V3_PASS canonical=quality_review runtime=runtime_output")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
