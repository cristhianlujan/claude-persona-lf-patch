from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
skill = (ROOT / "SKILL.md").read_text(encoding="utf-8")
binding = json.loads((ROOT / "contracts/runtime_binding.json").read_text(encoding="utf-8"))
projection = binding["model_context"]["source_projection"]
include = projection["include_sections"]

sections = {}
current = None
for line in skill.splitlines():
    if line.startswith("## "):
        current = line[3:].strip()
        sections[current] = [line]
    elif current is not None:
        sections[current].append(line)

missing = [name for name in include if name not in sections]
assert not missing, missing
projected = "\n\n".join("\n".join(sections[name]).strip() for name in include) + "\n"

assert binding["model_context"]["full_source_to_model"] is False
assert binding["model_context"]["required_source_refs"] == [
    "profiles/systemic_root_cause_repair_lf/SKILL.md"
]
assert include == ["Purpose", "Runtime method capsule"]
assert projection["max_chars"] == 8000
assert len(projected) <= 8000, len(projected)

capsule = "\n".join(sections["Runtime method capsule"])
for required in [
    "Authority and currentness first",
    "Find the first bad boundary",
    "Select methods dynamically",
    "Second-order recurrence",
    "Operability ownership is conditional",
    "Mechanical terminality",
    "pipeline_blocking_codes",
    "NEEDS_MORE_EVIDENCE",
    "SYSTEMIC_REPAIR_SPEC",
    "R4 universal overlay is not part",
    "exactly one object",
]:
    assert required in capsule, required

assert "Output trajectory (field order for the typed output)" not in include
assert "Typed output" not in include
assert (ROOT / "contracts/main_contract.md").is_file()
assert (ROOT / "schemas/output.schema.json").is_file()

print(f"PASS_SRCR_RUNTIME_CONTEXT_BUDGET=19/19 projected_chars={len(projected)}")
