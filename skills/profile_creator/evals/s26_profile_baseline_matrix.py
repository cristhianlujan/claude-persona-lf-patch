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


def materialize(root: Path, *, complete: bool = True, ambiguous: bool = False, side_effect_marker: Path | None = None, validator_src: str | None = None, suite: bool = True) -> None:
    p = root / "profiles/demo"
    (p / "contracts").mkdir(parents=True)
    (p / "schemas").mkdir()
    (p / "validators").mkdir()
    (p / "SKILL.md").write_text("# Demo\nMaintenance: ACTUALIZACION_PERFIL_LF\n## Purpose\nAnswer demo questions.\n", encoding="utf-8")
    schema = {"type": "object", "properties": {"answer": {"type": "string"}}, "required": ["answer"]}
    (p / "schemas/output.schema.json").write_text(json.dumps(schema), encoding="utf-8")
    if ambiguous:
        (p / "schemas/other.schema.json").write_text(json.dumps(schema), encoding="utf-8")
    (p / "validators/validate_pack.py").write_text("raise SystemExit(0)\n", encoding="utf-8")
    marker = f"from pathlib import Path\nPath({str(side_effect_marker)!r}).write_text('EXECUTED')\n" if side_effect_marker else ""
    (p / "examples").mkdir()
    (p / "examples/good.json").write_text(json.dumps({"answer": "A clear answer."}), encoding="utf-8")
    validate_src = validator_src or (
        "def validate(payload):\n"
        "    ok = isinstance(payload, dict) and set(payload) == {'answer'} and isinstance(payload['answer'], str) and payload['answer'].replace('\\u200b','').replace('\\u00a0','').strip() != ''\n"
        "    return {'status': 'PASS' if ok else 'FAIL'}\n")
    (p / "validators/runtime_validate.py").write_text(marker + validate_src, encoding="utf-8")
    (p / "validators/runtime_semantic_utility.py").write_text(marker + (
        "import re\n"
        "def evaluate(payload, contract_gate):\n"
        "    t = re.sub(r'[^a-z0-9]+', ' ', str(payload.get('answer','')).lower())\n"
        "    bad = re.search(r'act now|last chance|aproveche|urgent', t)\n"
        "    return {'status': 'FAIL' if bad else 'PASS', 'blocking_codes': []}\n"), encoding="utf-8")
    if complete:
        binding = {
            "schema": "LF_PROFILE_RUNTIME_BINDING_V1", "profile_slug": "demo", "profile_code": "PERFIL-DEMO",
            "runtime_schema": {"default": "schemas/output.schema.json", "output_modes": {}},
            "canonical_validator": {"path": "validators/runtime_validate.py", "callable": "validate"},
            "semantic_utility": {"path": "validators/runtime_semantic_utility.py", "callable": "evaluate"},
            "governance": {"source_first_required": True, "schema_invention_allowed": False, "fail_closed": True, "exact_head_evidence_required": True, "post_update_baseline_required": True},
            "model_context": {"full_source_to_model": False, "source_projection": {"mode": "MARKDOWN_SECTIONS", "include_sections": ["Purpose"], "max_chars": 2000}},
            "execution_partition": {"schema": "LF_PROFILE_EXECUTION_PARTITION_V1", "field_classes": {"answer": "SEMANTIC"}, "deterministic_materialization": {}, "generation_limits": {"default_string_max_length": 160, "fields": {}}},
            "execution_budget": {"resource_class": "STANDARD", "max_prompt_tokens": 2048, "max_output_tokens": 512, "min_available_memory_mb": 0, "max_swap_used_pct": 100},
        }
        if suite:
            binding["adversarial_suite"] = {
                "schema": "LF_PROFILE_ADVERSARIAL_SUITE_V1", "base_example": "examples/good.json", "min_cases": 20, "min_catch_rate": 0.95,
                "blank_fields": ["answer"], "unknown_root_key": True,
                "injections": [{"fields": ["answer"], "phrases": ["Act now", "Last chance", "Aproveche ahora", "Urgent offer"]}],
                "valid_controls": [{"name": "plain", "set": {"answer": "No claim is made about the best option."}}],
            }
        (p / "contracts/runtime_binding.json").write_text(json.dumps(binding), encoding="utf-8")


def main() -> int:
    checks = {}
    t, r = make_repo()
    try:
        materialize(r); x = mod.evaluate(r, "demo")
        checks["complete_14_of_14"] = x["decision"] == "NO_UPDATE_REQUIRED" and x["score"] == 14 and x["required"] == 14
        checks["suite_catches_and_accepts_controls"] = x["adversarial_suite"]["catch_rate"] == 1.0 and x["adversarial_suite"]["controls_rejected_wrongly"] == []
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
        materialize(r); x = mod.evaluate(r, "demo", dynamic=False)
        checks["static_mode_never_executes"] = x["target_code_execution_performed"] is False and x["dimensions"]["B14_DYNAMIC_ADVERSARIAL_SUITE"]["code"] == "SUITE_NOT_EXECUTED"
        x = mod.evaluate(r, "demo")
        checks["dynamic_mode_declares_isolation"] = x["target_code_execution_performed"] is True and x["target_code_execution_mode"] == "ISOLATED_CHILD_NO_NETWORK_CLEARED_ENV"
    finally: t.cleanup()
    t, r = make_repo()
    try:
        materialize(r, suite=False); x = mod.evaluate(r, "demo")
        checks["undeclared_suite_fails_b14_only"] = x["score"] == 13 and x["dimensions"]["B14_DYNAMIC_ADVERSARIAL_SUITE"]["code"] == "SUITE_NOT_DECLARED" and x["target_code_execution_performed"] is False
    finally: t.cleanup()
    t, r = make_repo()
    try:
        materialize(r, validator_src="def validate(payload): return {'status': 'PASS'}\n"); x = mod.evaluate(r, "demo")
        checks["permissive_validator_fails_b14"] = x["dimensions"]["B14_DYNAMIC_ADVERSARIAL_SUITE"]["pass"] is False and x["adversarial_suite"]["catch_rate"] < 0.95
    finally: t.cleanup()
    t, r = make_repo()
    try:
        materialize(r, validator_src="import socket\ndef validate(payload):\n    socket.create_connection(('example.com', 80), timeout=2)\n    return {'status': 'PASS'}\n"); x = mod.evaluate(r, "demo")
        checks["network_blocked_fail_closed"] = x["dimensions"]["B14_DYNAMIC_ADVERSARIAL_SUITE"]["pass"] is False
    finally: t.cleanup()
    t, r = make_repo()
    try:
        import os
        os.environ["S26_TEST_SECRET"] = "SECRET-VALUE"
        materialize(r, validator_src="import os\ndef validate(payload):\n    return {'status': 'FAIL' if os.environ.get('S26_TEST_SECRET') else 'PASS'}\n"); x = mod.evaluate(r, "demo")
        checks["environment_cleared_in_child"] = x["adversarial_suite"]["controls_rejected_wrongly"] == [] if x["adversarial_suite"] else False
        os.environ.pop("S26_TEST_SECRET", None)
    finally: t.cleanup()
    t, r = make_repo()
    try:
        materialize(r, validator_src="import time\ndef validate(payload):\n    time.sleep(120)\n    return {'status': 'PASS'}\n"); x = mod.evaluate(r, "demo")
        checks["hanging_validator_times_out"] = x["dimensions"]["B14_DYNAMIC_ADVERSARIAL_SUITE"]["code"] == "SUITE_TIMEOUT"
    finally: t.cleanup()
    t, r = make_repo()
    try:
        materialize(r); a = mod.evaluate(r, "demo", seed="one")["adversarial_suite"]; b = mod.evaluate(r, "demo", seed="one")["adversarial_suite"]; c = mod.evaluate(r, "demo", seed="two")["adversarial_suite"]
        checks["same_seed_reproducible_other_seed_differs"] = a == b and a["seed_sha256"] != c["seed_sha256"]
    finally: t.cleanup()
    t, r = make_repo()
    try:
        materialize(r); raw = r / "profiles/demo"; outside = r / "outside"; raw.rename(outside); raw.symlink_to(outside, target_is_directory=True); x = mod.evaluate(r, "demo")
        checks["symlink_profile_blocked"] = "PROFILE_TARGET_SYMLINK_FORBIDDEN" in x["blocking_codes"]
    finally: t.cleanup()
    t, r = make_repo()
    try:
        materialize(r); p = r / "profiles/demo/contracts/runtime_binding.json"; b = json.loads(p.read_text()); del b["execution_partition"]["generation_limits"]; p.write_text(json.dumps(b)); x = mod.evaluate(r, "demo")
        checks["partition_without_generation_limits_rejected"] = x["dimensions"]["B12_EXECUTION_PARTITION"]["pass"] is False
    finally: t.cleanup()
    t, r = make_repo()
    try:
        materialize(r); p = r / "profiles/demo/contracts/runtime_binding.json"; b = json.loads(p.read_text()); b["execution_partition"]["field_classes"]["answer"] = "DETERMINISTIC"; b["execution_partition"]["deterministic_materialization"] = {"answer": "free text description"}; p.write_text(json.dumps(b)); x = mod.evaluate(r, "demo")
        checks["prose_materialization_rejected"] = x["dimensions"]["B12_EXECUTION_PARTITION"]["pass"] is False
        b["execution_partition"]["deterministic_materialization"] = {"answer": {"source": "profile_slug"}}; p.write_text(json.dumps(b)); x = mod.evaluate(r, "demo")
        checks["structured_materialization_accepted"] = x["dimensions"]["B12_EXECUTION_PARTITION"]["pass"] is True
    finally: t.cleanup()
    ok = all(checks.values())
    print(json.dumps({"contract":"S26_PROFILE_BASELINE_MATRIX_V2","checks":checks,"count":len(checks),"result":"PASS" if ok else "FAIL"}, sort_keys=True)); return 0 if ok else 1


if __name__ == "__main__": raise SystemExit(main())
