#!/usr/bin/env python3
from pathlib import Path
import base64
import hashlib

EXPECTED_SHA256 = "f84f3e327d99b14091671a462c85dacbffaa3da90e649a7076e12aec2dfcdaac"
ROOT = Path(__file__).resolve().parent
NAMES = [
    "P0_VISUAL_READING_V1_BUNDLE.tar.gz.b64.part01",
    "P0_VISUAL_READING_V1_BUNDLE.tar.gz.b64.part02",
    "P0_VISUAL_READING_V1_BUNDLE.tar.gz.b64.part03a",
    "P0_VISUAL_READING_V1_BUNDLE.tar.gz.b64.part03b",
    "P0_VISUAL_READING_V1_BUNDLE.tar.gz.b64.part04a",
    "P0_VISUAL_READING_V1_BUNDLE.tar.gz.b64.part04b",
    "P0_VISUAL_READING_V1_BUNDLE.tar.gz.b64.part05",
]
parts = [ROOT / name for name in NAMES]
missing = [p.name for p in parts if not p.is_file()]
if missing:
    raise SystemExit(f"Missing Base64 parts: {missing}")
payload = "".join(p.read_text(encoding="ascii").strip() for p in parts)
archive = base64.b64decode(payload, validate=True)
actual = hashlib.sha256(archive).hexdigest()
if actual != EXPECTED_SHA256:
    raise SystemExit(f"SHA-256 mismatch: expected {EXPECTED_SHA256}, got {actual}")
out = ROOT / "P0_VISUAL_READING_V1_BUNDLE.tar.gz"
out.write_bytes(archive)
print(f"Reconstructed {out.name}: {len(archive)} bytes, sha256={actual}")
