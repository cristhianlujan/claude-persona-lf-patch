"""SC-M3.1 authority-bound checks for Story Implementation Package.

This module is a domain validator extension, not a source resolver, currentness
engine, qualification writer, or runtime controller. Authority snapshots must be
produced/read back through the existing LF capabilities.
"""
from __future__ import annotations

import copy
from typing import Any

SNAPSHOT_SCHEMA = "STORY_SOURCE_AUTHORITY_SNAPSHOT_V1"
CURRENT_CAPABILITY_STATES = {"ACTIVE", "READ_ONLY"}


def _parts(pointer: str) -> list[str]:
    if not pointer.startswith("/"):
        raise ValueError(f"invalid JSON pointer: {pointer}")
    return [p.replace("~1", "/").replace("~0", "~") for p in pointer.split("/")[1:]]


def get_pointer(doc: dict[str, Any], pointer: str) -> tuple[bool, Any]:
    cur: Any = doc
    try:
        for part in _parts(pointer):
            if isinstance(cur, dict):
                cur = cur[part]
            elif isinstance(cur, list):
                cur = cur[int(part)]
            else:
                return False, None
        return True, cur
    except (KeyError, IndexError, ValueError, TypeError):
        return False, None


def set_pointer(doc: dict[str, Any], pointer: str, value: Any) -> None:
    parts = _parts(pointer)
    cur: Any = doc
    for part in parts[:-1]:
        if isinstance(cur, dict):
            cur = cur.setdefault(part, {})
        elif isinstance(cur, list):
            cur = cur[int(part)]
        else:
            raise ValueError(pointer)
    cur[parts[-1]] = value


def validate_authority(pkg: dict[str, Any], snapshot: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if snapshot.get("schema_version") != SNAPSHOT_SCHEMA:
        return ["AUTHORITY_SNAPSHOT_SCHEMA_INVALID"]

    for key in ("source_resolution_policy", "currentness_authority", "qualification_framework"):
        cap = snapshot.get(key)
        if not isinstance(cap, dict) or cap.get("state") not in CURRENT_CAPABILITY_STATES:
            code = cap.get("capability_code", key) if isinstance(cap, dict) else key
            errors.append(f"CAPABILITY_NOT_CURRENT:{code}")

    assertions = snapshot.get("authority_assertions")
    required = snapshot.get("required_package_pointers")
    if not isinstance(assertions, list) or not isinstance(required, list):
        return errors + ["AUTHORITY_SNAPSHOT_ASSERTIONS_INVALID"]

    by_pointer: dict[str, dict[str, Any]] = {}
    for item in assertions:
        if not isinstance(item, dict) or not isinstance(item.get("package_pointer"), str):
            errors.append("AUTHORITY_ASSERTION_INVALID")
            continue
        pointer = item["package_pointer"]
        if pointer in by_pointer:
            errors.append(f"DUPLICATE_AUTHORITY_ASSERTION:{pointer}")
        by_pointer[pointer] = item

    for pointer in required:
        if pointer not in by_pointer:
            errors.append(f"REQUIRED_AUTHORITY_ASSERTION_MISSING:{pointer}")

    for pointer, assertion in by_pointer.items():
        if assertion.get("source_currentness_state") != "PROVEN_CURRENT":
            errors.append(f"SOURCE_CURRENTNESS_UNPROVEN:{pointer}")
        if assertion.get("source_decision_state") != "VIGENTE":
            errors.append(f"SOURCE_DECISION_NOT_CURRENT:{pointer}")
        if not assertion.get("authority_ref"):
            errors.append(f"AUTHORITY_REF_MISSING:{pointer}")
        exists, actual = get_pointer(pkg, pointer)
        if not exists:
            errors.append(f"PACKAGE_POINTER_MISSING:{pointer}")
        elif actual != assertion.get("authority_value"):
            errors.append(f"INVENTED_OR_STALE_VALUE:{pointer}")

    current_capabilities: dict[str, list[dict[str, Any]]] = {}
    for cap in snapshot.get("existing_capabilities", []):
        if not isinstance(cap, dict):
            continue
        if cap.get("state") in CURRENT_CAPABILITY_STATES and cap.get("need_code"):
            current_capabilities.setdefault(str(cap["need_code"]), []).append(cap)

    for decision in pkg.get("architecture_and_reuse_decisions", []):
        if not isinstance(decision, dict):
            continue
        need = str(decision.get("need_code") or "")
        if decision.get("classification") == "CREATE_NEW" and current_capabilities.get(need):
            codes = ",".join(sorted(str(c.get("capability_code")) for c in current_capabilities[need]))
            errors.append(f"DUPLICATE_CAPABILITY_EXISTS:{need}:{codes}")

    return errors


def materialize_authority_positive(base_pkg: dict[str, Any], snapshot: dict[str, Any]) -> dict[str, Any]:
    pkg = copy.deepcopy(base_pkg)
    for assertion in snapshot["authority_assertions"]:
        set_pointer(pkg, assertion["package_pointer"], assertion["authority_value"])
    return pkg


def authority_self_test(base_pkg: dict[str, Any], snapshot: dict[str, Any]) -> dict[str, Any]:
    positive = materialize_authority_positive(base_pkg, snapshot)
    cases: list[tuple[str, dict[str, Any], dict[str, Any], str | None]] = [
        ("authority_positive", positive, snapshot, None)
    ]

    def neg(name: str, pkg_mut=None, snap_mut=None, expected: str = "") -> None:
        p = copy.deepcopy(positive)
        s = copy.deepcopy(snapshot)
        if pkg_mut:
            pkg_mut(p)
        if snap_mut:
            snap_mut(s)
        cases.append((name, p, s, expected))

    neg(
        "invented_route_pattern",
        pkg_mut=lambda p: set_pointer(p, "/story_contracts/state_navigation_contract/route_pattern", "/invented/route"),
        expected="INVENTED_OR_STALE_VALUE:/story_contracts/state_navigation_contract/route_pattern",
    )
    neg(
        "invented_route_code",
        pkg_mut=lambda p: set_pointer(p, "/story_contracts/state_navigation_contract/route_code", "ROUTE_NOT_REGISTERED"),
        expected="INVENTED_OR_STALE_VALUE:/story_contracts/state_navigation_contract/route_code",
    )
    neg(
        "invented_design_token",
        pkg_mut=lambda p: set_pointer(p, "/story_contracts/design_system_contract/layout_component_token_code", "invented_card_v99"),
        expected="INVENTED_OR_STALE_VALUE:/story_contracts/design_system_contract/layout_component_token_code",
    )
    neg(
        "invented_source_version",
        pkg_mut=lambda p: set_pointer(p, "/story_identity/source_version", "v99"),
        expected="INVENTED_OR_STALE_VALUE:/story_identity/source_version",
    )
    neg(
        "source_currentness_unproven",
        snap_mut=lambda s: s["authority_assertions"][3].__setitem__("source_currentness_state", "UNPROVEN"),
        expected="SOURCE_CURRENTNESS_UNPROVEN:/story_contracts/state_navigation_contract/route_pattern",
    )
    neg(
        "source_decision_stale",
        snap_mut=lambda s: s["authority_assertions"][4].__setitem__("source_decision_state", "SUPERADA"),
        expected="SOURCE_DECISION_NOT_CURRENT:/story_contracts/design_system_contract/layout_component_token_code",
    )
    neg(
        "required_assertion_missing",
        snap_mut=lambda s: s["authority_assertions"].pop(2),
        expected="REQUIRED_AUTHORITY_ASSERTION_MISSING:/story_contracts/state_navigation_contract/route_code",
    )
    neg(
        "package_pointer_missing",
        pkg_mut=lambda p: p["story_contracts"]["design_system_contract"].pop("theme_binding_code"),
        expected="PACKAGE_POINTER_MISSING:/story_contracts/design_system_contract/theme_binding_code",
    )
    neg(
        "duplicate_source_resolution_capability",
        pkg_mut=lambda p: p["architecture_and_reuse_decisions"].append({
            "need_code": "SOURCE_RESOLUTION", "classification": "CREATE_NEW",
            "selected_asset_ref": None, "owner_state": "RESOLVED", "currentness_state": "PROVEN_CURRENT",
            "consumer_refs": ["STORY_CREATOR", "PROGRAMMING_AGENT"], "evidence_refs": ["inventory://checked"],
            "rationale": "negative duplicate case"
        }),
        expected="DUPLICATE_CAPABILITY_EXISTS:SOURCE_RESOLUTION:SOURCE_RESOLUTION_POLICY",
    )
    neg(
        "qualification_capability_not_current",
        snap_mut=lambda s: s["qualification_framework"].__setitem__("state", "STALE"),
        expected="CAPABILITY_NOT_CURRENT:QUALIFICATION_FRAMEWORK",
    )

    results = []
    for name, pkg, snap, expected in cases:
        errors = validate_authority(pkg, snap)
        ok = (not errors) if expected is None else expected in errors
        results.append({"case": name, "expected": expected or "PASS", "ok": ok, "errors": errors})
    passed = sum(1 for result in results if result["ok"])
    return {
        "schema": "SC_M3_1_ANTI_INVENTION_SELF_TEST_V1",
        "cases_total": len(results),
        "cases_passed": passed,
        "result": "PASS" if passed == len(results) else "FAIL",
        "results": results,
    }
