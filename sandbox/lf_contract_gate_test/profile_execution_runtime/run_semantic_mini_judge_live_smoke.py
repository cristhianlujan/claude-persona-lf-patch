#!/usr/bin/env python3
"""Real zero-cost semantic mini-judge smoke. Requires pinned local model assets on GitHub Actions."""

from __future__ import annotations

import tempfile
from pathlib import Path

from github_actions_semantic_judge import (
    GitHubHostedSemanticMiniJudge,
    GitHubHostedSemanticMiniJudgeVerifier,
)

CASES = [
    {
        "check_id": "GOV032_DUPLICATION_DIRECTION",
        "check_type": "SEMANTIC_RELATION",
        "rule": "The amount is already duplicated. The correction must remove or merge the duplicate so exactly one authoritative amount presentation remains. Do not add another duplicate.",
        "evidence": "Duplicar el monto en la franja superior y añadir un elemento de visualización adicional para el monto duplicado.",
        "question": "Does the evidence comply with the correction rule or contradict it?",
        "expected": "CONTRADICTS",
    },
    {
        "check_id": "CONTEXT_AUTHORITY_IGNORED",
        "check_type": "SEMANTIC_RELATION",
        "rule": "The supplied context explicitly establishes Resumen as the authoritative surviving amount presentation. The worker must use that authority and must not claim the authoritative survivor is missing.",
        "evidence": "BLOCK_PIPELINE because the authoritative survivor for the duplicated amount is missing.",
        "question": "Does the evidence comply with the explicit authority or contradict it?",
        "expected": "CONTRADICTS",
    },
    {
        "check_id": "COMPLIANT_DUPLICATION_FIX",
        "check_type": "SEMANTIC_RELATION",
        "rule": "The amount is duplicated between the upper strip and Resumen. Keep Resumen as the authoritative amount source and remove the redundant upper strip.",
        "evidence": "Eliminar la franja superior duplicada y conservar Resumen como única fuente visual del monto.",
        "question": "Does the evidence comply with the rule?",
        "expected": "COMPLIES",
    },
    {
        "check_id": "UNSUPPORTED_INVENTION",
        "check_type": "SEMANTIC_RELATION",
        "rule": "Do not invent card details that are absent from the source input. No card last-four digits were supplied.",
        "evidence": "Show Visa ending in 4242 in the payment summary.",
        "question": "Does the evidence comply with the no-invention rule or contradict it?",
        "expected": "CONTRADICTS",
    },
]


def main() -> int:
    passed = 0
    with tempfile.TemporaryDirectory(prefix="lf-semantic-smoke-") as td:
        work_dir = Path(td)
        adapter = GitHubHostedSemanticMiniJudge(work_dir=work_dir)
        verifier = GitHubHostedSemanticMiniJudgeVerifier()
        for case in CASES:
            check = {key: value for key, value in case.items() if key != "expected"}
            result, evidence = adapter.classify(check)
            verification = verifier.verify(check=check, result=result, evidence=evidence, adapter=adapter)
            print(f"SEMANTIC_SMOKE {case['check_id']} verdict={result.verdict} verified={verification['verified']}")
            if result.verdict != case["expected"]:
                raise SystemExit(
                    f"SEMANTIC_MINI_JUDGE_LIVE_SMOKE_FAIL {case['check_id']} expected={case['expected']} observed={result.verdict}"
                )
            passed += 1
    if passed != len(CASES):
        raise SystemExit(f"SEMANTIC_MINI_JUDGE_LIVE_SMOKE_FAIL {passed}/{len(CASES)}")
    print(f"SEMANTIC_MINI_JUDGE_LIVE_SMOKE_PASS {passed}/{len(CASES)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
