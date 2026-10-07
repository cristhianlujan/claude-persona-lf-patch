from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
skill=(ROOT/"SKILL.md").read_text(encoding="utf-8")
binding=json.loads((ROOT/"contracts/runtime_binding.json").read_text(encoding="utf-8"))
projection=binding["model_context"]["source_projection"]
include=projection["include_sections"]

sections={}
current=None
for line in skill.splitlines():
    if line.startswith("## "):
        current=line[3:].strip()
        sections[current]=[line]
    elif current is not None:
        sections[current].append(line)

missing=[name for name in include if name not in sections]
assert not missing, missing
projected="\n\n".join("\n".join(sections[name]).strip() for name in include)+"\n"

assert binding["model_context"]["required_source_refs"] == [
    "profiles/systemic_root_cause_repair_lf/SKILL.md"
]
assert "Output trajectory (field order for the typed output)" not in include
assert "Typed output" not in include
assert "Working method (do this first; the rules below are how the result is checked)" in include
assert "Status semantics" in include
assert "Non-negotiable rules" in include
assert "Closure-proof contract" in include
assert len(projected) <= 18000, len(projected)
assert len(projected) <= projection["max_chars"]
assert (ROOT/"contracts/main_contract.md").is_file()
assert (ROOT/"schemas/output.schema.json").is_file()
print(f"PASS_SRCR_RUNTIME_CONTEXT_BUDGET=10/10 projected_chars={len(projected)}")
