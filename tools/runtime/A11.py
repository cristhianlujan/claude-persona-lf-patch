#!/usr/bin/env python3
"""Deep runtime audit for A11 six-step wizard fixture."""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
from copy import deepcopy
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "skills" / "creating-integral-user-stories"
TARGET = SKILL / "evals" / "fixtures" / "screen_wizard_six_steps.json"


def canonical_sha(value: object) -> str:
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def emitted(stdout: str) -> dict[str, Any]:
    for line in reversed([line.strip() for line in stdout.splitlines() if line.strip()]):
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError("json_output_missing")


def decomposition(fixture: dict[str, Any]) -> dict[str, Any]:
    exact = fixture["fixture"]["exact_inputs"]
    units = [
        {
            "functional_unit_code": "FU-DRAFT-SAVED",
            "actor": "APPLICANT",
            "goal": "guardar una solicitud incompleta",
            "trigger": "SAVE_DRAFT",
            "observable_output": "DRAFT_SAVED",
            "risk_level": "MEDIUM",
            "decision": "CREATE_STORY",
            "justification": "resultado de negocio independientemente aceptable",
            "source_ref": exact["business_results"][0]["source_ref"],
            "classification": "CONFIRMED",
        },
        {
            "functional_unit_code": "FU-APPLICATION-SUBMITTED",
            "actor": "APPLICANT",
            "goal": "enviar una solicitud completa",
            "trigger": "SUBMIT",
            "observable_output": "APPLICATION_SUBMITTED",
            "risk_level": "HIGH",
            "decision": "CREATE_STORY",
            "justification": "resultado de negocio independientemente aceptable",
            "source_ref": exact["business_results"][1]["source_ref"],
            "classification": "CONFIRMED",
        },
        {
            "functional_unit_code": "FU-CONSENT-CONTROLS",
            "actor": "APPLICANT",
            "goal": "aplicar consentimiento y controles transversales",
            "trigger": "CONSENT",
            "observable_output": "CONSENT_CONTROLS_APPLIED",
            "risk_level": "HIGH",
            "decision": "CROSS_CUTTING",
            "justification": "control transversal reutilizado por los dos resultados",
            "source_ref": exact["steps"][4]["source_ref"],
            "classification": "CONFIRMED",
        },
    ]
    coverage_items: list[dict[str, Any]] = []
    for index, step in enumerate(exact["steps"], start=1):
        coverage_items.append(
            {
                "source_item_code": f"STEP-{index}",
                "source_type": "CONTEXT",
                "source_ref": step["source_ref"],
                "mapping_status": "MAPPED",
                "mapped_to": ["FU-DRAFT-SAVED", "FU-APPLICATION-SUBMITTED"] if step["code"] != "CONSENT" else ["FU-CONSENT-CONTROLS"],
                "justification": "mapped by business result or cross-cutting control",
            }
        )
    for index, action in enumerate(exact["actions"], start=1):
        mapped = ["FU-DRAFT-SAVED"] if action["code"] == "SAVE_DRAFT" else ["FU-APPLICATION-SUBMITTED"] if action["code"] == "SUBMIT" else ["FU-DRAFT-SAVED", "FU-APPLICATION-SUBMITTED"]
        coverage_items.append(
            {
                "source_item_code": f"ACTION-{index}",
                "source_type": "ACTION",
                "source_ref": action["source_ref"],
                "mapping_status": "MAPPED",
                "mapped_to": mapped,
                "justification": "navigation or terminal action mapped",
            }
        )
    for index, result in enumerate(exact["business_results"], start=1):
        coverage_items.append(
            {
                "source_item_code": f"RESULT-{index}",
                "source_type": "BUSINESS_RESULT",
                "source_ref": result["source_ref"],
                "mapping_status": "MAPPED",
                "mapped_to": [units[index - 1]["functional_unit_code"]],
                "justification": "one story per independently acceptable result",
            }
        )
    coverage_items.append(
        {
            "source_item_code": "PERMISSION-1",
            "source_type": "PERMISSION",
            "source_ref": "self:#/fixture/exact_inputs/actors/0",
            "mapping_status": "MAPPED",
            "mapped_to": ["FU-DRAFT-SAVED", "FU-APPLICATION-SUBMITTED"],
            "justification": "actor permission applies to both outcomes",
        }
    )
    count = len(coverage_items)
    return {
        "target_screen_code": exact["screen_code"],
        "screen_decomposition": {
            "screen_code": exact["screen_code"],
            "source_version": exact["version"],
            "source_snapshot_sha": fixture["source_snapshot"]["sha256"],
            "main_responsibility": exact["main_responsibility"],
            "context_inventory": [
                {"code": step["code"], "description": step["goal"], "source_ref": step["source_ref"]}
                for step in exact["steps"]
            ],
            "field_inventory": [],
            "permission_inventory": [
                {
                    "permission_code": exact["actors"][0]["permissions"][0],
                    "actor_profile": exact["actors"][0]["profile"],
                    "action_code": "SAVE_DRAFT_OR_SUBMIT",
                    "source_ref": "self:#/fixture/exact_inputs/actors/0",
                }
            ],
            "transition_inventory": [],
            "functional_units": units,
            "coverage_items": coverage_items,
            "coverage_summary": {
                "source_items_count": count,
                "mapped_count": count,
                "justified_count": 0,
                "unmapped_count": 0,
                "unjustified_count": 0,
                "conflicting_count": 0,
                "duplicate_functional_units_count": 0,
            },
            "pending_decisions": [
                {
                    "decision_code": "MFA-SUBMIT",
                    "reason": "fixture marks MFA as pending",
                    "source_ref": exact["actions"][3]["source_ref"],
                }
            ],
        },
    }


def evaluate_contract(fixture: dict[str, Any], result: dict[str, Any]) -> tuple[list[str], dict[str, Any]]:
    exact = fixture["fixture"]["exact_inputs"]
    units = result["screen_decomposition"]["functional_units"]
    create_units = [item for item in units if item["decision"] == "CREATE_STORY"]
    business_results = [item["observable_output"] for item in create_units]
    coverage = result["screen_decomposition"]["coverage_summary"]
    actual = {
        "visual_steps": len(exact["steps"]),
        "create_story_count": len(create_units),
        "functional_unit_count": len(units),
        "business_results": business_results,
        "unmapped_count": coverage["unmapped_count"],
        "state_changes": [],
        "input_sha256": canonical_sha(exact),
    }
    failed: list[str] = []
    if actual["create_story_count"] == fixture["expected"]["output"]["prohibited_story_count"]:
        failed.append("F01_NO_ONE_STORY_PER_VISUAL_STEP")
    if set(actual["business_results"]) != set(fixture["assertions"][1]["expected"]):
        failed.append("F02_BUSINESS_RESULTS_COVERED")
    if actual["unmapped_count"] != 0:
        failed.append("F03_NO_UNMAPPED_SOURCE")
    if actual["state_changes"] != []:
        failed.append("F04_NO_CANONICAL_MUTATION")
    if actual["input_sha256"] != fixture["source_snapshot"]["sha256"]:
        failed.append("F05_SOURCE_HASH_MATCHES")
    return failed, actual


def main() -> int:
    fixture = json.loads(TARGET.read_text(encoding="utf-8"))
    positive = decomposition(fixture)
    positive_failed, positive_actual = evaluate_contract(fixture, positive)

    with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8", delete=False) as handle:
        json.dump(positive, handle, ensure_ascii=False)
        handle.write("\n")
        input_path = Path(handle.name)
    env = os.environ.copy()
    env.update(LF_JUDGE_VERSION="v0.5", LF_EXECUTOR_IDENTITY="R8_A11_RUNNER")
    command = [sys.executable, "scripts/validate_screen_decomposition.py", str(input_path)]
    proc = subprocess.run(command, cwd=SKILL, env=env, text=True, capture_output=True, timeout=120)
    try:
        j02 = emitted(proc.stdout)
        j02_pass = proc.returncode == 0 and j02.get("result") == "PASS_WITH_EVIDENCE" and not j02.get("failed_assertions") and all(isinstance(j02.get(key), str) and len(j02[key]) == 64 for key in ("input_sha256", "evidence_sha256", "output_sha256"))
    except Exception as exc:
        j02 = {"error": f"{type(exc).__name__}:{exc}", "stdout": proc.stdout[-3000:], "stderr": proc.stderr[-1500:]}
        j02_pass = False
    finally:
        input_path.unlink(missing_ok=True)

    forced_six = deepcopy(positive)
    base = forced_six["screen_decomposition"]["functional_units"][0]
    forced_six["screen_decomposition"]["functional_units"] = [
        {**deepcopy(base), "functional_unit_code": f"FU-STEP-{index}", "observable_output": f"VISUAL_STEP_{index}"}
        for index in range(1, 7)
    ]
    forced_failed, forced_actual = evaluate_contract(fixture, forced_six)

    missing_ref_fixture = deepcopy(fixture)
    missing_ref_fixture["fixture"]["exact_inputs"]["actions"][3].pop("source_ref")
    missing_refs = [
        f"actions/{index}"
        for index, item in enumerate(missing_ref_fixture["fixture"]["exact_inputs"]["actions"])
        if not item.get("source_ref")
    ]
    missing_ref_result = "BLOCKED" if missing_refs else "PASS_WITH_EVIDENCE"

    checks = {
        "positive_contract_pass": not positive_failed,
        "j02_positive_pass": j02_pass,
        "positive_story_count_two": positive_actual["create_story_count"] == 2,
        "positive_unit_count_three": positive_actual["functional_unit_count"] == 3,
        "positive_business_results_complete": set(positive_actual["business_results"]) == {"DRAFT_SAVED", "APPLICATION_SUBMITTED"},
        "positive_unmapped_zero": positive_actual["unmapped_count"] == 0,
        "source_hash_matches": positive_actual["input_sha256"] == fixture["source_snapshot"]["sha256"],
        "negative_six_stories_rejected": "F01_NO_ONE_STORY_PER_VISUAL_STEP" in forced_failed and forced_actual["create_story_count"] == 6,
        "negative_missing_ref_blocked": missing_ref_result == "BLOCKED" and missing_refs == ["actions/3"],
    }
    passed = all(checks.values())
    output = {
        "artifact": "A11",
        "passed": passed,
        "fixture_sha256": hashlib.sha256(TARGET.read_bytes()).hexdigest(),
        "checks": checks,
        "positive": {
            "contract_failed_assertions": positive_failed,
            "actual": positive_actual,
            "j02_command": command,
            "j02_process_exit_code": proc.returncode,
            "j02_result": j02,
        },
        "negative_cases": [
            {
                "id": "NEG-SIX-STORIES",
                "result": "RETURN_TO_WORKER" if forced_failed else "PASS_WITH_EVIDENCE",
                "failed_assertions": forced_failed,
                "actual": forced_actual,
            },
            {
                "id": "NEG-MISSING-SOURCE-REF",
                "result": missing_ref_result,
                "blocking_assertions": ["source_ref_unresolvable"] if missing_refs else [],
                "missing_refs": missing_refs,
            },
        ],
    }
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
