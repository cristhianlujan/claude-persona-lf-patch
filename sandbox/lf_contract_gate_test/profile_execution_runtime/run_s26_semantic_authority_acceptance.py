#!/usr/bin/env python3
"""One-call S26 acceptance canary for the owner-approved Nemotron semantic authority."""
from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path

from github_actions_semantic_judge import (
    ADAPTER_ID,
    SEMANTIC_AUTHORITY_DECISION_REF,
    SEMANTIC_MODEL_ID,
    GitHubHostedSemanticMiniJudge,
    GitHubHostedSemanticMiniJudgeVerifier,
)

CASE = {
    "check_id": "S26_NEMOTRON_AUTHORITY_ACCEPTANCE_ROW_COUNT_SELECTOR",
    "check_type": "SEMANTIC_RELATION",
    "rule": "The update must preserve the visible row-count selector in the table footer.",
    "evidence": "Tighten spacing in the table footer while keeping the overall layout compact.",
    "question": "Does the supplied evidence directly establish that the row-count selector is preserved?",
}
EXPECTED = "UNCERTAIN"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-path", type=Path, required=True)
    args = parser.parse_args()

    if os.getenv("LF_REPOSITORY_VISIBILITY", "").strip() != "public":
        raise SystemExit("S26_NEMOTRON_AUTHORITY_ACCEPTANCE_BLOCK_VISIBILITY")
    if os.getenv("LF_RUNNER_LABEL", "").strip() != "ubuntu-latest":
        raise SystemExit("S26_NEMOTRON_AUTHORITY_ACCEPTANCE_BLOCK_RUNNER")

    work_root = Path(os.environ.get("RUNNER_TEMP") or tempfile.gettempdir()).resolve()
    verifier = GitHubHostedSemanticMiniJudgeVerifier()
    with GitHubHostedSemanticMiniJudge(work_dir=work_root / "s26-nemotron-authority-acceptance") as judge:
        classification, evidence = judge.classify(CASE)
        verification = verifier.verify(
            check=CASE,
            result=classification,
            evidence=evidence,
            adapter=judge,
        )

    passed = (
        classification.verdict == EXPECTED
        and classification.decided_by == "REMOTE_SEMANTIC_MODEL"
        and verification.get("verified") is True
        and evidence.get("adapter_id") == ADAPTER_ID
        and evidence.get("model_id") == SEMANTIC_MODEL_ID
        and evidence.get("authority_decision_ref") == SEMANTIC_AUTHORITY_DECISION_REF
        and evidence.get("model_weights_downloaded") is False
        and evidence.get("local_model_fallback_used") is False
        and evidence.get("paid_fallback_used") is False
        and evidence.get("shared_provider_owner_approved") is True
    )
    payload = {
        "schema": "S26_NEMOTRON_SEMANTIC_AUTHORITY_ACCEPTANCE_V1",
        "strategy": "S26",
        "status": "PASS" if passed else "FAIL_CLOSED",
        "expected": EXPECTED,
        "observed": classification.verdict,
        "classification": classification.as_dict(),
        "adapter_evidence": evidence,
        "verification": verification,
        "authority_changed": True,
        "authority_decision_ref": SEMANTIC_AUTHORITY_DECISION_REF,
        "semantic_model_id": SEMANTIC_MODEL_ID,
        "provider_infrastructure_shared": True,
        "shared_provider_owner_approved": True,
        "production_mutation": False,
        "promotion_authorized": False,
    }
    args.result_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print("S26_NEMOTRON_AUTHORITY_ACCEPTANCE=" + json.dumps(payload, ensure_ascii=False, sort_keys=True))
    print("S26_NEMOTRON_AUTHORITY_ACCEPTANCE_STATUS=" + payload["status"])
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
