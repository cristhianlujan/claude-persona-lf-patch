#!/usr/bin/env python3
"""M4.12: independent, fail-closed correlation rerun for Validator v. Curator.

This is a CHECKPOINT TEST, not a runtime rewrite. It consumes a LIVE pg_proc
snapshot and the recorded M4.1 inventory, never a fabricated PASS fixture.
Usage: python correlation_rerun.py
Requires: psql and standard libpq connection env (PGHOST/PGUSER/PGDATABASE...).
"""
import json
import re
import subprocess
import sys

SQL = r"""
SELECT jsonb_build_object(
 'source','SUPABASE_LIVE_PG_PROC',
 'observed_at',clock_timestamp(),
 'm4_1_event',(SELECT payload FROM public.lf_eventos WHERE id=19381),
 'functions',(SELECT coalesce(jsonb_agg(jsonb_build_object(
   'name', p.proname, 'definition',p.prosrc,'md5',md5(p.prosrc))),
   '[]'::jsonb)
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='programacion' AND p.proname LIKE 'fn_input_%')
)::text;
"""
ROOT_CURATOR = "fn_input_governance_curator_materialize_v1"
CHECKED_PATHS = (
    "fn_input_governance_validator_rebind_v1",
    "fn_input_governance_validate_v2",
    "fn_input_governance_bootstrap_validate_v1",
)
# Explicit M1.3 contract debt: reused assertion builder is not an independent oracle.
ASSERTION_BUILDER = "fn_input_v58_build_assertions"
CALL = re.compile(r"\b(fn_[a-z0-9_]+)\s*\(", re.I)


def graph_closure(root, source_by_name, depth=8):
    if root not in source_by_name:
        raise ValueError("MISSING_ROOT:" + root)
    seen = set()
    frontier = {root}
    for _ in range(depth + 1):
        if not frontier:
            break
        nxt = set()
        for name in frontier:
            if name in seen:
                continue
            seen.add(name)
            body = source_by_name.get(name, "")
            nxt.update(CALL.findall(body))
        frontier = nxt - seen
    return seen


def evaluate(data):
    if data.get("source") != "SUPABASE_LIVE_PG_PROC":
        raise ValueError("LIVE_AUTHORITY_REQUIRED")
    evidence = data.get("m4_1_event") or {}
    paths = {p.get("path"): p for p in evidence.get("paths", [])}
    source_by_name = {f["name"]: f["definition"] for f in data.get("functions", [])}
    missing = sorted(set(CHECKED_PATHS + (ROOT_CURATOR,)) - source_by_name.keys())
    if missing:
        raise ValueError("MISSING_DECLARED_FUNCTIONS:" + ",".join(missing))
    curator = graph_closure(ROOT_CURATOR, source_by_name)
    failures = []
    coverage = []
    for name in CHECKED_PATHS:
        if name not in paths:
            raise ValueError("M4_1_PATH_MISSING:" + name)
        validator = graph_closure(name, source_by_name)
        shared = validator & curator
        known_conclusions = set()
        if paths[name].get("shared_classifier"):
            known_conclusions.add(paths[name]["shared_classifier"])
        if name == "fn_input_governance_validator_rebind_v1":
            known_conclusions.add(ASSERTION_BUILDER)
        # Semantic authority must be anchored to actual executable code,
        # not to overlap percentages or Curator-generated pass claims.
        violations = sorted(shared & known_conclusions)
        if violations:
            failures.append({"path":name, "shared_conclusion_dependencies":violations})
        coverage.append({"path":name, "reachable_functions":len(validator),
                         "shared_functions":len(shared),
                         "checked_conclusion_symbols":sorted(known_conclusions)})
    # A historic inventory alone cannot prove completeness; report scope.
    return {"test_code":"ENG_M4_12_CORRELATION_RERUN",
            "semantic_authority_bound":True, "scope":"M4_1_NAMED_CONCLUSION_DEPENDENCIES",
            "path_count":len(coverage), "paths":coverage, "violations":failures,
            "test_passed":not failures}


def adversarial_case(data):
    """Injected shared conclusion must fail when an otherwise clean path does not."""
    victim = "fn_input_governance_validate_v2"
    paths = {p.get("path"): p for p in data["m4_1_event"]["paths"]}
    classifier = paths[victim]["shared_classifier"]
    clean = json.loads(json.dumps(data))
    for fn in clean["functions"]:
        if fn["name"] == victim:
            fn["definition"] = "BEGIN PERFORM 1; END;"
            break
    sources = {f["name"]: f["definition"] for f in clean["functions"]}
    if classifier in graph_closure(victim, sources):
        raise AssertionError("NEGATIVE_CONTROL_NOT_CLEAN")
    dirty = json.loads(json.dumps(clean))
    for fn in dirty["functions"]:
        if fn["name"] == victim:
            fn["definition"] += "\nPERFORM " + classifier + "(1);"
            break
    result = evaluate(dirty)
    detected = any(
        failure["path"] == victim
        and classifier in failure["shared_conclusion_dependencies"]
        for failure in result["violations"]
    )
    if not detected:
        raise AssertionError("ADVERSARIAL_INJECTION_NOT_DETECTED")
    return True


def main():
    proc = subprocess.run(
        ["psql", "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-c", SQL],
        capture_output=True, text=True, check=False)
    if proc.returncode:
        print(json.dumps({"test_code":"ENG_M4_12_CORRELATION_RERUN",
                          "test_passed":False, "test_exit_code":2,
                          "reason":"LIVE_READ_FAILED", "stderr":proc.stderr[-1500:]}))
        return 2
    try:
        data = json.loads(proc.stdout.strip())
        report = evaluate(data)
        report["adversarial_case_executed"] = adversarial_case(data)
        report["observed_at"] = data.get("observed_at")
        report["test_exit_code"] = 0 if report["test_passed"] else 1
    except (ValueError, KeyError, AssertionError) as exc:
        report = {"test_code":"ENG_M4_12_CORRELATION_RERUN",
                  "test_passed":False, "test_exit_code":2,
                  "reason":"FAIL_CLOSED:" + str(exc),
                  "adversarial_case_executed":False}
    print(json.dumps(report, sort_keys=True))
    return report["test_exit_code"]


if __name__ == "__main__":
    sys.exit(main())
