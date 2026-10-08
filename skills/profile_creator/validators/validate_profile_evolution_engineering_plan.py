#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


FORBIDDEN_VALIDATOR_STATES = {"MISSING", "RETIRED"}
ALLOWED_CHECKPOINT_STATUS = {"PENDING_FRESH_VALIDATION", "DONE", "NOT_APPLICABLE"}


def evaluate(plan: dict[str, Any], registry: dict[str, Any], repo_root: Path) -> dict[str, Any]:
    blockers: list[str] = []
    warnings: list[str] = []

    if plan.get("schema") != "PROFILE_EVOLUTION_ENGINEERING_PLAN_V1":
        blockers.append("PLAN_SCHEMA_INVALID")
    if registry.get("schema") != "PROFILE_EVOLUTION_VALIDATOR_REGISTRY_V1":
        blockers.append("VALIDATOR_REGISTRY_SCHEMA_INVALID")

    validators = {
        x.get("validator_code"): x
        for x in registry.get("validators", [])
        if isinstance(x, dict) and isinstance(x.get("validator_code"), str)
    }
    units = plan.get("units")
    if not isinstance(units, list) or not units:
        blockers.append("PLAN_UNITS_EMPTY")
        units = []

    unit_codes = [u.get("unit_code") for u in units if isinstance(u, dict)]
    if len(unit_codes) != len(set(unit_codes)):
        blockers.append("PLAN_UNIT_DUPLICATE")

    known_units = set(unit_codes)
    graph: dict[str, list[str]] = {}
    checkpoint_total = 0
    required_total = 0

    for unit in units:
        if not isinstance(unit, dict):
            blockers.append("PLAN_UNIT_INVALID")
            continue
        code = unit.get("unit_code")
        deps = unit.get("depends_on", [])
        if not isinstance(deps, list):
            blockers.append(f"{code}:DEPENDENCIES_INVALID")
            deps = []
        graph[str(code)] = [str(x) for x in deps]
        for dep in deps:
            if dep not in known_units:
                blockers.append(f"{code}:DEPENDENCY_UNKNOWN:{dep}")

        checkpoints = unit.get("checkpoints")
        if not isinstance(checkpoints, list) or not checkpoints:
            blockers.append(f"{code}:CHECKPOINTS_EMPTY")
            continue
        cp_codes = [c.get("checkpoint_code") for c in checkpoints if isinstance(c, dict)]
        if len(cp_codes) != len(set(cp_codes)):
            blockers.append(f"{code}:CHECKPOINT_DUPLICATE")

        for cp in checkpoints:
            if not isinstance(cp, dict):
                blockers.append(f"{code}:CHECKPOINT_INVALID")
                continue
            checkpoint_total += 1
            if cp.get("required") is True:
                required_total += 1
            cpc = cp.get("checkpoint_code")
            if cp.get("status") not in ALLOWED_CHECKPOINT_STATUS:
                blockers.append(f"{code}.{cpc}:STATUS_INVALID")
            vcode = cp.get("validator_code")
            if not isinstance(vcode, str) or not vcode:
                blockers.append(f"{code}.{cpc}:VALIDATOR_MISSING")
                continue
            val = validators.get(vcode)
            if not val:
                blockers.append(f"{code}.{cpc}:VALIDATOR_UNREGISTERED:{vcode}")
                continue
            if val.get("deterministic") is not True:
                blockers.append(f"{code}.{cpc}:VALIDATOR_NONDETERMINISTIC:{vcode}")
            if val.get("state") in FORBIDDEN_VALIDATOR_STATES:
                blockers.append(f"{code}.{cpc}:VALIDATOR_UNUSABLE:{vcode}")
            source_ref = val.get("source_ref")
            if not isinstance(source_ref, str) or not source_ref:
                blockers.append(f"{code}.{cpc}:VALIDATOR_SOURCE_REF_MISSING:{vcode}")
            elif not source_ref.startswith(("docs/", "skills/", "sandbox/", "supabase/")):
                blockers.append(f"{code}.{cpc}:VALIDATOR_SOURCE_NOT_GITHUB_PATH:{vcode}")
            elif not (repo_root / source_ref.split(" --self-test", 1)[0]).exists():
                warnings.append(f"{code}.{cpc}:VALIDATOR_SOURCE_NOT_PRESENT_IN_LOCAL_SNAPSHOT:{source_ref}")
            if not isinstance(cp.get("validation_input"), dict):
                blockers.append(f"{code}.{cpc}:VALIDATION_INPUT_NOT_OBJECT")
            if cp.get("pass_when") in (None, "", {}, []):
                blockers.append(f"{code}.{cpc}:PASS_CONDITION_MISSING")
            if not cp.get("failure_code"):
                blockers.append(f"{code}.{cpc}:FAILURE_CODE_MISSING")
            if not cp.get("resolver_policy"):
                blockers.append(f"{code}.{cpc}:RESOLVER_POLICY_MISSING")

    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(node: str) -> None:
        if node in visiting:
            blockers.append(f"DEPENDENCY_CYCLE:{node}")
            return
        if node in visited:
            return
        visiting.add(node)
        for dep in graph.get(node, []):
            visit(dep)
        visiting.remove(node)
        visited.add(node)

    for node in graph:
        visit(node)

    policy = plan.get("execution_policy", {})
    if policy.get("previous_pass_reuse_forbidden") is not True:
        blockers.append("PREVIOUS_PASS_REUSE_NOT_FORBIDDEN")
    if policy.get("title_inference_forbidden") is not True:
        blockers.append("TITLE_INFERENCE_NOT_FORBIDDEN")
    if policy.get("generic_or_transversal_first") is not True:
        blockers.append("TRANSVERSAL_REUSE_NOT_REQUIRED")
    if plan.get("storage_model", {}).get("programming_specific_tables_reused") is not False:
        blockers.append("PROGRAMMING_RUNTIME_TABLE_INVASION")

    return {
        "schema": "PROFILE_EVOLUTION_ENGINEERING_PLAN_VALIDATION_V1",
        "status": "PASS" if not blockers else "FAIL",
        "blocking_codes": sorted(set(blockers)),
        "warnings": sorted(set(warnings)),
        "unit_count": len(units),
        "checkpoint_count": checkpoint_total,
        "required_checkpoint_count": required_total,
        "registered_validator_count": len(validators),
    }


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print("usage: validate_profile_evolution_engineering_plan.py <plan.json> <registry.json> [repo_root]", file=sys.stderr)
        return 2
    plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    registry = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    root = Path(sys.argv[3]).resolve() if len(sys.argv) == 4 else Path(__file__).resolve().parents[3]
    result = evaluate(plan, registry, root)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "PASS" else 3


if __name__ == "__main__":
    raise SystemExit(main())
