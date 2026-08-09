#!/usr/bin/env python3
"""Networkless P0 visual-worker implementation for the engineering-smoke lane.

The worker intentionally emits only OCR-grounded visible-text observations. It
does not infer business rules or interactive semantics, and its synthetic
self-test is never eligible for P0-5 empirical denominators.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import shutil
import struct
import subprocess
import sys
import copy
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont, ImageOps, __version__ as PILLOW_VERSION

from admit_p0_image import admit_bytes, canonical_bytes
from p0_schema import validate_instance
from validate_p0_j02_handoff import load
from validate_p0_visual_output import LOW_CONFIDENCE_THRESHOLD, validate as validate_visual_output

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "evals" / "p0-p03-runtime-config.json"
BUNDLE_SCHEMA = ROOT / "schemas" / "blind-input-bundle.schema.json"
MAX_TESSERACT_STDERR = 400


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def tesseract_version() -> str:
    binary = shutil.which("tesseract")
    if not binary:
        raise RuntimeError("tesseract_not_found")
    proc = subprocess.run([binary, "--version"], capture_output=True, text=True, check=False)
    if proc.returncode != 0 or not proc.stdout.strip():
        raise RuntimeError("tesseract_version_unavailable")
    first = proc.stdout.splitlines()[0].strip().split()
    if len(first) < 2:
        raise RuntimeError("tesseract_version_unparseable")
    return first[1]


def preflight(config: dict[str, Any], *, engineering_smoke: bool) -> list[str]:
    failures: list[str] = []
    if config.get("execution_lane") != "ENGINEERING_SMOKE":
        failures.append("execution_lane_not_engineering_smoke")
    if not engineering_smoke:
        failures.append("engineering_smoke_flag_required")
    if config.get("runtime_enabled") is not False:
        failures.append("runtime_must_remain_disabled")
    if config.get("production_authorized") is not False:
        failures.append("production_must_remain_unauthorized")
    if config.get("network_egress_required") is not False:
        failures.append("network_egress_must_not_be_required")
    calibration = config.get("calibration_scope", {})
    if not isinstance(calibration, dict) or calibration.get("status") != "SYNTHETIC_ENGINEERING_SMOKE_ONLY":
        failures.append("synthetic_smoke_calibration_missing")
    if not isinstance(calibration, dict) or calibration.get("p0_5_denominator_eligible") is not False:
        failures.append("p0_5_eligibility_must_be_false")
    expected_pillow = config.get("image_runtime", {}).get("version") if isinstance(config.get("image_runtime"), dict) else None
    if expected_pillow != PILLOW_VERSION:
        failures.append("pillow_version_mismatch")
    try:
        observed_tesseract = tesseract_version()
    except RuntimeError as exc:
        failures.append(str(exc))
    else:
        expected_tesseract = config.get("ocr_runtime", {}).get("version") if isinstance(config.get("ocr_runtime"), dict) else None
        if expected_tesseract != observed_tesseract:
            failures.append("tesseract_version_mismatch")
    threshold = config.get("confidence_threshold")
    if not isinstance(threshold, (int, float)) or threshold != LOW_CONFIDENCE_THRESHOLD:
        failures.append("confidence_threshold_contract_mismatch")
    scales = config.get("scan_scales")
    if not isinstance(scales, list) or len(scales) < 2 or any(not isinstance(scale, (int, float)) or scale <= 0 for scale in scales):
        failures.append("multiscale_configuration_invalid")
    return failures


def image_png_bytes(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def crop_pixel_sha(image: Image.Image, box: tuple[int, int, int, int]) -> str:
    crop = image.crop(box).convert("RGBA")
    material = struct.pack(">II", crop.width, crop.height) + crop.tobytes()
    return sha256_bytes(material)


def iou(a: dict[str, float], b: dict[str, float]) -> float:
    ax2, ay2 = a["x"] + a["width"], a["y"] + a["height"]
    bx2, by2 = b["x"] + b["width"], b["y"] + b["height"]
    x1, y1 = max(a["x"], b["x"]), max(a["y"], b["y"])
    x2, y2 = min(ax2, bx2), min(ay2, by2)
    overlap = max(0.0, x2 - x1) * max(0.0, y2 - y1)
    union = a["width"] * a["height"] + b["width"] * b["height"] - overlap
    return overlap / union if union > 0 else 0.0


def ocr_scale(image: Image.Image, *, scale: float, config: dict[str, Any]) -> list[dict[str, Any]]:
    width = max(1, round(image.width * scale))
    height = max(1, round(image.height * scale))
    scaled = image.resize((width, height), Image.Resampling.LANCZOS) if scale != 1.0 else image.copy()
    runtime = config["ocr_runtime"]
    proc = subprocess.run(
        ["tesseract", "stdin", "stdout", "-l", runtime["language"], "--psm", str(runtime["psm"]), "tsv"],
        input=image_png_bytes(scaled.convert("RGB")),
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        detail = proc.stderr.decode("utf-8", "replace")[-MAX_TESSERACT_STDERR:]
        raise RuntimeError(f"tesseract_failed:{detail}")
    rows: list[dict[str, Any]] = []
    text = proc.stdout.decode("utf-8", "replace")
    for row in csv.DictReader(io.StringIO(text), delimiter="\t"):
        token = (row.get("text") or "").strip()
        if not token or row.get("level") != "5":
            continue
        try:
            confidence_raw = float(row.get("conf", "-1"))
            left = float(row["left"]) / scale
            top = float(row["top"]) / scale
            box_width = float(row["width"]) / scale
            box_height = float(row["height"]) / scale
        except (KeyError, TypeError, ValueError, ZeroDivisionError):
            continue
        if confidence_raw < 0 or box_width <= 0 or box_height <= 0:
            continue
        region = {
            "x": round(max(0.0, left), 3),
            "y": round(max(0.0, top), 3),
            "width": round(min(float(image.width) - max(0.0, left), box_width), 3),
            "height": round(min(float(image.height) - max(0.0, top), box_height), 3),
        }
        if region["width"] <= 0 or region["height"] <= 0:
            continue
        rows.append({
            "text": token,
            "normalized_text": " ".join(token.casefold().split()),
            "confidence": round(min(100.0, confidence_raw) / 100.0, 6),
            "region": region,
            "scan_scale": scale,
        })
    return rows


def deduplicate(candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    for candidate in sorted(candidates, key=lambda item: (-item["confidence"], item["region"]["y"], item["region"]["x"], item["normalized_text"])):
        duplicate = any(
            candidate["normalized_text"] == current["normalized_text"]
            and iou(candidate["region"], current["region"]) >= 0.50
            for current in selected
        )
        if not duplicate:
            selected.append(candidate)
    return sorted(selected, key=lambda item: (item["region"]["y"], item["region"]["x"], item["normalized_text"]))


def expected_format_name(image: Image.Image) -> str:
    value = image.format
    if value == "JPG":
        return "JPEG"
    return str(value)


def run_worker(
    bundle: dict[str, Any],
    raw_by_ref: dict[str, bytes],
    *,
    config: dict[str, Any],
    engineering_smoke: bool,
) -> dict[str, Any]:
    failures = preflight(config, engineering_smoke=engineering_smoke)
    failures.extend(f"bundle:{item}" for item in validate_instance(load(BUNDLE_SCHEMA), bundle))
    source_images = bundle.get("source_images") if isinstance(bundle.get("source_images"), list) else []
    dimensions = bundle.get("dimensions") if isinstance(bundle.get("dimensions"), list) else []
    if len(source_images) > int(config.get("max_images_per_screen_set", 0)):
        failures.append("screen_set_image_limit_exceeded")
    if set(raw_by_ref) != {item.get("ref") for item in source_images if isinstance(item, dict)}:
        failures.append("source_ref_set_mismatch")
    if any(len(raw) > int(config.get("max_image_bytes", 0)) for raw in raw_by_ref.values()):
        failures.append("image_byte_limit_exceeded")
    if failures:
        return {"result": "BLOCKED", "blocking_assertions": sorted(set(failures))}

    admissions: list[dict[str, Any]] = []
    normalized_images: dict[str, Image.Image] = {}
    total_pixels = 0
    for index, source in enumerate(source_images):
        ref = source["ref"]
        raw = raw_by_ref[ref]
        admitted = admit_bytes(raw, ref)
        if admitted.get("result") != "PASS_WITH_EVIDENCE":
            failures.extend(f"admission:{value}" for value in admitted.get("blocking_assertions", []))
            continue
        record = admitted["record"]
        if record["raw_bytes_sha256"] != source["sha256"]:
            failures.append(f"source_sha_mismatch:{ref}")
        if index >= len(dimensions) or record["width"] != dimensions[index].get("width") or record["height"] != dimensions[index].get("height"):
            failures.append(f"source_dimensions_mismatch:{ref}")
        if record["input_format"] != bundle.get("format"):
            failures.append(f"source_format_mismatch:{ref}")
        total_pixels += record["width"] * record["height"]
        admissions.append(record)
        with Image.open(io.BytesIO(raw)) as opened:
            opened.load()
            normalized_images[ref] = ImageOps.exif_transpose(opened).convert("RGBA")
    if total_pixels > int(config.get("max_total_pixels_per_screen_set", 0)):
        failures.append("screen_set_pixel_limit_exceeded")
    if failures:
        return {"result": "BLOCKED", "blocking_assertions": sorted(set(failures))}

    observations: list[dict[str, Any]] = []
    evidence: list[dict[str, Any]] = []
    roots: list[str] = []
    edges: list[dict[str, str]] = []
    reading_orders: list[dict[str, Any]] = []
    threshold = float(config["confidence_threshold"])
    scales = [float(value) for value in config["scan_scales"]]
    scan_counts: dict[str, dict[str, int]] = {}

    for image_index, source in enumerate(source_images, start=1):
        ref = source["ref"]
        image = normalized_images[ref]
        root = f"ROOT-{image_index:03d}"
        roots.append(root)
        source_evidence_ref = f"source://p0-runtime/{image_index:03d}"
        evidence.append({
            "evidence_id": f"EV-SOURCE-{image_index:03d}",
            "evidence_ref": source_evidence_ref,
            "source_ref": ref,
            "sha256": source["sha256"],
            "kind": "SOURCE_IMAGE",
            "data_classification": "CONFIDENTIAL",
            "redacted": False,
            "retention_until": None,
        })
        candidates: list[dict[str, Any]] = []
        per_scale: dict[str, int] = {}
        for scale in scales:
            found = ocr_scale(image, scale=scale, config=config)
            per_scale[f"{scale:g}x"] = len(found)
            candidates.extend(found)
        selected = deduplicate(candidates)
        scan_counts[ref] = {**per_scale, "deduplicated": len(selected)}
        order_ids: list[str] = []
        for item in selected:
            obs_number = len(observations) + 1
            observation_id = f"OBS-RUNTIME-{obs_number:04d}"
            evidence_ref = f"crop://p0-runtime/{obs_number:04d}"
            region = item["region"]
            x1 = max(0, min(image.width - 1, int(region["x"])))
            y1 = max(0, min(image.height - 1, int(region["y"])))
            x2 = max(x1 + 1, min(image.width, int(round(region["x"] + region["width"]))))
            y2 = max(y1 + 1, min(image.height, int(round(region["y"] + region["height"]))))
            observations.append({
                "observation_id": observation_id,
                "source_image_ref": ref,
                "region": region,
                "element_type": "VISIBLE_TEXT",
                "visible_text": item["text"],
                "visual_state": "STATIC_VISIBLE",
                "confidence": item["confidence"],
                "abstained": item["confidence"] < threshold,
                "evidence_ref": evidence_ref,
            })
            evidence.append({
                "evidence_id": f"EV-RUNTIME-{obs_number:04d}",
                "evidence_ref": evidence_ref,
                "source_ref": ref,
                "sha256": crop_pixel_sha(image, (x1, y1, x2, y2)),
                "source_raw_sha256": source["sha256"],
                "region": region,
                "kind": "CROP",
                "data_classification": "CONFIDENTIAL",
                "redacted": False,
                "retention_until": None,
            })
            edges.append({"parent": root, "child": observation_id, "source_ref": ref})
            order_ids.append(observation_id)
        if order_ids:
            reading_orders.append({"basis": "VISUAL_HEURISTIC_LTR_TTB", "element_ids": order_ids, "source_ref": ref})

    if not observations:
        return {"result": "BLOCKED", "blocking_assertions": ["no_ocr_observations"]}

    output = {
        "blind_bundle": bundle,
        "observations": observations,
        "ui_structure": {
            "visual_containment_tree": {"roots": roots, "edges": edges},
            "visual_layer_graph": [],
            "candidate_reading_orders": reading_orders,
        },
        "evidence": evidence,
    }
    validation = validate_visual_output(output, admissions, raw_by_ref, require_crop_recompute=True)
    output_sha = sha256_bytes(canonical_bytes(output))
    return {
        "result": validation["result"],
        "blocking_assertions": validation.get("blocking_assertions", []),
        "runtime_metadata": {
            "configuration_id": config["configuration_id"],
            "execution_lane": "ENGINEERING_SMOKE",
            "runtime_enabled": False,
            "production_authorized": False,
            "p0_5_denominator_eligible": False,
            "tesseract_version": tesseract_version(),
            "pillow_version": PILLOW_VERSION,
            "scan_scales": scales,
            "scan_counts": scan_counts,
        },
        "admission_records": admissions,
        "visual_output": output,
        "visual_output_sha256": output_sha,
        "validation": validation,
    }


def dense_fixture() -> tuple[bytes, list[str]]:
    labels = [
        "PROFILE SETTINGS", "ACCOUNT EMAIL", "DISPLAY NAME", "LANGUAGE ENGLISH",
        "SECURITY SETTINGS", "TWO FACTOR AUTHENTICATION", "ACTIVE SESSIONS",
        "NOTIFICATION PREFERENCES", "EMAIL ALERTS", "MOBILE ALERTS", "PRIVACY CONTROLS",
        "DOWNLOAD DATA", "DELETE ACCOUNT", "HELP CENTER", "PRIVACY POLICY",
    ]
    image = Image.new("RGB", (1100, 850), "white")
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.load_default(size=28)
    except TypeError:
        font = ImageFont.load_default()
    for index, label in enumerate(labels):
        draw.text((36, 30 + index * 52), label, fill="black", font=font)
    return image_png_bytes(image), labels


def synthetic_bundle(raw: bytes) -> dict[str, Any]:
    with Image.open(io.BytesIO(raw)) as image:
        width, height = image.size
        input_format = expected_format_name(image)
    source_sha = sha256_bytes(raw)
    base = {
        "tenant_id": "TEN-P0-SYNTHETIC",
        "project_id": "LF-P0-RECOVERY",
        "screen_set_code": "SET-P03-DENSE-V1",
        "target_screen_code": "SCR-P03-DENSE",
        "source_images": [{"ref": "image://p03-dense-v1", "sha256": source_sha}],
        "hashes": [source_sha],
        "dimensions": [{"width": width, "height": height}],
        "format": input_format,
        "sequence_order": ["SCR-P03-DENSE"],
        "state_code": "STATIC",
        "security_scope": "LF-SANDBOX-ENGINEERING-SMOKE",
        "data_policy_version": "p0-visual-data-policy/v2",
    }
    base["blind_input_manifest_sha256"] = sha256_bytes(canonical_bytes(base))
    return base


def self_test(config: dict[str, Any]) -> int:
    raw, labels = dense_fixture()
    bundle = synthetic_bundle(raw)
    result = run_worker(bundle, {"image://p03-dense-v1": raw}, config=config, engineering_smoke=True)
    visual = result.get("visual_output", {})
    observations = visual.get("observations", []) if isinstance(visual, dict) else []
    recognized = {str(item.get("visible_text", "")).casefold() for item in observations if isinstance(item, dict)}
    expected_tokens = {token.casefold() for label in labels for token in label.split()}
    recognized_tokens = {token for value in recognized for token in value.split()}
    covered = sorted(expected_tokens & recognized_tokens)
    tampered_output = copy.deepcopy(visual)
    crop = next((item for item in tampered_output.get("evidence", []) if item.get("kind") == "CROP"), None) if isinstance(tampered_output, dict) else None
    tampered_crop_blocked = False
    if isinstance(crop, dict):
        evidence_ref = crop.get("evidence_ref")
        crop["region"]["x"] += 3
        for observation in tampered_output.get("observations", []):
            if observation.get("evidence_ref") == evidence_ref:
                observation["region"]["x"] += 3
        tampered = validate_visual_output(tampered_output, result.get("admission_records", []), {"image://p03-dense-v1": raw}, require_crop_recompute=True)
        tampered_crop_blocked = tampered.get("result") == "BLOCKED" and "crop_pixel_hash_mismatch" in tampered.get("blocking_assertions", [])
    no_flag_failures = preflight(config, engineering_smoke=False)
    enabled_config = copy.deepcopy(config)
    enabled_config["runtime_enabled"] = True
    enabled_failures = preflight(enabled_config, engineering_smoke=True)
    p05_config = copy.deepcopy(config)
    p05_config["calibration_scope"]["p0_5_denominator_eligible"] = True
    p05_failures = preflight(p05_config, engineering_smoke=True)
    checks = {
        "worker_result_pass": result.get("result") == "PASS_WITH_EVIDENCE",
        "dense_observation_floor": len(observations) >= 20,
        "multiscale_executed": set(result.get("runtime_metadata", {}).get("scan_counts", {}).get("image://p03-dense-v1", {})) >= {"1x", "2x", "deduplicated"},
        "synthetic_token_coverage_floor": len(covered) >= max(12, int(len(expected_tokens) * 0.65)),
        "p0_5_denominator_ineligible": result.get("runtime_metadata", {}).get("p0_5_denominator_eligible") is False,
        "runtime_remains_disabled": result.get("runtime_metadata", {}).get("runtime_enabled") is False,
        "production_unauthorized": result.get("runtime_metadata", {}).get("production_authorized") is False,
        "missing_smoke_flag_blocked": "engineering_smoke_flag_required" in no_flag_failures,
        "runtime_enablement_attempt_blocked": "runtime_must_remain_disabled" in enabled_failures,
        "p0_5_eligibility_attempt_blocked": "p0_5_eligibility_must_be_false" in p05_failures,
        "crop_recompute_mutation_blocked": tampered_crop_blocked,
    }
    passed = all(checks.values())
    receipt = {
        "schema_version": "p0-p03-runtime-smoke-receipt/v1",
        "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED",
        "evidence_mode": "SYNTHETIC_DENSE_RUNTIME_FIXTURE",
        "fixture_sha256": sha256_bytes(raw),
        "fixture_expected_token_count": len(expected_tokens),
        "fixture_covered_token_count": len(covered),
        "observation_count": len(observations),
        "visual_output_sha256": result.get("visual_output_sha256"),
        "configuration_id": config.get("configuration_id"),
        "runtime_config_sha256": sha256_bytes(CONFIG_PATH.read_bytes()),
        "worker_source_sha256": sha256_bytes(Path(__file__).read_bytes()),
        "tesseract_binary_sha256": sha256_bytes(Path(shutil.which("tesseract") or "/nonexistent").read_bytes()),
        "tesseract_version": result.get("runtime_metadata", {}).get("tesseract_version"),
        "pillow_version": result.get("runtime_metadata", {}).get("pillow_version"),
        "scan_counts": result.get("runtime_metadata", {}).get("scan_counts"),
        "checks": checks,
        "claims": {
            "runtime_worker_implemented": True,
            "engineering_smoke_executed": True,
            "runtime_enabled": False,
            "empirical_visual_quality_claimed": False,
            "p0_5_denominator_eligible": False,
            "production_authorized": False,
        },
    }
    print(json.dumps(receipt, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 2


def parse_images(values: list[str]) -> dict[str, bytes]:
    result: dict[str, bytes] = {}
    for value in values:
        if "=" not in value:
            raise ValueError("--image must be REF=PATH")
        ref, raw_path = value.split("=", 1)
        if not ref or not raw_path or ref in result:
            raise ValueError("--image must use unique non-empty REF=PATH values")
        result[ref] = Path(raw_path).read_bytes()
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--image", action="append", default=[], metavar="REF=PATH")
    parser.add_argument("--engineering-smoke", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    config = load(CONFIG_PATH)
    if args.self_test:
        return self_test(config)
    if args.bundle is None or not args.image:
        parser.error("--bundle and at least one --image REF=PATH are required")
    try:
        raw_by_ref = parse_images(args.image)
    except (ValueError, OSError) as exc:
        print(json.dumps({"result": "BLOCKED", "blocking_assertions": [f"input:{type(exc).__name__}:{exc}"]}, sort_keys=True))
        return 2
    result = run_worker(load(args.bundle), raw_by_ref, config=config, engineering_smoke=args.engineering_smoke)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result.get("result") == "PASS_WITH_EVIDENCE" else 2


if __name__ == "__main__":
    raise SystemExit(main())
