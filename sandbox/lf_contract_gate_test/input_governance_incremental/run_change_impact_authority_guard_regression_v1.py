from __future__ import annotations

import json
from pathlib import Path
import re

from change_impact_resolver_readonly_v1 import RuntimeAuthority, resolve_change_impact as base_resolve
from change_impact_resolver_authority_guard_v1 import resolve_change_impact as guarded_resolve

ROW_RE = re.compile(
    r"\(\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*\)"
)


def unescape(value: str) -> str:
    return value.replace("''", "'")


text = Path(__file__).with_name("change_impact_l3c_gold_50.sql").read_text(encoding="utf-8")
rows = []
for match in ROW_RE.finditer(text):
    case_code, case_family, mutation, expected_decision, impacts_json, _, _ = (unescape(x) for x in match.groups())
    if case_code.startswith("CI-"):
        rows.append((case_code, case_family, mutation, expected_decision, set(json.loads(impacts_json))))

assert len(rows) == 50, len(rows)
runtime = RuntimeAuthority(True, False)
for case_code, family, mutation, _, _ in rows:
    base = base_resolve(family, mutation, runtime)
    guarded = guarded_resolve(family, mutation, runtime)
    assert guarded == base, (case_code, base, guarded)

print("CHANGE_IMPACT_AUTHORITY_GUARD_NEUTRAL_CURRENT_AUTHORITY_PASS 50/50")
