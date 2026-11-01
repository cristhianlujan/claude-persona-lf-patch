#!/usr/bin/env python3
"""Read-only reporting projection for Profile Updater Group 2.

The source of measured check truth is operational_coverage_v1 (trusted root).
This module neither executes a profile nor decides EVOLUTION_DEMONSTRATED.
Destination anchors are verified against the selected profile's exact source;
a Markdown step is *not* promoted to a canonical executable step.
"""
from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Any

VALID_RESULTS = {"PASS", "FAIL", "NO_VERIFICADO"}
CHANGE_TYPES = {"CONSERVAR", "MODIFICAR", "AGREGAR", "SUSTITUIR", "RETIRAR"}
SHA256 = re.compile(r"^[0-9a-f]{64}$")
MD_HEADING = re.compile(r"^#{1,6}\s+(.+?)\s*$")
# Keep the ordered number, but do not assume all profiles bold the item title.
MD_ITEM = re.compile(r"^\\s*(\\d+)\\.\\s+(.+?)\\s*$")


def _section_matches(actual: str, declared: str) -> bool:
    """Exact title, or its unambiguous short form before a parenthetical suffix."""
    return actual == declared or actual.startswith(declared + " (")


def _item_matches(item_body: str, declared: str) -> bool:
    """Allow a full plain-text item or exact bold-title match; never keyword search."""
    body = item_body.strip()
    if body.startswith("**"):
        m = re.match(r"^\\*\\*(.+?)\\*\\*", body)
        return bool(m and m.group(1).strip() == declared)
    # Plain numbered steps may have no bold title. Require the complete line
    # (or the first sentence, delimited by '. '), never a loose substring.
    return body == declared or (body.startswith(declared) and
                                body[len(declared):].startswith(". "))



def resolve_destination(profile_dir: Path, binding: dict[str, Any] | None) -> dict[str, Any]:
    """Prove a textual destination exists, never assert a canonical runtime step."""
    unresolved = {"destination_status": "DESTINO_PENDIENTE",
                  "destination_profile_step_id": None,
                  "destination_profile_step_name": None}
    if not isinstance(binding, dict):
        return {**unresolved, "blocking_code": "DESTINATION_BINDING_MISSING"}
    if binding.get("change_type") not in CHANGE_TYPES:
        return {**unresolved, "blocking_code": "DESTINATION_CHANGE_TYPE_INVALID"}
    expected = binding.get("source_sha256")
    section = binding.get("section_title")
    number = binding.get("ordered_item")
    title = binding.get("item_title")
    if (not isinstance(expected, str) or not SHA256.fullmatch(expected)
            or not isinstance(section, str) or not section.strip()
            or not isinstance(number, int) or isinstance(number, bool) or number < 0
            or not isinstance(title, str) or not title.strip()):
        return {**unresolved, "blocking_code": "DESTINATION_SOURCE_BINDING_INVALID"}
    path = profile_dir / "SKILL.md"
    if path.is_symlink() or not path.is_file():
        return {**unresolved, "blocking_code": "DESTINATION_SOURCE_UNAVAILABLE"}
    source = path.read_bytes()
    actual = hashlib.sha256(source).hexdigest()
    if actual != expected:
        return {**unresolved, "blocking_code": "DESTINATION_SOURCE_SHA_MISMATCH"}
    try:
        lines = source.decode("utf-8").splitlines()
    except UnicodeDecodeError:
        return {**unresolved, "blocking_code": "DESTINATION_SOURCE_UNREADABLE"}
    matches: list[tuple[int, str]] = []
    in_section = False
    section_level = None
    heading_count = 0
    for index, line in enumerate(lines, start=1):
        m = MD_HEADING.match(line)
        if m:
            level = len(line) - len(line.lstrip("#"))
            if _section_matches(m.group(1).strip(), section):
                heading_count += 1
                in_section, section_level = True, level
            elif in_section and section_level is not None and level <= section_level:
                in_section = False
        item = MD_ITEM.match(line)
        if (in_section and item and int(item.group(1)) == number
                and _item_matches(item.group(2), title)):
            matches.append((index, title))
    if heading_count != 1 or len(matches) != 1:
        return {**unresolved, "blocking_code": "DESTINATION_ANCHOR_AMBIGUOUS_OR_NOT_FOUND"}
    line, text = matches[0]
    return {
        "destination_status": "SOURCE_ANCHORED_NOT_CANONICAL",
        "destination_profile_step_id": f"{section}::{number}",
        "destination_profile_step_name": text,
        "destination_source_path": "SKILL.md",
        "destination_source_sha256": actual,
        "destination_source_line": line,
        "change_type": binding["change_type"],
        "blocking_code": "CANONICAL_STEP_AUTHORITY_NOT_VERIFIED",
    }


def source_bound_bindings_from_cases(
    cases: dict[str, dict[str, Any]],
    slug: str,
    profile_dir: Path,
) -> tuple[dict[str, dict[str, Any]], list[str]]:
    """Consume optional destinations from trusted Group-2 case definitions.

    The existing canonical case reader is responsible for sourcing cases from
    trusted main. A candidate profile can never supply or rewrite these case
    bindings. Every destination is still re-verified against the exact target
    SKILL source and remains TEXTUAL, not an operational step ID.
    """
    result: dict[str, dict[str, Any]] = {}
    issues: list[str] = []
    path = profile_dir / "SKILL.md"
    if path.is_symlink() or not path.is_file():
        return result, ["DESTINATION_PROFILE_SOURCE_UNAVAILABLE"]
    actual_sha = hashlib.sha256(path.read_bytes()).hexdigest()
    for case_id, case in sorted(cases.items()):
        if case.get("profile_slug") != slug or case.get("case_id") != case_id:
            issues.append(f"DESTINATION_CASE_IDENTITY_MISMATCH:{case_id}")
            continue
        declared = case.get("destination_bindings")
        if declared is None:
            continue  # Old cases remain valid; unknown destinations stay pending.
        if not isinstance(declared, dict):
            issues.append(f"DESTINATION_BINDINGS_INVALID:{case_id}")
            continue
        check_ids = {c["id"] for c in case["checks"]}
        for check_id, value in sorted(declared.items()):
            key = f"{case_id}:{check_id}"
            if check_id not in check_ids or not isinstance(value, dict):
                issues.append(f"DESTINATION_CONTROL_NOT_DECLARED_OR_INVALID:{key}")
                continue
            if value.get("profile_slug") != slug:
                issues.append(f"DESTINATION_PROFILE_MISMATCH:{key}")
                continue
            if value.get("source_sha256") not in (None, actual_sha):
                issues.append(f"DESTINATION_SOURCE_SHA_MISMATCH:{key}")
                continue
            bound = {
                "source_sha256": actual_sha,
                "section_title": value.get("section_title"),
                "ordered_item": value.get("ordered_item"),
                "item_title": value.get("item_title"),
                "change_type": value.get("change_type"),
            }
            # A trusted case's declaration is not proof that a destination
            # actually exists. Re-verify exact source before admitting it.
            resolved = resolve_destination(profile_dir, bound)
            if resolved["destination_status"] != "SOURCE_ANCHORED_NOT_CANONICAL":
                issues.append(f"{resolved['blocking_code']}:{key}")
                continue
            result[key] = bound
    return result, issues


def build_control_matrix(
    cases: dict[str, dict[str, Any]],
    base_results: dict[str, dict[str, Any]],
    evolved_results: dict[str, dict[str, Any]],
    destination_bindings: dict[str, dict[str, Any]],
    profile_dir: Path,
) -> dict[str, Any]:
    """Project the existing typed Group-2 check outcomes; don't recalculate them.

    base/evolved results are exactly operational_coverage_v1.measure outputs.
    This report is advisory until its provenance and destinations are approved
    by the governed execution/independent judge.
    """
    rows = []
    for case_id, case in sorted(cases.items()):
        b = base_results.get(case_id, {})
        e = evolved_results.get(case_id, {})
        measured = b.get("measured") is True and e.get("measured") is True
        for check in case.get("checks", []):
            control_id = check["id"]
            key = f"{case_id}:{control_id}"
            baseline = b.get("checks", {}).get(control_id) if measured else None
            candidate = e.get("checks", {}).get(control_id) if measured else None
            original = "PASS" if baseline is True else "FAIL" if baseline is False else "NO_VERIFICADO"
            evolved = "PASS" if candidate is True else "FAIL" if candidate is False else "NO_VERIFICADO"
            destination = resolve_destination(profile_dir, destination_bindings.get(key))
            if "NO_VERIFICADO" in (original, evolved):
                decision = "NO_VERIFICADO"
            elif original == "PASS" and evolved == "FAIL":
                decision = "REGRESION"
            elif original == "FAIL" and evolved == "PASS":
                decision = "MEJORA"
            elif original == "PASS":
                decision = "CONSERVADO"
            else:
                decision = "SIN_MEJORA"
            rows.append({
                "case_id": case_id, "control_id": control_id,
                "original_result": original, "evolved_result": evolved,
                "comparison": decision,
                "original_run_ids": b.get("run_ids", []) if measured else [],
                "evolved_run_ids": e.get("run_ids", []) if measured else [],
                "original_attestation": b.get("attestation", []) if measured else [],
                "evolved_attestation": e.get("attestation", []) if measured else [],
                **destination,
            })
    summary = {
        "total": len(rows),
        "mejorados": sum(x["comparison"] == "MEJORA" for x in rows),
        "preservados": sum(x["comparison"] == "CONSERVADO" for x in rows),
        "regresados": sum(x["comparison"] == "REGRESION" for x in rows),
        "no_verificados": sum(x["comparison"] == "NO_VERIFICADO" for x in rows),
        "destinos_pendientes": sum(x["destination_status"] == "DESTINO_PENDIENTE" for x in rows),
        "destinos_solo_textuales": sum(x["destination_status"] == "SOURCE_ANCHORED_NOT_CANONICAL" for x in rows),
    }
    return {"schema": "LF_PROFILE_CONTROL_MATRIX_V1",
            "status": "READ_ONLY_REPORT_NOT_AUTHORITY", "summary": summary, "rows": rows}
