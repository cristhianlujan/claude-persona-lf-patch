#!/usr/bin/env python3
from pathlib import Path
import json

skill = Path(__file__).resolve().parents[2] / "SKILL.md"
text = skill.read_text(encoding="utf-8")
head = "\n".join(text.splitlines()[:30])

checks = {
    "critical_gate_first": "RUNTIME CRITICAL GATE" in head,
    "authority_resolution_first": "AUTHORITY RESOLUTION FIRST" in head,
    "resolved_authority_forbids_unknown_survivor_block": "blocking for an unknown survivor is FORBIDDEN" in head,
    "generic_keep_remove_rule_present": "KEEP A` + `REMOVE/HIDE/MERGE B" in head,
    "block_only_if_unresolved": "BLOCK ONLY IF AUTHORITY IS STILL UNRESOLVED" in head,
    "no_block_for_resolved_context": "Never block for information already resolved in the supplied context" in head,
    "duplicate_amplification_still_forbidden": "ADD/SHOW/COPY/CREATE another duplicate` is FORBIDDEN" in head,
}

print(json.dumps(checks, ensure_ascii=False, indent=2))
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("FAIL: " + ", ".join(failed))
print("PASS: explicit authority short-circuits missing-survivor blocking while directionality remains fail-closed")
