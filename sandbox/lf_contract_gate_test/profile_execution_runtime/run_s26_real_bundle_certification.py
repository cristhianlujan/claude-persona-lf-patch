#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from s26_bundle_certification import build_bundle, certify_zip, dump_json

REPO = "cristhianlujan/claude-persona-lf-patch"
RUN_ID = "EXEC-S26-N08E-GPT-NATIVE-GOLDEN-E-001"
EVIDENCE_REL = Path("sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005")
GITHUB_REF_RE = re.compile(r"^github://([^@]+)@([0-9a-f]{40})/(.+)$")


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def iter_refs(value):
    if isinstance(value, dict):
        for item in value.values():
            yield from iter_refs(item)
    elif isinstance(value, list):
        for item in value:
            yield from iter_refs(item)
    elif isinstance(value, str) and value.startswith("github://"):
        yield value


def git_show(repo_root: Path, revision: str, source_path: str) -> bytes:
    proc = subprocess.run(
        ["git", "show", f"{revision}:{source_path}"],
        cwd=repo_root,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        detail = proc.stderr.decode("utf-8", errors="replace").strip()[:300]
        raise RuntimeError(f"GIT_SHOW_FAILED:{revision}:{source_path}:{detail}")
    return proc.stdout


def stage_current(repo_root: Path, stage: Path, rel: Path) -> str:
    src = repo_root / rel
    if not src.is_file():
        raise RuntimeError(f"REAL_SOURCE_MISSING:{rel.as_posix()}")
    target_rel = Path("current") / rel
    dst = stage / target_rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    return target_rel.as_posix()


def stage_historical(repo_root: Path, stage: Path, revision: str, rel: str) -> str:
    target_rel = Path("historical") / revision / rel
    dst = stage / target_rel
    if not dst.is_file():
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(git_show(repo_root, revision, rel))
    return target_rel.as_posix()


def category_for(rel: str) -> str:
    if rel.endswith("/input.txt") or rel.endswith("input.txt"):
        return "input"
    if rel.startswith("cards/"):
        return "cards_context"
    if rel.startswith("profiles/") or rel.startswith("adapters/"):
        return "authority"
    return "evidence"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", type=Path, required=True)
    ap.add_argument("--zip", dest="zip_path", type=Path, required=True)
    ap.add_argument("--receipt-out", type=Path, required=True)
    args = ap.parse_args()

    repo_root = Path(__file__).resolve().parents[3]
    head_sha = os.environ.get("GITHUB_SHA") or subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=repo_root, text=True
    ).strip()
    branch = os.environ.get("GITHUB_HEAD_REF") or os.environ.get("GITHUB_REF_NAME") or "lf/s26-c-bundle-certification-20260909"
    base_sha = os.environ.get("S26_C_BASE_SHA", "9632cab4acde619ac7c5b68a3259e31acf5c557d")

    artifact_repo_rel = EVIDENCE_REL / "raw_output.json"
    execution_repo_rel = EVIDENCE_REL / "execution_receipt.json"
    governance_repo_rel = EVIDENCE_REL / "governed_context_receipt.json"
    semantic_repo_rel = EVIDENCE_REL / "semantic_check_bundle.json"
    visual_ref_repo_rel = EVIDENCE_REL / "visual_artifact_ref.json"
    handoff_repo_rel = EVIDENCE_REL / "independent_quality_review_handoff.md"
    validator_repo_rel = Path("sandbox/lf_contract_gate_test/profile_execution_runtime/s26_real_bundle_replay_validator.py")

    artifact = read_json(repo_root / artifact_repo_rel)
    execution = read_json(repo_root / execution_repo_rel)
    execution_id = execution.get("execution_id")
    if execution_id != RUN_ID:
        raise RuntimeError(f"REAL_EXECUTION_ID_MISMATCH:{execution_id}")

    governance = artifact.get("deliverable_created", {}).get("governance_context", {})
    pinned = governance.get("prebound_commit_sha")
    if not isinstance(pinned, str) or not re.fullmatch(r"[0-9a-f]{40}", pinned):
        raise RuntimeError(f"REAL_PREBOUND_SHA_INVALID:{pinned}")

    with tempfile.TemporaryDirectory(prefix="s26_real_bundle_stage_") as td:
        stage = Path(td) / "stage"
        stage.mkdir()

        artifact_source = stage_current(repo_root, stage, artifact_repo_rel)
        execution_source = stage_current(repo_root, stage, execution_repo_rel)
        governance_source = stage_current(repo_root, stage, governance_repo_rel)
        semantic_source = stage_current(repo_root, stage, semantic_repo_rel)
        visual_ref_source = stage_current(repo_root, stage, visual_ref_repo_rel)
        handoff_source = stage_current(repo_root, stage, handoff_repo_rel)
        validator_source = stage_current(repo_root, stage, validator_repo_rel)

        explicit_historical = [
            "profiles/ui_architect/SKILL.md",
            "profiles/ui_architect/contracts/existing_screen_review.md",
        ]
        items = [
            {
                "category": "evidence",
                "source": execution_source,
                "bundle_path": "evidence/execution_receipt.json",
                "source_revision": head_sha,
            },
            {
                "category": "evidence",
                "source": governance_source,
                "bundle_path": "evidence/governed_context_receipt.json",
                "source_revision": head_sha,
            },
            {
                "category": "evidence",
                "source": semantic_source,
                "bundle_path": "evidence/semantic_check_bundle.json",
                "source_revision": head_sha,
            },
            {
                "category": "evidence",
                "source": visual_ref_source,
                "bundle_path": "evidence/visual_artifact_ref.json",
                "source_revision": head_sha,
            },
            {
                "category": "evidence",
                "source": handoff_source,
                "bundle_path": "evidence/independent_quality_review_handoff.md",
                "source_revision": head_sha,
            },
        ]
        external_ref_map: dict[str, str] = {}
        seen_refs: set[str] = set()

        scan_paths = [
            stage / artifact_source,
            stage / execution_source,
            stage / governance_source,
            stage / semantic_source,
            stage / visual_ref_source,
        ]
        idx = 0
        while idx < len(scan_paths):
            path = scan_paths[idx]
            idx += 1
            if path.suffix.lower() != ".json":
                continue
            obj = read_json(path)
            for ref in iter_refs(obj):
                if ref in seen_refs:
                    continue
                seen_refs.add(ref)
                match = GITHUB_REF_RE.match(ref)
                if not match:
                    raise RuntimeError(f"REAL_GITHUB_REF_UNPINNED:{ref}")
                repo_name, revision, source_rel = match.groups()
                if repo_name != REPO:
                    raise RuntimeError(f"REAL_EXTERNAL_REPO_FORBIDDEN:{repo_name}")
                staged = stage_historical(repo_root, stage, revision, source_rel)
                bundle_rel = f"dependencies/{revision}/{source_rel}"
                external_ref_map[ref] = bundle_rel
                category = category_for(source_rel)
                items.append({
                    "category": category,
                    "source": staged,
                    "bundle_path": bundle_rel,
                    "source_revision": revision,
                })
                if source_rel.endswith(".json"):
                    scan_paths.append(stage / staged)

        existing_bundle_paths = {x["bundle_path"] for x in items}
        for source_rel in explicit_historical:
            staged = stage_historical(repo_root, stage, pinned, source_rel)
            bundle_rel = f"dependencies/{pinned}/{source_rel}"
            if bundle_rel not in existing_bundle_paths:
                items.append({
                    "category": "authority",
                    "source": staged,
                    "bundle_path": bundle_rel,
                    "source_revision": pinned,
                })
                existing_bundle_paths.add(bundle_rel)

        input_bundle = external_ref_map.get(
            f"github://{REPO}@{pinned}/{EVIDENCE_REL.as_posix()}/input.txt"
        )
        card_bundle = external_ref_map.get(
            f"github://{REPO}@{pinned}/cards/marketplace_lf/decision_product_experience/CARD.md"
        )
        input_governance_bundle = external_ref_map.get(
            f"github://{REPO}@{pinned}/{EVIDENCE_REL.as_posix()}/input_governance_snapshot.json"
        )
        if not input_bundle or not card_bundle or not input_governance_bundle:
            raise RuntimeError("REAL_REQUIRED_PROTOCOL_DEPENDENCY_MISSING")

        authority_bundle = f"dependencies/{pinned}/profiles/ui_architect/SKILL.md"

        spec = {
            "schema": "S26_REVIEW_BUNDLE_SPEC_V1",
            "run_id": RUN_ID,
            "run_metadata": {
                "run_id": RUN_ID,
                "base_sha": base_sha,
                "branch": branch,
                "head_sha": head_sha,
            },
            "artifact": {
                "source": artifact_source,
                "bundle_path": "artifact/raw_output.json",
                "source_revision": head_sha,
            },
            "items": items,
            "generated_receipts": [{
                "bundle_path": "receipts/s26_c_artifact_binding_receipt.json",
                "metadata": {
                    "source_execution_receipt": "bundle://evidence/execution_receipt.json",
                    "source_execution_id": RUN_ID,
                },
            }],
            "validators": [{
                "source": validator_source,
                "bundle_path": "validators/s26_real_bundle_replay_validator.py",
                "source_revision": head_sha,
                "argv": [
                    "python3",
                    "validators/s26_real_bundle_replay_validator.py",
                    "artifact/raw_output.json",
                    input_bundle,
                    "evidence/execution_receipt.json",
                    input_governance_bundle,
                    card_bundle,
                    authority_bundle,
                ],
            }],
            "external_ref_map": external_ref_map,
        }
        spec_path = stage / "real_bundle_spec.json"
        dump_json(spec_path, spec)

        build_bundle(spec_path, stage, args.out_dir, args.zip_path)
        receipt = certify_zip(args.zip_path, replay=True)
        dump_json(args.receipt_out, receipt)
        if receipt.get("status") != "PASS":
            raise RuntimeError("REAL_BUNDLE_CERTIFICATION_FAILED:" + "|".join(receipt.get("errors", [])))

    print(json.dumps({
        "status": "PASS",
        "run_id": RUN_ID,
        "head_sha": head_sha,
        "bundle": str(args.zip_path),
        "receipt": str(args.receipt_out),
        "external_dependency_count": len(external_ref_map),
        "proof": "REAL_S26_REPOSITORY_EVIDENCE_FRESH_UNPACK_REPLAY"
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
