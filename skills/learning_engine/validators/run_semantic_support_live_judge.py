#!/usr/bin/env python3
"""Independent zero-cost Qwen2.5-VL-7B semantic review of the Learning Engine support contract.

This is package-semantic evidence only. It does not execute Learning Engine behavior and
must not be reported as general behavioral PASS.
"""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
RUNTIME_DIR = REPO_ROOT / "sandbox" / "lf_contract_gate_test" / "profile_execution_runtime"
sys.path.insert(0, str(RUNTIME_DIR))

from github_actions_semantic_judge import (  # noqa: E402
    GitHubHostedSemanticMiniJudge,
    GitHubHostedSemanticMiniJudgeVerifier,
)

JUDGE_PATH = REPO_ROOT / "skills" / "learning_engine" / "judges" / "semantic_support_judge.md"

OBLIGATIONS = [
    ("LE-SUP-O01", "1. **Directionality**", "2. **Causal support**",
     "A support correction must explicitly reduce or eliminate the diagnosed defect and must not reproduce, invert, or amplify it."),
    ("LE-SUP-O02", "2. **Causal support**", "3. **Upstream validity**",
     "A rule or change must not be justified by correlation alone; unsupported causal leaps must be returned for repair."),
    ("LE-SUP-O03", "3. **Upstream validity**", "4. **Provenance**",
     "A material upstream must be checked for currentness, exact revision or SHA binding, and compatible current validator or judge state; existence alone is insufficient."),
    ("LE-SUP-O04", "4. **Provenance**", "5. **Semantic correctness**",
     "When execution provenance is claimed, it must be verified and bound to the exact execution, input, and output."),
    ("LE-SUP-O05", "5. **Semantic correctness**", "6. **Evidence ceiling**",
     "An authentic runtime receipt is not semantic proof; semantic PASS requires an applicable independent semantic judge and correlated or self-certified judgment must block."),
    ("LE-SUP-O06", "6. **Evidence ceiling**", "7. **Resolved-input preservation**",
     "Claims must remain at or below the strongest demonstrated evidence layer and valid lower-layer evidence must be preserved when a higher layer remains blocked."),
    ("LE-SUP-O07", "7. **Resolved-input preservation**", "8. **Coverage completeness**",
     "Material authority or values already supplied or resolved in the run must be consumed rather than asked for again."),
    ("LE-SUP-O08", "8. **Coverage completeness**", "9. **Known vs new**",
     "When semantic PASS depends on enumerable obligations, every required obligation must have a unique 1:1 check mapping; partial check bundles cannot prove semantic completeness."),
    ("LE-SUP-O09", "9. **Known vs new**", "10. **Domain ownership**",
     "New unproven behavior must stay capability-only and cannot be generalized as known or regression-protected until its target outcome is proven."),
    ("LE-SUP-O10", "10. **Domain ownership**", "## PASS conditions",
     "Learning Engine may support rules, evidence use, safety, messaging and reliability but must preserve the caller profile as domain owner and Quality Pack as downstream quality authority."),
]


def section(text: str, start: str, end: str) -> str:
    try:
        after = text.split(start, 1)[1]
        body = after.split(end, 1)[0]
    except IndexError as exc:
        raise SystemExit(f"SEMANTIC_SUPPORT_SECTION_MISSING:{start}") from exc
    body = body.strip()
    if not body:
        raise SystemExit(f"SEMANTIC_SUPPORT_SECTION_EMPTY:{start}")
    return start + "\n" + body


def main() -> int:
    text = JUDGE_PATH.read_text(encoding="utf-8")
    obligation_ids = [item[0] for item in OBLIGATIONS]
    if len(obligation_ids) != len(set(obligation_ids)):
        raise SystemExit("SEMANTIC_SUPPORT_COVERAGE_DUPLICATE_OBLIGATION_ID")

    checks = []
    for obligation_id, start, end, rule in OBLIGATIONS:
        checks.append({
            "check_id": obligation_id,
            "check_type": "SEMANTIC_RELATION",
            "rule": rule,
            "evidence": section(text, start, end),
            "question": "Does the actual Learning Engine support-judge section comply with this obligation?",
            "source_refs": [str(JUDGE_PATH.relative_to(REPO_ROOT))],
        })

    check_ids = [check["check_id"] for check in checks]
    if obligation_ids != check_ids or len(check_ids) != len(set(check_ids)):
        raise SystemExit("SEMANTIC_SUPPORT_COVERAGE_NOT_1_TO_1")

    results = []
    runtime_evidence = []
    verifier = GitHubHostedSemanticMiniJudgeVerifier()
    with tempfile.TemporaryDirectory(prefix="lf-learning-semantic-") as td:
        with GitHubHostedSemanticMiniJudge(work_dir=Path(td)) as adapter:
            for check in checks:
                result, evidence = adapter.classify(check)
                verification = verifier.verify(
                    check=check, result=result, evidence=evidence, adapter=adapter
                )
                results.append(result.as_dict())
                runtime_evidence.append({
                    "check_id": check["check_id"],
                    "verification": verification,
                    "model_id": evidence["model_id"],
                    "model_sha256": evidence["model_sha256"],
                    "raw_output_sha256": evidence["raw_output_sha256"],
                })
                print(
                    f"LEARNING_ENGINE_SEMANTIC_CHECK {check['check_id']} "
                    f"verdict={result.verdict} verified={verification['verified']}",
                    flush=True,
                )
                if result.verdict != "COMPLIES" or verification.get("verified") is not True:
                    raise SystemExit(
                        f"LEARNING_ENGINE_SEMANTIC_SUPPORT_LIVE_FAIL:{check['check_id']}:"
                        f"{result.verdict}"
                    )

    receipt = {
        "schema": "LF_LEARNING_ENGINE_PACKAGE_SEMANTIC_JUDGE_V1",
        "execution_id": "EXEC-ACTUALIZACION-SKILL-LEARNING-ENGINE-20260827-001",
        "target_code": "ACT-0046",
        "judge_source": str(JUDGE_PATH.relative_to(REPO_ROOT)),
        "coverage_manifest": {
            "required_obligation_ids": obligation_ids,
            "check_ids": check_ids,
            "mapping": {item: item for item in obligation_ids},
            "complete": True,
        },
        "results": results,
        "runtime_evidence": runtime_evidence,
        "verdict": "PASS_PACKAGE_SEMANTIC_CONTRACT",
        "evidence_ceiling": "SEMANTIC_SUPPORTED_PACKAGE_ONLY_NOT_BEHAVIORAL",
        "general_behavioral_eval_status": "NOT_CLAIMED",
    }
    print(json.dumps(receipt, ensure_ascii=False, sort_keys=True), flush=True)
    print(
        f"LEARNING_ENGINE_SEMANTIC_SUPPORT_LIVE_PASS {len(results)}/{len(obligation_ids)} "
        f"coverage={len(check_ids)}/{len(obligation_ids)}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
