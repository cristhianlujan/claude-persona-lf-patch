#!/usr/bin/env python3
"""Read-only input provenance preflight for ACTUALIZACION_PERFIL_LF.

Proposal-only: NEVER records a step, invokes OIDC, certifies a GitHub proof,
changes the authoritative policy, or upgrades an execution to PASS.
The existing Edge/RPC and the frozen policy remain the only authorities.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
CATALOG = ROOT / "skills/profile_creator/contracts/profile_updater_io_bindings_v1.json"
SCHEMA = "LF_PROFILE_UPDATER_INPUT_CONTRACT_V1"
STEPS = (
    "init_execution", "router", "profile_resolve", "baseline_read",
    "method_selection", "evolution_decision", "change_scope",
    "regression_plan", "pre_write_execution_binding_gate", "github_write",
    "github_readback", "deterministic_validation", "semantic_judge",
    "regression_after", "post_merge_reconcile", "close", "report_output",
)
SHA40 = re.compile(r"^[0-9a-f]{40}$")
RUN_ID = re.compile(r"^[1-9][0-9]{0,14}$")
EMPTY_ALLOWED = {("method_selection", "selected_methods"), ("close", "open_blockers")}


def _get(obj: Any, path: str) -> Any:
    for key in path.split("."):
        if not isinstance(obj, dict) or key not in obj:
            return None
        obj = obj[key]
    return obj


def _present(value: Any, allow_empty: bool) -> bool:
    if value is None or value == "":
        return False
    if isinstance(value, (list, dict)) and not value and not allow_empty:
        return False
    return True


def validate_catalog(spec: dict) -> list[str]:
    failures: list[str] = []
    if spec.get("schema_version") != SCHEMA or spec.get("operation_code") != "ACTUALIZACION_PERFIL_LF":
        failures.append("CATALOG_IDENTITY_INVALID")
    stages = spec.get("steps")
    if not isinstance(stages, list) or [x.get("step_id") for x in stages if isinstance(x, dict)] != list(STEPS):
        return failures + ["CATALOG_STEP_SEQUENCE_INVALID"]
    for index, stage in enumerate(stages):
        names = stage.get("input_required")
        bindings = stage.get("bindings")
        if (not isinstance(names, list) or not names
                or not isinstance(bindings, list) or len(bindings) != len(names)
                or len(names) != len(set(names))
                or any(not isinstance(name, str) or not name for name in names)):
            failures.append("CATALOG_INPUT_SHAPE_INVALID:" + stage["step_id"])
            continue
        if names != [b.get("name") for b in bindings if isinstance(b, dict)]:
            failures.append("CATALOG_BINDING_NAMES_MISMATCH:" + stage["step_id"])
        for b in bindings:
            if not isinstance(b, dict) or b.get("source") not in {"execution", "request", "prior_step"}:
                failures.append("CATALOG_SOURCE_INVALID:" + stage["step_id"])
                continue
            path = b.get("path")
            if not isinstance(path, str) or not re.fullmatch(r"[a-z_][a-z_0-9]*(\\.[a-z_][a-z_0-9]*)*", path):
                failures.append("CATALOG_PATH_INVALID:" + stage["step_id"])
            if b["source"] == "prior_step":
                parent = b.get("step_id")
                if parent not in STEPS[:index]:
                    failures.append("CATALOG_FORWARD_OR_UNKNOWN_REFERENCE:" + stage["step_id"])
            elif "step_id" in b:
                failures.append("CATALOG_UNEXPECTED_STEP_REF:" + stage["step_id"])
    mapping = {s["step_id"]: s["input_required"] for s in stages}
    if mapping.get("method_selection") != [
        "profile_assessment_receipt_id", "selector_version", "selected_methods"
    ] or mapping.get("evolution_decision") != [
        "profile_assessment_receipt_id", "decision", "evolution_mode"
    ]:
        failures.append("CATALOG_HISTORICAL_35_37_CHANGED")
    return failures


def check_step(spec: dict, step_id: str, execution: dict, request: dict,
               prior_steps: dict[str, dict]) -> dict:
    """Diagnose the input boundary. READY never means an approved step."""
    report = {
        "schema_version": "LF_PROFILE_UPDATER_IO_PREFLIGHT_RECEIPT_V1",
        "step_id": step_id,
        "execution_id": execution.get("execution_id"),
        "status": "BLOCKED",
        "approval_effect": "NONE",
        "missing": [], "inconsistent": [], "bindings": [],
        "server_proof_verification": "NOT_PERFORMED",
    }
    problems = validate_catalog(spec)
    if problems:
        report["inconsistent"].extend(problems)
        return report
    if step_id not in STEPS:
        report["inconsistent"].append("UNKNOWN_STEP")
        return report
    if (execution.get("operation_code") != "ACTUALIZACION_PERFIL_LF"
            or execution.get("status") != "IN_PROGRESS"
            or not isinstance(execution.get("execution_id"), str)
            or not execution["execution_id"]):
        report["inconsistent"].append("EXECUTION_CONTEXT_INVALID")
        return report
    if request.get("step_id") != step_id or request.get("execution_id") != execution["execution_id"]:
        report["inconsistent"].append("REQUEST_EXECUTION_OR_STEP_MISMATCH")
        return report
    if not isinstance(prior_steps, dict):
        report["inconsistent"].append("LEDGER_CONTEXT_NOT_OBJECT")
        return report

    stage = spec["steps"][STEPS.index(step_id)]
    values = {}
    for binding in stage["bindings"]:
        name, source, path = binding["name"], binding["source"], binding["path"]
        if source == "execution":
            origin = execution
        elif source == "request":
            origin = request
        else:
            prior = prior_steps.get(binding["step_id"])
            if not isinstance(prior, dict):
                report["missing"].append(f"{name}:PRIOR_RECEIPT_MISSING:{binding['step_id']}")
                continue
            if prior.get("execution_id") != execution["execution_id"]:
                report["inconsistent"].append(f"{name}:CROSS_EXECUTION_RECEIPT")
                continue
            if prior.get("step_id") != binding["step_id"] or prior.get("status") != "STEP_PASS_WITH_EVIDENCE":
                report["inconsistent"].append(f"{name}:PRIOR_RECEIPT_NOT_CLEAN")
                continue
            origin = prior
        value = _get(origin, path)
        if not _present(value, (step_id, name) in EMPTY_ALLOWED):
            report["missing"].append(f"{name}:INPUT_REQUIRED_MISSING")
            continue
        values[name] = value
        report["bindings"].append({"name": name, "source": source,
                                    **({"producer_step_id": binding["step_id"]} if source == "prior_step" else {}),
                                    "status": "PRESENT_NOT_ATTESTED"})

    if step_id == "deterministic_validation" and not report["missing"] and not report["inconsistent"]:
        base, candidate, head, proof_id = (
            values["bound_revision"], values["candidate_commit_sha"],
            values["readback_exact_head"], values["evolution_proof_run_id"]
        )
        write = prior_steps.get("github_write", {})
        prewrite = prior_steps.get("pre_write_execution_binding_gate", {})
        if (not isinstance(base, str) or not SHA40.fullmatch(base)
                or base != _get(prewrite, "evidence_payload.server_trust_context.bound_revision")):
            report["inconsistent"].append("BOUND_REVISION_NOT_SERVER_BOUND")
        if (not isinstance(candidate, str) or not SHA40.fullmatch(candidate)
                or candidate != head or candidate != _get(write, "evidence_payload.commit_sha")):
            report["inconsistent"].append("CANDIDATE_HEAD_PARITY_FAILED")
        if not isinstance(proof_id, (str, int)) or not RUN_ID.fullmatch(str(proof_id)):
            report["inconsistent"].append("PROOF_RUN_ID_INVALID")
        # A well-formed proof ID still needs a real GitHub Actions readback from Edge.
        report["server_proof_verification"] = "REQUIRED_BY_EXISTING_EDGE"
    report["status"] = (
        "BLOCKED_MISSING_INPUT" if report["missing"] else
        "BLOCKED_INCONSISTENT_INPUT" if report["inconsistent"] else
        "READY_FOR_SERVER_VERIFICATION"
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--step-id", required=True, choices=STEPS)
    parser.add_argument("--context-json", type=Path, required=True,
                        help="Local JSON with execution, request and prior_steps (no credentials).")
    args = parser.parse_args()
    spec = json.loads(CATALOG.read_text(encoding="utf-8"))
    ctx = json.loads(args.context_json.read_text(encoding="utf-8"))
    result = check_step(spec, args.step_id, ctx["execution"], ctx["request"],
                        ctx.get("prior_steps", {}))
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    return 0 if result["status"] == "READY_FOR_SERVER_VERIFICATION" else 1


if __name__ == "__main__":
    raise SystemExit(main())
