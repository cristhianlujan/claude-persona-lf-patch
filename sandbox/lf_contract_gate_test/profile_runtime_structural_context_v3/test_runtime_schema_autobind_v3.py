#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
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


def expect_ambiguous(runtime, profile_slug: str, repo: Path, work: Path) -> None:
    try:
        runtime._materialize_runtime_output_schema(profile_slug, repo, work)
    except runtime.RuntimeExecutionBlocked as exc:
        assert exc.code == "QUEUE_RUNTIME_SCHEMA_AMBIGUOUS", (exc.code, exc.detail)
        return
    raise AssertionError(f"expected ambiguous schema block for {profile_slug}")


def main() -> int:
    runtime = load(RUNTIME, "runtime_schema_autobind_v3")

    with tempfile.TemporaryDirectory() as td:
        expect_ambiguous(runtime, "product_director_lf", REPO, Path(td))

    with tempfile.TemporaryDirectory() as td:
        expect_ambiguous(runtime, "ui_architect", REPO, Path(td))

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
        single = schemas / "a.schema.json"
        single.write_text('{"type":"object"}\n', encoding="utf-8")
        work = Path(td) / "work"
        materialized = runtime._materialize_runtime_output_schema("p", fake_repo, work)
        assert materialized is not None
        assert materialized.read_bytes() == single.read_bytes(), "single schema must be copied byte-for-byte"

    with tempfile.TemporaryDirectory() as td:
        fake_repo = Path(td) / "repo"
        schemas = fake_repo / "profiles" / "p" / "schemas"
        schemas.mkdir(parents=True)
        (schemas / "a.schema.json").write_text('{"type":"object"}', encoding="utf-8")
        (schemas / "b.schema.json").write_text('{"type":"object","required":["x"]}', encoding="utf-8")
        expect_ambiguous(runtime, "p", fake_repo, Path(td) / "work")

    print(
        "RUNTIME_SCHEMA_AUTOBIND_V3_PASS "
        "ambiguous_blocked=true single_preserved=true explicit_quality_preserved=true schema_synthesis=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
