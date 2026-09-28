#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PLAN_PATH = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py"
ORCH_PATH = ROOT / "sandbox/lf_contract_gate_test/pase_orchestrator/pase_orchestrator_v1.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"FAIL_PASE_INTEGRATION_LOAD:{name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def flatten_carriers(carrier_controls):
    return {
        control: carrier
        for carrier, controls in carrier_controls.items()
        for control in controls
    }


def assert_dependency_order(orch, dispatch, required):
    registry = orch._load_registry()
    carrier_for = {
        control: row["carrier"]
        for row in dispatch["dispatches"]
        for control in row["controls"]
    }
    position = {row["carrier"]: row["sequence"] for row in dispatch["dispatches"]}
    required_set = set(required)
    for control in required:
        for dependency in registry[control]["dependencies"]:
            if dependency not in required_set:
                continue
            dep_carrier = carrier_for[dependency]
            target_carrier = carrier_for[control]
            if dep_carrier != target_carrier:
                assert position[dep_carrier] < position[target_carrier], (
                    dependency,
                    control,
                    position,
                )


def main() -> int:
    plan_mod = load_module("lf_ci_execution_plan_v2_replay", PLAN_PATH)
    orch = load_module("pase_orchestrator_v1_replay", ORCH_PATH)

    scenarios = [
        ("PROFILE_CHANGE", ["profiles/systemic_root_cause_repair_lf/SKILL.md"], False),
        ("SKILL_CHANGE", ["skills/learning_engine/SKILL.md"], False),
        ("MIGRATION_CHANGE", ["supabase/migrations/20991231235959_replay_probe.sql"], False),
        ("GCO_CHANGE", ["sandbox/lf_contract_gate_test/gate_check_observability/test_replay_probe.py"], False),
        ("S30_CHANGE", ["sandbox/lf_contract_gate_test/s30_replay_probe/test_probe.py"], False),
        ("CARRIER_SELF_CHANGE", [".github/workflows/validate-lf-packs.yml"], False),
        ("FULL_REGRESSION", ["profiles/systemic_root_cause_repair_lf/SKILL.md"], True),
    ]

    checks = 0
    for name, changed_paths, force_full in scenarios:
        plan = plan_mod.build_plan(
            changed_paths=changed_paths,
            lane_required_controls=[],
            lane_mode="FAST",
            repo_root=ROOT,
            force_full=force_full,
            force_full_reason="REPLAY_FULL_REGRESSION" if force_full else None,
        )
        dispatch = orch.build_dispatch_plan(plan)

        assert plan["coverage_complete"] is True, name
        assert dispatch["coverage_complete"] is True, name
        assert dispatch["governance_admin"] == plan["governance_admin"], name
        assert dispatch["governance_admin"]["super_admin"] == "LF_GOVERNANCE", name
        assert dispatch["governance_admin"]["binding_materialized"] is False, name
        assert dispatch["applicability_authority"] == "UPSTREAM_PLAN_ONLY", name
        assert dispatch["execution_semantics"] == "SEQUENTIAL_DELEGATION_ONLY", name
        assert dispatch["required_controls"] == plan["required_controls"], name
        assert dispatch["control_count"] == len(plan["required_controls"]), name

        expected = flatten_carriers(plan["carrier_controls"])
        observed = {
            control: row["carrier"]
            for row in dispatch["dispatches"]
            for control in row["controls"]
        }
        assert observed == expected, (name, expected, observed)
        assert len(observed) == len(plan["required_controls"]), name
        assert_dependency_order(orch, dispatch, plan["required_controls"])

        replay = orch.build_dispatch_plan(plan)
        assert replay == dispatch, name
        assert replay["dispatch_sha256"] == dispatch["dispatch_sha256"], name
        checks += 1

    baseline = plan_mod.build_plan(
        changed_paths=["profiles/systemic_root_cause_repair_lf/SKILL.md"],
        lane_required_controls=[],
        lane_mode="FAST",
        repo_root=ROOT,
    )

    wrong_admin = dict(baseline)
    wrong_admin["governance_admin"] = dict(baseline["governance_admin"])
    wrong_admin["governance_admin"]["super_admin"] = "OTHER_ADMIN"
    try:
        orch.build_dispatch_plan(wrong_admin)
    except orch.PaseOrchestratorError as exc:
        assert str(exc).startswith("FAIL_PASE_GOVERNANCE_ADMIN_IDENTITY"), str(exc)
    else:
        raise AssertionError("wrong governance admin did not fail closed")
    checks += 1

    future_binding = dict(baseline)
    future_binding["governance_admin"] = dict(baseline["governance_admin"])
    future_binding["governance_admin"]["binding_materialized"] = True
    try:
        orch.build_dispatch_plan(future_binding)
    except orch.PaseOrchestratorError as exc:
        assert str(exc).startswith("BLOCK_PASE_BINDING_MATERIALIZED_UNSUPPORTED"), str(exc)
    else:
        raise AssertionError("unsupported materialized binding did not block")
    checks += 1

    print(f"PASS_PASE_INTEGRATION_REPLAY_V1 scenarios={len(scenarios)} checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
