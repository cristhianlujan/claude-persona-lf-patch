from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
migrations = sorted((root / "supabase" / "migrations").glob("*_fix_profile_update_begin_uppercase_path_v1.sql"))
assert migrations, "migration missing"
sql = migrations[-1].read_text(encoding="utf-8")

assert "^profiles/[A-Za-z0-9][A-Za-z0-9_./-]*$" in sql
pattern = re.compile(r"^profiles/[A-Za-z0-9][A-Za-z0-9_./-]*$")

positive = [
    "profiles/systemic_root_cause_repair_lf/SKILL.md",
    "profiles/systemic_root_cause_repair_lf/manifest.json",
    "profiles/systemic_root_cause_repair_lf/contracts/runtime_binding.json",
]
negative = [
    "profiles/systemic_root_cause_repair_lf/SKILL:md",
    r"profiles/systemic_root_cause_repair_lf\SKILL.md",
]

for value in positive:
    assert pattern.fullmatch(value), value
for value in negative:
    assert not pattern.fullmatch(value), value

traversal = "profiles/systemic_root_cause_repair_lf/../SKILL.md"
assert pattern.fullmatch(traversal)
assert ".." in traversal

print("PASS_PROFILE_UPDATE_UPPERCASE_TARGET_PATH=6/6")
