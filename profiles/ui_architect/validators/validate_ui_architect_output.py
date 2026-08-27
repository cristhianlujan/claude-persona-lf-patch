#!/usr/bin/env python3
import json, sys
from pathlib import Path

PRODUCTION_REQUIRED = {
    "screen_definition", "component_tree", "layout_grid", "visual_hierarchy",
    "state_map", "token_map", "spacing_typography", "density_rules",
    "risk_controls", "prompt_constraints"
}
COMPONENT_REQUIRED = {
    "zone_id", "component_id", "component_type", "role", "content",
    "visual_priority", "color_tokens", "typography", "spacing", "state",
    "allowed_variants", "blocked_variants"
}
SCORE_KEYS = [
    "layout_precision", "visual_hierarchy", "lf_system_fidelity",
    "state_mapping", "handoff_quality"
]
REMEDIATION_REQUIRED = {
    "issue_id", "priority", "category", "evidence_anchor", "decision",
    "implementation_change", "acceptance_criteria"
}
CATEGORIES = {"LAYOUT", "HIERARCHY", "INTERACTION", "COPY", "RISK"}
PRIORITIES = {"P0", "P1", "P2", "P3"}
VAGUE = ("could use", "should consider", "consider ", "maybe ", "improve hierarchy", "make it better")


def fail(code, detail, errors):
    errors.append({"code": code, "detail": detail})


def validate(data):
    errors = []
    if data.get("output_type") != "PRODUCTION_UI_SPEC":
        fail("OUTPUT_MODE_INVALID", "Expected output_type=PRODUCTION_UI_SPEC for this validator.", errors)

    d = data.get("deliverable_created")
    if not isinstance(d, dict):
        fail("DELIVERABLE_NOT_OBJECT", "deliverable_created must be an object.", errors)
        return errors

    missing = sorted(PRODUCTION_REQUIRED - set(d))
    if missing:
        fail("PRODUCTION_FIELDS_MISSING", ", ".join(missing), errors)

    tree = d.get("component_tree")
    if not isinstance(tree, list) or not tree:
        fail("COMPONENT_TREE_MISSING", "component_tree must be a non-empty array.", errors)
    else:
        for i, node in enumerate(tree):
            if not isinstance(node, dict):
                fail("COMPONENT_NODE_INVALID", f"component_tree[{i}] is not an object", errors)
                continue
            miss = sorted(COMPONENT_REQUIRED - set(node))
            if miss:
                fail("COMPONENT_FIELDS_MISSING", f"component_tree[{i}]: {', '.join(miss)}", errors)

    score = data.get("score")
    if not isinstance(score, dict):
        fail("SCORE_MISSING", "score object required", errors)
    else:
        for key in SCORE_KEYS:
            val = score.get(key)
            if not isinstance(val, int) or not 0 <= val <= 5:
                fail("SCORE_CRITERION_INVALID", f"{key} must be integer 0..5", errors)
        if all(isinstance(score.get(k), int) for k in SCORE_KEYS):
            expected = sum(score[k] for k in SCORE_KEYS)
            if score.get("total") != expected:
                fail("SCORE_TOTAL_INVALID", f"total={score.get('total')} expected={expected}", errors)
        evidence = score.get("evidence_by_criterion")
        if not isinstance(evidence, dict) or any(not str(evidence.get(k, "")).strip() for k in SCORE_KEYS):
            fail("SCORE_EVIDENCE_MISSING", "Each canonical score criterion requires evidence.", errors)

    if not isinstance(data.get("handoff_to_next"), dict):
        fail("HANDOFF_MISSING", "handoff_to_next object required", errors)
    if not isinstance(data.get("self_verdict"), str) or not data.get("self_verdict").strip():
        fail("SELF_VERDICT_MISSING", "self_verdict required", errors)

    screen_def = d.get("screen_definition") if isinstance(d.get("screen_definition"), dict) else {}
    task_mode = screen_def.get("task_mode")
    if task_mode in {"EVALUATE_EXISTING", "REMEDIATE_EXISTING"}:
        actions = d.get("remediation_actions")
        if not isinstance(actions, list) or not actions:
            fail("REMEDIATION_ACTIONS_MISSING", "Existing-screen review requires remediation_actions.", errors)
        else:
            seen_ids, seen_decisions, categories = set(), set(), set()
            for i, action in enumerate(actions):
                if not isinstance(action, dict):
                    fail("REMEDIATION_ACTION_INVALID", f"remediation_actions[{i}] not object", errors)
                    continue
                miss = sorted(REMEDIATION_REQUIRED - set(action))
                if miss:
                    fail("REMEDIATION_FIELDS_MISSING", f"action[{i}]: {', '.join(miss)}", errors)
                    continue
                iid = str(action["issue_id"]).strip()
                if iid in seen_ids:
                    fail("REMEDIATION_DUPLICATE_ID", iid, errors)
                seen_ids.add(iid)
                if action["priority"] not in PRIORITIES:
                    fail("REMEDIATION_PRIORITY_INVALID", str(action["priority"]), errors)
                if action["category"] not in CATEGORIES:
                    fail("REMEDIATION_CATEGORY_INVALID", str(action["category"]), errors)
                else:
                    categories.add(action["category"])
                anchor = str(action["evidence_anchor"]).strip().lower()
                if anchor in {"screen", "ui", "layout", "page"} or len(anchor) < 8:
                    fail("EVIDENCE_ANCHOR_GENERIC", str(action["evidence_anchor"]), errors)
                decision = str(action["decision"]).strip()
                if any(term in decision.lower() for term in VAGUE):
                    fail("DECISION_NOT_EXECUTABLE", decision, errors)
                normalized = " ".join(decision.lower().split())
                if normalized in seen_decisions:
                    fail("REPEATED_DECISION", decision, errors)
                seen_decisions.add(normalized)
                if len(str(action["implementation_change"]).strip()) < 12:
                    fail("IMPLEMENTATION_CHANGE_TOO_VAGUE", str(action["implementation_change"]), errors)
                if len(str(action["acceptance_criteria"]).strip()) < 12:
                    fail("ACCEPTANCE_CRITERIA_TOO_VAGUE", str(action["acceptance_criteria"]), errors)
            if len(actions) > 1 and len(categories) < 2:
                fail("REMEDIATION_CATEGORY_COLLAPSE", "Multiple material issues collapsed into one category.", errors)

    return errors


def main():
    if len(sys.argv) != 2:
        print("usage: validate_ui_architect_output.py <json>", file=sys.stderr)
        return 2
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    errors = validate(data)
    result = {"valid": not errors, "errors": errors}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if not errors else 1

if __name__ == "__main__":
    raise SystemExit(main())
