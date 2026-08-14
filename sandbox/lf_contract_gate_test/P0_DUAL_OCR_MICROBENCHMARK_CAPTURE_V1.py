#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BENCHMARK = Path(__file__).with_name("P0_DUAL_OCR_MICROBENCHMARK_EXEC_V2.py")
OUTPUT = ROOT / ".audit-output" / "creating-integral-user-stories" / "p0-dual-ocr-microbenchmark-result.json"
PREFIX = "DUAL_OCR_RESULT="


def main() -> int:
    completed = subprocess.run(
        [sys.executable, str(BENCHMARK)],
        cwd=ROOT,
        env=os.environ.copy(),
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.stdout:
        print(completed.stdout, end="")
    if completed.stderr:
        print(completed.stderr, end="", file=sys.stderr)
    if completed.returncode != 0:
        raise SystemExit(completed.returncode)
    lines = [line for line in completed.stdout.splitlines() if line.startswith(PREFIX)]
    if len(lines) != 1:
        raise SystemExit(f"FAIL_DUAL_OCR_CAPTURE_RESULT_COUNT:{len(lines)}")
    payload = json.loads(lines[0][len(PREFIX):])
    checks = {
        "github_sha": payload.get("github_sha") == os.environ.get("GITHUB_SHA"),
        "source_sha": payload.get("source_sha256") == "e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7",
        "zero_real_corpus_credit": payload.get("real_corpus_credit") == 0,
        "zero_p05_credit": payload.get("p0_5_credit") == 0,
        "not_adoption_grade": payload.get("adoption_grade") is False,
        "not_promoted": payload.get("runtime_promoted") is False,
        "not_production": payload.get("production_authorized") is False,
        "holdout_not_accessed": payload.get("holdout_accessed") is False,
    }
    if not all(checks.values()):
        raise SystemExit("FAIL_DUAL_OCR_CAPTURE_GOVERNANCE:" + json.dumps(checks, sort_keys=True))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(f"PASS_DUAL_OCR_CAPTURE=8/8 output={OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
