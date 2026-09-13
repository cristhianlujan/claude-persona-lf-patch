#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PLAN = json.loads((ROOT / "s31_strategy_master_plan_v0_2.json").read_text(encoding="utf-8"))
SPEC = importlib.util.spec_from_file_location("s31_master_plan", ROOT / "validate_s31_strategy_master_plan_v0_2.py")
m = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = m
SPEC.loader.exec_module(m)

cases = 0

# Positive canonical plan.
assert m.validate_plan(PLAN)["status"] == "PASS"; cases += 1

# Execution sequence cannot skip adversarial audit.
x = copy.deepcopy(PLAN); x["execution_sequence"].remove("ADVERSARIAL_BYPASS_AUDIT")
assert m.validate_plan(x)["code"] == "BLOCK_EXECUTION_SEQUENCE_DRIFT"; cases += 1

# Safe-work non-empty must remain close-blocking.
x = copy.deepcopy(PLAN); x["close_policy"]["safe_parallel_work_nonempty_forbids_close"] = False
assert m.validate_plan(x)["code"] == "BLOCK_ANTI_CLOSE_WEAKENED"; cases += 1

# Zero-safe-work claim requires global discovery.
x = copy.deepcopy(PLAN); x["close_policy"]["global_remaining_work_discovery_required_before_zero_safe_work"] = False
assert m.validate_plan(x)["code"] == "BLOCK_ANTI_CLOSE_WEAKENED"; cases += 1

# Unresolved causal blocker cannot be converted to successful close.
x = copy.deepcopy(PLAN); x["close_policy"]["unresolved_blocker_with_no_safe_work_disposition"] = "PASS_CLOSE"
assert m.validate_plan(x)["code"] == "BLOCK_UNRESOLVED_BLOCKER_CLOSE_BYPASS"; cases += 1

# A transversal defect cannot omit regression.
x = copy.deepcopy(PLAN); x["defect_response"]["regression_required"] = False
assert m.validate_plan(x)["code"] == "BLOCK_DEFECT_LEARNING_CHAIN_WEAKENED"; cases += 1

# Workaround cannot be treated as causal closure.
x = copy.deepcopy(PLAN); x["defect_response"]["workaround_without_causal_repair_is_closure"] = True
assert m.validate_plan(x)["code"] == "BLOCK_WORKAROUND_AS_CLOSURE"; cases += 1

# Lifecycle dimensions must remain separate.
x = copy.deepcopy(PLAN); x["evidence_lifecycle_dimensions"] = ["LIFECYCLE"]
assert m.validate_plan(x)["code"] == "BLOCK_LIFECYCLE_DIMENSIONS_COLLAPSED"; cases += 1

# Canonical lifecycle vocabulary cannot be invented early.
x = copy.deepcopy(PLAN); x["evidence_rules"]["canonical_lifecycle_vocabulary_status"] = "RESOLVED"
assert m.validate_plan(x)["code"] == "BLOCK_LIFECYCLE_VOCABULARY_OVERCLAIM"; cases += 1

# Custom review receiver cannot replace Quality Pack.
x = copy.deepcopy(PLAN); x["review_policy"]["canonical_receiver"] = "S31_CUSTOM_JUDGE"
assert m.validate_plan(x)["code"] == "BLOCK_CANONICAL_REVIEW_BOUNDARY"; cases += 1

# Scope-specific freeze cannot regress to global refreeze.
x = copy.deepcopy(PLAN); x["review_policy"]["scope_specific_freeze"] = False
assert m.validate_plan(x)["code"] == "BLOCK_REVIEW_POLICY_WEAKENED"; cases += 1

# S31-H cannot advance before internal semantic reconciliation.
x = copy.deepcopy(PLAN); x["lanes"]["S31-H"]["state"] = "ACTIVE_POC"
assert m.validate_plan(x)["code"] == "BLOCK_S31_H_PREMATURE_ADVANCE"; cases += 1

# External framework cannot become authority.
x = copy.deepcopy(PLAN); x["s31_h_policy"]["framework_is_authority"] = True
assert m.validate_plan(x)["code"] == "BLOCK_FRAMEWORK_AUTHORITY_LEAK"; cases += 1

# External PoC execution cannot be silently pre-authorized.
x = copy.deepcopy(PLAN); x["s31_h_policy"]["install_or_poc_execution_currently_authorized"] = True
assert m.validate_plan(x)["code"] == "BLOCK_EXTERNAL_POC_PREMATURE_AUTHORIZATION"; cases += 1

# Promotion authority remains explicitly false.
x = copy.deepcopy(PLAN); x["promotion_authority"]["merge_main_authorized"] = True
assert m.validate_plan(x)["code"] == "BLOCK_PROMOTION_AUTHORITY_OVERCLAIM"; cases += 1

# Completion cannot omit independent semantic review.
x = copy.deepcopy(PLAN); x["completion_definition"]["independent_semantic_pass_required"] = False
assert m.validate_plan(x)["code"] == "BLOCK_COMPLETION_DEFINITION_WEAKENED"; cases += 1

print(f"PASS_S31_STRATEGY_MASTER_PLAN_V0_2={cases}/{cases}")
