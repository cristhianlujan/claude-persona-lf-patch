#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve()
SKILL = HERE.parents[1]
MODULE = SKILL / "validators/evaluate_s26_profile_baseline.py"
spec = importlib.util.spec_from_file_location("s26_profile_baseline_eval", MODULE)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(mod)


def make_repo() -> tuple[tempfile.TemporaryDirectory, Path]:
    tmp = tempfile.TemporaryDirectory()
    root = Path(tmp.name)
    dst = root / "skills/profile_creator/contracts"
    dst.mkdir(parents=True)
    shutil.copy2(SKILL / "contracts/s26_profile_baseline_v1.json", dst / "s26_profile_baseline_v1.json")
    return tmp, root


def materialize(root: Path, *, complete: bool = True, ambiguous: bool = False, side_effect_marker: Path | None = None) -> None:
    p = root / "profiles/demo"
    (p / "contracts").mkdir(parents=True)
    (p / "schemas").mkdir()
    (p / "validators").mkdir()
    (p / "SKILL.md").write_text("# Demo\nMaintenance: ACTUALIZACION_PERFIL_LF\n", encoding="utf-8")
    schema = {"type": "object", "properties": {"answer": {"type": "string"}}, "required": ["answer"]}
    (p / "schemas/output.schema.json").write_text(json.dumps(schema), encoding="utf-8")
    if ambiguous:
        (p / "schemas/other.schema.json").write_text(json.dumps(schema), encoding="utf-8")
    (p / "validators/validate_pack.py").write_text("raise SystemExit(0)\n", encoding="utf-8")
    marker = f"from pathlib import Path\nPath({str(side_effect_marker)!r}).write_text('EXECUTED')\n" if side_effect_marker else ""
    (p / "validators/runtime_validate.py").write_text(marker + "def validate(payload): return []\n", encoding="utf-8")
    (p / "validators/runtime_semantic_utility.py").write_text(marker + 'def evaluate(payload, contract_gate): return {"status":"PASS","blocking_codes":[]}\n', encoding="utf-8")
    if complete:
        binding = {
            "schema": "LF_PROFILE_RUNTIME_BINDING_V1", "profile_slug": "demo", "profile_code": "PERFIL-DEMO",
            "runtime_schema": {"default": "schemas/output.schema.json", "output_modes": {}},
            "canonical_validator": {"path": "validators/runtime_validate.py", "callable": "validate"},
            "semantic_utility": {"path": "validators/runtime_semantic_utility.py", "callable": "evaluate"},
            "governance": {"source_first_required": True, "schema_invention_allowed": False, "fail_closed": True, "exact_head_evidence_required": True, "post_update_baseline_required": True},
        }
        (p / "contracts/runtime_binding.json").write_text(json.dumps(binding), encoding="utf-8")


def main() -> int:
    checks = {}
    t, r = make_repo()
    try:
        materialize(r); x = mod.evaluate(r, "demo")
        checks["complete_10_of_10"] = x["decision"] == "NO_UPDATE_REQUIRED" and x["score"] == 10
        checks["static_callable_discovery"] = x["callable_discovery_mode"] == "STATIC_AST_NO_IMPORT"
    finally: t.cleanup()
    t, r = make_repo()
    try:
        materialize(r, complete=False, ambiguous=True); x = mod.evaluate(r, "demo")
        checks["ambiguous_requires_authority"] = x["decision"] == "BLOCKED_AUTHORITY_REQUIRED" and "RUNTIME_SCHEMA_EXPLICIT_BINDING_REQUIRED" in x["blocking_codes"]
        checks["repair_plan_materialized"] = any(i["action"] == "MATERIALIZE_RUNTIME_BINDING" for i in x["repair_actions"])
    finally: t.cleanup()
    t, r = make_repo()
    try:
        materialize(r); p = r / "profiles/demo/contracts/runtime_binding.json"; b = json.loads(p.read_text()); b["governance"]["fail_closed"] = False; p.write_text(json.dumps(b)); x = mod.evaluate(r, "demo")
        checks["weak_fail_closed_detected"] = x["dimensions"]["B09_FAIL_CLOSED"]["pass"] is False
    finally: t.cleanup()
    t, r = make_repo()
    try:
        marker = r / "IMPORT_SIDE_EFFECT"; materialize(r, side_effect_marker=marker); x = mod.evaluate(r, "demo")
        checks["target_code_not_executed"] = x["score"] == 10 and x["target_code_execution_performed"] is False and not marker.exists()
    finally: t.cleanup()
    t, r = make_repo()
    try:
        materialize(r); raw = r / "profiles/demo"; outside = r / "outside"; raw.rename(outside); raw.symlink_to(outside, target_is_directory=True); x = mod.evaluate(r, "demo")
        checks["symlink_profile_blocked"] = "PROFILE_TARGET_SYMLINK_FORBIDDEN" in x["blocking_codes"]
    finally: t.cleanup()
    ok = all(checks.values())
    print(json.dumps({"contract":"S26_PROFILE_BASELINE_MATRIX_V2","checks":checks,"count":len(checks),"result":"PASS" if ok else "FAIL"}, sort_keys=True)); return 0 if ok else 1


if __name__ == "__main__": raise SystemExit(main())
