#!/usr/bin/env python3
import json
import re
import sys
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
SCORE_ALLOWED = set(SCORE_KEYS) | {"total", "evidence_by_criterion"}
REMEDIATION_REQUIRED = {
    "issue_id", "priority", "category", "evidence_anchor", "decision",
    "implementation_change", "acceptance_criteria", "evidence_component_ids",
    "execution", "acceptance_check"
}
EXECUTION_REQUIRED = {"operation", "target_component_id", "property", "desired_value"}
ACCEPTANCE_REQUIRED = {"check_type", "target_component_id", "expected"}
CATEGORIES = {"LAYOUT", "HIERARCHY", "INTERACTION", "COPY", "RISK"}
PRIORITIES = {"P0", "P1", "P2", "P3"}
OPERATIONS = {
    "REMOVE", "MOVE", "ALIGN", "REPLACE_COPY", "RESIZE", "REORDER",
    "SET_STATE", "SET_SPACING", "MERGE", "SPLIT", "HIDE", "SHOW",
    "CHANGE_TOKEN"
}
CHECK_TYPES = {
    "ABSENT", "PRESENT", "ALIGNED", "STATE", "COPY_EQUALS", "COUNT_EQUALS",
    "SPACING", "ORDER", "TOKEN", "RELATIONSHIP"
}
CATEGORY_OPERATIONS = {
    "LAYOUT": {"MOVE", "ALIGN", "RESIZE", "REORDER", "SET_SPACING"},
    "HIERARCHY": {"REMOVE", "MOVE", "REORDER", "RESIZE", "MERGE", "SPLIT", "HIDE", "SHOW", "CHANGE_TOKEN"},
    "INTERACTION": {"SET_STATE", "SHOW", "HIDE"},
    "COPY": {"REPLACE_COPY"},
    "RISK": {"REPLACE_COPY", "REMOVE", "HIDE", "SET_STATE", "CHANGE_TOKEN"},
}
OPERATION_CHECKS = {
    "REMOVE": {"ABSENT", "COUNT_EQUALS"},
    "MOVE": {"RELATIONSHIP", "ORDER", "ALIGNED"},
    "ALIGN": {"ALIGNED", "RELATIONSHIP"},
    "REPLACE_COPY": {"COPY_EQUALS", "PRESENT"},
    "RESIZE": {"RELATIONSHIP", "PRESENT"},
    "REORDER": {"ORDER", "RELATIONSHIP"},
    "SET_STATE": {"STATE"},
    "SET_SPACING": {"SPACING"},
    "MERGE": {"COUNT_EQUALS", "RELATIONSHIP"},
    "SPLIT": {"COUNT_EQUALS", "RELATIONSHIP"},
    "HIDE": {"ABSENT", "STATE"},
    "SHOW": {"PRESENT", "STATE"},
    "CHANGE_TOKEN": {"TOKEN"},
}
PASS_VERDICTS = {"PASS_TO_QUALITY_PACK_CANDIDATE", "PASS_TO_QUALITY_PACK", "PASS"}
ALLOWED_VERDICTS = PASS_VERDICTS | {
    "NEEDS_ADJUSTMENT", "RETURN_TO_WORKER_FOR_SELF_REPAIR",
    "RETURN_TO_ORCHESTRATOR", "BLOCK_PIPELINE", "BLOCKED"
}
NOMINAL_EVIDENCE = {"ok", "pass", "passed", "yes", "good", "valid", "done", "complete"}
GENERIC_ACTION_PHRASES = {
    "adjust colors spaces and general distribution",
    "ajustar colores espacios y distribución general",
    "improve the ui",
    "mejorar la ui",
}
OPERATION_TERMS = {
    "REMOVE": {"remove", "delete", "eliminate", "eliminar", "quitar"},
    "MOVE": {"move", "relocate", "mover", "reubicar"},
    "ALIGN": {"align", "aligned", "alinear", "alineado"},
    "REPLACE_COPY": {"replace", "copy", "label", "text", "usar", "reemplazar", "texto"},
    "RESIZE": {"resize", "width", "height", "size", "tamaño", "ancho", "alto"},
    "REORDER": {"reorder", "order", "before", "after", "orden", "antes", "después"},
    "SET_STATE": {"state", "disable", "enable", "selected", "estado", "deshabilitar", "habilitar", "seleccion"},
    "SET_SPACING": {"spacing", "gap", "padding", "margin", "espacio", "separación"},
    "MERGE": {"merge", "combine", "unify", "unificar", "combinar"},
    "SPLIT": {"split", "separate", "separar", "dividir"},
    "HIDE": {"hide", "hidden", "ocultar"},
    "SHOW": {"show", "visible", "mostrar"},
    "CHANGE_TOKEN": {"token", "color", "surface", "typography", "tipografia"},
}
STOP_TARGET_TOKENS = {"component", "card", "section", "block", "container", "wrapper", "ui"}

def fail(code, detail, errors):
    errors.append({"code": code, "detail": str(detail)})

def is_nonempty_dict(v):
    return isinstance(v, dict) and bool(v)

def normalize_text(value):
    return " ".join(re.sub(r"[^a-z0-9áéíóúñ_ ]+", " ", str(value).lower()).split())

def target_tokens(component_id):
    return {t for t in re.split(r"[_\-\s]+", str(component_id).lower()) if len(t) >= 4 and t not in STOP_TARGET_TOKENS}

def validate_score(score, deliverable, component_ids, handoff, self_verdict, errors):
    if not isinstance(score, dict):
        fail("SCORE_MISSING", "score object required", errors); return
    extra = sorted(set(score) - SCORE_ALLOWED); missing = sorted(SCORE_ALLOWED - set(score))
    if extra: fail("SCORE_FIELDS_UNEXPECTED", ", ".join(extra), errors)
    if missing: fail("SCORE_FIELDS_MISSING", ", ".join(missing), errors)
    valid_numeric = True
    for key in SCORE_KEYS:
        val = score.get(key)
        if isinstance(val, bool) or not isinstance(val, int) or not 0 <= val <= 5:
            valid_numeric = False; fail("SCORE_CRITERION_INVALID", f"{key} must be integer 0..5", errors)
    if valid_numeric:
        expected = sum(score[k] for k in SCORE_KEYS)
        if score.get("total") != expected: fail("SCORE_TOTAL_INVALID", f"total={score.get('total')} expected={expected}", errors)
    evidence = score.get("evidence_by_criterion"); known_refs = set(deliverable.keys()) | set(component_ids) | {"handoff_to_next", "self_verdict"}
    if not isinstance(evidence, dict):
        fail("SCORE_EVIDENCE_MISSING", "evidence_by_criterion object required", errors)
    else:
        if set(evidence) != set(SCORE_KEYS): fail("SCORE_EVIDENCE_KEYS_INVALID", f"expected exactly {SCORE_KEYS}", errors)
        for key in SCORE_KEYS:
            ev = evidence.get(key)
            if not isinstance(ev, dict): fail("SCORE_EVIDENCE_INVALID", f"{key} evidence must be object with refs + summary", errors); continue
            refs = ev.get("refs"); summary = ev.get("summary")
            if not isinstance(refs, list) or not refs or any(not isinstance(r, str) or not r.strip() for r in refs):
                fail("SCORE_EVIDENCE_REFS_INVALID", f"{key} requires non-empty refs[]", errors)
            else:
                unknown = sorted(set(refs) - known_refs)
                if unknown: fail("SCORE_EVIDENCE_REF_UNKNOWN", f"{key}: {', '.join(unknown)}", errors)
            if not isinstance(summary, str) or len(summary.strip()) < 12 or normalize_text(summary) in NOMINAL_EVIDENCE:
                fail("SCORE_EVIDENCE_SUMMARY_WEAK", f"{key} summary must be substantive", errors)
    total = score.get("total")
    if self_verdict in PASS_VERDICTS:
        if not isinstance(total, int) or total < 20: fail("PASS_THRESHOLD_NOT_MET", f"PASS verdict requires score total >=20, got {total}", errors)
        if score.get("layout_precision") == 0: fail("PASS_LAYOUT_ZERO", "PASS verdict cannot have layout_precision=0", errors)
        if score.get("handoff_quality") == 0: fail("PASS_HANDOFF_ZERO", "PASS verdict cannot have handoff_quality=0", errors)
    if score.get("layout_precision") == 5 and not (is_nonempty_dict(deliverable.get("layout_grid")) and is_nonempty_dict(deliverable.get("spacing_typography"))): fail("SCORE_5_LAYOUT_UNSUPPORTED", "layout_precision=5 requires layout_grid + spacing_typography", errors)
    if score.get("visual_hierarchy") == 5 and not isinstance(deliverable.get("visual_hierarchy"), list): fail("SCORE_5_HIERARCHY_UNSUPPORTED", "visual_hierarchy=5 requires explicit hierarchy list", errors)
    if score.get("lf_system_fidelity") == 5 and not (is_nonempty_dict(deliverable.get("token_map")) and isinstance(deliverable.get("risk_controls"), list) and deliverable.get("risk_controls")): fail("SCORE_5_LF_UNSUPPORTED", "lf_system_fidelity=5 requires token_map + risk_controls", errors)
    if score.get("state_mapping") == 5 and not is_nonempty_dict(deliverable.get("state_map")): fail("SCORE_5_STATE_UNSUPPORTED", "state_mapping=5 requires state_map", errors)
    if score.get("handoff_quality") == 5 and not is_nonempty_dict(handoff): fail("SCORE_5_HANDOFF_UNSUPPORTED", "handoff_quality=5 requires structured handoff_to_next", errors)

def validate_action(action, index, component_ids, errors):
    if not isinstance(action, dict): fail("REMEDIATION_ACTION_INVALID", f"action[{index}] is not object", errors); return
    missing = sorted(REMEDIATION_REQUIRED - set(action))
    if missing: fail("REMEDIATION_FIELDS_MISSING", f"action[{index}]: {', '.join(missing)}", errors); return
    iid=action.get("issue_id"); priority=action.get("priority"); category=action.get("category")
    if not isinstance(iid,str) or not iid.strip(): fail("REMEDIATION_ID_INVALID",f"action[{index}]",errors)
    if priority not in PRIORITIES: fail("REMEDIATION_PRIORITY_INVALID",priority,errors)
    if category not in CATEGORIES: fail("REMEDIATION_CATEGORY_INVALID",category,errors)
    anchor=action.get("evidence_anchor")
    if not isinstance(anchor,str) or len(anchor.strip())<12 or normalize_text(anchor) in {"screen","ui","layout","page"}: fail("EVIDENCE_ANCHOR_GENERIC",anchor,errors)
    evidence_ids=action.get("evidence_component_ids")
    if not isinstance(evidence_ids,list) or not evidence_ids: fail("EVIDENCE_COMPONENT_IDS_MISSING",f"action[{index}]",errors); evidence_ids=[]
    else:
        unknown=sorted(set(evidence_ids)-component_ids)
        if unknown: fail("EVIDENCE_COMPONENT_UNKNOWN",f"action[{index}]: {', '.join(unknown)}",errors)
    execution=action.get("execution")
    if not isinstance(execution,dict): fail("EXECUTION_BINDING_MISSING",f"action[{index}]",errors); return
    missing_exec=sorted(EXECUTION_REQUIRED-set(execution))
    if missing_exec: fail("EXECUTION_FIELDS_MISSING",f"action[{index}]: {', '.join(missing_exec)}",errors); return
    operation=execution.get("operation"); target=execution.get("target_component_id")
    if operation not in OPERATIONS: fail("EXECUTION_OPERATION_INVALID",operation,errors)
    if not isinstance(target,str) or target not in component_ids: fail("EXECUTION_TARGET_UNKNOWN",target,errors)
    if target not in evidence_ids: fail("EXECUTION_TARGET_NOT_EVIDENCED",f"{target} must appear in evidence_component_ids",errors)
    if category in CATEGORY_OPERATIONS and operation not in CATEGORY_OPERATIONS[category]: fail("CATEGORY_OPERATION_MISMATCH",f"{category} cannot use {operation}",errors)
    if not isinstance(execution.get("property"),str) or not execution.get("property").strip(): fail("EXECUTION_PROPERTY_INVALID",f"action[{index}]",errors)
    if execution.get("desired_value") in (None,"",[],{}): fail("EXECUTION_DESIRED_VALUE_INVALID",f"action[{index}]",errors)
    check=action.get("acceptance_check")
    if not isinstance(check,dict): fail("ACCEPTANCE_CHECK_MISSING",f"action[{index}]",errors); return
    missing_check=sorted(ACCEPTANCE_REQUIRED-set(check))
    if missing_check: fail("ACCEPTANCE_CHECK_FIELDS_MISSING",f"action[{index}]: {', '.join(missing_check)}",errors); return
    check_type=check.get("check_type"); check_target=check.get("target_component_id")
    if check_type not in CHECK_TYPES: fail("ACCEPTANCE_CHECK_TYPE_INVALID",check_type,errors)
    if operation in OPERATION_CHECKS and check_type not in OPERATION_CHECKS[operation]: fail("OPERATION_CHECK_MISMATCH",f"{operation} incompatible with {check_type}",errors)
    if not isinstance(check_target,str) or check_target not in component_ids: fail("ACCEPTANCE_TARGET_UNKNOWN",check_target,errors)
    if check.get("expected") in (None,"",[],{}): fail("ACCEPTANCE_EXPECTED_INVALID",f"action[{index}]",errors)
    decision=action.get("decision"); implementation=action.get("implementation_change"); acceptance=action.get("acceptance_criteria")
    if any(not isinstance(x,str) or len(x.strip())<16 for x in (decision,implementation,acceptance)): fail("ACTION_TEXT_TOO_WEAK",f"action[{index}] decision/implementation/acceptance must be substantive",errors); return
    combined=normalize_text(f"{decision} {implementation} {acceptance}")
    if combined in GENERIC_ACTION_PHRASES: fail("ACTION_TEXT_GENERIC",f"action[{index}]",errors)
    tt=target_tokens(target)
    if tt and not any(token in combined for token in tt): fail("ACTION_TEXT_NOT_TARGET_SPECIFIC",f"action[{index}] must name target-specific concept for {target}",errors)
    expected_terms=OPERATION_TERMS.get(operation,set())
    if expected_terms and not any(term in combined for term in expected_terms): fail("ACTION_TEXT_OPERATION_NOT_EXPLICIT",f"action[{index}] text does not express {operation}",errors)
    authority=action.get("semantic_authority")
    if category in {"COPY","RISK"} or operation in {"REPLACE_COPY","SET_STATE"}:
        if not isinstance(authority,dict): fail("SEMANTIC_AUTHORITY_MISSING",f"action[{index}] meaning-changing action requires semantic_authority",errors)
        else:
            refs=authority.get("source_refs"); scope=authority.get("claim_scope")
            if not isinstance(refs,list) or not refs or any(not isinstance(r,str) or not r.strip() for r in refs): fail("SEMANTIC_AUTHORITY_REFS_INVALID",f"action[{index}]",errors)
            if scope not in {"INPUT_SUPPORTED","CONSERVATIVE_REDUCTION","PRESENTATION_ONLY"}: fail("SEMANTIC_AUTHORITY_SCOPE_INVALID",f"action[{index}]",errors)

def validate(data):
    errors=[]
    if not isinstance(data,dict): fail("ROOT_NOT_OBJECT","root must be JSON object",errors); return errors
    if data.get("output_type")!="PRODUCTION_UI_SPEC": fail("OUTPUT_MODE_INVALID","Expected output_type=PRODUCTION_UI_SPEC",errors)
    d=data.get("deliverable_created")
    if not isinstance(d,dict): fail("DELIVERABLE_NOT_OBJECT","deliverable_created must be object",errors); return errors
    missing=sorted(PRODUCTION_REQUIRED-set(d))
    if missing: fail("PRODUCTION_FIELDS_MISSING",", ".join(missing),errors)
    screen_def=d.get("screen_definition")
    if not isinstance(screen_def,dict): fail("SCREEN_DEFINITION_INVALID","screen_definition must be object",errors); screen_def={}
    tree=d.get("component_tree"); component_ids=set()
    if not isinstance(tree,list) or not tree: fail("COMPONENT_TREE_MISSING","component_tree must be non-empty array",errors)
    else:
        for i,node in enumerate(tree):
            if not isinstance(node,dict): fail("COMPONENT_NODE_INVALID",f"component_tree[{i}] is not object",errors); continue
            miss=sorted(COMPONENT_REQUIRED-set(node))
            if miss: fail("COMPONENT_FIELDS_MISSING",f"component_tree[{i}]: {', '.join(miss)}",errors)
            cid=node.get("component_id")
            if not isinstance(cid,str) or not cid.strip(): fail("COMPONENT_ID_INVALID",f"component_tree[{i}]",errors)
            elif cid in component_ids: fail("COMPONENT_ID_DUPLICATE",cid,errors)
            else: component_ids.add(cid)
    for key in ("layout_grid","state_map","token_map","spacing_typography"):
        if key in d and not isinstance(d.get(key),dict): fail("PRODUCTION_FIELD_TYPE_INVALID",f"{key} must be object",errors)
    for key in ("visual_hierarchy","density_rules","risk_controls","prompt_constraints"):
        if key in d and not isinstance(d.get(key),list): fail("PRODUCTION_FIELD_TYPE_INVALID",f"{key} must be array",errors)
    handoff=data.get("handoff_to_next")
    if not isinstance(handoff,dict) or not handoff: fail("HANDOFF_MISSING","handoff_to_next non-empty object required",errors)
    verdict=data.get("self_verdict")
    if not isinstance(verdict,str) or verdict not in ALLOWED_VERDICTS: fail("SELF_VERDICT_INVALID",verdict,errors); verdict=None
    validate_score(data.get("score"),d,component_ids,handoff,verdict,errors)
    task_mode=screen_def.get("task_mode")
    if task_mode in {"EVALUATE_EXISTING","REMEDIATE_EXISTING"}:
        actions=d.get("remediation_actions")
        if not isinstance(actions,list) or not actions: fail("REMEDIATION_ACTIONS_MISSING","existing-screen task requires remediation_actions",errors)
        else:
            seen_ids=set(); categories=set()
            for i,action in enumerate(actions):
                validate_action(action,i,component_ids,errors)
                if isinstance(action,dict):
                    iid=action.get("issue_id")
                    if isinstance(iid,str):
                        if iid in seen_ids: fail("REMEDIATION_DUPLICATE_ID",iid,errors)
                        seen_ids.add(iid)
                    if action.get("category") in CATEGORIES: categories.add(action.get("category"))
            if len(actions)>1 and len(categories)<2: fail("REMEDIATION_CATEGORY_COLLAPSE","multiple issues require distinct categories when evidence differs",errors)
    return errors

def main():
    if len(sys.argv)!=2:
        print(json.dumps({"valid":False,"errors":[{"code":"USAGE","detail":"validate_ui_architect_output.py <json>"}]})); return 2
    try:
        raw=Path(sys.argv[1]).read_text(encoding="utf-8"); data=json.loads(raw)
    except Exception as exc:
        print(json.dumps({"valid":False,"errors":[{"code":"INPUT_PARSE_ERROR","detail":str(exc)}]},ensure_ascii=False,indent=2)); return 1
    try: errors=validate(data)
    except Exception as exc: errors=[{"code":"VALIDATOR_INTERNAL_GUARD","detail":f"{type(exc).__name__}: {exc}"}]
    result={"valid":not errors,"errors":errors}; print(json.dumps(result,ensure_ascii=False,indent=2)); return 0 if not errors else 1

if __name__=="__main__": raise SystemExit(main())
