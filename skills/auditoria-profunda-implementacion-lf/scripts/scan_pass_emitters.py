#!/usr/bin/env python3
"""Inventory literal success emissions and risk candidates without executing targets.

Every returned site needs contextual review and a broken-input negative. Dynamic
values, generated SQL and indirect dispatch remain explicitly outside completeness.
"""
import argparse
import ast
import hashlib
import json
import re
from pathlib import Path

SUCCESS = re.compile(r"^(?:PASS(?:_[A-Z0-9_]+)?|STEP_PASS(?:_[A-Z0-9_]+)?|APPLIED)$")
FLAGS = {"ig_findings_reported", "applied", "success"}
KEYS = {"status", "eval_status", "validator_status", "step_status", "verdict", "step_result", "outcome", "result"} | FLAGS


def scan(path):
    path = Path(path)
    text = path.read_text(encoding="utf8")
    lines = text.splitlines()
    sha = hashlib.sha256(text.encode("utf8")).hexdigest()
    found = []
    def add(line, marker, risks, classification="EMITTER_CANDIDATE"):
        signature = f"{path.as_posix()}:{line}:{marker}"
        found.append({"id": "PASS-" + hashlib.sha256(signature.encode()).hexdigest()[:12],
            "file": path.as_posix(), "line": line, "literal": lines[line - 1],
            "source_sha256": sha, "marker": marker, "risk_candidates": sorted(set(risks)),
            "classification": classification, "evidence_required": [],
            "context_review": "NOT_EVALUATED",
            "negative_test": {"status": "NOT_EXECUTED", "command": None, "evidence_refs": [],
                              "expected_rejection": "Resolve the applicable input/contract before testing"}})
    if path.suffix == ".py":
        tree = ast.parse(text)
        parents = {}
        for parent in ast.walk(tree):
            for child in ast.iter_child_nodes(parent): parents[child] = parent
        for node in ast.walk(tree):
            if not isinstance(node, ast.Dict): continue
            for key, value in zip(node.keys, node.values):
                if not isinstance(key, ast.Constant) or key.value not in KEYS: continue
                marker = None
                if isinstance(value, ast.Constant):
                    if isinstance(value.value, str) and SUCCESS.fullmatch(value.value): marker = value.value
                    elif key.value in FLAGS and value.value is True: marker = key.value + "=true"
                elif isinstance(value, ast.IfExp):
                    choices = [c.value for c in (value.body, value.orelse) if isinstance(c, ast.Constant)]
                    marker = next((v for v in choices if isinstance(v, str) and SUCCESS.fullmatch(v)), None)
                if marker is None and isinstance(value, (ast.Name, ast.Call)):
                    marker = "DYNAMIC:" + key.value
                if marker is None: continue
                risks = []
                current = node
                while current in parents:
                    current = parents[current]
                    if isinstance(current, ast.ExceptHandler): risks.append("EXCEPT_EMITS_SUCCESS")
                add(value.lineno, marker, risks)
        # Subscript assignments can feed a later return; do not assume all do.
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign):
                if isinstance(node.value, ast.Constant) and isinstance(node.value.value, str) and SUCCESS.fullmatch(node.value.value):
                    add(node.lineno, node.value.value, ["SUCCESS_ASSIGNMENT_REQUIRES_DATAFLOW_REVIEW"])
                elif isinstance(node.value, ast.IfExp):
                    for value in (node.value.body, node.value.orelse):
                        if isinstance(value, ast.Constant) and isinstance(value.value, str) and SUCCESS.fullmatch(value.value):
                            add(value.lineno, value.value, ["CONDITIONAL_SUCCESS_REQUIRES_DATAFLOW_REVIEW"])
    else:
        pattern = re.compile(r"(?:['\"](?P<quoted>status|eval_status|validator_status|step_status|verdict|step_result|outcome|result|ig_findings_reported|applied|success)['\"]|\b(?P<bare>status|eval_status|validator_status|step_status|verdict|step_result|outcome|result|ig_findings_reported|applied|success))\s*[:,=]\s*(?:['\"](?P<status>PASS(?:_[A-Z0-9_]+)?|STEP_PASS(?:_[A-Z0-9_]+)?|APPLIED)['\"]|(?P<truth>true)\b)")
        for m in pattern.finditer(text):
            key = m.group("quoted") or m.group("bare")
            if m.group("truth") and key not in FLAGS: continue
            line = text.count("\n", 0, m.start()) + 1
            window = text[max(0, m.start() - 250):m.end()]
            risks = ["DEFAULT_TRUE_REQUIRES_CONTEXT"] if re.search(r"coalesce\([^;]*?,\s*true\s*\)", window, re.I) else []
            add(line, m.group("status") or key + "=true", risks)
        # Computed flags (e.g. array_length(findings)>0) still require inspection.
        flag = re.compile(r"(?:['\"](?P<quoted>ig_findings_reported|applied|success)['\"]|\b(?P<bare>ig_findings_reported|applied|success))\s*[:,]\s*(?!true\b)(?P<expr>[^\n]+)")
        for m in flag.finditer(text):
            line = text.count("\n", 0, m.start()) + 1
            add(line, "DYNAMIC:" + (m.group("quoted") or m.group("bare")), ["COMPUTED_FLAG_REQUIRES_CONTEXT"])
    # Record dangerous defaults separately; they are not automatically PASS emitters.
    for i, line in enumerate(lines, 1):
        if re.search(r"coalesce\([^\n]*,\s*true\s*\)|\.get\([^\n]*,\s*True\s*\)|\?\?\s*true\b", line):
            add(i, "DEFAULT_TRUE", ["DEFAULT_TRUE_REQUIRES_CONTEXT"], "RISK_PATTERN_ONLY")
    unique = {(f["line"], f["marker"]): f for f in found}
    return {"file": path.as_posix(), "source_sha256": sha,
            "sites": sorted(unique.values(), key=lambda r: (r["line"], r["marker"])),
            "dynamic_emissions_complete": False,
            "limits": ["Literal Python AST and SQL/TS token candidates only", "No runtime or generated SQL execution",
                       "Comparisons, metadata and returns need native context classification"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()
    print(json.dumps([scan(p) for p in args.paths], ensure_ascii=False, indent=2))
