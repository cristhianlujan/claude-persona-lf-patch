#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ADAPTERS = [
    "lf_shell_profile_adapter",
    "project_brand_mockup_render_lf",
]
REQUIRED = [
    "ADAPTER.md",
    "manifest.yaml",
    "runtime_capsule.md",
    "validators/validate_adapter_package.py",
    "evals/quality_v2/run_cases.py",
]
MAX_CAPSULE_CHARS = 2000


def main() -> int:
    errors = []
    for adapter in ADAPTERS:
        base = ROOT / adapter
        for rel in REQUIRED:
            if not (base / rel).exists():
                errors.append(f"{adapter}: missing {rel}")
        capsule = base / "runtime_capsule.md"
        if capsule.exists():
            size = len(capsule.read_text(encoding="utf-8"))
            if size > MAX_CAPSULE_CHARS:
                errors.append(f"{adapter}: runtime capsule {size} > {MAX_CAPSULE_CHARS} chars")
    if errors:
        for error in errors:
            print("FAIL", error)
        return 1
    print("ADAPTER_QUALITY_V2_STATIC_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
