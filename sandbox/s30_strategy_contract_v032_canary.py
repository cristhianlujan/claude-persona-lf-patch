#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path

VALIDATOR_PATH = Path("gobernanza/judges/validate_strategy_contract_v032.py")
CANDIDATE_PATH = Path("sandbox/lf_contract_gate_test/s32_strategy_factory_v032_candidate.yaml")
SNAPSHOT_ID = 45
SUPABASE_READBACK_REF = "supabase://public/lf_strategy_snapshots/45#independent-second-statement"

spec = importlib.util.spec_from_file_location("validate_strategy_contract_v032", VALIDATOR_PATH)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL_S32_VALIDATOR_V032_MODULE_LOAD")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

raw_bytes = CANDIDATE_PATH.read_bytes()
raw_text = raw_bytes.decode("utf-8")
raw_sha256 = hashlib.sha256(raw_bytes).hexdigest()
strategy_archetype_key_count = sum(1 for line in raw_text.splitlines() if line.startswith("strategy_archetype:"))
if strategy_archetype_key_count != 1:
    raise SystemExit(f"FAIL_S32_DUPLICATE_TOP_LEVEL_ARCHETYPE_KEY count={strategy_archetype_key_count}")

candidate = validator.load_document(CANDIDATE_PATH)
results = []

prewrite = validator.validate(candidate, "prewrite")
results.append({
    "name": "s32_exact_candidate_prewrite",
    "ok": bool(prewrite.get("valid")) and prewrite.get("blocking_codes") == [],
    "valid": prewrite.get("valid"),
    "blocking_codes": prewrite.get("blocking_codes"),
    "results_sha256": prewrite.get("results_sha256"),
})

close_conclusion = {
    "conclusion_id": "S32-CONCLUSION-02-001",
    "stage_code": "S32-02",
    "status": "CLOSE_CANDIDATE",
    "conclusion": (
        "Git write/readback and Supabase candidate registration/readback are complete; "
        "the bounded canary is eligible for deterministic close validation and aggregate judging."
    ),
    "claim_ceiling": "R3_SELF_HOSTED_CANARY_NOT_PRODUCTION",
    "open_risks": [
        "Independent Product + Quality review remains post-canary.",
        "Global exact-head/control-plane gates remain separate from this canary claim.",
    ],
    "carry_forward": ["aggregate judge", "factory demotion", "final readback"],
    "invalidation_triggers": [
        "source head changes",
        "snapshot 45 identity changes",
        "policy or contract fingerprint changes",
    ],
}

stale = copy.deepcopy(candidate)
stale["baseline"]["supabase_snapshot_id"] = SNAPSHOT_ID
stale["baseline"]["supabase_readback_ref"] = SUPABASE_READBACK_REF
stale["stage_conclusions"] = [candidate["stage_conclusions"][0], close_conclusion]
stale["execution_frontier"] = {
    "state": "CLOSED",
    "current_stage": "S32-01",
    "current_action": "NONE",
    "safe_parallel_work": [],
    "blockers": [],
}
stale_result = validator.validate(stale, "close")
results.append({
    "name": "s32_stale_frontier_negative",
    "ok": (not stale_result.get("valid")) and "STALE_EXECUTION_FRONTIER" in stale_result.get("blocking_codes", []),
    "valid": stale_result.get("valid"),
    "blocking_codes": stale_result.get("blocking_codes"),
    "results_sha256": stale_result.get("results_sha256"),
})

closed = copy.deepcopy(candidate)
closed["baseline"]["supabase_snapshot_id"] = SNAPSHOT_ID
closed["baseline"]["supabase_readback_ref"] = SUPABASE_READBACK_REF
closed["stages"][0]["status"] = "COMPLETED"
closed["stages"][1]["status"] = "COMPLETED"
closed["stage_conclusions"] = [candidate["stage_conclusions"][0], close_conclusion]
closed["execution_frontier"] = {
    "state": "CLOSED",
    "current_stage": "TERMINAL",
    "current_action": "NONE",
    "safe_parallel_work": [],
    "blockers": [],
}
closed_projection_bytes = json.dumps(
    closed, ensure_ascii=False, sort_keys=True, separators=(",", ":")
).encode("utf-8")
close_projection_sha256 = hashlib.sha256(closed_projection_bytes).hexdigest()
closed_result = validator.validate(closed, "close")
results.append({
    "name": "s32_terminal_frontier_positive_close",
    "ok": bool(closed_result.get("valid")) and closed_result.get("blocking_codes") == [],
    "valid": closed_result.get("valid"),
    "blocking_codes": closed_result.get("blocking_codes"),
    "results_sha256": closed_result.get("results_sha256"),
    "close_projection_sha256": close_projection_sha256,
    "snapshot_id": SNAPSHOT_ID,
    "supabase_readback_ref": SUPABASE_READBACK_REF,
})

summary = {
    "validator_version": validator.VERSION,
    "validator_path": str(VALIDATOR_PATH),
    "candidate_path": str(CANDIDATE_PATH),
    "candidate_raw_sha256": raw_sha256,
    "close_projection_sha256": close_projection_sha256,
    "close_projection_snapshot_id": SNAPSHOT_ID,
    "close_projection_supabase_readback_ref": SUPABASE_READBACK_REF,
    "strategy_archetype_key_count": strategy_archetype_key_count,
    "total_cases": len(results),
    "passed": sum(1 for item in results if item["ok"]),
    "failed": sum(1 for item in results if not item["ok"]),
    "all_pass": all(item["ok"] for item in results),
    "results": results,
}
print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))
if not summary["all_pass"]:
    raise SystemExit("FAIL_S32_EXACT_V032_CANARY")
print("PASS_S32_EXACT_V032_CANARY")
