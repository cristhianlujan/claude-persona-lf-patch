#!/usr/bin/env python3
"""Deterministically admit a screenshot and record raw/pixel/manifest hashes."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import struct
import subprocess
from pathlib import Path
from typing import Any

from PIL import Image, ImageOps, UnidentifiedImageError, __version__ as PILLOW_VERSION

from validate_p0_j02_handoff import load

ROOT = Path(__file__).resolve().parent.parent
CANONICALIZER = ROOT / "P0_RFC8785_CANONICALIZER_v1.1.mjs"
SCHEMA = ROOT / "schemas" / "image-admission-record.schema.json"
ALLOWED_FORMATS = {"PNG", "JPEG", "WEBP"}
MAX_SIDE = 10000
MAX_PIXELS = 40_000_000


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_bytes(value: Any) -> bytes:
    raw = json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8")
    proc = subprocess.run(["node", str(CANONICALIZER)], input=raw, capture_output=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"canonicalizer_failed:{proc.stderr.decode('utf-8', 'replace')[-300:]}")
    return proc.stdout


def schema_errors(record: Any) -> list[str]:
    try:
        import jsonschema
    except ImportError as exc:
        raise RuntimeError("jsonschema_not_available") from exc
    validator = jsonschema.Draft7Validator(load(SCHEMA))
    return sorted(error.message for error in validator.iter_errors(record))


def admit_bytes(raw: bytes, source_ref: str) -> dict[str, Any]:
    raw_sha = sha256(raw)
    try:
        with Image.open(io.BytesIO(raw)) as image:
            input_format = image.format
            width, height = image.size
            frame_count = getattr(image, "n_frames", 1)
            if input_format not in ALLOWED_FORMATS:
                return {"result": "BLOCKED", "blocking_assertions": ["format_not_allowed"]}
            if width < 1 or height < 1 or width > MAX_SIDE or height > MAX_SIDE or width * height > MAX_PIXELS:
                return {"result": "BLOCKED", "blocking_assertions": ["image_dimensions_out_of_policy"]}
            if frame_count != 1:
                return {"result": "BLOCKED", "blocking_assertions": ["animated_image_not_allowed"]}
            image.load()
            normalized = ImageOps.exif_transpose(image).convert("RGBA")
            normalized_width, normalized_height = normalized.size
            pixel_material = struct.pack(">II", normalized_width, normalized_height) + normalized.tobytes()
            pixel_sha = sha256(pixel_material)
    except (UnidentifiedImageError, OSError, ValueError):
        return {"result": "BLOCKED", "blocking_assertions": ["image_decode_failed"]}

    processing_manifest = {
        "schema_version": "p0-processing-manifest/v1",
        "source_ref": source_ref,
        "raw_bytes_sha256": raw_sha,
        "decoder": {"name": "Pillow", "version": PILLOW_VERSION},
        "input_format": input_format,
        "input_dimensions": {"width": width, "height": height},
        "steps": ["exif_transpose", "convert_RGBA", "hash_width_height_plus_rgba_bytes"],
        "normalized_mode": "RGBA",
        "normalized_dimensions": {"width": normalized_width, "height": normalized_height},
        "normalized_pixel_sha256": pixel_sha,
    }
    manifest_sha = sha256(canonical_bytes(processing_manifest))
    record = {
        "schema_version": "p0-image-admission/v1",
        "source_ref": source_ref,
        "raw_bytes_sha256": raw_sha,
        "normalized_pixel_sha256": pixel_sha,
        "processing_manifest_sha256": manifest_sha,
        "input_format": input_format,
        "width": normalized_width,
        "height": normalized_height,
        "normalized_mode": "RGBA",
        "decoder_name": "Pillow",
        "decoder_version": PILLOW_VERSION,
    }
    errors = schema_errors(record)
    return {"result": "PASS_WITH_EVIDENCE" if not errors else "BLOCKED", "blocking_assertions": ["admission_record_schema_invalid"] if errors else [], "schema_errors": errors, "record": record, "processing_manifest": processing_manifest}


def png_bytes(width: int = 4, height: int = 3) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", (width, height), (24, 80, 160)).save(buffer, format="PNG")
    return buffer.getvalue()


def self_test() -> int:
    good = admit_bytes(png_bytes(), "image://synthetic-admission")
    good_repeat = admit_bytes(png_bytes(), "image://synthetic-admission")
    deterministic = good.get("record") == good_repeat.get("record") and good.get("processing_manifest") == good_repeat.get("processing_manifest")
    bad_decode = admit_bytes(b"not-an-image", "image://bad")
    oversized = admit_bytes(png_bytes(MAX_SIDE + 1, 1), "image://oversized")
    buffer = io.BytesIO(); Image.new("RGB", (2, 2), (1, 2, 3)).save(buffer, format="BMP")
    bad_format = admit_bytes(buffer.getvalue(), "image://bmp")
    negatives = [
        ("corrupt_image", bad_decode, "image_decode_failed"),
        ("oversized_image", oversized, "image_dimensions_out_of_policy"),
        ("disallowed_format", bad_format, "format_not_allowed"),
    ]
    outcomes = [{"name": name, "expected_assertion": expected, "passed": result.get("result") == "BLOCKED" and expected in result.get("blocking_assertions", [])} for name, result, expected in negatives]
    passed = good.get("result") == "PASS_WITH_EVIDENCE" and deterministic and all(item["passed"] for item in outcomes)
    print(json.dumps({"positive_pass": good.get("result") == "PASS_WITH_EVIDENCE", "triple_hash_recorded": bool(good.get("record", {}).get("raw_bytes_sha256") and good.get("record", {}).get("normalized_pixel_sha256") and good.get("record", {}).get("processing_manifest_sha256")), "deterministic_repeat": deterministic, "negative_cases_passed": sum(item["passed"] for item in outcomes), "negative_cases_total": len(outcomes), "negative_results": outcomes, "evidence_mode": "SYNTHETIC_IMAGE_FIXTURE", "empirical_visual_quality_claimed": False, "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED"}, sort_keys=True))
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--source-ref", default=None)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        parser.error("input is required unless --self-test is used")
    source_ref = args.source_ref or f"file://{args.input.name}"
    result = admit_bytes(args.input.read_bytes(), source_ref)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["result"] == "PASS_WITH_EVIDENCE" else 2


if __name__ == "__main__":
    raise SystemExit(main())
