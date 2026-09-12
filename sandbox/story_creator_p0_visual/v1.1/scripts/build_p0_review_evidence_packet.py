#!/usr/bin/env python3
"""Build and verify a reviewable P0 packet without claiming human attestation.

The packet retains the exact source bytes, locked visual output and every crop
referenced by that output.  It remains an ENGINEERING_SMOKE artifact until an
external durable store and an authenticated reviewer readback are available.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image, ImageOps

from admit_p0_image import admit_bytes, canonical_bytes
from p0_schema import validate_instance
from run_p0_visual_worker import (
    CONFIG_PATH,
    crop_pixel_sha,
    dense_fixture,
    parse_images,
    run_worker,
    synthetic_bundle,
)
from validate_p0_j02_handoff import load

ROOT = Path(__file__).resolve().parent.parent
REVIEW_SCHEMA = ROOT / "schemas" / "human-review-packet.schema.json"
SHA1_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
CLASSIFICATIONS = {"PUBLIC", "INTERNAL", "CONFIDENTIAL", "SENSITIVE"}
REVIEWER_ROLES = {"P0_VISUAL_ADJUDICATOR", "P0_SECURITY_REVIEWER", "P0_PRIVACY_REVIEWER"}
FORMAT_SUFFIX = {"PNG": ".png", "JPEG": ".jpg", "WEBP": ".webp"}


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def parse_time(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(timezone.utc)


def safe_child(root: Path, relative: str) -> Path | None:
    if not isinstance(relative, str) or not relative or relative.startswith("/"):
        return None
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        return None
    return candidate


def canonical_write(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(canonical_bytes(value))


def inventory(root: Path) -> list[dict[str, Any]]:
    rows = []
    for path in sorted(root.rglob("*")):
        if path.is_dir() or path.name == "packet-manifest.json":
            continue
        relative = path.relative_to(root).as_posix()
        raw = path.read_bytes()
        rows.append({"path": relative, "bytes": len(raw), "sha256": sha256_bytes(raw)})
    return rows


def crop_box(region: dict[str, Any], width: int, height: int) -> tuple[int, int, int, int]:
    x1 = max(0, min(width - 1, int(region["x"])))
    y1 = max(0, min(height - 1, int(region["y"])))
    x2 = max(x1 + 1, min(width, int(round(region["x"] + region["width"]))))
    y2 = max(y1 + 1, min(height, int(round(region["y"] + region["height"]))))
    return x1, y1, x2, y2


def input_failures(
    *,
    head_sha: str,
    created_at: str,
    expires_at: str,
    data_classification: str,
    required_reviewer_role: str,
    dual_review_required: bool,
    encrypted_evidence_policy_ref: str | None,
) -> list[str]:
    failures = []
    created = parse_time(created_at)
    expires = parse_time(expires_at)
    if not SHA1_RE.fullmatch(head_sha):
        failures.append("head_sha_invalid")
    if created is None or expires is None or created >= expires:
        failures.append("review_window_invalid")
    if data_classification not in CLASSIFICATIONS:
        failures.append("data_classification_invalid")
    if required_reviewer_role not in REVIEWER_ROLES:
        failures.append("required_reviewer_role_invalid")
    if data_classification == "SENSITIVE" and not dual_review_required:
        failures.append("sensitive_packet_requires_dual_review")
    if data_classification == "SENSITIVE" and not (
        isinstance(encrypted_evidence_policy_ref, str)
        and encrypted_evidence_policy_ref.startswith("p0://policy/")
        and len(encrypted_evidence_policy_ref) > len("p0://policy/")
    ):
        failures.append("sensitive_packet_encrypted_policy_missing")
    return failures


def build_packet(
    bundle: dict[str, Any],
    raw_by_ref: dict[str, bytes],
    output_dir: Path,
    *,
    head_sha: str,
    review_id: str,
    execution_id: str,
    created_at: str,
    expires_at: str,
    data_classification: str,
    required_reviewer_role: str,
    dual_review_required: bool,
    encrypted_evidence_policy_ref: str | None,
    engineering_smoke: bool,
) -> dict[str, Any]:
    failures = input_failures(
        head_sha=head_sha,
        created_at=created_at,
        expires_at=expires_at,
        data_classification=data_classification,
        required_reviewer_role=required_reviewer_role,
        dual_review_required=dual_review_required,
        encrypted_evidence_policy_ref=encrypted_evidence_policy_ref,
    )
    if not review_id or not execution_id:
        failures.append("review_or_execution_id_missing")
    if output_dir.exists():
        failures.append("output_dir_must_not_exist")
    if failures:
        return {"result": "BLOCKED", "blocking_assertions": sorted(set(failures)), "p0_4_closed": False}

    config = load(CONFIG_PATH)
    worker = run_worker(bundle, raw_by_ref, config=config, engineering_smoke=engineering_smoke)
    if worker.get("result") != "PASS_WITH_EVIDENCE":
        return {
            "result": "BLOCKED",
            "blocking_assertions": [f"worker:{item}" for item in worker.get("blocking_assertions", [])],
            "p0_4_closed": False,
        }

    visual_output = worker["visual_output"]
    output_dir.mkdir(parents=True)
    source_bindings = []
    normalized_images: dict[str, Image.Image] = {}
    for index, source in enumerate(bundle["source_images"], start=1):
        source_ref = source["ref"]
        admitted = admit_bytes(raw_by_ref[source_ref], source_ref)
        if admitted.get("result") != "PASS_WITH_EVIDENCE":
            return {"result": "BLOCKED", "blocking_assertions": ["source_readmission_failed"], "p0_4_closed": False}
        record = admitted["record"]
        suffix = FORMAT_SUFFIX[record["input_format"]]
        source_rel = f"source/source-{index:03d}{suffix}"
        admission_rel = f"admission/source-{index:03d}-admission.json"
        processing_rel = f"admission/source-{index:03d}-processing-manifest.json"
        (output_dir / source_rel).parent.mkdir(parents=True, exist_ok=True)
        (output_dir / source_rel).write_bytes(raw_by_ref[source_ref])
        canonical_write(output_dir / admission_rel, record)
        canonical_write(output_dir / processing_rel, admitted["processing_manifest"])
        with Image.open(io.BytesIO(raw_by_ref[source_ref])) as opened:
            opened.load()
            normalized_images[source_ref] = ImageOps.exif_transpose(opened).convert("RGBA")
        source_bindings.append({
            "source_ref": source_ref,
            "source_file": source_rel,
            "raw_bytes_sha256": record["raw_bytes_sha256"],
            "normalized_pixel_sha256": record["normalized_pixel_sha256"],
            "admission_file": admission_rel,
            "processing_manifest_file": processing_rel,
        })

    output_rel = "output/visual-output.json"
    canonical_write(output_dir / output_rel, visual_output)
    if sha256_bytes((output_dir / output_rel).read_bytes()) != worker["visual_output_sha256"]:
        return {"result": "BLOCKED", "blocking_assertions": ["visual_output_lock_mismatch"], "p0_4_closed": False}

    crop_bindings = []
    crop_refs = []
    for evidence in visual_output["evidence"]:
        if evidence.get("kind") != "CROP":
            continue
        source_ref = evidence["source_ref"]
        image = normalized_images[source_ref]
        box = crop_box(evidence["region"], image.width, image.height)
        observed_pixel_sha = crop_pixel_sha(image, box)
        if observed_pixel_sha != evidence["sha256"]:
            return {"result": "BLOCKED", "blocking_assertions": ["crop_pixel_hash_mismatch"], "p0_4_closed": False}
        crop_rel = f"crops/{evidence['evidence_id']}.png"
        crop = image.crop(box).convert("RGBA")
        buffer = io.BytesIO()
        crop.save(buffer, format="PNG")
        crop_raw = buffer.getvalue()
        (output_dir / crop_rel).parent.mkdir(parents=True, exist_ok=True)
        (output_dir / crop_rel).write_bytes(crop_raw)
        crop_refs.append(f"packet://{crop_rel}")
        crop_bindings.append({
            "evidence_id": evidence["evidence_id"],
            "evidence_ref": evidence["evidence_ref"],
            "source_ref": source_ref,
            "region": evidence["region"],
            "crop_file": crop_rel,
            "crop_pixel_sha256": observed_pixel_sha,
            "crop_file_sha256": sha256_bytes(crop_raw),
        })

    review_packet = {
        "review_id": review_id,
        "execution_id": execution_id,
        "visual_output_ref": f"packet://{output_rel}",
        "visual_output_sha256": worker["visual_output_sha256"],
        "reason_codes": ["P0_4_REAL_SCREEN_HUMAN_ADJUDICATION_REQUIRED"],
        "source_image_refs": [f"packet://{item['source_file']}" for item in source_bindings],
        "evidence_crops": crop_refs,
        "candidate_interpretations": ["OCR-grounded visible-text observations only; no business semantics are asserted."],
        "worker_outputs": [f"packet://{output_rel}"],
        "judge_findings": ["Independent judge and authenticated human decisions are not included in this preparation packet."],
        "data_classification": data_classification,
        "required_reviewer_role": required_reviewer_role,
        "dual_review_required": dual_review_required,
        "created_at": created_at,
        "expires_at": expires_at,
    }
    schema_errors = validate_instance(load(REVIEW_SCHEMA), review_packet)
    if schema_errors:
        return {"result": "BLOCKED", "blocking_assertions": ["review_packet_schema_invalid"], "schema_errors": schema_errors, "p0_4_closed": False}
    review_rel = "review/human-review-packet.json"
    canonical_write(output_dir / review_rel, review_packet)

    packet_manifest = {
        "schema_version": "p0-review-evidence-packet-manifest/v1",
        "review_id": review_id,
        "execution_id": execution_id,
        "head_sha": head_sha,
        "execution_lane": "ENGINEERING_SMOKE",
        "runtime_enabled": False,
        "production_authorized": False,
        "p0_5_denominator_eligible": False,
        "visual_output_file": output_rel,
        "visual_output_sha256": worker["visual_output_sha256"],
        "review_packet_file": review_rel,
        "source_bindings": source_bindings,
        "crop_bindings": crop_bindings,
        "data_classification": data_classification,
        "encrypted_evidence_policy_ref": encrypted_evidence_policy_ref,
        "raw_source_retention_required_until_terminal_review": True,
        "external_durable_persistence_verified": False,
        "challenge_issued": False,
        "human_attestation_claimed": False,
        "created_at": created_at,
        "expires_at": expires_at,
        "inventory": inventory(output_dir),
    }
    manifest_path = output_dir / "packet-manifest.json"
    canonical_write(manifest_path, packet_manifest)
    verification = verify_packet(output_dir)
    return {
        "result": verification["result"],
        "blocking_assertions": verification["blocking_assertions"],
        "packet_manifest_sha256": sha256_bytes(manifest_path.read_bytes()),
        "visual_output_sha256": worker["visual_output_sha256"],
        "source_count": len(source_bindings),
        "crop_count": len(crop_bindings),
        "external_durable_persistence_verified": False,
        "challenge_issued": False,
        "human_attestation_claimed": False,
        "empirical_visual_quality_claimed": False,
        "p0_4_closed": False,
    }


def verify_packet(root: Path) -> dict[str, Any]:
    failures: list[str] = []
    manifest_path = root / "packet-manifest.json"
    if not manifest_path.is_file() or manifest_path.is_symlink():
        return {"result": "BLOCKED", "blocking_assertions": ["packet_manifest_missing"], "p0_4_closed": False}
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {"result": "BLOCKED", "blocking_assertions": ["packet_manifest_invalid"], "p0_4_closed": False}

    declared_rows = manifest.get("inventory") if isinstance(manifest.get("inventory"), list) else []
    declared = {row.get("path"): row for row in declared_rows if isinstance(row, dict) and isinstance(row.get("path"), str)}
    actual_rows = inventory(root)
    actual = {row["path"]: row for row in actual_rows}
    if set(actual) != set(declared):
        failures.append("packet_inventory_mismatch")
    for relative in set(actual) & set(declared):
        if actual[relative] != declared[relative]:
            failures.append("packet_file_hash_mismatch")
    if any(path.is_symlink() for path in root.rglob("*")):
        failures.append("packet_symlink_forbidden")
    if manifest.get("schema_version") != "p0-review-evidence-packet-manifest/v1":
        failures.append("packet_schema_version_invalid")
    if not SHA1_RE.fullmatch(str(manifest.get("head_sha", ""))):
        failures.append("packet_head_sha_invalid")
    if manifest.get("execution_lane") != "ENGINEERING_SMOKE" or manifest.get("runtime_enabled") is not False:
        failures.append("packet_lane_claim_invalid")
    if manifest.get("production_authorized") is not False or manifest.get("p0_5_denominator_eligible") is not False:
        failures.append("packet_authorization_claim_invalid")
    if manifest.get("challenge_issued") is not False or manifest.get("human_attestation_claimed") is not False:
        failures.append("packet_false_human_claim")
    if manifest.get("external_durable_persistence_verified") is not False:
        failures.append("packet_false_persistence_claim")
    if manifest.get("data_classification") == "SENSITIVE" and not (
        isinstance(manifest.get("encrypted_evidence_policy_ref"), str)
        and manifest["encrypted_evidence_policy_ref"].startswith("p0://policy/")
    ):
        failures.append("sensitive_packet_encrypted_policy_missing")

    output_path = safe_child(root, manifest.get("visual_output_file"))
    review_path = safe_child(root, manifest.get("review_packet_file"))
    if output_path is None or not output_path.is_file() or output_path.is_symlink():
        failures.append("visual_output_file_unresolved")
        visual_output = None
    else:
        try:
            visual_output = json.loads(output_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            visual_output = None
            failures.append("visual_output_file_invalid")
        if sha256_bytes(output_path.read_bytes()) != manifest.get("visual_output_sha256"):
            failures.append("visual_output_sha_mismatch")
    if review_path is None or not review_path.is_file() or review_path.is_symlink():
        failures.append("review_packet_file_unresolved")
        review_packet = None
    else:
        try:
            review_packet = json.loads(review_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            review_packet = None
            failures.append("review_packet_file_invalid")
        if review_packet is not None:
            if validate_instance(load(REVIEW_SCHEMA), review_packet):
                failures.append("review_packet_schema_invalid")
            if review_packet.get("visual_output_sha256") != manifest.get("visual_output_sha256"):
                failures.append("review_packet_visual_sha_mismatch")
            if review_packet.get("data_classification") == "SENSITIVE" and review_packet.get("dual_review_required") is not True:
                failures.append("sensitive_packet_requires_dual_review")

    source_images: dict[str, Image.Image] = {}
    for binding in manifest.get("source_bindings", []):
        if not isinstance(binding, dict):
            failures.append("source_binding_invalid")
            continue
        source_path = safe_child(root, binding.get("source_file"))
        admission_path = safe_child(root, binding.get("admission_file"))
        processing_path = safe_child(root, binding.get("processing_manifest_file"))
        if any(path is None or not path.is_file() or path.is_symlink() for path in (source_path, admission_path, processing_path)):
            failures.append("source_binding_unresolved")
            continue
        raw = source_path.read_bytes()
        if sha256_bytes(raw) != binding.get("raw_bytes_sha256"):
            failures.append("source_raw_sha_mismatch")
        try:
            admission = json.loads(admission_path.read_text(encoding="utf-8"))
            processing = json.loads(processing_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            failures.append("source_metadata_invalid")
            continue
        if admission.get("raw_bytes_sha256") != binding.get("raw_bytes_sha256"):
            failures.append("source_admission_sha_mismatch")
        if processing.get("raw_bytes_sha256") != binding.get("raw_bytes_sha256"):
            failures.append("source_processing_sha_mismatch")
        try:
            with Image.open(io.BytesIO(raw)) as opened:
                opened.load()
                source_images[binding.get("source_ref")] = ImageOps.exif_transpose(opened).convert("RGBA")
        except OSError:
            failures.append("source_decode_failed")

    visual_evidence = {}
    if isinstance(visual_output, dict):
        visual_evidence = {item.get("evidence_ref"): item for item in visual_output.get("evidence", []) if isinstance(item, dict)}
    for binding in manifest.get("crop_bindings", []):
        if not isinstance(binding, dict):
            failures.append("crop_binding_invalid")
            continue
        crop_path = safe_child(root, binding.get("crop_file"))
        source = source_images.get(binding.get("source_ref"))
        evidence = visual_evidence.get(binding.get("evidence_ref"))
        if crop_path is None or not crop_path.is_file() or crop_path.is_symlink() or source is None or not isinstance(evidence, dict):
            failures.append("crop_binding_unresolved")
            continue
        if sha256_bytes(crop_path.read_bytes()) != binding.get("crop_file_sha256"):
            failures.append("crop_file_sha_mismatch")
        box = crop_box(binding.get("region", {}), source.width, source.height)
        observed_pixel_sha = crop_pixel_sha(source, box)
        if observed_pixel_sha != binding.get("crop_pixel_sha256") or observed_pixel_sha != evidence.get("sha256"):
            failures.append("crop_pixel_sha_mismatch")

    return {
        "result": "PASS_REVIEW_PACKET_READY_EXTERNAL_PERSISTENCE_REQUIRED" if not failures else "BLOCKED",
        "blocking_assertions": sorted(set(failures)),
        "inventory_count": len(actual),
        "source_count": len(manifest.get("source_bindings", [])),
        "crop_count": len(manifest.get("crop_bindings", [])),
        "external_durable_persistence_verified": False,
        "challenge_issued": False,
        "human_attestation_claimed": False,
        "p0_4_closed": False,
    }


def self_test() -> int:
    raw, _ = dense_fixture()
    bundle = synthetic_bundle(raw)
    with tempfile.TemporaryDirectory(prefix="p0-review-packet-") as temporary:
        root = Path(temporary) / "packet"
        built = build_packet(
            bundle,
            {"image://p03-dense-v1": raw},
            root,
            head_sha="a" * 40,
            review_id="REV-P0-PACKET-SELFTEST",
            execution_id="EXEC-P0-PACKET-SELFTEST",
            created_at="2026-08-09T10:00:00Z",
            expires_at="2026-08-09T14:00:00Z",
            data_classification="INTERNAL",
            required_reviewer_role="P0_VISUAL_ADJUDICATOR",
            dual_review_required=False,
            encrypted_evidence_policy_ref=None,
            engineering_smoke=True,
        )
        verified = verify_packet(root)
        overwrite = build_packet(
            bundle,
            {"image://p03-dense-v1": raw},
            root,
            head_sha="a" * 40,
            review_id="REV-P0-PACKET-SELFTEST",
            execution_id="EXEC-P0-PACKET-SELFTEST",
            created_at="2026-08-09T10:00:00Z",
            expires_at="2026-08-09T14:00:00Z",
            data_classification="INTERNAL",
            required_reviewer_role="P0_VISUAL_ADJUDICATOR",
            dual_review_required=False,
            encrypted_evidence_policy_ref=None,
            engineering_smoke=True,
        )
        sensitive_failures = input_failures(
            head_sha="a" * 40,
            created_at="2026-08-09T10:00:00Z",
            expires_at="2026-08-09T14:00:00Z",
            data_classification="SENSITIVE",
            required_reviewer_role="P0_VISUAL_ADJUDICATOR",
            dual_review_required=False,
            encrypted_evidence_policy_ref=None,
        )
        first_crop = next((root / "crops").glob("*.png"))
        first_crop.write_bytes(first_crop.read_bytes() + b"tamper")
        tampered = verify_packet(root)
        checks = {
            "packet_build_pass": built.get("result") == "PASS_REVIEW_PACKET_READY_EXTERNAL_PERSISTENCE_REQUIRED",
            "packet_verify_pass": verified.get("result") == "PASS_REVIEW_PACKET_READY_EXTERNAL_PERSISTENCE_REQUIRED",
            "source_bytes_retained": verified.get("source_count") == 1,
            "crop_bytes_retained": verified.get("crop_count", 0) >= 20,
            "overwrite_blocked": overwrite.get("result") == "BLOCKED" and "output_dir_must_not_exist" in overwrite.get("blocking_assertions", []),
            "sensitive_single_review_blocked": "sensitive_packet_requires_dual_review" in sensitive_failures,
            "sensitive_without_encrypted_policy_blocked": "sensitive_packet_encrypted_policy_missing" in sensitive_failures,
            "tampered_crop_blocked": tampered.get("result") == "BLOCKED" and "packet_file_hash_mismatch" in tampered.get("blocking_assertions", []),
            "no_false_persistence_claim": built.get("external_durable_persistence_verified") is False,
            "no_false_human_claim": built.get("human_attestation_claimed") is False and built.get("p0_4_closed") is False,
        }
    passed = all(checks.values())
    print(json.dumps({
        "schema_version": "p0-review-evidence-packet-selftest/v1",
        "evidence_mode": "SYNTHETIC_PACKET_CONTRACT_FIXTURE",
        "checks": checks,
        "external_durable_persistence_verified": False,
        "human_attestation_claimed": False,
        "empirical_visual_quality_claimed": False,
        "p0_4_closed": False,
        "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED",
    }, sort_keys=True))
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--image", action="append", default=[], metavar="REF=PATH")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--head-sha")
    parser.add_argument("--review-id")
    parser.add_argument("--execution-id")
    parser.add_argument("--created-at")
    parser.add_argument("--expires-at")
    parser.add_argument("--data-classification", default="CONFIDENTIAL", choices=sorted(CLASSIFICATIONS))
    parser.add_argument("--required-reviewer-role", default="P0_VISUAL_ADJUDICATOR", choices=sorted(REVIEWER_ROLES))
    parser.add_argument("--dual-review-required", action="store_true")
    parser.add_argument("--encrypted-evidence-policy-ref")
    parser.add_argument("--engineering-smoke", action="store_true")
    parser.add_argument("--verify-dir", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.verify_dir is not None:
        result = verify_packet(args.verify_dir)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0 if result["result"] == "PASS_REVIEW_PACKET_READY_EXTERNAL_PERSISTENCE_REQUIRED" else 2
    required = [args.bundle, args.output_dir, args.head_sha, args.review_id, args.execution_id, args.created_at, args.expires_at]
    if any(value is None for value in required) or not args.image:
        parser.error("build mode requires --bundle, --image, --output-dir, --head-sha, --review-id, --execution-id, --created-at and --expires-at")
    try:
        raw_by_ref = parse_images(args.image)
        bundle = load(args.bundle)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"result": "BLOCKED", "blocking_assertions": [f"input:{type(exc).__name__}:{exc}"]}, sort_keys=True))
        return 2
    result = build_packet(
        bundle,
        raw_by_ref,
        args.output_dir,
        head_sha=args.head_sha,
        review_id=args.review_id,
        execution_id=args.execution_id,
        created_at=args.created_at,
        expires_at=args.expires_at,
        data_classification=args.data_classification,
        required_reviewer_role=args.required_reviewer_role,
        dual_review_required=args.dual_review_required,
        encrypted_evidence_policy_ref=args.encrypted_evidence_policy_ref,
        engineering_smoke=args.engineering_smoke,
    )
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result.get("result") == "PASS_REVIEW_PACKET_READY_EXTERNAL_PERSISTENCE_REQUIRED" else 2


if __name__ == "__main__":
    raise SystemExit(main())
