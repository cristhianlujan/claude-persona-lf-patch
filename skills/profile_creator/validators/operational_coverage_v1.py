#!/usr/bin/env python3
"""Operational (business-case) coverage for the Profile evolution proof.

Group 2 of the profile evaluation: besides the structural S26 dimensions, a profile is judged by how
many verifiable checks of real business cases its recorded runs satisfy. Cases and runs are trusted
data that live on the trusted root (main), never in the candidate tree. A run only counts for a profile
tree when its recorded `profile_tree_sha256` equals the hash of that exact tree, and its embedded output
matches its recorded `output_sha256`. Checks are structural predicates over the typed output, never
keyword searches over free text. Free-text points a predicate cannot judge are listed as
`semantic_pending`: they are never counted, so coverage cannot be read as a claim about them.

Rule (stated by the owner): an update is accepted when coverage rises at all and no check regresses.
When several bound runs exist for a case, a check passes only if it passes in all of them.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

CASE_SCHEMA = "PROFILE_OPERATIONAL_CASE_V1"
RUN_SCHEMA = "PROFILE_OPERATIONAL_RUN_V1"
OPERATIONAL_REL = Path("skills/profile_creator/operational_cases")
OPS = ("eq", "in", "nonempty", "min_len", "no_node", "if_then")
ATTESTATIONS = ("NONE", "RUNTIME_ATTESTED")


def tree_sha256(directory: Path) -> str:
    """Hash of a profile tree: relative path and bytes of every file, in sorted order."""
    h = hashlib.sha256()
    for p in sorted(directory.rglob("*")):
        if p.is_file():
            h.update(str(p.relative_to(directory)).encode() + b"\0" + p.read_bytes() + b"\0")
    return h.hexdigest()


def canonical_sha256(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


_MISSING = object()


def _get(doc: Any, pointer: str) -> Any:
    node = doc
    for raw in [p for p in pointer.split("/") if p != ""]:
        part = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(node, dict) and part in node:
            node = node[part]
        elif isinstance(node, list) and part.isdigit() and int(part) < len(node):
            node = node[int(part)]
        else:
            return _MISSING
    return node


def _has_node(value: Any, key: str, forbidden: list[Any]) -> bool:
    if isinstance(value, dict):
        if key in value and value[key] in forbidden:
            return True
        return any(_has_node(v, key, forbidden) for v in value.values())
    if isinstance(value, list):
        return any(_has_node(v, key, forbidden) for v in value)
    return False


def evaluate_check(doc: Any, check: dict[str, Any]) -> bool:
    op = check["op"]
    if op == "if_then":
        return (not evaluate_check(doc, check["if"])) or evaluate_check(doc, check["then"])
    value = _get(doc, check["pointer"])
    if op == "no_node":
        return value is not _MISSING and not _has_node(value, check["key"], check["values"])
    if value is _MISSING:
        return False
    if op == "eq":
        return value == check["value"]
    if op == "in":
        return value in check["value"]
    if op == "nonempty":
        return value not in (None, "", [], {})
    if op == "min_len":
        return isinstance(value, (list, str)) and len(value) >= check["value"]
    raise ValueError(f"UNKNOWN_OP:{op}")


def _valid_check(check: Any) -> bool:
    if not isinstance(check, dict) or check.get("op") not in OPS:
        return False
    if check["op"] == "if_then":
        return _valid_check(check.get("if")) and _valid_check(check.get("then"))
    if not isinstance(check.get("pointer"), str):
        return False
    if check["op"] == "no_node":
        return isinstance(check.get("key"), str) and isinstance(check.get("values"), list)
    if check["op"] in ("eq", "in", "min_len"):
        return "value" in check
    return True


def load_cases(operational_root: Path, slug: str) -> tuple[dict[str, dict], list[str]]:
    cases: dict[str, dict] = {}
    problems: list[str] = []
    for path in sorted((operational_root / slug).glob("*.case.json")):
        try:
            case = json.loads(path.read_text(encoding="utf-8"))
        except ValueError:
            problems.append(f"CASE_UNREADABLE:{path.name}")
            continue
        checks = case.get("checks") if isinstance(case, dict) else None
        ids = [c.get("id") for c in checks] if isinstance(checks, list) else []
        if (case.get("schema_version") != CASE_SCHEMA or case.get("profile_slug") != slug
                or not isinstance(case.get("case_id"), str) or not checks
                or len(set(ids)) != len(ids) or not all(isinstance(i, str) for i in ids)
                or not all(_valid_check(c) for c in checks)):
            problems.append(f"CASE_INVALID:{path.name}")
            continue
        cases[case["case_id"]] = case
    return cases, problems


def load_runs(operational_root: Path, slug: str, cases: dict[str, dict]) -> tuple[list[dict], list[str]]:
    runs: list[dict] = []
    rejected: list[str] = []
    for path in sorted((operational_root / slug / "runs").glob("*.json")):
        try:
            run = json.loads(path.read_text(encoding="utf-8"))
        except ValueError:
            rejected.append(f"RUN_UNREADABLE:{path.name}")
            continue
        ok = (isinstance(run, dict) and run.get("schema_version") == RUN_SCHEMA and run.get("profile_slug") == slug
              and run.get("case_id") in cases and isinstance(run.get("profile_tree_sha256"), str)
              and run.get("attestation") in ATTESTATIONS and isinstance(run.get("validator"), dict)
              and isinstance(run.get("output"), dict) and run.get("output_sha256") == canonical_sha256(run.get("output")))
        if ok:
            runs.append(run)
        else:
            rejected.append(f"RUN_REJECTED:{path.name}")
    return runs, rejected


def measure(cases: dict[str, dict], runs: list[dict], tree_sha: str) -> dict[str, Any]:
    """Per-case check results for the runs bound to this exact tree (a check passes only if all runs pass)."""
    out: dict[str, Any] = {}
    for case_id, case in cases.items():
        bound = [r for r in runs if r["case_id"] == case_id and r["profile_tree_sha256"] == tree_sha]
        if not bound:
            out[case_id] = {"measured": False, "run_ids": [], "checks": {}}
            continue
        checks = {}
        for check in case["checks"]:
            checks[check["id"]] = all(evaluate_check({"output": r["output"], "validator": r["validator"]}, check) for r in bound)
        out[case_id] = {"measured": True, "run_ids": sorted(r.get("run_id", "?") for r in bound),
                        "attestation": sorted({r["attestation"] for r in bound}), "checks": checks}
    return out


def compare(base: dict[str, Any], cand: dict[str, Any]) -> dict[str, Any]:
    improved: list[str] = []
    regressed: list[str] = []
    unmeasured: list[str] = []
    base_pass = cand_pass = total = 0
    for case_id in sorted(base):
        if not (base[case_id]["measured"] and cand[case_id]["measured"]):
            unmeasured.append(case_id)
            continue
        for check_id, b in base[case_id]["checks"].items():
            c = cand[case_id]["checks"][check_id]
            total += 1
            base_pass += bool(b)
            cand_pass += bool(c)
            if c and not b:
                improved.append(f"{case_id}:{check_id}")
            if b and not c:
                regressed.append(f"{case_id}:{check_id}")
    return {"cases_unmeasured": unmeasured, "checks_total": total, "base_passed": base_pass,
            "candidate_passed": cand_pass, "improved_checks": improved, "regressed_checks": regressed}


def evaluate(operational_root: Path, slug: str, base_dir: Path, candidate_dir: Path) -> dict[str, Any]:
    cases, problems = load_cases(operational_root, slug)
    if not cases:
        return {"status": "NOT_APPLICABLE", "problems": problems, "improved_checks": [], "regressed_checks": []}
    runs, rejected = load_runs(operational_root, slug, cases)
    base_sha, cand_sha = tree_sha256(base_dir), tree_sha256(candidate_dir)
    result = compare(measure(cases, runs, base_sha), measure(cases, runs, cand_sha))
    result.update({"status": "MEASURED" if result["checks_total"] else "UNMEASURED", "problems": problems + rejected,
                   "base_tree_sha256": base_sha, "candidate_tree_sha256": cand_sha,
                   "semantic_pending": sorted({p for c in cases.values() for p in c.get("semantic_pending", [])})})
    return result


def unmet(operational_root: Path, slug: str, profile_dir: Path) -> dict[str, Any]:
    """Checks still unmet by the runs bound to this exact tree (drives the UPDATE_REQUIRED decision)."""
    cases, problems = load_cases(operational_root, slug)
    if not cases:
        return {"status": "NOT_APPLICABLE", "unmet_checks": [], "problems": problems}
    runs, rejected = load_runs(operational_root, slug, cases)
    measured = measure(cases, runs, tree_sha256(profile_dir))
    unmet_checks = sorted(f"{cid}:{chk}" for cid, m in measured.items() if m["measured"] for chk, ok in m["checks"].items() if not ok)
    any_measured = any(m["measured"] for m in measured.values())
    return {"status": "MEASURED" if any_measured else "UNMEASURED", "unmet_checks": unmet_checks, "problems": problems + rejected,
            "profile_tree_sha256": tree_sha256(profile_dir)}


def _problem_observed_field(run: dict[str, Any], pointer: str) -> dict[str, Any]:
    """Short read-only preview; the full JSON RAW remains the source of truth."""
    value = _get({"output": run.get("output", {})}, pointer)
    if value is _MISSING:
        return {"pointer": pointer, "present": False, "preview": None}
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, default=str)
    return {"pointer": pointer, "present": True,
            "value_sha256": canonical_sha256(value),
            "preview": raw[:240], "truncated": len(raw) > 240}


def problem_comparison_report(
    cases: dict[str, dict],
    runs: list[dict],
    base_tree_sha256: str,
    candidate_tree_sha256: str,
) -> dict[str, Any]:
    """Side-by-side evidence for independent per-problem review, NEVER a new proof gate.

    comparison_dimensions are optional and read ONLY from trusted operational cases.
    This helper does not decide functional improvement and is not a model executor.
    """
    rows: list[dict[str, Any]] = []
    issues: list[str] = []
    for case_id, case in sorted(cases.items()):
        dimensions = case.get("comparison_dimensions", [])
        if not isinstance(dimensions, list):
            issues.append(f"COMPARISON_DIMENSIONS_INVALID:{case_id}")
            continue
        original = [r for r in runs if r.get("case_id") == case_id
                    and r.get("profile_tree_sha256") == base_tree_sha256]
        evolved = [r for r in runs if r.get("case_id") == case_id
                   and r.get("profile_tree_sha256") == candidate_tree_sha256]
        same_input = (bool(original) and bool(evolved)
                      and all(isinstance(r.get("input_literal"), str) and r["input_literal"]
                              for r in original + evolved)
                      and len({r["input_literal"] for r in original + evolved}) == 1)
        attested = (bool(original) and bool(evolved)
                    and all(r.get("attestation") == "RUNTIME_ATTESTED"
                            for r in original + evolved))
        index = {c["id"]: c for c in case["checks"]}
        for dim in dimensions:
            if not isinstance(dim, dict):
                issues.append(f"COMPARISON_DIMENSION_INVALID:{case_id}")
                continue
            dim_id, fields, control_ids = (dim.get("problem_id"),
                                           dim.get("output_pointers"),
                                           dim.get("control_ids"))
            if (not isinstance(dim_id, str) or not dim_id
                    or not isinstance(dim.get("question"), str) or not dim["question"]
                    or not isinstance(fields, list) or not fields
                    or not all(isinstance(f, str) and f.startswith("/output/") for f in fields)
                    or not isinstance(control_ids, list)
                    or not all(isinstance(c, str) and c in index for c in control_ids)):
                issues.append(f"COMPARISON_DIMENSION_BINDING_INVALID:{case_id}:{dim_id}")
                continue
            observations = []
            for arm, selected in (("original", original), ("evolved", evolved)):
                snapshots = [{
                    "run_id": r.get("run_id"),
                    "tree_sha256": r.get("profile_tree_sha256"),
                    "output_sha256": r.get("output_sha256"),
                    "attestation": r.get("attestation"),
                    "validator_valid": r.get("validator", {}).get("valid"),
                    "fields": [_problem_observed_field(r, p) for p in fields],
                } for r in selected]
                observations.append({"arm": arm, "runs": snapshots})
            control_rows = []
            for check_id in control_ids:
                c = index[check_id]
                def _state(arm_runs: list[dict]) -> str:
                    if not arm_runs:
                        return "NO_VERIFICADO"
                    return ("PASS" if all(evaluate_check(
                        {"output": r["output"], "validator": r["validator"]}, c
                    ) for r in arm_runs) else "FAIL")
                # A conditional may pass vacuously if its antecedent was not exercised.
                def _vacuous(arm_runs: list[dict]) -> bool:
                    return (c["op"] == "if_then" and bool(arm_runs)
                            and all(not evaluate_check(
                                {"output": r["output"], "validator": r["validator"]},
                                c["if"]
                            ) for r in arm_runs))
                control_rows.append({
                    "control_id": check_id,
                    "original": _state(original), "evolved": _state(evolved),
                    "original_vacuous_conditional": _vacuous(original),
                    "evolved_vacuous_conditional": _vacuous(evolved),
                })
            if not original or not evolved:
                evidence_status = "UNMEASURED"
            elif not same_input:
                evidence_status = "PREVIEW_INPUT_IDENTITY_UNVERIFIED"
            elif not attested:
                evidence_status = "PREVIEW_UNATTESTED"
            else:
                evidence_status = "READY_FOR_INDEPENDENT_SEMANTIC_REVIEW"
            rows.append({
                "case_id": case_id, "problem_id": dim_id,
                "question": dim["question"],
                "evidence_status": evidence_status,
                "same_input_literal_verified": bool(same_input),
                "both_run_attestations_declared": bool(attested),
                "semantic_verdict": "NO_VERIFICADO_PENDING_INDEPENDENT_JUDGE",
                "observations": observations, "controls": control_rows,
            })
    return {
        "schema": "LF_PROFILE_PROBLEM_SIDE_BY_SIDE_REPORT_V1",
        "status": "READ_ONLY_REPORT_NOT_AUTHORITY",
        "base_tree_sha256": base_tree_sha256,
        "candidate_tree_sha256": candidate_tree_sha256,
        "rows": rows,
        "issues": issues,
    }
