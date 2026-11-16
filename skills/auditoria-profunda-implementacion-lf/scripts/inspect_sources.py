#!/usr/bin/env python3
"""Read-only, bounded Python AST evidence extraction. Candidates are not verdicts.

Never imports the target or executes repository code. Dynamic calls, star args,
ambiguous imports and nested functions need semantic inspection.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
from pathlib import Path


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def load_source(path):
    path = Path(path)
    source = path.read_text(encoding="utf8")
    return source, ast.parse(source, filename=str(path))


def functions(tree):
    return {n.name: n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}


def direct_reads(node, parameter):
    """Direct required subscript reads; get() is optional/unknown, never required."""
    aliases = {parameter}
    # Deliberately do not guess value-flow across reassignments or scopes.
    for stmt in node.body:
        if isinstance(stmt, ast.Assign) and isinstance(stmt.value, ast.Name) and stmt.value.id in aliases:
            for target in stmt.targets:
                if isinstance(target, ast.Name):
                    aliases.add(target.id)
    reads = []
    for one in ast.walk(node):
        if (isinstance(one, ast.Subscript) and isinstance(one.value, ast.Name)
                and one.value.id in aliases and isinstance(one.slice, ast.Constant)
                and isinstance(one.slice.value, str) and isinstance(one.ctx, ast.Load)):
            reads.append({"field": one.slice.value, "line": one.lineno,
                          "expression": ast.unparse(one)})
    return sorted(reads, key=lambda x: (x["line"], x["field"]))


def contract_candidates(schema, consumer_path, consumer_function, parameter):
    source, tree = load_source(consumer_path)
    fn = functions(tree)[consumer_function]
    props = schema.get("properties", {})
    required = set(schema.get("required", []))
    out = []
    for read in direct_reads(fn, parameter):
        field = read["field"]
        if field not in props or field not in required:
            out.append({"code": "SPEC_REQUIRED_FIELD_OMITTED", "status": "HYPOTHESIS",
                        "field": field, "consumer": consumer_function, **read,
                        "cause": "UNDECLARED_PROPERTY" if field not in props else "NOT_REQUIRED",
                        "source_sha256": sha256(source.encode("utf8"))})
    return out


def call_candidates(paths):
    """Resolve module-level local/from-import calls, without executing them."""
    modules = {}
    for path in paths:
        source, tree = load_source(path)
        modules[str(Path(path))] = (source, tree, functions(tree))
    by_stem = {}
    for path in modules:
        by_stem.setdefault(Path(path).stem, []).append(path)
    results = []
    for path, (source, tree, local) in modules.items():
        imports = {}
        for n in tree.body:
            if isinstance(n, ast.ImportFrom) and n.module:
                targets = by_stem.get(n.module.split(".")[-1], [])
                if len(targets) == 1:
                    for alias in n.names:
                        imports[alias.asname or alias.name] = (targets[0], alias.name)
        for owner, fn in local.items():
            assignments = {a.targets[0].id: ast.unparse(a.value) for a in fn.body
                           if isinstance(a, ast.Assign) and len(a.targets) == 1
                           and isinstance(a.targets[0], ast.Name)}
            for call in ast.walk(fn):
                if not isinstance(call, ast.Call) or not isinstance(call.func, ast.Name):
                    continue
                name = call.func.id
                resolved_path, resolved_name = imports.get(name, (path, name))
                target = modules[resolved_path][2].get(resolved_name)
                if target is None:
                    continue
                if any(isinstance(x, ast.Starred) for x in call.args) or any(k.arg is None for k in call.keywords):
                    results.append({"code": "DYNAMIC_BINDING_NOT_VERIFIED", "status": "NOT_VERIFIED",
                                    "file": path, "line": call.lineno, "caller": owner,
                                    "callee": resolved_name})
                    continue
                args = target.args
                positional = args.posonlyargs + args.args
                nrequired = len(positional) - len(args.defaults)
                supplied = {a.arg for a in positional[:len(call.args)]}
                supplied.update(k.arg for k in call.keywords)
                required = {a.arg for a in positional[:nrequired]}
                required.update(a.arg for a, default in zip(args.kwonlyargs, args.kw_defaults) if default is None)
                missing = sorted(required - supplied)
                invalid_kw = sorted(k.arg for k in call.keywords if k.arg not in
                                    {a.arg for a in args.args + args.kwonlyargs}) if args.kwarg is None else []
                too_many = len(call.args) > len(positional) and args.vararg is None
                if missing or invalid_kw or too_many:
                    results.append({"code": "CALL_BINDING_INCOMPATIBLE", "status": "HYPOTHESIS",
                                    "file": path, "line": call.lineno, "caller": owner,
                                    "callee_file": resolved_path, "callee": resolved_name,
                                    "callee_line": target.lineno, "missing": missing,
                                    "invalid_keywords": invalid_kw, "too_many": too_many,
                                    "literal": ast.get_source_segment(source, call),
                                    "bindings": {a.arg: ast.unparse(v) for a, v in zip(positional, call.args)},
                                    "available_assignments": assignments})
    return results


def enum_candidates(path, function, parameter, allowed):
    """Conservative equality-only hints. An else/default makes this inconclusive."""
    _, tree = load_source(path)
    fn = functions(tree)[function]
    seen = set()
    has_default = False
    for node in ast.walk(fn):
        if isinstance(node, ast.If):
            if node.orelse and not (len(node.orelse) == 1 and isinstance(node.orelse[0], ast.If)):
                has_default = True
        if (isinstance(node, ast.Compare) and isinstance(node.left, ast.Name)
                and node.left.id == parameter and len(node.ops) == 1
                and isinstance(node.ops[0], ast.Eq) and len(node.comparators) == 1
                and isinstance(node.comparators[0], ast.Constant)):
            seen.add(node.comparators[0].value)
    missing = sorted(set(allowed) - seen)
    return [] if has_default or not missing else [{"code": "STATE_BRANCH_MISSING",
                "status": "HYPOTHESIS", "missing": missing, "function": function,
                "line": fn.lineno}]


def inventory(path):
    source, tree = load_source(path)
    return {"file": str(path), "sha256": sha256(source.encode("utf8")),
            "lines": len(source.splitlines()),
            "functions": [{"name": n.name, "line": n.lineno, "end_line": n.end_lineno,
                           "parameters": [a.arg for a in n.args.posonlyargs + n.args.args + n.args.kwonlyargs],
                           "calls": [{"line": c.lineno, "expression": ast.unparse(c)}
                                     for c in ast.walk(n) if isinstance(c, ast.Call)]}
                          for n in functions(tree).values()],
            "limitations": ["No execution", "No complete interprocedural data-flow",
                            "Nested scopes/dynamic bindings require semantic review"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()
    print(json.dumps({"inventory": [inventory(p) for p in args.paths],
                      "call_candidates": call_candidates(args.paths)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
