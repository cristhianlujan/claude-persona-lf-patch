#!/usr/bin/env python3
"""M4.12: independent, fail-closed correlation rerun for Validator v. Curator.

This is a CHECKPOINT TEST, not a runtime rewrite. It consumes a LIVE pg_proc
snapshot and the recorded M4.1 inventory, never a fabricated PASS fixture.
Usage: python correlation_rerun.py
Requires: psql and standard libpq connection env (PGHOST/PGUSER/PGDATABASE...).
"""
import argparse
import json
import re
import subprocess
import sys

SQL = r"""
SELECT jsonb_build_object(
 'source','SUPABASE_LIVE_PG_PROC',
 'observed_at',clock_timestamp(),
 'm4_1_event',(SELECT payload FROM public.lf_eventos WHERE id=19381),
 'independence_measure',public.lf_independent_assurance_measure_v1(
   'programacion',
   'fn_input_governance_curator_materialize_v1',
   'fn_input_governance_validator_validate_v1',
   8,'{}'::jsonb),
 'family_registry',(SELECT especificacion FROM programacion.contratos
   WHERE contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
     AND estado='defined'
   ORDER BY version_id DESC,id DESC LIMIT 1),
 'selected_run',(SELECT jsonb_build_object(
   'run_id',r.id,'pantalla_id',r.pantalla_id,'version_id',r.version_id,
   'screen_code',(SELECT p.codigo FROM lf_ops.pantallas p WHERE p.id=r.pantalla_id),
   'families',(SELECT coalesce(jsonb_agg(a.family_code ORDER BY a.family_code),'[]'::jsonb)
              FROM programacion.input_family_assessments a WHERE a.run_id=r.id))
   FROM programacion.input_readiness_runs r WHERE r.id=:selected_run_id),
 'comparison_families',coalesce(to_jsonb(string_to_array(nullif(:'comparison_families',''),',')),'[]'::jsonb),
 'selected_oracles',(SELECT coalesce(jsonb_agg(jsonb_build_object(
     'family_code',a.family_code,
     'oracle',programacion.fn_input_governance_shadow_priority_oracle_v2(
        r.pantalla_id,a.family_code,r.version_id)) ORDER BY a.family_code),'[]'::jsonb)
   FROM programacion.input_readiness_runs r
   JOIN programacion.input_family_assessments a ON a.run_id=r.id
   WHERE r.id=:selected_run_id AND a.family_code=any(string_to_array(nullif(:'comparison_families',''),','))),
 'selected_family_specs',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'family_code',a.family_code,
      'spec',programacion.fn_input_governance_shadow_family_spec_v2(
        a.family_code,r.version_id)) ORDER BY a.family_code),'[]'::jsonb)
   FROM programacion.input_readiness_runs r
   JOIN programacion.input_family_assessments a ON a.run_id=r.id
   WHERE r.id=:selected_run_id AND a.family_code=any(string_to_array(nullif(:'comparison_families',''),','))),
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
    # Use existing transversal independence authority, not an invented
    # second evaluator. Shared canonical source helpers are reported, not
    # silently treated as semantic conclusions.
    measure = data.get("independence_measure") or {}
    registry = data.get("family_registry") or {}
    families = registry.get("families") or {}
    if not isinstance(families, dict) or not families:
        raise ValueError("LIVE_FAMILY_REGISTRY_MISSING")
    if int(registry.get("family_count", -1)) != len(families):
        raise ValueError("LIVE_FAMILY_REGISTRY_COUNT_DRIFT")
    missing_strategies = sorted(
        code for code, spec in families.items()
        if not (spec.get("validator_oracle_strategy") or {}).get("strategy")
    )
    if missing_strategies:
        failures.append({"path":"REGISTRY", "missing_strategy_for":missing_strategies})
    if measure.get("schema_version") != "LF_INDEPENDENT_ASSURANCE_MEASURE_V1":
        raise ValueError("CANONICAL_INDEPENDENCE_MEASURE_MISSING")
    # The selected screen is supplied by the random-selection upstream run.
    # Never replace it with REC_001 or choose a convenient fixture silently.
    selected = data.get("selected_run") or {}
    run_id = selected.get("run_id")
    screen_id = selected.get("pantalla_id")
    requested = selected.get("families") or []
    if not run_id or not screen_id or not requested:
        raise ValueError("SELECTED_RUN_OR_SCREEN_UNRESOLVED")
    if len(set(requested)) != len(requested):
        raise ValueError("SELECTED_RUN_DUPLICATE_FAMILY")
    oracle_rows = data.get("selected_oracles") or []
    if len(oracle_rows) != len(requested):
        raise ValueError("SELECTED_RUN_ORACLE_CARDINALITY_DRIFT")
    if {r.get("family_code") for r in oracle_rows} != set(requested):
        raise ValueError("SELECTED_RUN_ORACLE_FAMILY_MISMATCH")
    if any(code not in families for code in requested):
        raise ValueError("SELECTED_RUN_FAMILY_NOT_IN_REGISTRY")
    specs = data.get("selected_family_specs") or []
    if len(specs) != len(requested):
        raise ValueError("SELECTED_SCREEN_POLICY_CARDINALITY_DRIFT")
    if {row.get("family_code") for row in specs} != set(requested):
        raise ValueError("SELECTED_SCREEN_POLICY_FAMILY_MISMATCH")
    structural_failed = []
    for row in specs:
        spec = row.get("spec") or {}
        checks = spec.get("test_obligations")
        if (spec.get("family_code") != row["family_code"]
                or spec.get("version_id") != selected.get("version_id")
                or (spec.get("stage_authority") or {}).get("status") != "EXPLICIT"
                or not isinstance(checks, list)
                or len(checks) < 1
                or any(c.get("status") != "PASS" for c in checks)):
            structural_failed.append(row["family_code"])
    if structural_failed:
        failures.append({"path":"STRUCTURAL_POLICY_ORACLE",
                         "code":"STRUCTURAL_EVIDENCE_FAILED",
                         "families":sorted(structural_failed)})
    def oracle_has_bounded_evidence(row):
        oracle = row.get("oracle") or {}
        return (
            oracle.get("implemented") is True
            and oracle.get("pantalla_id") == screen_id
            and oracle.get("version_id") == selected.get("version_id")
            and oracle.get("comparison_only") is True
            and oracle.get("decisional") is False
            and isinstance(oracle.get("classification"), str)
            and not oracle["classification"].startswith("UNRESOLVED")
            and oracle.get("shadow_sha256")
            and isinstance(oracle.get("trace"), list)
            and len(oracle["trace"]) > 0
        )
    uncovered = sorted(r["family_code"] for r in oracle_rows
                       if not oracle_has_bounded_evidence(r))
    if uncovered:
        failures.append({"path":"SELECTED_SCREEN_ORACLE_COVERAGE",
                         "run_id":run_id, "pantalla_id":screen_id,
                         "code":"NOT_COVERED", "families":uncovered})
    # A valid shadow candidate is not yet a certified independent oracle.
    # The existing family registry explicitly declares independence_claim=false
    # for current Validator. Until a verified per-family receipt is added to
    # the contract, no candidate-only path may satisfy checkpoint acceptance.
    if not uncovered:
        failures.append({"path":"SEMANTIC_ORACLE_CERTIFICATION",
                         "code":"INDEPENDENCE_UNPROVEN",
                         "reason":"SHADOW_CANDIDATES_NOT_A_CERTIFIED_INDEPENDENT_ORACLE"})
    # Independent conclusions may share canonical data-source helpers.
    # All-overlap assurance remains diagnostic, never the semantic PASS gate.
    if measure.get("state") not in ("INDEPENDENT", "UNPROVEN", "NOT_INDEPENDENT"):
        raise ValueError("CANONICAL_ASSURANCE_INVALID")
    shared = set((measure.get("dependency_dimension") or {}).get("shared_dependencies") or [])
    for issue in failures:
        if issue.get("path") in CHECKED_PATHS:
            for symbol in issue.get("shared_conclusion_dependencies", []):
                if symbol not in shared:
                    raise ValueError("ASSURANCE_DRIFT:" + symbol)
    return {"test_code":"ENG_M4_12_CORRELATION_RERUN",
            "semantic_authority_bound":True,
            "scope":"M4_1_CONCLUSION_PATHS_PLUS_LF_INDEPENDENT_ASSURANCE",
            "path_count":len(coverage), "paths":coverage, "violations":failures,
            "family_registry_count":len(families),
            "selected_run_id":run_id, "selected_pantalla_id":screen_id,
            "selected_screen_code":selected.get("screen_code"),
            "selected_family_count":len(requested),
            "selected_structural_observed_count":len(requested),
            "selected_structural_pass_count":len(requested)-len(structural_failed),
            "selected_oracle_candidate_covered_count":len(requested)-len(uncovered),
            "selected_oracle_status":"NOT_COVERED" if uncovered else "CANDIDATE_ONLY",
            "semantic_independence_credited":False,
            "canonical_independence_state":measure.get("state"),
            "independence_shared_dependency_count":
                (measure.get("dependency_dimension") or {}).get("shared_dependency_count"),
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
    parser = argparse.ArgumentParser(description="M4.12 correlation and selected-screen coverage readback")
    parser.add_argument("--run-id", type=int, required=True,
                        help="Actual readiness run chosen by upstream random screen selection")
    parser.add_argument("--family-code",action="append",default=[])
    options = parser.parse_args()
    if options.run_id < 1:
        parser.error("run-id must be a positive integer")
    if any(not re.fullmatch(r"[A-Z][A-Z0-9_]*", x) for x in options.family_code):
        parser.error("invalid family code")
    if len(set(options.family_code)) != len(options.family_code):
        parser.error("duplicate family code")
    try:
        proc = subprocess.run(
            ["psql", "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1",
             "-v", f"selected_run_id={options.run_id}",
             "-v", "comparison_families=" + ",".join(options.family_code)],
            input=SQL, capture_output=True, text=True, check=False)
    except OSError as exc:
        print(json.dumps({"test_code":"ENG_M4_12_CORRELATION_RERUN",
                          "test_passed":False, "test_exit_code":2,
                          "reason":"PSQL_EXECUTOR_UNAVAILABLE", "error":str(exc)}))
        return 2
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
