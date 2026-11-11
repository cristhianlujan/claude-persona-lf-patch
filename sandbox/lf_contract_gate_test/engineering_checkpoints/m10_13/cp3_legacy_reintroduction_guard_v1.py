#!/usr/bin/env python3
"""IG M10.13 CP3: fail closed on NEW operational calls to frozen M10.4 functions.

Runs from the trusted PR base inside the EXISTING IG candidate-judge workflow.
Reads PR head strictly as Git data, never executes PR code. Does not edit DB.
Historical read-only references in old migrations / tests are not retired.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
MANIFEST = HERE.parent / "m10_4" / "legacy_freeze_manifest_v1.json"
WORKFLOW = ".github/workflows/lf-ig-runtime-candidate-judge.yml"
GUARD = "sandbox/lf_contract_gate_test/engineering_checkpoints/m10_13/cp3_legacy_reintroduction_guard_v1.py"
TEST = "sandbox/lf_contract_gate_test/engineering_checkpoints/m10_13/test_cp3_legacy_reintroduction_guard_v1.py"
PROTECTED = frozenset({WORKFLOW, GUARD, TEST})
CURRENT_SHARED = "public.fn_lf_evidence_ledger_anchor_v1"
# Four EXACT, observed live callers of CURRENT EVIDENCE_LEDGER v1.1.0.
# Not a claim that unknown new callers have owner approval.
CURRENT_SHARED_CALLERS = frozenset({
    "programacion.fn_ig_graph_receipt_emit_per_run_v1",
    "programacion.fn_ig_spec_traversal_emit_per_run_v1",
    "programacion.fn_input_governance_shadow_receipt_emit_v1",
    "public.lf_record_independent_review_step_v3",
})
CREATE = re.compile(
    r"\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+"
    r'((?:"?[a-z_][a-z_0-9]*"?\s*\.\s*)?"?[a-z_][a-z_0-9]*"?)\s*\(',
    re.I,
)
RPC = re.compile(r"\.rpc\s*\(\s*['\"]([a-z_][a-z_0-9]*)['\"]", re.I)
SQL_COMMENT = re.compile(r"/\*[\s\S]*?\*/|--[^\n]*")


def targets_from_manifest(manifest: dict) -> set[str]:
    if manifest.get("schema_version") != "IG_M104_LEGACY_FREEZE_MANIFEST_V1":
        raise ValueError("BLOCK_CP3_MANIFEST_SCHEMA")
    items = manifest.get("legacy_functions")
    if not isinstance(items, list) or len(items) != 26:
        raise ValueError("BLOCK_CP3_FROZEN_SET_CARDINALITY")
    names = {item["identity"].split("(", 1)[0].lower() for item in items}
    if len(names) != 26 or CURRENT_SHARED not in names:
        raise ValueError("BLOCK_CP3_FROZEN_SET_NOT_EXACT")
    return names


def strip_comments(text: str) -> str:
    return SQL_COMMENT.sub("", text)


def normalize(name: str) -> str:
    return re.sub(r'[\s"]', "", name).lower()


def statement_until_semicolon(text: str, start: int) -> str:
    """End at first semicolon outside SQL single/double/dollar-quoted bodies."""
    i, quote, dollar = start, "", ""
    while i < len(text):
        c = text[i]
        if dollar:
            if text.startswith(dollar, i):
                i += len(dollar)
                dollar = ""
                continue
        elif quote:
            if c == quote:
                if i + 1 < len(text) and text[i + 1] == quote:
                    i += 2
                    continue
                quote = ""
        else:
            if c in ("'", '"'):
                quote = c
            elif c == "$":
                m = re.match(r"\$[a-zA-Z_0-9]*\$", text[i:])
                if m:
                    dollar = m.group()
                    i += len(dollar)
                    continue
            elif c == ";":
                return text[start:i + 1]
        i += 1
    # Incomplete DDL must never be allowed to bypass the guard.
    raise ValueError("BLOCK_CP3_INCOMPLETE_FUNCTION_DDL")


def functions_in_sql(text: str) -> list[tuple[str, str]]:
    src = strip_comments(text)
    return [(normalize(m.group(1)), statement_until_semicolon(src, m.start()))
            for m in CREATE.finditer(src)]


def frozen_calls(ddl: str, targets: set[str]) -> dict[str, int]:
    calls = {}
    for ident in targets:
        schema, name = ident.split(".", 1)
        pat = re.compile(
            rf"(?<![a-z_0-9])(?:(?P<schema>public|programacion|lf_ops)\s*\.\s*)?"
            rf"{re.escape(name)}\s*\(", re.I)
        count = sum(1 for m in pat.finditer(ddl)
                    if m.group("schema") is None or m.group("schema").lower() == schema)
        if count:
            calls[ident] = count
    return calls


def scan(path: str, before: str, after: str, targets: set[str]) -> list[str]:
    """Flag new operational edges; allow current 4 ledger callers only."""
    findings = []
    if path.startswith("supabase/migrations/") and path.endswith(".sql"):
        old = {}
        for caller, ddl in functions_in_sql(before):
            for target, n in frozen_calls(ddl, targets).items():
                old[(caller, target)] = max(old.get((caller, target), 0), n)
        for caller, ddl in functions_in_sql(after):
            for target, n in frozen_calls(ddl, targets).items():
                canonical_caller = caller if "." in caller else "public." + caller
                if target == CURRENT_SHARED and canonical_caller in CURRENT_SHARED_CALLERS:
                    continue
                if n > old.get((caller, target), 0):
                    findings.append(f"NEW_SQL_EDGE:{caller}->{target}")
        # Dynamic SQL generating functions is not statically attestable:
        # reject new executable CREATE+EXECUTE+frozen reference patterns.
        dynamic = re.compile(r"\bEXECUTE\b[\s\S]{0,300}\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\b", re.I)
        new_dynamic = bool(dynamic.search(strip_comments(after)))
        old_dynamic = bool(dynamic.search(strip_comments(before)))
        if new_dynamic and not old_dynamic and any(
            name in strip_comments(after).lower() for name in (s.split(".")[1] for s in targets)
        ):
            findings.append("UNVERIFIED_DYNAMIC_FUNCTION_DDL_WITH_FROZEN_REFERENCE")
    elif path.startswith("supabase/functions/") and path.endswith((".ts", ".js", ".mjs", ".cjs")):
        old_rpc = {m.group(1).lower() for m in RPC.finditer(before)}
        for m in RPC.finditer(after):
            name = m.group(1).lower()
            if name not in old_rpc and any(x.endswith("." + name) for x in targets):
                findings.append("NEW_EDGE_RPC_TO_FROZEN:" + name)
    return findings


def git(*args: str) -> str:
    r = subprocess.run(["git", *args], capture_output=True, check=False)
    if r.returncode:
        raise ValueError("BLOCK_CP3_GIT_SOURCE_READ:" + " ".join(args[:3]))
    try:
        return r.stdout.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError("BLOCK_CP3_NON_UTF8_SOURCE") from exc


def check_commit(base: str, head: str) -> int:
    if not all(re.fullmatch(r"[0-9a-f]{40}", sha) for sha in (base, head)):
        raise ValueError("BLOCK_CP3_UNPINNED_SOURCE_HEAD")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    targets = targets_from_manifest(manifest)
    changed = git("diff", "--name-only", "--diff-filter=ACMRD", base, head).splitlines()
    if len(changed) > 2000:
        raise ValueError("BLOCK_CP3_EXCESSIVE_PR_SCOPE")
    for path in changed:
        if path in PROTECTED:
            raise ValueError("BLOCK_CP3_GUARD_SELF_CHANGE:" + path)
        if not (path.startswith("supabase/migrations/") or path.startswith("supabase/functions/")):
            continue
        def read(sha: str) -> str:
            probe = subprocess.run(["git", "cat-file", "-e", f"{sha}:{path}"], capture_output=True)
            return git("show", f"{sha}:{path}") if probe.returncode == 0 else ""
        result = scan(path, read(base), read(head), targets)
        if result:
            raise ValueError("BLOCK_CP3_REINTRODUCTION:" + path + ":" + ",".join(result))
    print(f"PASS_CP3_NO_NEW_LEGACY_EDGES base={base} head={head} sources={len(changed)} frozen={len(targets)}")
    return 0


def self_test() -> int:
    targets = targets_from_manifest(json.loads(MANIFEST.read_text(encoding="utf-8")))
    legacy = "programacion.fn_input_governance_semantic_probe_v2_cached_v1(1,'RATE_LIMIT',1,'{}'::jsonb)"
    def ddl(name: str, body: str) -> str:
        return f"CREATE OR REPLACE FUNCTION programacion.{name}() RETURNS void LANGUAGE plpgsql AS $$ BEGIN PERFORM {body}; END $$;"
    p = "supabase/migrations/20300101000000_check.sql"
    assert scan(p, "", ddl("new_consumer", legacy), targets)
    assert not scan(p, "", ddl("new_consumer", "programacion.fn_input_governance_semantic_probe_v2(1,'RATE_LIMIT',1,'{}'::jsonb)"), targets)
    assert not scan(p, "", "-- read only\nSELECT " + legacy + ";", targets)
    assert not scan(p, "", "-- " + ddl("bad", legacy), targets)
    assert scan(p, "", ddl("bad", legacy), targets)
    same = ddl("unchanged", legacy)
    assert not scan(p, same, same, targets)
    anchor = "public.fn_lf_evidence_ledger_anchor_v1('a')"
    assert scan(p, "", ddl("unknown_consumer", anchor), targets)
    assert not scan(p, "", ddl("fn_ig_graph_receipt_emit_per_run_v1", anchor), targets)
    assert scan("supabase/functions/new/index.ts", "", "await db.rpc('fn_input_governance_semantic_probe_v2_cached_v1')", targets)
    assert not scan("supabase/functions/new/index.ts", "", "await db.rpc('fn_input_governance_semantic_probe_v2')", targets)
    assert len(targets) == 26
    print("PASS_CP3_GUARD_SELF_TEST 11/11")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["self-test", "check-commit"])
    parser.add_argument("--base")
    parser.add_argument("--head")
    args = parser.parse_args()
    try:
        if args.mode == "self-test":
            return self_test()
        if not args.base or not args.head:
            raise ValueError("BLOCK_CP3_BASE_HEAD_REQUIRED")
        return check_commit(args.base, args.head)
    except (ValueError, KeyError, AssertionError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
