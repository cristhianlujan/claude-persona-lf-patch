#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FRAGMENTS = ROOT / "fragments"
TARGETS = {
    "HANDOFF_TECNICO_P0_LECTURA_VISUAL_Y_CONTEXTO_AUXILIAR_LF_v1.1.md": [
        FRAGMENTS / "handoff.md.part01",
        FRAGMENTS / "handoff.md.part02",
    ],
    "P0_VISUAL_READING_CANONICAL_MANIFEST_v1.1.json": [
        FRAGMENTS / "manifest.json.part01",
        FRAGMENTS / "manifest.json.part02",
        FRAGMENTS / "manifest.json.part03",
        FRAGMENTS / "manifest.json.part04",
    ],
}
EXPECTED = {
    "HANDOFF_TECNICO_P0_LECTURA_VISUAL_Y_CONTEXTO_AUXILIAR_LF_v1.1.md": "a8d53b736e7d2d672b0927f7deaca4422f7429fdda0d1997b1eaa54fc06e7531",
    "P0_VISUAL_READING_CANONICAL_MANIFEST_v1.1.json": "f1c776c8d4f633aff6dbf362d5ba4702d2307f826c8ce5bd274cbb2cc88185e4",
}

for name, parts in TARGETS.items():
    data = b"".join(path.read_bytes() for path in parts)
    digest = hashlib.sha256(data).hexdigest()
    if digest != EXPECTED[name]:
        raise SystemExit(f"ASSEMBLY_HASH_MISMATCH:{name}:{digest}")
    (ROOT / name).write_bytes(data)
    print(json.dumps({"file": name, "bytes": len(data), "sha256": digest}, sort_keys=True))
