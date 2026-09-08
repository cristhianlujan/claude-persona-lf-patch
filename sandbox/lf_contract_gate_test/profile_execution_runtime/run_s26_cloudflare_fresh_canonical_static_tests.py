#!/usr/bin/env python3
"""Offline canonical binding tests for the fresh Cloudflare S26 qualification plan."""
from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path

BRANCH_RUNTIME = Path(__file__).resolve().parent
PLAN_PATH = BRANCH_RUNTIME / "s26_cloudflare_fresh_canonical_plan_v1.json"
AUTHORITY_ROOT = Path(os.environ.get("S26_AUTHORITY_ROOT", ".")).resolve()
AUTHORITY_RUNTIME = AUTHORITY_ROOT / "sandbox" / "lf_contract_gate_test" / "profile_execution_runtime"
AUTHORITY_SERVICE = AUTHORITY_ROOT / "services" / "profile_runtime_api"
for path in (AUTHORITY_RUNTIME, AUTHORITY_SERVICE):
    if not path.is_dir():
        raise SystemExit(f"BLOCK_STATIC_AUTHORITY_PATH_MISSING:{path}")
sys.path.insert(0, str(AUTHORITY_RUNTIME))
sys.path.insert(0, str(AUTHORITY_SERVICE))

from profile_runtime_api.llama import governed_generation_schema  # noqa: E402
from profile_runtime_api.repository import RepositoryBindings  # noqa: E402
from profile_runtime_runner import build_runtime_request  # noqa: E402
from semantic_obligation_manifest import obligation_manifest_sha256, validate_obligation_manifest  # noqa: E402

PROFILE_CODE = "PERFIL-UI-ARCHITECT"
PROFILE_SLUG = "ui_architect"
PROFILE_PATHS = ["profiles/ui_architect/SKILL.md"]
FORBIDDEN_OLD_CASES = {
    "S26_HOLDOUT_PAYMENT_SELECTION",
    "S26_HOLDOUT_SEARCH_LOADING",
    "S26_ADVERSARIAL_STATUS_OVERFLOW",
}


def _literal_input(case: dict) -> str:
    return "\n".join([
        str(case["task"]),
        "",
        "GOVERNED FACTS:",
        *[f"- {item}" for item in case["governed_facts"]],
        "",
        "QUALITY REQUIREMENTS:",
        *[f"- {item}" for item in case["quality_requirements"]],
    ])


def _manifest(*, case: dict, execution_id: str, profile_source_sha: str, input_sha: str) -> dict:
    obligation_ids = [str(item["obligation_id"]) for item in case["obligations"]]
    raw = {
        "schema": "PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1",
        "execution_id": execution_id,
        "profile_code": PROFILE_CODE,
        "profile_source_sha256": profile_source_sha,
        "input_sha256": input_sha,
        "authority_sources": [
            {
                "authority_id": "PROFILE-CONTRACT",
                "authority_type": "PROFILE_CONTRACT",
                "source_ref": PROFILE_PATHS[0],
                "source_sha256": profile_source_sha,
                "required_obligation_ids": obligation_ids,
            },
            {
                "authority_id": "EXECUTION-INPUT",
                "authority_type": "EXECUTION_INPUT",
                "source_ref": f"fresh-plan:{case['case_id']}",
                "source_sha256": input_sha,
                "required_obligation_ids": obligation_ids,
            },
        ],
        "obligations": [
            {
                "obligation_id": str(item["obligation_id"]),
                "rule": str(item["rule"]),
                "check_type": "SEMANTIC_RELATION",
                "evidence_pointer": "$",
                "authority_ids": ["PROFILE-CONTRACT", "EXECUTION-INPUT"],
                "question": str(item["question"]),
            }
            for item in case["obligations"]
        ],
    }
    return validate_obligation_manifest(
        raw,
        expected_execution_id=execution_id,
        expected_profile_code=PROFILE_CODE,
        expected_profile_source_sha256=profile_source_sha,
        expected_input_sha256=input_sha,
    )


def main() -> int:
    plan = json.loads(PLAN_PATH.read_text(encoding="utf-8"))
    assert plan["schema"] == "S26_CLOUDFLARE_FRESH_CANONICAL_PLAN_V1"
    assert plan["frozen_before_any_candidate_output"] is True
    assert plan["tuning_from_candidate_output_forbidden"] is True
    assert plan["diagnostic_holdouts_reused"] is False
    cases = plan["cases"]
    assert len(cases) == 3
    case_ids = [str(case["case_id"]) for case in cases]
    assert len(set(case_ids)) == 3
    assert not (set(case_ids) & FORBIDDEN_OLD_CASES)

    repository = RepositoryBindings(AUTHORITY_ROOT, max_prompt_chars=120_000)
    repository.validate()
    profile_sources = repository.profile_sources(PROFILE_SLUG, PROFILE_PATHS)
    assert [item["ref"] for item in profile_sources] == PROFILE_PATHS
    schema_binding = repository.runtime_schema(PROFILE_SLUG, "UI_FOCUSED_DECISION")
    generation_schema, generation_policy = governed_generation_schema(
        schema_binding.payload,
        profile_slug=PROFILE_SLUG,
        schema_mode="UI_FOCUSED_DECISION",
    )
    assert generation_policy == "UI_FOCUSED_BOUNDED_GENERATION_V1"
    assert isinstance(generation_schema, dict) and generation_schema

    summaries = []
    all_obligations = []
    for index, case in enumerate(cases, start=1):
        case_id = str(case["case_id"])
        execution_id = f"EXEC-S26-CF-FRESH-{index:02d}-{case_id}"
        literal = _literal_input(case)
        preliminary = build_runtime_request(
            execution_id=execution_id,
            profile_code=PROFILE_CODE,
            profile_slug=PROFILE_SLUG,
            profile_sources=profile_sources,
            input_literal=literal,
        )
        manifest = _manifest(
            case=case,
            execution_id=execution_id,
            profile_source_sha=preliminary["profile_source_sha256"],
            input_sha=preliminary["input_sha256"],
        )
        manifest_sha = obligation_manifest_sha256(manifest)
        bound = build_runtime_request(
            execution_id=execution_id,
            profile_code=PROFILE_CODE,
            profile_slug=PROFILE_SLUG,
            profile_sources=profile_sources,
            input_literal=literal,
            obligation_manifest=manifest,
        )
        assert bound["obligation_manifest_sha256"] == manifest_sha
        assert bound["profile_source_sha256"] == preliminary["profile_source_sha256"]
        assert bound["input_sha256"] == preliminary["input_sha256"]
        obligation_ids = [str(item["obligation_id"]) for item in manifest["obligations"]]
        assert len(obligation_ids) == 4 and len(set(obligation_ids)) == 4
        all_obligations.extend(obligation_ids)
        summaries.append({
            "case_id": case_id,
            "execution_id": execution_id,
            "input_sha256": bound["input_sha256"],
            "profile_source_sha256": bound["profile_source_sha256"],
            "obligation_manifest_sha256": manifest_sha,
            "request_sha256": bound["request_sha256"],
            "obligation_count": len(obligation_ids),
        })

    assert len(all_obligations) == len(set(all_obligations)) == 12
    plan_sha = hashlib.sha256(PLAN_PATH.read_bytes()).hexdigest()
    output = {
        "status": "PASS",
        "plan_sha256": plan_sha,
        "authority_ref": os.environ.get("S26_AUTHORITY_REF", ""),
        "profile_source_refs": PROFILE_PATHS,
        "schema_source_refs": list(schema_binding.source_refs),
        "schema_sha256": schema_binding.sha256,
        "generation_policy": generation_policy,
        "case_count": 3,
        "obligation_count": 12,
        "cases": summaries,
        "inference_executed": False,
        "judge_executed": False,
    }
    print("S26_CLOUDFLARE_FRESH_CANONICAL_STATIC=" + json.dumps(output, sort_keys=True))
    print("S26_CLOUDFLARE_FRESH_CANONICAL_STATIC_PASS_NO_INFERENCE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
