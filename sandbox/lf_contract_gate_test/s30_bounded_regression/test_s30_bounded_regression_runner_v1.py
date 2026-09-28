#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
RUNNER = HERE / "run_s30_bounded_regression_v1.py"
CONTRACT = HERE / "s30_bounded_regression_runner_v1.json"


def load_runner():
    spec = importlib.util.spec_from_file_location("s30_bounded_runner", RUNNER)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    runner = load_runner()
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    checks = 0

    assert contract["durable_name"] == "S30_BOUNDED_REGRESSION_OWNER_RUNNER_V1"; checks += 1
    assert contract["owner"] == "S30_BOUNDED_REGRESSION"; checks += 1
    assert contract["input_contract"]["must_not_decide_run_skip"] is True; checks += 1
    assert contract["handoff"] == "PASE_ORCHESTRATOR_BIND_S30_BOUNDED_REGRESSION"; checks += 1
    assert contract["merge_authorized"] is False and contract["deployment_authorized"] is False and contract["production_authorized"] is False; checks += 1

    real = runner.discover_tests(ROOT)
    assert real == sorted(real, key=lambda p: p.as_posix())
    assert real, "expected existing S30 regression corpus"
    assert all(p.parent.name != "s30_bounded_regression" for p in real); checks += 1

    source = RUNNER.read_text(encoding="utf-8")
    forbidden_execution_tokens = (
        ".github/workflows/",
        "emit_ci_execution_plan_v2.py",
        "lf_ci_execution_plan_v2.py",
        "validate_pack.py",
        "services/profile_runtime_api/",
        "git push",
        "psql ",
        "supabase db",
        "supabase functions",
    )
    lowered = source.lower()
    for token in forbidden_execution_tokens:
        assert token.lower() not in lowered, token
    checks += 1

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        base = root / "sandbox" / "lf_contract_gate_test"
        a = base / "s30_alpha" / "test_b.py"
        b = base / "s30_beta" / "test_a.py"
        self_test = base / "s30_bounded_regression" / "test_self.py"
        ignored = base / "not_s30" / "test_ignored.py"
        for path in (a, b, self_test, ignored):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("raise SystemExit(0)\n", encoding="utf-8")
        got = [p.relative_to(root).as_posix() for p in runner.discover_tests(root)]
        assert got == [
            "sandbox/lf_contract_gate_test/s30_alpha/test_b.py",
            "sandbox/lf_contract_gate_test/s30_beta/test_a.py",
        ]; checks += 1

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        base = root / "sandbox" / "lf_contract_gate_test"
        good = base / "s30_alpha" / "test_good.py"
        good.parent.mkdir(parents=True, exist_ok=True)
        good.write_text("raise SystemExit(0)\n", encoding="utf-8")
        results = runner.run_tests(root)
        assert len(results) == 1 and results[0].returncode == 0; checks += 1

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        try:
            runner.run_tests(root)
        except runner.S30BoundedRegressionError as exc:
            assert str(exc) == "BLOCK_S30_SANDBOX_REGRESSION_MISSING"
        else:
            raise AssertionError("empty corpus must fail closed")
        checks += 1

    print(f"S30_BOUNDED_REGRESSION_OWNER_RUNNER_V1=PASS {checks}/10")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
