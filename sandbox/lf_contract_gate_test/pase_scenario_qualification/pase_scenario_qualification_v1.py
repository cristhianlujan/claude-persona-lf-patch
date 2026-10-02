#!/usr/bin/env python3
"""Reusable scenario-aware qualification overlay for PASE controls.

This module is not a Changeset Governance/applicability authority. It consumes
one canonical scenario catalog, one control-owned trait/evidence profile,
explicit maturity, exact base/head and bounded runtime evidence already produced
by the control.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from typing import Any, Mapping, Sequence

CATALOG_SCHEMA = "lf-pase-scenario-catalog/v1"
PROFILE_SCHEMA = "lf-pase-scenario-profile/v1"
RESULT_SCHEMA = "lf-pase-scenario-qualification-result/v1"
POLICY_ID = "PASE_SCENARIO_QUALIFICATION_MATRIX_V1"
ALLOWED_SELECTED = {"TESTED", "BLOCKED_EXPLICITLY"}
UNSELECTED = "NOT_APPLICABLE"
SHA40 = re.compile(r"^[0-9a-f]{40}$")
ID_RE = re.compile(r"^[A-Z0-9][A-Z0-9_-]*$")
SAFE_TEST_ROOT = "sandbox/lf_contract_gate_test/"

class ScenarioQualificationError(RuntimeError):
    pass

def _fail(code: str, detail: str = "") -> None:
    raise ScenarioQualificationError(f"{code}:{detail}" if detail else code)

def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)

def _digest(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()

def _read_json(path: Path, code: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        _fail(code, type(exc).__name__)
    if not isinstance(value, dict):
        _fail(code, "not_object")
    return value

def _str_list(value: Any, *, allow_empty: bool = False) -> list[str]:
    if not isinstance(value, list) or (not allow_empty and not value):
        _fail("FAIL_SCENARIO_STRING_LIST")
    if any(not isinstance(x, str) or not x.strip() for x in value):
        _fail("FAIL_SCENARIO_STRING_LIST_ITEM")
    if len(value) != len(set(value)):
        _fail("FAIL_SCENARIO_STRING_LIST_DUPLICATE")
    return [x.strip() for x in value]

def validate_catalog(catalog: Mapping[str, Any]) -> None:
    if catalog.get("schema_version") != CATALOG_SCHEMA or catalog.get("policy_id") != POLICY_ID:
        _fail("FAIL_SCENARIO_CATALOG_IDENTITY")
    maturities = set(_str_list(catalog.get("allowed_maturities")))
    if catalog.get("allowed_selected_dispositions") != ["TESTED", "BLOCKED_EXPLICITLY"]:
        _fail("FAIL_SCENARIO_CATALOG_SELECTED_DISPOSITIONS")
    if catalog.get("unselected_disposition") != UNSELECTED or catalog.get("unknown_selected_forbidden") is not True:
        _fail("FAIL_SCENARIO_CATALOG_FAIL_CLOSED")
    scenarios = catalog.get("scenarios")
    if not isinstance(scenarios, list) or not scenarios:
        _fail("FAIL_SCENARIO_CATALOG_EMPTY")
    seen: set[str] = set()
    for row in scenarios:
        if not isinstance(row, Mapping):
            _fail("FAIL_SCENARIO_CATALOG_ROW")
        sid = row.get("scenario_id")
        if not isinstance(sid, str) or not ID_RE.fullmatch(sid) or sid in seen:
            _fail("FAIL_SCENARIO_CATALOG_SCENARIO_ID", str(sid))
        seen.add(sid)
        if not isinstance(row.get("family"), str) or not row["family"].strip():
            _fail("FAIL_SCENARIO_CATALOG_FAMILY", sid)
        if not set(_str_list(row.get("maturities"))) <= maturities:
            _fail("FAIL_SCENARIO_CATALOG_MATURITY", sid)
        _str_list(row.get("all_traits", []), allow_empty=True)
        _str_list(row.get("any_traits", []), allow_empty=True)
        if not isinstance(row.get("purpose"), str) or not row["purpose"].strip():
            _fail("FAIL_SCENARIO_CATALOG_PURPOSE", sid)

def _validate_safe_command(argv: Sequence[str], command_id: str) -> None:
    if argv[0] != "python3":
        _fail("FAIL_SCENARIO_UNSAFE_COMMAND_BINARY", command_id)
    script = argv[1].replace("\\", "/")
    if script.startswith("/") or not script.startswith(SAFE_TEST_ROOT) or ".." in Path(script).parts:
        _fail("FAIL_SCENARIO_UNSAFE_COMMAND_PATH", command_id)
    if any(x in {"-c", "-m"} or "\n" in x or "\r" in x for x in argv):
        _fail("FAIL_SCENARIO_UNSAFE_COMMAND_ARG", command_id)

def validate_profile(profile: Mapping[str, Any], catalog: Mapping[str, Any]) -> None:
    if profile.get("schema_version") != PROFILE_SCHEMA or profile.get("policy_id") != POLICY_ID:
        _fail("FAIL_SCENARIO_PROFILE_IDENTITY")
    if not isinstance(profile.get("control_id"), str) or not profile["control_id"].strip():
        _fail("FAIL_SCENARIO_PROFILE_CONTROL_ID")
    if profile.get("maturity") not in set(catalog["allowed_maturities"]):
        _fail("FAIL_SCENARIO_PROFILE_MATURITY")
    traits = _str_list(profile.get("traits"))
    if traits != sorted(traits):
        _fail("FAIL_SCENARIO_PROFILE_TRAITS_NOT_SORTED")
    commands = profile.get("evidence_commands")
    if not isinstance(commands, dict):
        _fail("FAIL_SCENARIO_PROFILE_COMMANDS")
    for cid, spec in commands.items():
        if not isinstance(cid, str) or not ID_RE.fullmatch(cid) or not isinstance(spec, Mapping):
            _fail("FAIL_SCENARIO_PROFILE_COMMAND", str(cid))
        argv = spec.get("argv")
        if not isinstance(argv, list) or len(argv) < 2 or any(not isinstance(x, str) or not x for x in argv):
            _fail("FAIL_SCENARIO_PROFILE_COMMAND_ARGV", cid)
        _validate_safe_command(argv, cid)
    assertions = profile.get("assertions")
    if not isinstance(assertions, dict):
        _fail("FAIL_SCENARIO_PROFILE_ASSERTIONS")
    catalog_ids = {row["scenario_id"] for row in catalog["scenarios"]}
    unknown = set(assertions) - catalog_ids
    if unknown:
        _fail("FAIL_SCENARIO_PROFILE_UNKNOWN_ASSERTION", ",".join(sorted(unknown)))
    for sid, assertion in assertions.items():
        if not isinstance(assertion, Mapping) or assertion.get("disposition") not in ALLOWED_SELECTED:
            _fail("FAIL_SCENARIO_PROFILE_DISPOSITION", sid)
        evidence = assertion.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            _fail("FAIL_SCENARIO_PROFILE_EVIDENCE", sid)
        for ev in evidence:
            if not isinstance(ev, Mapping):
                _fail("FAIL_SCENARIO_PROFILE_EVIDENCE_SHAPE", sid)
            kinds = [key for key in ("command_id", "runtime_assertion") if key in ev]
            if len(kinds) != 1:
                _fail("FAIL_SCENARIO_PROFILE_EVIDENCE_KIND", sid)
            if "command_id" in ev:
                if ev["command_id"] not in commands or not isinstance(ev.get("marker"), str) or not ev["marker"]:
                    _fail("FAIL_SCENARIO_PROFILE_COMMAND_EVIDENCE", sid)
            elif ev["runtime_assertion"] not in {"SCOPE_MANIFEST_EXACT", "RUN_SUMMARY_SCOPE"}:
                _fail("FAIL_SCENARIO_PROFILE_RUNTIME_ASSERTION", sid)

def select_scenarios(catalog: Mapping[str, Any], maturity: str, traits: set[str]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    selected: list[dict[str, Any]] = []
    unselected: list[dict[str, Any]] = []
    for row in catalog["scenarios"]:
        maturity_match = maturity in row["maturities"]
        all_match = set(row["all_traits"]) <= traits
        any_match = not row["any_traits"] or bool(set(row["any_traits"]) & traits)
        if maturity_match and all_match and any_match:
            selected.append(dict(row))
        else:
            reasons = []
            if not maturity_match: reasons.append("MATURITY")
            if not all_match: reasons.append("ALL_TRAITS")
            if not any_match: reasons.append("ANY_TRAITS")
            copy = dict(row)
            copy["not_applicable_reason"] = "+".join(reasons) or "PREDICATE_FALSE"
            unselected.append(copy)
    return selected, unselected

def _run_commands(root: Path, profile: Mapping[str, Any], selected_ids: set[str]) -> dict[str, str]:
    needed: set[str] = set()
    for sid in selected_ids:
        for ev in profile["assertions"][sid]["evidence"]:
            if "command_id" in ev:
                needed.add(ev["command_id"])
    outputs: dict[str, str] = {}
    for cid in sorted(needed):
        argv = profile["evidence_commands"][cid]["argv"]
        _validate_safe_command(argv, cid)
        proc = subprocess.run(argv, cwd=root, text=True, capture_output=True, check=False)
        combined = (proc.stdout or "") + ("\n" + proc.stderr if proc.stderr else "")
        if proc.returncode != 0:
            _fail("BLOCK_SCENARIO_EVIDENCE_COMMAND", f"{cid}:rc={proc.returncode}:{combined[-1000:]}")
        outputs[cid] = combined
    return outputs

def _runtime_context(runtime_dir: Path, *, base_sha: str, head_sha: str, maturity: str) -> dict[str, bool]:
    scope = _read_json(runtime_dir / "scope-manifest.json", "BLOCK_SCENARIO_SCOPE_MANIFEST")
    summary = _read_json(runtime_dir / "run-summary.json", "BLOCK_SCENARIO_RUN_SUMMARY")
    expected_scope = "CHANGESET_SCOPED"
    expected_disposition = "RECONCILIATION_WORK_ITEM"
    scope_ok = (
        scope.get("policy_id") == "PASE_EVALUATION_SCOPE_POLICY_V1"
        and scope.get("control_maturity") == maturity
        and scope.get("evaluation_scope") == expected_scope
        and scope.get("historical_debt_disposition") == expected_disposition
        and scope.get("base_sha") == base_sha
        and scope.get("head_sha") == head_sha
        and scope.get("unbounded_historical_scan") is False
    )
    summary_ok = (
        summary.get("policy_id") == "PASE_EVALUATION_SCOPE_POLICY_V1"
        and summary.get("control_maturity") == maturity
        and summary.get("evaluation_scope") == expected_scope
        and summary.get("historical_debt_disposition") == expected_disposition
        and summary.get("unbounded_historical_scan") is False
        and summary.get("status") == "PASS"
        and summary.get("returncode") == 0
    )
    return {"SCOPE_MANIFEST_EXACT": scope_ok, "RUN_SUMMARY_SCOPE": summary_ok}

def qualify(*, root: Path, catalog: Mapping[str, Any], profile: Mapping[str, Any], maturity: str, base_sha: str, head_sha: str, runtime_dir: Path) -> dict[str, Any]:
    validate_catalog(catalog)
    validate_profile(profile, catalog)
    if maturity != profile["maturity"]:
        _fail("FAIL_SCENARIO_MATURITY_PROFILE_DRIFT", f"{maturity}!={profile['maturity']}")
    if not SHA40.fullmatch(base_sha) or not SHA40.fullmatch(head_sha) or base_sha == head_sha:
        _fail("FAIL_SCENARIO_EXACT_RANGE")
    selected, unselected = select_scenarios(catalog, maturity, set(profile["traits"]))
    selected_ids = {row["scenario_id"] for row in selected}
    assertion_ids = set(profile["assertions"])
    missing = selected_ids - assertion_ids
    extra = assertion_ids - selected_ids
    if missing:
        _fail("BLOCK_SCENARIO_SELECTED_UNKNOWN", ",".join(sorted(missing)))
    if extra:
        _fail("FAIL_SCENARIO_ASSERTION_NOT_APPLICABLE", ",".join(sorted(extra)))
    command_outputs = _run_commands(root, profile, selected_ids)
    runtime = _runtime_context(runtime_dir, base_sha=base_sha, head_sha=head_sha, maturity=maturity)
    rows: list[dict[str, Any]] = []
    for row in selected:
        sid = row["scenario_id"]
        assertion = profile["assertions"][sid]
        evidence_result = []
        for ev in assertion["evidence"]:
            if "command_id" in ev:
                observed = ev["marker"] in command_outputs[ev["command_id"]]
                evidence_result.append({"kind":"COMMAND_MARKER","command_id":ev["command_id"],"marker":ev["marker"],"observed":observed})
            else:
                observed = runtime.get(ev["runtime_assertion"], False)
                evidence_result.append({"kind":"RUNTIME_ASSERTION","assertion":ev["runtime_assertion"],"observed":observed})
            if not observed:
                _fail("BLOCK_SCENARIO_EVIDENCE_NOT_OBSERVED", sid)
        rows.append({"scenario_id":sid,"family":row["family"],"selected":True,"disposition":assertion["disposition"],"evidence":evidence_result})
    for row in unselected:
        rows.append({"scenario_id":row["scenario_id"],"family":row["family"],"selected":False,"disposition":UNSELECTED,"reason":row["not_applicable_reason"],"evidence":[]})
    rows.sort(key=lambda r: r["scenario_id"])
    return {
        "schema_version":RESULT_SCHEMA,"policy_id":POLICY_ID,"control_id":profile["control_id"],"maturity":maturity,
        "base_sha":base_sha,"head_sha":head_sha,"catalog_sha256":_digest(catalog),"profile_sha256":_digest(profile),
        "scenario_count":len(rows),"selected_count":len(selected),"not_applicable_count":len(unselected),"unknown_selected_count":0,
        "no_first_discovery_in_production":True,"bounded_execution":True,
        "changeset_applicability_authority":"UNCHANGED_EXTERNAL_CHANGESET_GOVERNANCE","scenarios":rows,"verdict":"PASS"
    }

def self_test() -> int:
    mini_catalog = {
        "schema_version":CATALOG_SCHEMA,"policy_id":POLICY_ID,"selection_rule":"maturity_match AND all_traits_subset AND (any_traits_empty OR any_trait_matches)",
        "allowed_maturities":["CUTOVER","ACTIVE"],"allowed_selected_dispositions":["TESTED","BLOCKED_EXPLICITLY"],
        "unselected_disposition":UNSELECTED,"unknown_selected_forbidden":True,
        "scenarios":[
            {"scenario_id":"SCN-A","family":"X","maturities":["CUTOVER"],"all_traits":["A"],"any_traits":[],"purpose":"a"},
            {"scenario_id":"SCN-B","family":"X","maturities":["ACTIVE"],"all_traits":["B"],"any_traits":[],"purpose":"b"}
        ]
    }
    validate_catalog(mini_catalog)
    chosen, skipped = select_scenarios(mini_catalog,"CUTOVER",{"A"})
    if [x["scenario_id"] for x in chosen] != ["SCN-A"] or [x["scenario_id"] for x in skipped] != ["SCN-B"]:
        _fail("FAIL_SCENARIO_SELFTEST_SELECTOR")
    checks = 1
    unsafe = {"schema_version":PROFILE_SCHEMA,"policy_id":POLICY_ID,"control_id":"X","maturity":"CUTOVER","traits":["A"],
              "evidence_commands":{"BAD":{"argv":["bash","-c","true"]}},
              "assertions":{"SCN-A":{"disposition":"TESTED","evidence":[{"command_id":"BAD","marker":"x"}]}}}
    try:
        validate_profile(unsafe, mini_catalog)
    except ScenarioQualificationError as exc:
        if "FAIL_SCENARIO_UNSAFE_COMMAND_BINARY" not in str(exc): raise
    else:
        _fail("FAIL_SCENARIO_SELFTEST_UNSAFE_ACCEPTED")
    checks += 1
    print(f"PASS_PASE_SCENARIO_QUALIFICATION_SELFTEST={checks}/2")
    return 0

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--catalog")
    parser.add_argument("--profile")
    parser.add_argument("--maturity")
    parser.add_argument("--base-sha")
    parser.add_argument("--head-sha")
    parser.add_argument("--runtime-dir")
    parser.add_argument("--output")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test: return self_test()
    required = ("catalog","profile","maturity","base_sha","head_sha","runtime_dir","output")
    if any(not getattr(args, key) for key in required): _fail("FAIL_SCENARIO_REQUIRED_ARGUMENT")
    root = Path(args.repo_root).resolve()
    catalog = _read_json((root / args.catalog).resolve(), "FAIL_SCENARIO_CATALOG_READ")
    profile = _read_json((root / args.profile).resolve(), "FAIL_SCENARIO_PROFILE_READ")
    runtime_dir = (root / args.runtime_dir).resolve()
    output = (root / args.output).resolve()
    try:
        runtime_dir.relative_to(root); output.relative_to(root)
    except ValueError:
        _fail("FAIL_SCENARIO_PATH_OUTSIDE_REPO")
    result = qualify(root=root,catalog=catalog,profile=profile,maturity=args.maturity.strip().upper(),base_sha=args.base_sha.strip().lower(),head_sha=args.head_sha.strip().lower(),runtime_dir=runtime_dir)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, sort_keys=True) + "\n", encoding="utf-8")
    print(f"PASS_PASE_SCENARIO_QUALIFICATION_MATRIX_V1 control={result['control_id']} maturity={result['maturity']} selected={result['selected_count']} not_applicable={result['not_applicable_count']} unknown={result['unknown_selected_count']}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
