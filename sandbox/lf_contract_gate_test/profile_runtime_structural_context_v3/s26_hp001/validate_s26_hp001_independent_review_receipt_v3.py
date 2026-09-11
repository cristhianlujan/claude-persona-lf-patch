#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

SOURCE_SHA = "d8c10954d5a6058ffdde7f4b520efcbabf50d180"
ARTIFACT_COMMIT = "bde82803a3116054d9d8b6fc81912fb97582278d"
ARTIFACT_PATH = "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_f_exact_materialized_output.review.json"
ARTIFACT_REF = f"github://cristhianlujan/claude-persona-lf-patch@{ARTIFACT_COMMIT}/{ARTIFACT_PATH}"
ARTIFACT_SHA256 = "5d938ada46cdaf809ad38791d3c9b59f8c9f6134d0577cbca2f56ac4bf71c3a7"
ARTIFACT_DIGEST = "decompressed_sha256=5d938ada46cdaf809ad38791d3c9b59f8c9f6134d0577cbca2f56ac4bf71c3a7;gzip_sha256=45d32702a97a8d9141d1283cfa3065221434ae2cc9bc19f138bca61010999b2a"

EXPECTED_CASE = {
    "GPT": "S26-HP001-COLD-GPT-QUALITY-001",
    "CLAUDE": "S26-HP001-COLD-CLAUDE-QUALITY-001",
}
EXPECTED_REVIEW_ID = {
    "GPT": "S26-HP001-COLD-GPT-QUALITY-REVIEW-001",
    "CLAUDE": "S26-HP001-COLD-CLAUDE-QUALITY-REVIEW-001",
}

EXPECTED_SOURCE = {
    "artifact_ref": ARTIFACT_REF,
    "upstream_worker_contract_ref": f"github://cristhianlujan/claude-persona-lf-patch@{SOURCE_SHA}/profiles/ui_architect/SKILL.md",
    "quality_gate_contract_ref": f"github://cristhianlujan/claude-persona-lf-patch@{SOURCE_SHA}/profiles/quality_pack/contracts/quality_gate_contract.md",
    "lf_quality_controls_ref": f"github://cristhianlujan/claude-persona-lf-patch@{SOURCE_SHA}/profiles/quality_pack/contracts/lf_quality_controls.md",
    "score_rubric_ref": f"github://cristhianlujan/claude-persona-lf-patch@{SOURCE_SHA}/profiles/quality_pack/judges/quality_pack_score_rubric.md",
    "mini_judge_ref": f"github://cristhianlujan/claude-persona-lf-patch@{SOURCE_SHA}/profiles/quality_pack/judges/quality_pack_mini_judge.md",
    "quality_review_schema_ref": f"github://cristhianlujan/claude-persona-lf-patch@{SOURCE_SHA}/profiles/quality_pack/schemas/quality_review.schema.json",
}

SCORE_KEYS = [
    "contract_schema_compliance",
    "evidence_integrity",
    "lf_safety_governance",
    "handoff_readiness",
    "leakage_scope_control",
]

EXPECTED_EVIDENCE = {
    "contract_schema_compliance": (
        f"github://cristhianlujan/claude-persona-lf-patch@{SOURCE_SHA}/profiles/ui_architect/schemas/ui_production_spec.schema.json",
        "7f10c952796b045b99069b446f8dd7582d641d3514c25253fd27782045547112",
    ),
    "evidence_integrity": (ARTIFACT_REF, ARTIFACT_SHA256),
    "lf_safety_governance": (
        f"github://cristhianlujan/claude-persona-lf-patch@{SOURCE_SHA}/profiles/quality_pack/contracts/lf_quality_controls.md",
        "069962007fc1cc4320f3ead807973241c710f140e62d6869c2030c11552fe297",
    ),
    "handoff_readiness": (ARTIFACT_REF, ARTIFACT_SHA256),
    "leakage_scope_control": (
        f"github://cristhianlujan/claude-persona-lf-patch@{SOURCE_SHA}/profiles/ui_architect/contracts/composer_payload_boundary_v1.md",
        "d2b55e3c29c45642ebe18084b23c1ae96064c8c0a6bd8ecb1f5910f2753bb617",
    ),
}

ROUTES = {
    "PASS_TO_COMPOSER": ("CONTINUE", "COMPOSER", "GOLDEN_ELIGIBILITY"),
    "PASS_WITH_RESTRICTIONS": ("CONTINUE_WITH_RESTRICTIONS", "COMPOSER", "GOLDEN_ELIGIBILITY"),
    "RETURN_TO_WORKER_FOR_SELF_REPAIR": ("RETURN_TO_ORCHESTRATOR", "PRODUCER_REPAIR", "PRODUCER_REPAIR"),
    "RETURN_TO_ORCHESTRATOR": ("RETURN_TO_ORCHESTRATOR", "AUTHORITY_OR_CONTEXT_RESOLUTION", "AUTHORITY_OR_CONTEXT_RESOLUTION"),
    "BLOCK_PIPELINE": ("BLOCK_PIPELINE", "NONE", "NONE"),
}

TOP_KEYS = {
    "receipt_version", "execution_mode", "semantic_status", "review_case_id",
    "reviewer_is_producer", "producer_context_available", "external_paid_model_used",
    "automated_semantic_judge_implemented", "review_completed", "source_bundle",
    "quality_review", "execution_blockers",
}
SOURCE_KEYS = set(EXPECTED_SOURCE) | {"artifact_sha_or_digest"}
REVIEW_KEYS = {
    "review_id", "reviewed_artifact", "verdict", "score_breakdown", "evidence_map",
    "blocking_codes", "repair_actions", "remaining_risks", "next_gate", "routing",
}
ROUTING_KEYS = {"activation_path", "via", "pipeline_action", "resolution_target"}
EVIDENCE_KEYS = {"criterion", "decision_basis", "evidence_ref", "evidence_sha256"}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_show(repo_root: Path, commit: str, path: str) -> bytes:
    proc = subprocess.run(
        ["git", "-c", f"safe.directory={repo_root}", "show", f"{commit}:{path}"],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode:
        raise RuntimeError(proc.stderr.decode("utf-8", "replace")[:500])
    return proc.stdout


def validate(repo_root: Path, receipt_path: Path, reviewer: str) -> list[str]:
    errors: list[str] = []
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))

    if set(receipt) != TOP_KEYS:
        errors.append("TOP_LEVEL_KEYSET_MISMATCH")
    if receipt.get("review_case_id") != EXPECTED_CASE[reviewer]:
        errors.append("REVIEW_CASE_ID_MISMATCH")

    source = receipt.get("source_bundle")
    source = source if isinstance(source, dict) else {}
    if set(source) != SOURCE_KEYS:
        errors.append("SOURCE_BUNDLE_KEYSET_MISMATCH")
    if source.get("artifact_sha_or_digest") != ARTIFACT_DIGEST:
        errors.append("ARTIFACT_DIGEST_BINDING_MISMATCH")
    for key, expected in EXPECTED_SOURCE.items():
        if source.get(key) != expected:
            errors.append(f"SOURCE_REF_MISMATCH:{key}")

    review = receipt.get("quality_review")
    review = review if isinstance(review, dict) else {}
    if set(review) != REVIEW_KEYS:
        errors.append("QUALITY_REVIEW_KEYSET_MISMATCH")
    if review.get("review_id") != EXPECTED_REVIEW_ID[reviewer]:
        errors.append("REVIEW_ID_MISMATCH")
    if review.get("reviewed_artifact") != ARTIFACT_REF:
        errors.append("REVIEWED_ARTIFACT_MISMATCH")

    score = review.get("score_breakdown")
    score = score if isinstance(score, dict) else {}
    if set(score) != set(SCORE_KEYS + ["total"]):
        errors.append("SCORE_KEYSET_MISMATCH")

    routing = review.get("routing")
    routing = routing if isinstance(routing, dict) else {}
    if set(routing) != ROUTING_KEYS:
        errors.append("ROUTING_KEYSET_MISMATCH")
    if routing.get("activation_path") != "DIRECT":
        errors.append("ACTIVATION_PATH_MUST_BE_DIRECT")

    verdict = review.get("verdict")
    if verdict in ROUTES:
        action, target, next_gate = ROUTES[verdict]
        if routing.get("via") != "ORCHESTRATOR":
            errors.append("ROUTING_VIA_MISMATCH")
        if routing.get("pipeline_action") != action:
            errors.append("ROUTING_ACTION_MISMATCH")
        if routing.get("resolution_target") != target:
            errors.append("ROUTING_TARGET_MISMATCH")
        if review.get("next_gate") != next_gate:
            errors.append("NEXT_GATE_BINDING_MISMATCH")

    evidence = review.get("evidence_map")
    if not isinstance(evidence, list) or len(evidence) != 5:
        errors.append("EVIDENCE_MAP_MUST_HAVE_EXACTLY_5_ITEMS")
    else:
        for index, criterion in enumerate(SCORE_KEYS):
            item = evidence[index]
            if not isinstance(item, dict) or set(item) != EVIDENCE_KEYS:
                errors.append(f"EVIDENCE_ITEM_KEYSET_MISMATCH:{index}")
                continue
            if item.get("criterion") != criterion:
                errors.append(f"EVIDENCE_CRITERION_ORDER_MISMATCH:{index}")
            if not isinstance(item.get("decision_basis"), str) or not item["decision_basis"].strip():
                errors.append(f"EVIDENCE_DECISION_BASIS_REQUIRED:{index}")
            expected_ref, expected_sha = EXPECTED_EVIDENCE[criterion]
            if item.get("evidence_ref") != expected_ref:
                errors.append(f"EVIDENCE_REF_BINDING_MISMATCH:{criterion}")
            if item.get("evidence_sha256") != expected_sha:
                errors.append(f"EVIDENCE_SHA_BINDING_MISMATCH:{criterion}")

    try:
        artifact = git_show(repo_root, ARTIFACT_COMMIT, ARTIFACT_PATH)
        if sha256(artifact) != ARTIFACT_SHA256:
            errors.append("IMMUTABLE_ARTIFACT_SHA_MISMATCH")
    except Exception:
        errors.append("IMMUTABLE_ARTIFACT_UNRESOLVED")

    with tempfile.TemporaryDirectory(prefix="s26_hp001_review_v3_") as tmp:
        tmp_path = Path(tmp)
        independent_validator = tmp_path / "independent.py"
        routing_validator = tmp_path / "routing.py"
        quality_schema = tmp_path / "quality_review.schema.json"
        quality_payload = tmp_path / "quality_review.json"
        try:
            independent_validator.write_bytes(git_show(repo_root, SOURCE_SHA, "profiles/quality_pack/validators/validate_independent_semantic_review.py"))
            routing_validator.write_bytes(git_show(repo_root, SOURCE_SHA, "profiles/quality_pack/validators/validate_routing.py"))
            quality_schema.write_bytes(git_show(repo_root, SOURCE_SHA, "profiles/quality_pack/schemas/quality_review.schema.json"))
            quality_payload.write_text(json.dumps(review, ensure_ascii=False), encoding="utf-8")

            proc = subprocess.run([sys.executable, str(independent_validator), str(receipt_path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if proc.returncode:
                errors.append("OFFICIAL_INDEPENDENT_RECEIPT_VALIDATOR_FAILED")

            proc = subprocess.run([sys.executable, str(routing_validator), str(quality_payload)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if proc.returncode:
                errors.append("OFFICIAL_ROUTING_VALIDATOR_FAILED")

            try:
                import jsonschema
                jsonschema.validate(review, json.loads(quality_schema.read_text(encoding="utf-8")))
            except Exception as exc:
                errors.append(f"QUALITY_REVIEW_SCHEMA_FAILED:{type(exc).__name__}")
        except Exception:
            errors.append("OFFICIAL_VALIDATOR_ASSET_UNRESOLVED")

    return sorted(set(errors))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--reviewer", choices=["GPT", "CLAUDE"], required=True)
    parser.add_argument("receipt")
    args = parser.parse_args()
    errors = validate(Path(args.repo_root).resolve(), Path(args.receipt).resolve(), args.reviewer)
    print(json.dumps({"valid": not errors, "reviewer": args.reviewer, "artifact_sha256": ARTIFACT_SHA256, "errors": errors}, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
