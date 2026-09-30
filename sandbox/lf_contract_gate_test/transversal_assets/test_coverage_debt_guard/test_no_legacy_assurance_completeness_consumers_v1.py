#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
TOKEN = "lf_s36_assurance_completeness_v1"
SELF = Path(__file__).resolve()


def main() -> None:
    offenders: list[str] = []
    roots = [ROOT / "sandbox", ROOT / ".github"]
    suffixes = {".py", ".yml", ".yaml", ".sh"}

    for base in roots:
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file() or path.suffix not in suffixes or path.resolve() == SELF:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            if TOKEN in text:
                offenders.append(str(path.relative_to(ROOT)))

    assert not offenders, "LEGACY_ASSURANCE_COMPLETENESS_EXECUTABLE_CONSUMERS=" + ",".join(sorted(offenders))
    print("NO_LEGACY_ASSURANCE_COMPLETENESS_EXECUTABLE_CONSUMERS=PASS")


if __name__ == "__main__":
    main()
