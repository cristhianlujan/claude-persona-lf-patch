#!/usr/bin/env python3
"""S26 manifest-only continuation over the durable frozen-holdout artifact.

This execution exists only because the first holdout harness correctly failed
closed on one adversarial case before reaching the separately required prebound
semantic-obligation manifest. It does not rerun or tune any holdout case and
cannot change the already locked NO_PROMOTE disposition.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any

import run_s26_primary_candidate_holdout_manifest as holdout
from github_actions_semantic_judge import (
    GitHubHostedSemanticMiniJudge,
    GitHubHostedSemanticMiniJudgeVerifier,
    SEMANTIC_MODEL_ID,
    SEMANTIC_MODEL_SHA256,
)

EXPECTED_PRIOR_RUN_ID = "34138388750"
EXPECTED_PRIOR_HEAD = "a7e28032608d0c463358e4e360f9582e1ca45653"
EXPECTED_PRIOR_RESULT_SHA256 = "8213bc35bc0f59f650430f1a864d3dfb28b4ba3cd2702c89f1ad9b666f137a61"
EXPECTED_ARTIFACT_ID = "10025177238"
EXPECTED_ARTIFACT_DIGEST = "sha256:c7d6383711bc9862d6f909eaa7e77a3ec33f8839f5ba99d9ac84cd5b91705693"
WITNESS_CASE_ID = "S26_HOLDOUT_PAYMENT_SELECTION"


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _load_prior(path: Path) -> dict[str, Any]:
    observed = _sha256_file(path)
    if observed != EXPECTED_PRIOR_RESULT_SHA256:
        raise RuntimeError(
            f"PRIOR_RESULT_SHA_MISMATCH expected={EXPECTED_PRIOR_RESULT_SHA256} observed={observed}"
        )
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict) or value.get("result_schema") != "S26_PRIMARY_CANDIDATE_HOLDOUT_MANIFEST_V1":
        raise RuntimeError("PRIOR_RESULT_SCHEMA_MISMATCH")
    binding = value.get("candidate_binding") or {}
    if str(binding.get("candidate_head") or "") != EXPECTED_PRIOR_HEAD:
        raise RuntimeError("PRIOR_CANDIDATE_HEAD_MISMATCH")
    if str(binding.get("github_run_id") or "") != EXPECTED_PRIOR_RUN_ID:
        raise RuntimeError("PRIOR_RUN_BINDING_MISMATCH")
    if value.get("status") != "FAIL_CLOSED":
        raise RuntimeError("PRIOR_RESULT_NOT_FAIL_CLOSED")
    if value.get("promotion_authorized") is not False:
        raise RuntimeError("PRIOR_PROMOTION_SCOPE_ESCALATION")
    return value


def _witness_result(prior: dict[str, Any]) -> dict[str, Any]:
    matches = [
        item
        for item in prior.get("candidate_results") or []
        if isinstance(item, dict) and item.get("case_id") == WITNESS_CASE_ID
    ]
    if len(matches) != 1:
        raise RuntimeError("WITNESS_CASE_NOT_UNIQUE")
    witness = matches[0]
    if witness.get("execution_status") != "COMPLETED":
        raise RuntimeError("WITNESS_EXECUTION_NOT_COMPLETED")
    if witness.get("contract_gate", {}).get("status") != "PASS":
        raise RuntimeError("WITNESS_CONTRACT_NOT_PASS")
    if witness.get("semantic_gate", {}).get("status") != "PASS":
        raise RuntimeError("WITNESS_DETERMINISTIC_SEMANTIC_NOT_PASS")
    if not isinstance(witness.get("output"), dict):
        raise RuntimeError("WITNESS_OUTPUT_MISSING")
    return witness


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prior-result", type=Path, required=True)
    parser.add_argument("--result-path", type=Path, required=True)
    args = parser.parse_args()

    if os.getenv("LF_REPOSITORY_VISIBILITY", "").strip() != "public":
        raise SystemExit("BLOCK S26_MANIFEST_CONTINUATION_ZERO_COST_VISIBILITY")
    if os.getenv("LF_RUNNER_LABEL", "").strip() != "ubuntu-latest":
        raise SystemExit("BLOCK S26_MANIFEST_CONTINUATION_ZERO_COST_RUNNER")
    if os.getenv("LF_LLAMA_SOURCE_COMMIT", "").strip() != holdout.base.LLAMA_COMMIT:
        raise SystemExit("BLOCK S26_MANIFEST_CONTINUATION_LLAMA_COMMIT_MISMATCH")

    plan = holdout._load_json(holdout.PLAN_PATH)
    manifest = holdout._load_json(holdout.MANIFEST_PATH)
    holdout._validate_frozen_plan(plan)
    holdout._validate_manifest(manifest)
    prior = _load_prior(args.prior_result)
    witness = _witness_result(prior)

    prior_manifest = prior.get("manifest_binding") or {}
    if prior_manifest.get("git_blob_sha") != holdout._git_blob_sha(holdout.MANIFEST_PATH):
        raise RuntimeError("MANIFEST_BLOB_CHANGED_SINCE_PRIOR_HOLDOUT")
    if prior_manifest.get("sha256") != _sha256_file(holdout.MANIFEST_PATH):
        raise RuntimeError("MANIFEST_CONTENT_CHANGED_SINCE_PRIOR_HOLDOUT")

    cases = {
        str(item.get("case_id") or ""): item
        for item in plan.get("cases") or []
        if isinstance(item, dict)
    }
    witness_case = cases.get(WITNESS_CASE_ID)
    if not isinstance(witness_case, dict):
        raise RuntimeError("FROZEN_WITNESS_CASE_MISSING")
    evidence = holdout._case_evidence(witness_case, witness)

    verifier = GitHubHostedSemanticMiniJudgeVerifier()
    checks: list[dict[str, Any]] = []
    work_root = Path(os.environ.get("RUNNER_TEMP") or tempfile.gettempdir()).resolve()
    with GitHubHostedSemanticMiniJudge(
        work_dir=work_root / "s26-manifest-continuation-independent-judge"
    ) as judge:
        for obligation in manifest["obligations"]:
            check_id = str(obligation["check_id"])
            if check_id == holdout.ROUTER_DIRECT_CHECK_ID:
                checks.append(
                    {
                        "obligation_id": obligation["obligation_id"],
                        "check_id": check_id,
                        "verdict": "NOT_APPLICABLE",
                        "reason_code": "NO_ROUTER_DIRECT_COUNTERPART_OR_CONSISTENCY_CLAIM_IN_BOUNDED_WITNESS",
                        "verification": {
                            "verified": True,
                            "method": "DETERMINISTIC_APPLICABILITY_FROM_FROZEN_BENCHMARK_INPUT",
                        },
                        "rule_sha256": holdout._sha256_text(str(obligation["rule"])),
                        "witness_case_id": WITNESS_CASE_ID,
                    }
                )
                continue
            judged = holdout._judge_one(
                judge=judge,
                verifier=verifier,
                check_id=check_id,
                rule=str(obligation["rule"]),
                question=str(obligation["question"]),
                evidence=evidence,
            )
            judged["obligation_id"] = obligation["obligation_id"]
            judged["witness_case_id"] = WITNESS_CASE_ID
            checks.append(judged)

    required = [str(item["check_id"]) for item in manifest["obligations"]]
    observed_ids = [str(item.get("check_id") or "") for item in checks]
    coverage_complete = (
        len(checks) == len(required)
        and len(set(observed_ids)) == len(required)
        and set(observed_ids) == set(required)
    )
    semantic_pass = coverage_complete and all(
        (
            item.get("verdict") == "COMPLIES"
            and item.get("verification", {}).get("verified") is True
        )
        or (
            item.get("check_id") == holdout.ROUTER_DIRECT_CHECK_ID
            and item.get("verdict") == "NOT_APPLICABLE"
            and item.get("verification", {}).get("verified") is True
        )
        for item in checks
    )

    payload = {
        "result_schema": "S26_MANIFEST_CONTINUATION_V1",
        "status": "PASS" if semantic_pass else "FAIL_CLOSED",
        "strategy": "S26",
        "scope": "PREBOUND_MANIFEST_EXECUTION_ONLY_FROM_DURABLE_FROZEN_HOLDOUT_WITNESS",
        "prior_holdout_binding": {
            "run_id": EXPECTED_PRIOR_RUN_ID,
            "candidate_head": EXPECTED_PRIOR_HEAD,
            "artifact_id": EXPECTED_ARTIFACT_ID,
            "artifact_digest": EXPECTED_ARTIFACT_DIGEST,
            "result_sha256": EXPECTED_PRIOR_RESULT_SHA256,
            "prior_status": prior.get("status"),
            "prior_holdout_judge_status": prior.get("holdout_judge_status"),
        },
        "witness_case_id": WITNESS_CASE_ID,
        "witness_raw_output_sha256": witness.get("raw_output_sha256"),
        "manifest_binding": {
            "path": str(holdout.MANIFEST_PATH.relative_to(holdout.base.REPO_ROOT)),
            "git_blob_sha": holdout._git_blob_sha(holdout.MANIFEST_PATH),
            "sha256": _sha256_file(holdout.MANIFEST_PATH),
            "obligation_count": len(required),
            "required_check_ids": required,
        },
        "checks": checks,
        "coverage_complete": coverage_complete,
        "semantic_status": "PASS" if semantic_pass else "FAIL",
        "complete_profile_obligation_manifest_executed": True,
        "judge_binding": {
            "model_id": SEMANTIC_MODEL_ID,
            "model_sha256": SEMANTIC_MODEL_SHA256,
        },
        "candidate_rerun_executed": False,
        "holdout_tuning_executed": False,
        "overall_candidate_disposition": "NO_PROMOTE_LOCKED_BY_PRIOR_HOLDOUT_FAILURE_AND_RESOURCE_BLOCK",
        "operational_parity": False,
        "downstream_authorized": False,
        "authority_changed": False,
        "production_mutation": False,
        "promotion_authorized": False,
        "paid_provider_call_executed": False,
        "api_cost_incurred": False,
    }
    args.result_path.parent.mkdir(parents=True, exist_ok=True)
    args.result_path.write_text(
        json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "S26_MANIFEST_CONTINUATION="
        + json.dumps(
            {
                "status": payload["status"],
                "coverage_complete": coverage_complete,
                "semantic_status": payload["semantic_status"],
                "complete_profile_obligation_manifest_executed": True,
                "overall_candidate_disposition": payload["overall_candidate_disposition"],
                "result_path": str(args.result_path),
            },
            sort_keys=True,
        ),
        flush=True,
    )
    if semantic_pass:
        print("S26_MANIFEST_CONTINUATION_PASS_NO_PROMOTION", flush=True)
    else:
        print("S26_MANIFEST_CONTINUATION_FAIL_CLOSED_NO_PROMOTION", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
