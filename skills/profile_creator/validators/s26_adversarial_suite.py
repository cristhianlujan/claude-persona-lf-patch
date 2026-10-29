#!/usr/bin/env python3
"""S26 B14: dynamic adversarial suite.

The measurer (this trusted module), not the profile, fabricates the mutants. The profile only declares
WHERE its output can be attacked (field paths, id lists, phrase lexicon, valid controls) in
runtime_binding.adversarial_suite. Cases vary with a seed, so a profile cannot memorise a fixed list.

The profile's own validators are executed, so the run happens in an isolated child process:
cleared environment, no network (socket blocked), CPU / memory / file limits, wall-clock timeout, and a
private copy of the profile as working directory.
"""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
import random
import re
import subprocess
import sys
import tempfile
import shutil
from pathlib import Path
from typing import Any

SUITE_SCHEMA = "LF_PROFILE_ADVERSARIAL_SUITE_V1"
RESULT_SCHEMA = "S26_ADVERSARIAL_RESULT_V1"
BLANK_VARIANTS = ["", "   ", "​", "\n\t ", " "]
MAX_CASES_PER_FAMILY = 24
_TOKEN = re.compile(r"([A-Za-z0-9_]+)|\[(\d*)\]")


# ---------------------------------------------------------------- declaration (static, no execution)
def declaration_errors(decl: Any) -> list[str]:
    if not isinstance(decl, dict) or decl.get("schema") != SUITE_SCHEMA:
        return ["SUITE_NOT_DECLARED"]
    errs: list[str] = []
    if not isinstance(decl.get("base_example"), str) or not decl["base_example"] or decl["base_example"].startswith("/") or ".." in Path(decl["base_example"]).parts:
        errs.append("SUITE_BASE_EXAMPLE_INVALID")
    if not (isinstance(decl.get("min_cases"), int) and not isinstance(decl.get("min_cases"), bool) and decl["min_cases"] >= 20):
        errs.append("SUITE_MIN_CASES_INVALID")
    rate = decl.get("min_catch_rate")
    if not (isinstance(rate, (int, float)) and not isinstance(rate, bool) and 0.9 <= rate <= 1):
        errs.append("SUITE_MIN_CATCH_RATE_INVALID")
    for key in ("blank_fields",):
        v = decl.get(key)
        if not (isinstance(v, list) and v and all(isinstance(x, str) and x for x in v)):
            errs.append(f"SUITE_{key.upper()}_INVALID")
    inj = decl.get("injections")
    if not (isinstance(inj, list) and inj and all(
            isinstance(i, dict) and isinstance(i.get("fields"), list) and i["fields"]
            and all(isinstance(f, str) and f for f in i["fields"])
            and isinstance(i.get("phrases"), list) and i["phrases"]
            and all(isinstance(p, str) and p.strip() for p in i["phrases"]) for i in inj)):
        errs.append("SUITE_INJECTIONS_INVALID")
    dups = decl.get("case_duplicate_ids", [])
    if not (isinstance(dups, list) and all(isinstance(d, dict) and isinstance(d.get("list"), str) and isinstance(d.get("key"), str) for d in dups)):
        errs.append("SUITE_CASE_DUPLICATE_IDS_INVALID")
    ctl = decl.get("valid_controls")
    if not (isinstance(ctl, list) and ctl and all(
            isinstance(c, dict) and isinstance(c.get("name"), str) and isinstance(c.get("set"), dict) and c["set"] for c in ctl)):
        errs.append("SUITE_VALID_CONTROLS_INVALID")
    return errs


# ---------------------------------------------------------------- path helpers
def _tokens(path: str) -> list[Any]:
    out: list[Any] = []
    for part in path.split("."):
        for m in _TOKEN.finditer(part):
            if m.group(1) is not None:
                out.append(m.group(1))
            else:
                out.append(None if m.group(2) == "" else int(m.group(2)))
    return out


def _expand(payload: Any, path: str) -> list[tuple[Any, ...]]:
    """Concrete token paths for `path` (a [] wildcard expands to every index)."""
    results: list[tuple[Any, ...]] = []

    def walk(node: Any, toks: list[Any], acc: tuple[Any, ...]) -> None:
        if not toks:
            results.append(acc)
            return
        head, rest = toks[0], toks[1:]
        if head is None and isinstance(node, list):
            for i in range(len(node)):
                walk(node[i], rest, acc + (i,))
        elif isinstance(head, int) and isinstance(node, list) and head < len(node):
            walk(node[head], rest, acc + (head,))
        elif isinstance(head, str) and isinstance(node, dict) and head in node:
            walk(node[head], rest, acc + (head,))

    walk(payload, _tokens(path), ())
    return results


def _get(payload: Any, path: tuple[Any, ...]) -> Any:
    for t in path:
        payload = payload[t]
    return payload


def _set(payload: Any, path: tuple[Any, ...], value: Any) -> None:
    node = payload
    for t in path[:-1]:
        node = node[t]
    node[path[-1]] = value


# ---------------------------------------------------------------- mutators (trusted)
def _phrase_variants(phrase: str) -> list[str]:
    return [phrase, phrase.upper(), phrase.replace(" ", "  "), phrase.replace(" ", "-"), phrase + "!", "Oferta: " + phrase, phrase.lower()]


def build_cases(decl: dict[str, Any], base: dict[str, Any], rng: random.Random) -> tuple[list[tuple[str, Any]], list[tuple[str, Any]]]:
    """Return (invalid_cases, valid_controls) as lists of (name, payload)."""
    invalid: list[tuple[str, Any]] = []

    def family(items: list[tuple[str, Any]]) -> None:
        rng.shuffle(items)
        invalid.extend(items[:MAX_CASES_PER_FAMILY])

    blanks = []
    for field in decl["blank_fields"]:
        for path in _expand(base, field):
            for v in BLANK_VARIANTS:
                p = copy.deepcopy(base)
                _set(p, path, v)
                blanks.append((f"blank:{'.'.join(map(str, path))}:{v!r}", p))
    family(blanks)

    inj = []
    for group in decl["injections"]:
        for field in group["fields"]:
            for path in _expand(base, field):
                for phrase in group["phrases"]:
                    for variant in _phrase_variants(phrase):
                        p = copy.deepcopy(base)
                        _set(p, path, variant)
                        inj.append((f"inject:{'.'.join(map(str, path))}:{variant}", p))
    family(inj)

    dups = []
    for d in decl.get("case_duplicate_ids", []):
        items = base.get(d["list"]) if isinstance(base, dict) else None
        if isinstance(items, list) and len(items) >= 2 and isinstance(items[0], dict) and isinstance(items[0].get(d["key"]), str):
            for fn_name, fn in (("lower", str.lower), ("upper", str.upper), ("padded", lambda s: " " + s + " ")):
                p = copy.deepcopy(base)
                p[d["list"]][1][d["key"]] = fn(p[d["list"]][0][d["key"]])
                dups.append((f"dup_id:{d['list']}.{d['key']}:{fn_name}", p))
    family(dups)

    if decl.get("unknown_root_key", True):
        for n in range(3):
            p = copy.deepcopy(base)
            p[f"zz_extra_{rng.randrange(10**6)}"] = {"x": n}
            invalid.append(("unknown_root_key", p))

    controls: list[tuple[str, Any]] = []
    for c in decl["valid_controls"]:
        p = copy.deepcopy(base)
        ok = True
        for field, value in c["set"].items():
            paths = _expand(p, field)
            if not paths:
                ok = False
                break
            for path in paths[:1]:
                _set(p, path, value)
        if ok:
            controls.append((f"control:{c['name']}", p))
    controls.append(("control:base_example", copy.deepcopy(base)))
    return invalid, controls


# ---------------------------------------------------------------- in-process core (runs in the child)
def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _accepts(validate, semantic, payload: Any) -> bool:
    gate = validate(payload)
    if not isinstance(gate, dict) or gate.get("status") != "PASS":
        return False
    if semantic is None:
        return True
    sem = semantic(payload, gate)
    return isinstance(sem, dict) and sem.get("status") == "PASS"


def run_suite(profile_dir: Path, seed: str) -> dict[str, Any]:
    profile_dir = profile_dir.resolve()
    binding = json.loads((profile_dir / "contracts/runtime_binding.json").read_text(encoding="utf-8"))
    decl = binding.get("adversarial_suite")
    errs = declaration_errors(decl)
    if errs:
        return {"schema": RESULT_SCHEMA, "status": "NOT_DECLARED_OR_INVALID", "blocking_codes": errs}
    base = json.loads((profile_dir / decl["base_example"]).read_text(encoding="utf-8"))
    cv, su = binding["canonical_validator"], binding.get("semantic_utility")
    validate = getattr(_load("profile_validator", profile_dir / cv["path"]), cv["callable"])
    semantic = getattr(_load("profile_semantic", profile_dir / su["path"]), su["callable"]) if isinstance(su, dict) else None
    rng = random.Random(int(hashlib.sha256(seed.encode()).hexdigest(), 16))
    invalid, controls = build_cases(decl, base, rng)
    missed, wrong = [], []
    for name, payload in invalid:
        try:
            if _accepts(validate, semantic, payload):
                missed.append(name)
        except Exception:  # a crashing validator rejects (fail closed)
            pass
    for name, payload in controls:
        try:
            if not _accepts(validate, semantic, payload):
                wrong.append(name)
        except Exception:
            wrong.append(name)
    total = len(invalid)
    caught = total - len(missed)
    rate = caught / total if total else 0.0
    ok = total >= decl["min_cases"] and rate >= decl["min_catch_rate"] and not wrong
    return {"schema": RESULT_SCHEMA, "status": "PASS" if ok else "FAIL", "seed_sha256": hashlib.sha256(seed.encode()).hexdigest(),
            "invalid_cases": total, "caught": caught, "catch_rate": round(rate, 4), "min_catch_rate": decl["min_catch_rate"],
            "min_cases": decl["min_cases"], "controls": len(controls), "controls_rejected_wrongly": wrong,
            "missed_examples": missed[:8], "blocking_codes": [] if ok else (
                (["SUITE_TOO_FEW_CASES"] if total < decl["min_cases"] else []) +
                (["SUITE_CATCH_RATE_BELOW_MIN"] if rate < decl["min_catch_rate"] else []) +
                (["SUITE_VALID_CONTROL_REJECTED"] if wrong else []))}


# ---------------------------------------------------------------- isolation (parent side)
def _limits() -> None:  # runs in the child before exec
    import resource
    resource.setrlimit(resource.RLIMIT_CPU, (20, 20))
    resource.setrlimit(resource.RLIMIT_AS, (1 << 30, 1 << 30))
    resource.setrlimit(resource.RLIMIT_FSIZE, (1 << 20, 1 << 20))
    resource.setrlimit(resource.RLIMIT_NPROC, (64, 64))
    os.setsid()


def run_isolated(profile_dir: Path, seed: str, timeout: int = 30) -> dict[str, Any]:
    """Execute the suite in a child process against a private copy of the profile."""
    with tempfile.TemporaryDirectory(prefix="s26-adv-") as tmp:
        work = Path(tmp) / "profile"
        shutil.copytree(profile_dir, work, symlinks=False)
        env = {"PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1", "HOME": tmp, "LANG": "C.UTF-8"}
        try:
            proc = subprocess.run([sys.executable, "-I", str(Path(__file__).resolve()), "--child", str(work), seed],
                                  cwd=tmp, env=env, capture_output=True, text=True, timeout=timeout, preexec_fn=_limits)
        except subprocess.TimeoutExpired:
            return {"schema": RESULT_SCHEMA, "status": "ERROR", "blocking_codes": ["SUITE_TIMEOUT"]}
        if proc.returncode != 0:
            return {"schema": RESULT_SCHEMA, "status": "ERROR", "blocking_codes": ["SUITE_CHILD_FAILED"], "stderr_tail": proc.stderr[-300:]}
        try:
            return json.loads(proc.stdout)
        except json.JSONDecodeError:
            return {"schema": RESULT_SCHEMA, "status": "ERROR", "blocking_codes": ["SUITE_OUTPUT_INVALID"]}


def _child(profile_dir: str, seed: str) -> int:
    import socket

    def _blocked(*a: Any, **k: Any):
        raise OSError("NETWORK_BLOCKED_BY_S26_SUITE")

    socket.socket = _blocked  # type: ignore[assignment]
    socket.create_connection = _blocked  # type: ignore[assignment]
    socket.getaddrinfo = _blocked  # type: ignore[assignment]
    print(json.dumps(run_suite(Path(profile_dir), seed), sort_keys=True))
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--child":
        raise SystemExit(_child(sys.argv[2], sys.argv[3]))
    if len(sys.argv) == 3:
        print(json.dumps(run_isolated(Path(sys.argv[1]), sys.argv[2]), indent=2, sort_keys=True))
        raise SystemExit(0)
    print("usage: s26_adversarial_suite.py <profile_dir> <seed>", file=sys.stderr)
    raise SystemExit(2)
