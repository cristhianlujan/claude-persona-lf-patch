"""Candidate for EXISTING LF Profile Updater change_scope and readback checks.

Pure validation function, not a workflow, judge, operation or write authority.
Only the trusted GitHub exact-ref reader can supply profile-native step graphs.
Do not treat a producer-written graph or a textual locator as trusted readback.
"""
from __future__ import annotations
import re
from typing import Any

_SHA40 = re.compile(r"^[a-f0-9]{40}$")
_ACTIONS = frozenset({"MODIFY", "INSERT", "REPLACE", "REMOVE"})


def _graph(graph: Any, slug: str, head: str) -> tuple[dict[str, dict], str | None]:
    if not isinstance(graph, dict) or graph.get("profile_slug") != slug or graph.get("source_head_sha") != head:
        return {}, "PROFILE_GRAPH_SOURCE_BINDING_MISMATCH"
    if not isinstance(graph.get("source_ref"), str) or not graph["source_ref"] or not isinstance(graph.get("steps"), list) or not graph["steps"]:
        return {}, "PROFILE_GRAPH_NOT_READABLE"
    steps: dict[str, dict] = {}
    positions = set()
    for step in graph["steps"]:
        if not isinstance(step, dict):
            return {}, "PROFILE_STEP_GRAPH_MALFORMED"
        key, position = step.get("step_id"), step.get("order")
        if not isinstance(key, str) or not key or key in steps or not isinstance(position, int) or isinstance(position, bool) or position in positions:
            return {}, "PROFILE_STEP_ID_OR_ORDER_DUPLICATE"
        if not isinstance(step.get("source_anchor"), str) or not step["source_anchor"]:
            return {}, "PROFILE_STEP_ANCHOR_MISSING"
        steps[key] = step
        positions.add(position)
    ordered = sorted(steps.values(), key=lambda s: s["order"])
    for i, step in enumerate(ordered):
        previous = ordered[i - 1]["step_id"] if i else None
        following = ordered[i + 1]["step_id"] if i + 1 < len(ordered) else None
        if step.get("predecessor") != previous or step.get("successor") != following:
            return {}, "PROFILE_STEP_GRAPH_LINK_INCONSISTENT"
    return steps, None


def validate_change_scope_placement(
    *, profile_slug: str, source_head_sha: str, selected_method_ids: list[str],
    adoptions: list[dict[str, Any]], trusted_base_graph: dict[str, Any],
) -> list[str]:
    """Candidate call within the EXISTING change_scope (40). No writes."""
    if not isinstance(profile_slug, str) or not profile_slug or not isinstance(source_head_sha, str) or not _SHA40.fullmatch(source_head_sha):
        return ["PLACEMENT_PROFILE_REVISION_INVALID"]
    steps, problem = _graph(trusted_base_graph, profile_slug, source_head_sha)
    if problem:
        return [problem]
    if not isinstance(selected_method_ids, list) or not all(isinstance(x, str) and x for x in selected_method_ids) or len(selected_method_ids) != len(set(selected_method_ids)):
        return ["PLACEMENT_SELECTED_METHODS_INVALID"]
    if not isinstance(adoptions, list):
        return ["PLACEMENT_DECISIONS_NOT_ARRAY"]
    errors = []
    claimed_methods, targets = set(), set()
    for adoption in adoptions:
        if not isinstance(adoption, dict):
            errors.append("PLACEMENT_DECISION_NOT_OBJECT")
            continue
        mid, action, target = adoption.get("method_id"), adoption.get("action"), adoption.get("target_step_id")
        if mid not in selected_method_ids:
            errors.append("PLACEMENT_METHOD_NOT_SELECTED")
        if mid in claimed_methods:
            errors.append("PLACEMENT_METHOD_DUPLICATED")
        claimed_methods.add(mid)
        if action not in _ACTIONS:
            errors.append("PLACEMENT_ACTION_UNSUPPORTED")
            continue
        if not isinstance(target, str) or not target or target in targets:
            errors.append("PLACEMENT_TARGET_DUPLICATE_OR_MISSING")
            continue
        targets.add(target)
        predecessor, successor = adoption.get("predecessor"), adoption.get("successor")
        if action == "INSERT":
            if target in steps:
                errors.append("PLACEMENT_NEW_STEP_ALREADY_EXISTS")
            if predecessor is None and successor is None:
                errors.append("PLACEMENT_INSERT_NEIGHBORS_MISSING")
            if predecessor is not None and predecessor not in steps:
                errors.append("PLACEMENT_PREDECESSOR_NOT_FOUND")
            if successor is not None and successor not in steps:
                errors.append("PLACEMENT_SUCCESSOR_NOT_FOUND")
            if predecessor in steps and steps[predecessor].get("successor") != successor:
                errors.append("PLACEMENT_INSERT_NOT_ADJACENT")
            if successor in steps and steps[successor].get("predecessor") != predecessor:
                errors.append("PLACEMENT_INSERT_NOT_ADJACENT")
            if not isinstance(adoption.get("planned_enforcement_ref"), str) or not adoption["planned_enforcement_ref"]:
                errors.append("PLACEMENT_INSERT_ENFORCEMENT_UNSPECIFIED")
        else:
            old = steps.get(target)
            if old is None:
                errors.append("PLACEMENT_EXISTING_STEP_NOT_FOUND")
                continue
            if old.get("predecessor") != predecessor or old.get("successor") != successor:
                errors.append("PLACEMENT_EXISTING_LINK_MISMATCH")
        if not isinstance(adoption.get("reason_ref"), str) or not adoption["reason_ref"]:
            errors.append("PLACEMENT_JUSTIFICATION_MISSING")
    return sorted(set(errors))


def verify_candidate_placement_readback(
    *, profile_slug: str, base_head_sha: str, candidate_head_sha: str,
    adoptions: list[dict[str, Any]], trusted_base_graph: dict[str, Any],
    trusted_candidate_graph: dict[str, Any],
) -> list[str]:
    """Candidate call within EXISTING post-write readback/validation steps."""
    if not isinstance(candidate_head_sha, str) or not _SHA40.fullmatch(candidate_head_sha) or candidate_head_sha == base_head_sha:
        return ["PLACEMENT_CANDIDATE_HEAD_INVALID"]
    old, err = _graph(trusted_base_graph, profile_slug, base_head_sha)
    if err:
        return [err]
    new, err = _graph(trusted_candidate_graph, profile_slug, candidate_head_sha)
    if err:
        return [err]
    if not isinstance(adoptions, list):
        return ["PLACEMENT_DECISIONS_NOT_ARRAY"]
    errors: list[str] = []
    changed = set(old) ^ set(new)
    for step_id in old.keys() & new.keys():
        before = {k: v for k, v in old[step_id].items() if k != "order"}
        after = {k: v for k, v in new[step_id].items() if k != "order"}
        if before != after:
            changed.add(step_id)
    permitted: set[str] = set()
    for a in adoptions:
        if not isinstance(a, dict):
            errors.append("PLACEMENT_DECISION_NOT_OBJECT")
            continue
        target, action = a.get("target_step_id"), a.get("action")
        before, after = a.get("predecessor"), a.get("successor")
        permitted.update(s for s in (target, before, after) if s is not None)
        if action == "INSERT":
            row = new.get(target)
            if target in old or not row or row.get("predecessor") != before or row.get("successor") != after:
                errors.append("PLACEMENT_INSERT_NOT_REALIZED")
            if not row or row.get("enforcement_ref") != a.get("planned_enforcement_ref") or not row.get("call_ref"):
                errors.append("PLACEMENT_ENFORCEMENT_NOT_REALIZED")
        elif action == "REMOVE":
            if target not in old or target in new:
                errors.append("PLACEMENT_REMOVE_NOT_REALIZED")
        elif action in {"MODIFY", "REPLACE"}:
            if target not in old or target not in new or new[target] == old[target]:
                errors.append("PLACEMENT_STEP_CHANGE_NOT_REALIZED")
            elif not new[target].get("enforcement_ref") or not new[target].get("call_ref"):
                errors.append("PLACEMENT_ENFORCEMENT_NOT_REALIZED")
    if changed - permitted:
        errors.append("PLACEMENT_UNRELATED_STEP_CHANGED")
    return sorted(set(errors))
