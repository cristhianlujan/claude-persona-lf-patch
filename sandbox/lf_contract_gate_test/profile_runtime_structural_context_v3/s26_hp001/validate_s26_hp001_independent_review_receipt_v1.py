#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = "cristhianlujan/claude-persona-lf-patch"
SOURCE_SHA = "d8c10954d5a6058ffdde7f4b520efcbabf50d180"
ARTIFACT_TEXT_SHA = "bde82803a3116054d9d8b6fc81912fb97582278d"
ARTIFACT_TEXT_PATH = "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_f_exact_materialized_output.review.json"
ARTIFACT_REF = f"github://{REPO}@{ARTIFACT_TEXT_SHA}/{ARTIFACT_TEXT_PATH}"
ARTIFACT_SHA256 = "5d938ada46cdaf809ad38791d3c9b59f8c9f6134d0577cbca2f56ac4bf71c3a7"
GZIP_SHA256 = "45d32702a97a8d9141d1283cfa3065221434ae2cc9bc19f138bca61010999b2a"
ARTIFACT_DIGEST = f"decompressed_sha256={ARTIFACT_SHA256};gzip_sha256={GZIP_SHA256}"

EXPECTED_CASE = {
    "GPT": "S26-HP001-COLD-GPT-QUALITY-001",
    "CLAUDE": "S26-HP001-COLD-CLAUDE-QUALITY-001",
}

EXPECTED_SOURCE_REFS = {
    "upstream_worker_contract_ref": f"github://{REPO}@{SOURCE_SHA}/profiles/ui_architect/SKILL.md",
    "quality_gate_contract_ref": f"github://{REPO}@{SOURCE_SHA}/profiles/quality_pack/contracts/quality_gate_contract.md",
    "lf_quality_controls_ref": f"github://{REPO}@{SOURCE_SHA}/profiles/quality_pack/contracts/lf_quality_controls.md",
    "score_rubric_ref": f"github://{REPO}@{SOURCE_SHA}/profiles/quality_pack/judges/quality_pack_score_rubric.md",
    "mini_judge_ref": f"github://{REPO}@{SOURCE_SHA}/profiles/quality_pack/judges/quality_pack_mini_judge.md",
    "quality_review_schema_ref": f"github://{REPO}@{SOURCE_SHA}/profiles/quality_pack/schemas/quality_review.schema.json",
}

EXPECTED_CONTENT_SHA = {
    "profiles/ui_architect/SKILL.md": "b099944839af79cb97eac76f12ecf8bd38c39ea331224ee335ced32491f411c0",
    "profiles/quality_pack/contracts/quality_gate_contract.md": "6c2543a891143dbbec4d0f71eb134da2ac36b4d75fca174b885b4b00429c1553",
    "profiles/quality_pack/contracts/lf_quality_controls.md": "069962007fc1cc4320f3ead807973241c710f140e62d6869c2030c11552fe297",
    "profiles/quality_pack/judges/quality_pack_score_rubric.md": "cfb928f5e7d375bcf478666f704d617714be3c7369e8524fc387e78f290e0698",
    "profiles/quality_pack/judges/quality_pack_mini_judge.md": "b6191adfc3895398c5aa480998d130642fc0dd904208d86f884d998254b3e359",
    "profiles/quality_pack/schemas/quality_review.schema.json": "26eb79a876be9c7fb8aa699d7f7a549f361b0836d322995f4a5282c1b12443c3",
    "profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json": "8d126b2bf5dde42b88fc3fb334ab4d6ed25f6180497328159c501fcb80db808c",
    "profiles/quality_pack/validators/validate_independent_semantic_review.py": "8280788b32749887ca680a7f13a195aa2a5ec454f2dd1c8390b307bc60bf53ba",
    "profiles/quality_pack/validators/validate_routing.py": "9a03306077848d6cb9fb68a42078c26ad51d9d5a83f2ac73e823e479e1dea5c1",
}

HEX64 = re.compile(r"^[0-9a-f]{64}$")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_show(repo_root: Path, commit: str, path: str) -> bytes:
    proc = subprocess.run(
        ["git", "-c", f"safe.directory={repo_root}", "show", f"{commit}:{path}"],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"git show failed for {commit}:{path}: {proc.stderr.decode('utf-8', 'replace')[:300]}")
    return proc.stdout


def validate(repo_root: Path, receipt_path: Path, reviewer: str) -> list[str]:
    errors: list[str] = []
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))

    if receipt.get("review_case_id") != EXPECTED_CASE[reviewer]:
        errors.append("REVIEW_CASE_ID_MISMATCH")

    source = receipt.get("source_bundle")
    if not isinstance(source, dict):
        errors.append("SOURCE_BUNDLE_REQUIRED")
        source = {}
    if source.get("artifact_ref") != ARTIFACT_REF:
        errors.append("ARTIFACT_REF_MISMATCH")
    if source.get("artifact_sha_or_digest") != ARTIFACT_DIGEST:
        errors.append("ARTIFACT_DIGEST_BINDING_MISMATCH")
    for field, expected in EXPECTED_SOURCE_REFS.items():
        if source.get(field) != expected:
            errors.append(f"SOURCE_REF_MISMATCH:{field}")

    review = receipt.get("quality_review")
    if not isinstance(review, dict):
        errors.append("QUALITY_REVIEW_REQUIRED")
        review = {}
    if review.get("reviewed_artifact") != ARTIFACT_REF:
        errors.append("REVIEWED_ARTIFACT_MISMATCH")
    if not isinstance(review.get("routing"), dict):
        errors.append("QUALITY_REVIEW_ROUTING_REQUIRED")

    evidence_map = review.get("evidence_map")
    if not isinstance(evidence_map, list) or not evidence_map:
        errors.append("EVIDENCE_MAP_REQUIRED")
    else:
        for idx, item in enumerate(evidence_map):
            if not isinstance(item, dict):
                errors.append(f"EVIDENCE_MAP_ITEM_NOT_OBJECT:{idx}")
                continue
            for key in ("criterion", "decision_basis", "evidence_ref", "evidence_sha256"):
                if not isinstance(item.get(key), str) or not item[key].strip():
                    errors.append(f"EVIDENCE_MAP_FIELD_REQUIRED:{idx}:{key}")
            ev_sha = item.get("evidence_sha256")
            if isinstance(ev_sha, str) and not HEX64.fullmatch(ev_sha):
                errors.append(f"EVIDENCE_MAP_SHA_INVALID:{idx}")

    artifact_bytes = git_show(repo_root, ARTIFACT_TEXT_SHA, ARTIFACT_TEXT_PATH)
    if sha256(artifact_bytes) != ARTIFACT_SHA256:
        errors.append("IMMUTABLE_ARTIFACT_SHA_MISMATCH")

    immutable_paths = list(EXPECTED_CONTENT_SHA)
    for path in immutable_paths:
        try:
            content = git_show(repo_root, SOURCE_SHA, path)
        except RuntimeError:
            errors.append(f"IMMUTABLE_SOURCE_UNRESOLVED:{path}")
            continue
        if sha256(content) != EXPECTED_CONTENT_SHA[path]:
            errors.append(f"IMMUTABLE_SOURCE_SHA_MISMATCH:{path}")

    with tempfile.TemporaryDirectory(prefix="s26_hp001_review_validate_") as td:
        td_path = Path(td)
        validator_path = td_path / "validate_independent_semantic_review.py"
        routing_path = td_path / "validate_routing.py"
        quality_schema_path = td_path / "quality_review.schema.json"
        validator_path.write_bytes(git_show(repo_root, SOURCE_SHA, "profiles/quality_pack/validators/validate_independent_semantic_review.py"))
        routing_path.write_bytes(git_show(repo_root, SOURCE_SHA, "profiles/quality_pack/validators/validate_routing.py"))
        quality_schema_path.write_bytes(git_show(repo_root, SOURCE_SHA, "profiles/quality_pack/schemas/quality_review.schema.json"))

        proc = subprocess.run([sys.executable, str(validator_path), str(receipt_path)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if proc.returncode != 0:
            errors.append("OFFICIAL_INDEPENDENT_RECEIPT_VALIDATOR_FAILED")

        quality_path = td_path / "quality_review.json"
        quality_path.write_text(json.dumps(review, ensure_ascii=False), encoding="utf-8")
        proc = subprocess.run([sys.executable, str(routing_path), str(quality_path)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if proc.returncode != 0:
            errors.append("OFFICIAL_ROUTING_VALIDATOR_FAILED")

        try:
            import jsonschema
            schema = json.loads(quality_schema_path.read_text(encoding="utf-8"))
            jsonschema.validate(review, schema)
        except Exception as exc:
            errors.append(f"QUALITY_REVIEW_SCHEMA_FAILED:{type(exc).__name__}")

    if receipt.get("review_completed") is True:
        if receipt.get("reviewer_is_producer") is not False or receipt.get("producer_context_available") is not False:
            errors.append("INDEPENDENCE_METADATA_INVALID")

    if review.get("verdict") in {"PASS_TO_COMPOSER", "PASS_WITH_RESTRICTIONS"} and review.get("next_gate") != "GOLDEN_ELIGIBILITY":
        errors.append("PASS_NEXT_GATE_MUST_BE_GOLDEN_ELIGIBILITY")

    return sorted(set(errors))


def main() -> int:
    parser = argparse.ArgumentParser(description="S26 HP001 exact independent-review receipt validator")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--reviewer", choices=sorted(EXPECTED_CASE), required=True)
    parser.add_argument("receipt")
    args = parser.parse_args()
    errors = validate(Path(args.repo_root).resolve(), Path(args.receipt).resolve(), args.reviewer)
    result = {
        "valid": not errors,
        "reviewer": args.reviewer,
        "receipt": str(Path(args.receipt).resolve()),
        "artifact_ref": ARTIFACT_REF,
        "artifact_sha256": ARTIFACT_SHA256,
        "errors": errors,
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
