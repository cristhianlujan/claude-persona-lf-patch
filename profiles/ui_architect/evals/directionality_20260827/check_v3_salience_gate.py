#!/usr/bin/env python3
from pathlib import Path
import json

skill = Path(__file__).resolve().parents[2] / "SKILL.md"
text = skill.read_text(encoding="utf-8")
head = "\n".join(text.splitlines()[:25])

checks = {
    "critical_gate_in_first_25_lines": "RUNTIME CRITICAL GATE" in head,
    "defect_correction_postcondition_in_first_25_lines": "DEFECT -> CORRECTION -> POSTCONDITION" in head,
    "duplicate_amplification_forbidden": "ADD/SHOW/COPY/CREATE another duplicate` is FORBIDDEN" in head,
    "allowed_duplicate_directions_present": "`REMOVE`, `HIDE`, `MERGE`, or `BLOCK`" in head,
    "exact_block_pipeline_present": '"pipeline_action":"BLOCK_PIPELINE"' in head,
    "priority_over_format_rules_present": "higher priority than producing a Production UI Spec" in head,
}

print(json.dumps(checks, ensure_ascii=False, indent=2))
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("FAIL: " + ", ".join(failed))
print("PASS: V3 critical directionality gate is salient and fail-closed in runtime source")
