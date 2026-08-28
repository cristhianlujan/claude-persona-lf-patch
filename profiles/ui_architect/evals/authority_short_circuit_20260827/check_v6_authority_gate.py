#!/usr/bin/env python3
from pathlib import Path
import json

skill = Path(__file__).resolve().parents[2] / "SKILL.md"
text = skill.read_text(encoding="utf-8")
head = "\n".join(text.splitlines()[:90])

checks = {
    "critical_gate_first": "RUNTIME CRITICAL GATE" in head,
    "authority_resolution_first": "AUTHORITY RESOLUTION FIRST" in head,
    "resolved_duplicate_short_circuit": "RESOLVED DUPLICATE SHORT-CIRCUIT" in head,
    "single_destructive_redundant_target": "exactly one remediation action" in head and "redundant presentation" in head,
    "positive_resumen_survivor_example": "Resumen` canonical + `top strip` redundant" in head and "top_amount_strip" in head and "payment_summary" in head,
    "survivor_kept_out_of_remediation_target": "not as a remediation target" in head,
    "full_production_spec_required": "never abbreviate the output to a list of findings" in head and "PRODUCTION_UI_SPEC" in head,
    "unresolved_authority_short_circuit": "UNRESOLVED AUTHORITY SHORT-CIRCUIT" in head,
    "complete_missing_state_not_bare_token": "do not emit a bare pipeline-action token" in head,
}

print(json.dumps(checks, ensure_ascii=False, indent=2))
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("FAIL: " + ", ".join(failed))
print("PASS: resolved authority serializes one redundant-target remediation while unresolved authority fails closed with a complete Missing Input State")
