"""EX5C real world for the ORIGINAL PG-04..PG-14 producers.

The synthetic chain tests of PG-04..PG-14 build their inputs with fixture
functions ("lf-synthetic/pilot", base "a"*40, paths "src/<sid>/*.py", ...).
This module replaces ONLY those caller-side fixture functions/constants with
values taken from the real EX5C evidence (sandbox repo, commits 28de535 ->
e76b213 -> bc74940, Java paths, Maven/javac/format receipts, Worker cost).

Rules:
* No producer module is modified or monkeypatched: only test-side builders.
* Every override is registered in OVERRIDES so a reviewer can audit it.
* Authority flags stay False; evidence is REAL_SANDBOX_UNAUTHENTICATED.
"""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

STAGE_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = STAGE_ROOT / "pg07_worker_candidate" / "fixtures"

REPO = "paulozterra/lf-programming-sandbox"
BASE = "28de535acd4a76be038013cc6241c59a08102155"   # main before lote C
N = "e76b213cb2f367f787e0eba3bf8ff74136edd883"      # lote C merged (Worker patch)
N1 = "bc74940727f1bb51a076f52a4b20fb5ed00647c8"     # format remediation merged
DIFF_SOL1 = "bfba0329bcac92dbde06a1319a16acd535acd718f224df6121dae3c70fe307c6"  # BASE..N src/main
DIFF_SOL2 = "85e5f6bdd38d0714c781a50983434081f0ad312b2708978896270003562fbd68"  # N..N1 src/main
V1_SHA = "436bc771ccd04b5eeb407102f7c55a3338bacf43f8f292773f293aa615a8da3b"
V3_SHA = "417b504380e4ebe9f4345b2b33c21d6a8f0d0a05b1e51ef2a86de3822bc09ec0"
SPEC_SHA_N = "45f06d002dd7152f88bc9a3332eb3f3b6c10a2c8773e2cb7b0beeadf61810d00"
SPEC_SHA_N1 = "110d7076984880537e95b3f14bbdeb3801c132fc6dfc31a6fd61762fb45205b5"
J = "apps/time-service/src/main/java/lf/sandbox/time"
SPEC = "sandbox://apps/time-service/REMINDERS_SPEC.md"

SOL1_FILES = [J + "/reminder/InMemoryReminderRepository.java",
              J + "/reminder/ReminderController.java",
              J + "/reminder/ReminderRepository.java"]
SOL2_FILES = [J + "/TimeConfig.java", J + "/TimeController.java",
              J + "/reminder/InMemoryReminderRepository.java",
              J + "/reminder/Reminder.java",
              J + "/reminder/ReminderController.java",
              J + "/reminder/ReminderRepository.java"]

OVERRIDES: list[str] = []
_UNDO: list = []   # (module, attr, old_value) to restore the synthetic world


def sha_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def canon_sha(obj) -> str:
    return sha_bytes(json.dumps(obj, sort_keys=True, separators=(",", ":"),
                                ensure_ascii=True).encode())


def load_bundle(name: str, fixed: str) -> dict:
    raw = (FIXTURES / name).read_bytes()
    if sha_bytes(raw) != fixed:
        raise AssertionError("EX5C_REAL_BUNDLE_SHA_MISMATCH:" + name)
    return json.loads(raw)


def setup_paths() -> None:
    dirs = sorted(STAGE_ROOT.glob("pg0*_candidate")) + sorted(STAGE_ROOT.glob("pg1*_candidate"))
    for d in dirs + [STAGE_ROOT / "ex5c_real_chain_candidate"]:
        for sub in ("tests", "tools"):
            p = d / sub
            if p.is_dir() and str(p) not in sys.path:
                sys.path.insert(0, str(p))


def replace_everywhere(module, name: str, new) -> None:
    """Replace a test-side builder in its module AND every alias imported elsewhere."""
    old = getattr(module, name)
    _UNDO.append((module, name, old))
    setattr(module, name, new)
    hits = [module.__name__ + "." + name]
    for mod in list(sys.modules.values()):
        if mod is None or mod is module or not getattr(mod, "__file__", None):
            continue
        if "/tools/" in str(mod.__file__):
            continue  # never touch producers
        for attr, val in list(vars(mod).items()):
            if val is old:
                _UNDO.append((mod, attr, old))
                setattr(mod, attr, new)
                hits.append(mod.__name__ + "." + attr)
    OVERRIDES.append(" <- ".join(hits))


# ---------------------------------------------------------------- PG-04
STRATEGY = {"status": "CANDIDATE_NOT_ADMITTED", "production_authority": False,
            "handoff_allowed": False, "scope_ids": ["EX5C"],
            "requirement_ids": ["REM-C1", "REM-C2", "REM-C3", "REM-C4", "REM-C5",
                                "REM-C6", "REM-C7", "FMT-AOSP-1"],
            "acceptance_ids": ["ACC-C-REPO", "ACC-C-API", "ACC-FMT-CLASS-EQ"]}
STRATEGY["candidate_sha256"] = hashlib.sha256(
    json.dumps(STRATEGY, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
OUTCOMES = [
    {"outcome_id": "REMINDER_DELETE_SEARCH",
     "business_outcome": "Borrar y buscar recordatorios",
     "evidence_ref": SPEC + "#lote-c"},
    {"outcome_id": "FORMAT_STANDARD_AOSP",
     "business_outcome": "Codigo conforme a la norma de formato AOSP",
     "evidence_ref": SPEC + "#norma-de-formato"}]


def _atoms(t4):
    def atom(aid, outcome, reqs, accs, ws, dep=None, **k):
        row = t4.atom(aid, outcome, reqs[0], accs[0], depends=dep, write_scope=ws,
                      scope_id="EX5C", source_ref=SPEC + "#" + aid,
                      shared_contract_refs=["contract://reminders-api-v1"],
                      requirement_ids=reqs, acceptance_ids=accs,
                      bounded_reuse_assessment_ref="sandbox://pilot/worker_v08/derived-context/ex5c")
        row.update(k)
        return row
    return [
        atom("REPO", "REMINDER_DELETE_SEARCH", ["REM-C1", "REM-C2", "REM-C3", "REM-C4"],
             ["ACC-C-REPO"], [J + "/reminder"],
             write_scope_reason="ReminderRepository + InMemoryReminderRepository"),
        atom("API", "REMINDER_DELETE_SEARCH", ["REM-C5", "REM-C6", "REM-C7"],
             ["ACC-C-API"], [J + "/reminder"], dep=["REPO"],
             write_scope_reason="ReminderController"),
        atom("FMT", "FORMAT_STANDARD_AOSP", ["FMT-AOSP-1"], ["ACC-FMT-CLASS-EQ"], [J],
             dep=["API"], risk_level="LOW",
             semantic_rationale="Format-only normalization; javac -g:none classes identical",
             write_scope_reason="All Java under src/main/java per format norm"),
    ]


STANDARDS = [
    {"standard_code": "STD-EX5C-REMINDERS", "source_ref": SPEC + "@" + N,
     "source_sha256": SPEC_SHA_N, "applies_to_write_scopes": [J + "/reminder"]},
    {"standard_code": "STD-EX5C-FORMAT-AOSP", "source_ref": SPEC + "@" + N1,
     "source_sha256": SPEC_SHA_N1, "applies_to_write_scopes": [J]},
]


def _dod_fixtures(t4dod):
    def fixtures():
        partition = t4dod.partition_by_semantic_outcome(**t4dod.args())

        def check(cid, kind, req=None, acc=None, std=None, deps=None):
            row = {"check_id": cid, "kind": kind,
                   "validation_code": "PROGRAMMING_GITHUB_FILE_TEXT_ASSERT_V1",
                   "input_ref": "sandbox://evidence/ex5c#" + cid,
                   "requirement_ids": req or [], "acceptance_ids": acc or []}
            if std:
                row["standard_code"] = std
            if deps is not None:
                row["dependency_ids"] = deps
            return row
        plans = [
            {"solution_id": "SOL-001", "standard_codes": ["STD-EX5C-REMINDERS"],
             "checks": [check("S-REM", "STANDARD", std="STD-EX5C-REMINDERS")]
             + [check(r, "REQUIREMENT", req=[r]) for r in
                ["REM-C1", "REM-C2", "REM-C3", "REM-C4", "REM-C5", "REM-C6", "REM-C7"]]
             + [check("ACC-C-REPO", "ACCEPTANCE", acc=["ACC-C-REPO"]),
                check("ACC-C-API", "ACCEPTANCE", acc=["ACC-C-API"])]},
            {"solution_id": "SOL-002", "standard_codes": ["STD-EX5C-FORMAT-AOSP"],
             "checks": [check("S-FMT", "STANDARD", std="STD-EX5C-FORMAT-AOSP"),
                        check("FMT-AOSP-1", "REQUIREMENT", req=["FMT-AOSP-1"]),
                        check("ACC-FMT-CLASS-EQ", "ACCEPTANCE", acc=["ACC-FMT-CLASS-EQ"]),
                        check("D-SOL-001", "DEPENDENCY", deps=["SOL-001"])]},
        ]
        return {"partition": partition, "standards_catalog_version": "EX5C-SPEC-" + N1[:12],
                "standards": copy.deepcopy(STANDARDS),
                "validation_registry": [{"validation_code": "PROGRAMMING_GITHUB_FILE_TEXT_ASSERT_V1",
                                         "status": "ACTIVE",
                                         "source_ref": "fixture://registry/current"}],
                "solution_plans": plans}
    return fixtures



# ---------------------------------------------------------------- evidence runs
RUN_WORKER = "https://github.com/paulozterra/lf-programming-sandbox/actions/runs/42284754122"
RUN_V1 = "https://github.com/paulozterra/lf-programming-sandbox/actions/runs/42296841499"
RUN_V2 = "https://github.com/paulozterra/lf-programming-sandbox/actions/runs/42304928081"
RUN_V3 = "https://github.com/paulozterra/lf-programming-sandbox/actions/runs/42333657311"
V2_SHA = "0988de2e39f5139596d05c3cbfcbe8c8998c753cdb009414e5b38da65172217b"
SOL_FILES = {"SOL-001": SOL1_FILES, "SOL-002": SOL2_FILES}
SOL_HEAD = {"SOL-001": N, "SOL-002": N1}
SOL_DIFF = {"SOL-001": DIFF_SOL1, "SOL-002": DIFF_SOL2}


def gh_blob(path, commit):
    return "github://" + REPO + "/blob/" + commit + "/" + path


# ---------------------------------------------------------------- PG-05
def _pg05_overrides(t5):
    orig_exit_fixture = t5.exit_fixture

    def pg04_real_exit():
        inputs = orig_exit_fixture()
        inputs["target_binding"] = {
            "repo_full_name": REPO, "base_head_sha": BASE,
            "target_binding_ref": "github://" + REPO + "/commit/" + BASE}
        return t5.assemble_pg04_exit_candidate(**inputs)

    def resources(exit_obj):
        result = []
        for sol in exit_obj["solutions"]:
            sid = sol["solution_id"]
            groups = [{"scope_token": token,
                       "derivation_ref": "sandbox://pilot/worker_v08/tasks.json#ex5c/write_scope",
                       "resources": [{"kind": "REPO_PATH", "identity": f,
                                      "source_ref": gh_blob(f, BASE if f != J + "/reminder/Reminder.java" or True else BASE)}
                                     for f in SOL_FILES[sid] if f.startswith(token + "/")]}
                      for token in sol["write_scope_candidates"]]
            shared = [{"contract_ref": c, "derivation_ref": SPEC + "#lote-c",
                       "resource": {"kind": "REPO_PATH",
                                    "identity": "apps/time-service/REMINDERS_SPEC.md",
                                    "source_ref": gh_blob("apps/time-service/REMINDERS_SPEC.md", BASE)}}
                      for c in sol["shared_contract_refs"]]
            result.append({"solution_id": sid, "resolved_scopes": groups,
                           "shared_read_refs": shared,
                           "l3_structure_ref": "github://" + REPO + "/tree/" + BASE + "/apps/time-service"})
        return result

    def changes(c1, c2):
        out = []
        for sol in c2["solution_scopes"]:
            sid = sol["solution_id"]
            out.append({
                "solution_id": sid,
                "source_head_sha": c1["target_binding"]["base_head_sha"],
                "proposal_ref": "github://" + REPO + "/commit/" + SOL_HEAD[sid],
                "changes": [{"operation": "MODIFY", "resource": copy.deepcopy(entry),
                             "change_ref": "github://" + REPO + "/commit/" + SOL_HEAD[sid]
                                           + "#" + entry.get("identity", "")}
                            for entry in sol["write_resource_keys"]]})
        return out

    def manifest(exit_obj, c1, c2, c3, c4):
        parts = dict(pg04_exit=exit_obj, pg05_c1=c1, pg05_c2=c2, pg05_c3=c3, pg05_c4=c4)
        return dict(source_head_sha=BASE,
                    **{k: {"ref": "ex5c://pg05/" + k, "sha256": v["candidate_sha256"]}
                       for k, v in parts.items()})
    return pg04_real_exit, resources, changes, manifest


# ---------------------------------------------------------------- PG-06
def _v2_baseline():
    v2 = load_bundle("lf-evidence-bundle-v2.json", V2_SHA)
    snap = [x for x in v2["snapshots"] if x["label"] == "baseline"]
    if len(snap) != 1 or snap[0]["commit"] != BASE:
        raise AssertionError("EX5C_V2_BASELINE_NOT_BASE")
    return snap[0]


def _pg06_overrides(t6):
    def toolchain(exit_obj):
        target = exit_obj["target_binding"]
        sol_ids = [x["solution_id"] for x in exit_obj["solutions"]]
        catalog = {
            "schema_version": "PG06_TOOLCHAIN_CATALOG_SELECTION_CANDIDATE_V1",
            "catalog_ref": gh_blob("apps/time-service/pom.xml", BASE),
            "catalog_sha256": canon_sha({"java": "21", "maven": "3", "spring-boot": "4.1.1"}),
            "profile_ref": "stack://java21-maven-spring-boot",
            "target_repo": target["repo_full_name"],
            "target_base_head_sha": target["base_head_sha"],
            "requirements": [{"tool_id": "java", "component": "backend",
                              "version_exact": "21",
                              "source_ref": gh_blob("apps/time-service/pom.xml", BASE),
                              "applies_to_solution_ids": sol_ids}]}
        observed = {
            "schema_version": "PG06_TOOLCHAIN_ENVIRONMENT_OBSERVATION_CANDIDATE_V1",
            "environment_ref": RUN_V2,
            "observed_target_repo": target["repo_full_name"],
            "observed_base_head_sha": target["base_head_sha"],
            "observations": [{"tool_id": "java", "reported_version": "21",
                              "availability": "AVAILABLE",
                              "evidence_ref": RUN_V2 + "#javac-version"}]}
        return catalog, observed

    def baseline(exit_obj):
        target = exit_obj["target_binding"]
        snap = _v2_baseline()
        fmt, jav = snap["formatter"], snap["javac"]
        fmt_refs = sorted({"EX5C-GJF-BASE-" + canon_sha(f)[:24] for f in fmt["findings"]})
        rows = []
        for sol in exit_obj["solutions"]:
            sid = sol["solution_id"]
            for kind, ex, refs in (("BUILD", jav["execution"], []),
                                   ("LINT", fmt["execution"], fmt_refs)):
                rows.append({
                    "command_id": sid + "-" + kind, "solution_id": sid, "kind": kind,
                    "command_ref": RUN_V2 + "#baseline-" + kind.lower(),
                    "command_sha256": canon_sha(ex["argv"]),
                    "result": "PASS" if ex["exit_code"] == 0 else "FAIL",
                    "exit_code": ex["exit_code"],
                    "stdout_sha256": ex["stdout"]["sha256"],
                    "stderr_sha256": ex["stderr"]["sha256"],
                    "violation_refs": refs if ex["exit_code"] != 0 else [],
                    "execution_receipt_ref": RUN_V2 + "#" + sid + "-" + kind})
        return {"schema_version": "PG06_UNCHANGED_TARGET_BASELINE_OBSERVATION_CANDIDATE_V1",
                "target_repo": target["repo_full_name"], "base_head_sha": target["base_head_sha"],
                "observation_ref": RUN_V2 + "#baseline-" + BASE,
                "execution_environment_ref": RUN_V2,
                "unchanged_target_claim": True, "command_results": rows}
    return toolchain, baseline


# ---------------------------------------------------------------- PG-07
TASKS_JSON = "sandbox://pilot/worker_v08/tasks.json@" + N + "#ex5c"
PRICING = "sandbox://pilot/worker_v08/cost_adapter/pricing_v1.json@2026-11-05-owner-assumption"
RULES = {"SOL-001": "STD-EX5C-REMINDERS", "SOL-002": "STD-EX5C-FORMAT-AOSP"}


def worker_cost():
    import base64
    v1 = load_bundle("lf-evidence-bundle-v1.json", V1_SHA)
    raw = base64.b64decode(v1["worker"]["files"]["cost.json"]["content_base64"])
    return v1, json.loads(raw)


def _pg07_overrides(t7):
    def make_c1():
        upstream = t7.pg06_chain()
        exit_obj = upstream["exit"]
        sid = [x["solution_id"] for x in exit_obj["solutions"]]
        run = {"run_ref": RUN_WORKER, "provider": "anthropic", "model_id": "claude-sonnet-5-5",
               "model_profile_ref": "sandbox://pilot/worker_v08/anthropic_structured_client.py",
               "pricing_ref": PRICING, "pricing_currency": "USD",
               "input_price_per_million": "2.00", "output_price_per_million": "10.00",
               "cached_input_price_per_million": "2.00",  # table has no cache discount; 0 cached tokens used
               "lane_executor_ref": "sandbox://.github/workflows/worker-pilot.yml",
               "worker_contract_ref": "github://cristhianlujan/programming-agent@298307e2f9cac72abfde2b181f3554b0e28bad24",
               "worker_version": "0.8"}
        tasks = [{"solution_id": x, "agent_task_id": i + 1,
                  "task_binding_ref": TASKS_JSON if x == "SOL-001" else RUN_V3 + "#format-remediation",
                  "base_head_sha": exit_obj["target_binding"]["base_head_sha"],
                  "source_snapshot_sha256": SPEC_SHA_N if x == "SOL-001" else SPEC_SHA_N1,
                  "worker_spec_ref": TASKS_JSON if x == "SOL-001" else SPEC + "@" + N1 + "#norma-de-formato",
                  "task_execution_authority_ref": "ex5c://authority/owner-approved-sandbox-unverified"}
                 for i, x in enumerate(sid)]
        c1 = t7.prepare_pg07_c1(pg05_exit=exit_obj, pg06_c5=upstream["c5"],
                                run_binding=run, worker_task_bindings=tasks)
        return upstream, run, tasks, c1

    def worker_spec(task, base):
        sid = task["solution_id"]
        files = SOL_FILES[sid]
        return {"schema_version": 2, "task_id": "T-" + str(task["agent_task_id"]),
                "objective": ("Implement REM-C1 through REM-C7 by editing exactly three existing reminder files."
                              if sid == "SOL-001" else
                              "Apply google-java-format 1.30.0 --aosp to src/main/java; classes must stay identical."),
                "expected_change": "small patch" if sid == "SOL-001" else "format-only patch",
                "human_story": OUTCOMES[0 if sid == "SOL-001" else 1]["business_outcome"],
                "functional_contract": {"acceptance_criteria": (
                    ["REM-C1", "REM-C2", "REM-C3", "REM-C4", "REM-C5", "REM-C6", "REM-C7"]
                    if sid == "SOL-001" else ["FMT-AOSP-1", "javac -g:none classes identical"])},
                "scope": {"in_scope": files, "out_of_scope": ["apps/time-service/src/test/**"],
                          "must_not_change": ["apps/time-service/pom.xml"]},
                "cases": [], "dependency_resolution": {},
                "dependency_task_ids": [] if sid == "SOL-001" else ["T-1"],
                "required_tests": ["mvn test"], "required_evidence": ["diff", "maven", "holdout"],
                "blocked_if": ["write outside scope"], "base_head_sha": base,
                "source_snapshot_sha256": task["source_snapshot_sha256"],
                "context_path_patterns": ["apps/time-service/**"],
                "write_path_patterns": files,
                "protected_path_patterns": ["apps/time-service/src/test/**", "apps/time-service/pom.xml"],
                "files_expected": files, "platform_refs": [], "interface_refs": [],
                "acceptance_commands": ["mvn -B -q -f apps/time-service/pom.xml test"],
                "max_attempts": 1, "max_patch_bytes": 32000, "max_changed_files": len(files),
                "max_context_bytes": 240000, "allow_deletions": False}

    def make_chain():
        upstream, run, tasks, c1 = t7.make_c1()
        base = upstream["exit"]["target_binding"]["base_head_sha"]
        specs = [{"solution_id": t["solution_id"], "function_result_ref": t["worker_spec_ref"],
                  "worker_spec": t7.worker_spec(t, base),
                  "source_snapshot_sha256": t["source_snapshot_sha256"]} for t in tasks]
        oracle = [{"solution_id": t["solution_id"],
                   "verifier_only_ref": ("ex5c://holdout/verifier-only/" + t["solution_id"]),
                   "oracle_subject_sha256": ("2bf9c94f0c6db7bd660af7096b61cdb63715f0933ac24985c8d7e5b973d930a8"
                                             if t["solution_id"] == "SOL-001" else
                                             canon_sha({"class_equivalence": "javac -g:none", "v3": V3_SHA})),
                   "access_policy": "VERIFIER_ONLY"} for t in tasks]
        c2 = t7.prepare_pg07_c2(pg07_c1=c1, worker_spec_projections=specs, verifier_oracle_bindings=oracle)
        profile = {"profile_ref": run["model_profile_ref"], "provider": run["provider"],
                   "model_id": run["model_id"], "context_window_tokens": 200000,
                   "reserved_output_tokens": 16000, "reserved_system_tokens": 4000,
                   "safety_margin_tokens": 4000,
                   "token_estimator_ref": "sandbox://pilot/worker_v08/budget_gate.py",
                   "budget_policy_ref": "sandbox://pilot/worker_v08/derive_context.py#LOTE_DEMASIADO_GRANDE",
                   "budget_capability": "CONTEXT_BUDGET_GOVERNANCE"}
        selections = []
        for t in tasks:
            x = t["solution_id"]; rule = RULES[x]
            selections.append({"solution_id": x, "mandatory_ref_ids": [rule],
                "reference_catalog": [{"ref_id": rule, "source_ref": STANDARDS[0 if x == "SOL-001" else 1]["source_ref"],
                    "source_sha256": STANDARDS[0 if x == "SOL-001" else 1]["source_sha256"],
                    "kind": "STD", "material": True, "delivery": "EAGER",
                    "estimated_tokens": 1200, "estimated_bytes": 4800, "role": "REQUIRED"}],
                "stable_cache_refs": [], "token_estimate_ref": RUN_WORKER + "#derived-context",
                "estimated_static_tokens": 1200, "estimated_dynamic_tokens": 0,
                "estimated_jit_tokens": 0, "estimated_context_bytes": 4800})
        c3 = t7.prepare_pg07_c3(pg07_c1=c1, pg07_c2=c2, model_context_profile=profile,
                                task_context_selections=selections)
        catalog = {"catalog_ref": SPEC + "@" + N1, "catalog_sha256": SPEC_SHA_N1,
                   "catalog_version": "EX5C-SPEC-" + N1[:12], "selection_ref": TASKS_JSON,
                   "entries": [{"rule_id": RULES[x], "kind": "STD",
                                "source_ref": STANDARDS[i]["source_ref"],
                                "source_sha256": STANDARDS[i]["source_sha256"],
                                "version": ["N", "N1"][i],
                                "ok_example_ref": SPEC + "#" + RULES[x] + "-ok",
                                "no_example_ref": SPEC + "#" + RULES[x] + "-no",
                                "applies_to_solution_ids": [x]}
                               for i, x in enumerate(["SOL-001", "SOL-002"])]}
        plans = [{"solution_id": t["solution_id"], "required_rule_ids": [RULES[t["solution_id"]]],
                  "contract_first_ref": SPEC + "#lote-c",
                  "contract_first_rule_id": RULES[t["solution_id"]],
                  "formatter_commands": [{"command_id": "fmt-" + t["solution_id"],
                      "formatter_tool_ref": "google-java-format-1.30.0-all-deps.jar@f2239a8a234a240a54fdff7809d4b3e66702c21f590c77a0b6cf7b20c829e95a",
                      "command_ref": RUN_V3 + "#aosp", "scope_ref": J,
                      "expected_artifact_ref": RUN_V3 + "#candidate-format-check"}],
                  "formatter_plan_ref": SPEC + "@" + N1 + "#norma-de-formato"} for t in tasks]
        c4 = t7.prepare_pg07_c4(pg07_c1=c1, pg07_c2=c2, pg07_c3=c3,
                                standards_catalog_selection=catalog, solution_policy_plans=plans)
        c5 = t7.prepare_pg07_c5(pg07_c2=c2, pg07_c3=c3, pg07_c4=c4, iteration_proposals=[])
        v1, cost = worker_cost()
        evidence = []
        for t in tasks:
            x = t["solution_id"]
            evidence.append({"solution_id": x, "batch_id": "ex5c-" + x,
                "execution_ref": RUN_WORKER if x == "SOL-001" else RUN_V3,
                "context_pack_ref": RUN_WORKER + "#derived-context",
                "candidate_head_sha": SOL_HEAD[x],
                "diff_ref": "github://" + REPO + "/compare/" + (BASE if x == "SOL-001" else N) + "..." + SOL_HEAD[x],
                "diff_sha256": SOL_DIFF[x], "changed_paths": SOL_FILES[x],
                "input_refs": [TASKS_JSON if x == "SOL-001" else SPEC + "@" + N1],
                "applied_rule_ids": [RULES[x]],
                "formatter_receipt_refs": [RUN_V3 + "#candidate-format-check"],
                "worker_receipt_ref": (RUN_WORKER + "#verified-worker-receipt.json") if x == "SOL-001" else RUN_V3,
                "worker_receipt_sha256": (v1["worker"]["files"]["verified-worker-receipt.json"]["sha256"]
                                          if x == "SOL-001" else V3_SHA),
                "provider_usage_receipt_refs": ([RUN_WORKER + "#cost.json"] if x == "SOL-001"
                                                else [RUN_V3 + "#no-model-call"])})
        c6 = t7.prepare_pg07_c6(pg07_c1=c1, pg07_c2=c2, pg07_c3=c3, pg07_c4=c4,
                                pg07_c5=c5, worker_batch_evidence=evidence)
        return locals()
    return make_c1, worker_spec, make_chain


# ---------------------------------------------------------------- PG-08
def _receipts():
    """Real command receipts per solution (SOL-001 at N, SOL-002 at N1)."""
    v1, _ = worker_cost()
    v2 = load_bundle("lf-evidence-bundle-v2.json", V2_SHA)
    v3 = load_bundle("lf-evidence-bundle-v3.json", V3_SHA)
    cand = [x for x in v2["snapshots"] if x["label"] == "candidate"]
    if len(cand) != 1 or cand[0]["commit"] != N:
        raise AssertionError("EX5C_V2_CANDIDATE_NOT_N")
    c = cand[0]
    ce = v3["class_equivalence"]
    return {
        "SOL-001": {"run": RUN_V1, "build": v1["execution"]["maven"], "tests": v1["execution"]["maven"],
                    "smoke": v1["execution"]["smoke"], "format": c["formatter"]["execution"],
                    "format_findings": c["formatter"]["findings"], "format_tool": "1.30.0 (google default)",
                    "lint": c["javac"]["execution"], "lint_findings": c["javac"]["findings"],
                    "typecheck": c["javac"]["execution"], "fmt_run": RUN_V2},
        "SOL-002": {"run": RUN_V3, "build": v3["execution"]["maven_verify"],
                    "tests": v3["execution"]["maven_verify"], "smoke": v3["execution"]["smoke"],
                    "format": v3["execution"]["candidate_format_check"],
                    "format_findings": v3["execution"]["candidate_format_findings"],
                    "format_tool": "1.30.0 --aosp",
                    "lint": ce["candidate_compile_receipt"], "lint_findings": ce["candidate_lint_findings"],
                    "typecheck": ce["candidate_compile_receipt"], "fmt_run": RUN_V3},
    }


def _cmd(cid, ref, tool, version, ex, extra=None):
    row = {"command_id": cid, "command_ref": ref, "tool_name": tool, "tool_version": version,
           "config_sha256": canon_sha(ex["argv"]), "execution_receipt_ref": ref,
           "stdout_sha256": ex["stdout"]["sha256"], "stderr_sha256": ex["stderr"]["sha256"],
           "result": "PASS" if ex["exit_code"] == 0 else "FAIL", "exit_code": ex["exit_code"]}
    if extra:
        row.update(extra)
    return row


def _na(kind, reason, keys):
    row = {k: None for k in keys}
    row.update({"kind": kind, "applicability": "NOT_APPLICABLE",
                "applicability_ref": "ex5c://not-applicable/" + reason})
    return row


def _pg08_make_chain(t8):
    def make_chain():
        upstream = t8.pg07_chain()
        source = upstream["c6"]
        R = _receipts()

        def base(item):
            return t8.reported_base(source, item)

        def gjf_findings(sid):
            out = []
            for f in R[sid]["format_findings"]:
                out.append({"violation_ref": "EX5C-GJF-" + sid + "-" + canon_sha(f)[:24],
                            "severity": "BLOCK", "rule_id": "GOOGLE_JAVA_FORMAT_1_30_0",
                            "path": f["path"], "line": f.get("line_start") or f.get("line"),
                            "scope": "DIFF"})
            return out
        build = [{**base(x), "executor_result_ref": R[x["solution_id"]]["run"],
                  "commands": [_cmd("BUILD", R[x["solution_id"]]["run"] + "#maven", "mvn", "JDK21",
                                    R[x["solution_id"]]["build"])]} for x in source["batches"]]
        c1 = t8.prepare_pg08_c1(pg07_c6=source, build_observations=build)
        lint = [{**base(x), "checks": [
            _cmd("FORMAT", R[x["solution_id"]]["fmt_run"] + "#format", "google-java-format",
                 R[x["solution_id"]]["format_tool"], R[x["solution_id"]]["format"],
                 {"kind": "FORMAT", "findings": gjf_findings(x["solution_id"])}),
            _cmd("LINT", R[x["solution_id"]]["fmt_run"] + "#javac-xlint", "javac", "21 -Xlint:all",
                 R[x["solution_id"]]["lint"], {"kind": "LINT", "findings": []})]}
            for x in source["batches"]]
        baseline = upstream["upstream"]["c4"]
        c2 = t8.prepare_pg08_c2(pg06_c4=baseline, pg08_c1=c1, lint_observations=lint)
        types = [{**base(x), "required_profiles": ["JAVAC"],
                  "checks": [_cmd("JAVAC", R[x["solution_id"]]["fmt_run"] + "#javac", "javac", "21",
                                  R[x["solution_id"]]["typecheck"],
                                  {"profile": "JAVAC", "diagnostic_refs": []})]}
                 for x in source["batches"]]
        c3 = t8.prepare_pg08_c3(pg08_c1=c1, pg08_c2=c2, typecheck_observations=types)
        tests = [{**base(x), "flyway_applicability": "NOT_APPLICABLE",
                  "flyway_applicability_ref": "ex5c://not-applicable/no-database-in-time-service",
                  "local_pg_isolation_ref": None,
                  "checks": [_cmd("UNIT_FOCAL", R[x["solution_id"]]["run"] + "#maven-test", "mvn", "JDK21",
                                  R[x["solution_id"]]["tests"],
                                  {"kind": "UNIT_FOCAL", "diagnostic_refs": [],
                                   "runtime_target_ref": R[x["solution_id"]]["run"]}),
                             _cmd("SMOKE", R[x["solution_id"]]["run"] + "#smoke", "java -jar + http", "JDK21",
                                  {**R[x["solution_id"]]["smoke"], "exit_code": 0},
                                  {"kind": "SMOKE", "diagnostic_refs": [],
                                   "runtime_target_ref": R[x["solution_id"]]["run"] + "#jar"})]}
                 for x in source["batches"]]
        c4 = t8.prepare_pg08_c4(pg08_c1=c1, pg08_c3=c3, test_observations=tests)
        ckeys = ("command_id", "command_ref", "tool_name", "tool_version", "config_sha256",
                 "baseline_contract_sha256", "candidate_contract_sha256", "execution_receipt_ref",
                 "stdout_sha256", "stderr_sha256", "result", "exit_code")
        contracts = [{**base(x), "checks": [dict(_na(k, "no-openapi-or-db-catalog-in-time-service", ckeys),
                                                 findings=[])
                                            for k in ("SPECTRAL_OPENAPI", "OASDIFF_BREAKING", "MIGRATED_DB_CATALOG")]}
                     for x in source["batches"]]
        c5 = t8.prepare_pg08_c5(pg08_c1=c1, pg08_c4=c4, contract_observations=contracts)
        c6 = t8.prepare_pg08_c6(pg08_c1=c1, pg08_c2=c2, pg08_c3=c3, pg08_c4=c4, pg08_c5=c5)
        akeys = ("command_id", "command_ref", "tool_name", "tool_version", "config_sha256",
                 "execution_receipt_ref", "stdout_sha256", "stderr_sha256", "result", "exit_code")
        arch = [{**base(x), "architecture_profile_ref": SPEC + "#lote-c",
                 "checks": [dict(_na(k, "no-modulith-or-archunit-configured", akeys), findings=[])
                            for k in ("SPRING_MODULITH_VERIFY", "ARCHUNIT")]}
                for x in source["batches"]]
        c7 = t8.prepare_pg08_c7(pg08_c1=c1, pg08_c6=c6, architecture_observations=arch)
        ikeys = ("command_id", "command_ref", "tool_name", "tool_version", "config_sha256",
                 "stdout_sha256", "stderr_sha256", "execution_receipt_ref", "result", "exit_code",
                 "execution_target_type", "execution_target_ref")
        kinds = ("TERRAFORM_FMT", "TERRAFORM_VALIDATE", "IAC_LINT", "FLOCI_PLAN", "FLOCI_APPLY",
                 "CONTAINER_BUILD", "DOCKER_COMPOSE_UP", "CONTAINER_HEALTHCHECK")
        iac = [{**base(x), "iac_profile_ref": "github://" + REPO + "/tree/" + SOL_HEAD[x["solution_id"]] + "/apps/time-service",
                "isolation_policy_ref": "ex5c://not-applicable/no-iac",
                "checks": [dict(_na(k, "no-dockerfile-compose-or-iac-in-apps-time-service", ikeys),
                                finding_refs=[]) for k in kinds]}
               for x in source["batches"]]
        c8 = t8.prepare_pg08_c8(pg08_c1=c1, pg08_c7=c7, infrastructure_observations=iac)
        final = t8.consolidate_pg08_c6_c7_c8(pg08_c6=c6, pg08_c7=c7, pg08_c8=c8)
        return locals()
    return make_chain


# ---------------------------------------------------------------- PG-08 executor mode / PG-09
MODE = {"SOL-001": "WORKER_API",   # Anthropic API through Worker v0.8
        "SOL-002": "GPT_NATIVE"}   # GPT-orchestrated deterministic formatter, zero API calls
OWNER_ATTEMPT = "LF-OWNER-EX5C-ATTEMPT-1-20261106"
OWNER_FORMAT = "LF-OWNER-EX5C-FORMAT-REMEDIATION-20261106"


def _reported_base(t8):
    def reported_base(pg07, item):
        return dict(solution_id=item["solution_id"], executor_mode=MODE[item["solution_id"]],
                    candidate_head_sha=item["candidate_head_sha_reported"],
                    diff_sha256=item["diff_sha256_reported"], **t8.identity(pg07))
    return reported_base


def _pg09_overrides(t9):
    def policy():
        return {"policy_ref": "sandbox://pilot/worker_v08/budget_gate.py#ex5c",
                "currency": "USD", "request_budget": "0.35", "batch_budget": "0.35",
                "max_attempts_per_solution": 1,
                "existing_worker_limit_ref": "sandbox://pilot/worker_v08/budget_gate.py#MODEL_ATTEMPT_LIMITS"}

    def cost_observations(x, cost=None, mode=None, attempts=1):
        # The synthetic chain passes cost="79.99"/mode/attempts positionally; the
        # real world ignores those caller values: cost, mode and attempts come
        # only from the Worker cost.json and MODE.
        cost, mode, attempts = None, None, 1
        _, c = worker_cost()
        a = c["attempts"][0]
        rows = []
        for sol in x["tasks"]:
            sid = sol["solution_id"]
            calls = []
            if sid == "SOL-001":
                calls = [{"call_ref": RUN_WORKER + "#attempt-1",
                          "usage_receipt_ref": RUN_WORKER + "#cost.json",
                          "usage_authentication_ref": None, "provider": c["model_provider"],
                          "model_id": c["model"], "reported_cost": cost or a["estimated_usd"],
                          "currency": c["currency"], "input_tokens": a["input_tokens"],
                          "output_tokens": a["output_tokens"], "cached_input_tokens": 0}]
            rows.append({"solution_id": sid, "executor_mode": mode or MODE[sid],
                         "batch_id": "ex5c-" + sid, "attempts_used": attempts,
                         "attempt_limit_source_ref": "sandbox://pilot/worker_v08/budget_gate.py#MODEL_ATTEMPT_LIMITS",
                         "calls": calls})
        return rows

    def context(c1):
        return [{"solution_id": r["solution_id"], "run_ref": c1["run_ref"],
                 "owner_decision_ref": "ex5c://owner-decision/" + (OWNER_ATTEMPT if r["solution_id"] == "SOL-001" else OWNER_FORMAT),
                 "diagnostic_evidence_refs": [RUN_WORKER + "#cost.json" if r["solution_id"] == "SOL-001" else RUN_V3]}
                for r in c1["solutions"]]
    return policy, cost_observations, context


# ---------------------------------------------------------------- PG-10 (real conflict)
CONFLICT = "CONFLICT-EX5C-FMT-001"
QUESTION_KEY = "REM-C7-VS-STD-EX5C-FORMAT-AOSP"
DECISION_THREAD = "ex5c://chat/claude-2026-11-06-format-findings"


def _pg10_overrides(t10):
    def conflicts(pg09):
        ids = [x["solution_id"] for x in pg09["c4"]["solutions"]]
        first = ids[0]
        return ([{"solution_id": sid, "conflicts": ([{
            "conflict_id": CONFLICT, "classification": "REQUIREMENT_VS_STANDARD",
            "issue_kind": "CONFLICT",
            "requirement_ref": SPEC + "@" + N + "#REM-C7",
            "standard_ref": STANDARDS[1]["source_ref"] + "#norma-de-formato",
            "existing_contract_ref": None, "reuse_as_is_ref": None,
            "evidence_refs": [RUN_V2 + "#candidate-format-findings", SPEC + "@" + N1 + "#norma-de-formato"],
            "diagnosis_ref": DECISION_THREAD}] if sid == first else [])} for sid in ids], first)

    def routes(c2, prior=False):
        rows = []
        for sol in c2["solutions"]:
            issues = [{"conflict_id": a["conflict_id"], "issue_class": "HUMAN_DECISION",
                       "exact_query_ref": DECISION_THREAD + "#question",
                       "resolver_ref": "ex5c://owner/Paulo",
                       "prior_decision_ref": ("ex5c://owner-decision/" + OWNER_FORMAT) if prior else None,
                       "prior_decision_current_verified": False}
                      for a in sol["conflict_actions"]]
            rows.append({"solution_id": sol["solution_id"], "issues": issues})
        return rows

    def packets(c3, include=True):
        rows = []
        for sol in c3["solutions"]:
            entries = []
            for r in sol["routes"]:
                if include and r["route_candidate"] == "HUMAN_DECISION_PACKET_CANDIDATE":
                    entries.append({
                        "conflict_id": r["conflict_id"],
                        "question": "Los 29 hallazgos de google-java-format, ¿se aceptan con waiver o se reparan?",
                        "options": [
                            {"option_id": "KEEP", "description": "Aceptar con waiver; sin cambio de codigo",
                             "consequence": "Deuda de formato sin norma"},
                            {"option_id": "CHANGE", "description": "Fijar norma AOSP y reparar con ciclo N+1 solo-formato",
                             "consequence": "Nuevo candidato bc74940 con clases identicas"}],
                        "recommended_option_id": "CHANGE",
                        "recommendation_reason": "Hallazgos cosmeticos; la reparacion mecanica es verificable byte a byte",
                        "risk_if_undecided": "PG-08 C2 queda con REPORTED_NEW_BLOCKERS",
                        "source_refs": [RUN_V2 + "#candidate-format-findings", SPEC + "@" + N1],
                        "affected_scope_refs": [J],
                        "resume_condition": "Decision registrada " + OWNER_FORMAT + " y v3 con clases identicas",
                        "ready_unaffected_scope_refs": [J + "/reminder"]})
            rows.append({"solution_id": sol["solution_id"], "packets": entries})
        return rows

    def ledger_for(x, state="RESOLVED"):
        return [{"solution_id": x["sid"], "conflict_id": CONFLICT,
                 "decision_ref": "ex5c://owner-decision/" + OWNER_FORMAT,
                 "decision_state": state, "decision_question_key": QUESTION_KEY,
                 "currentness_ref": RUN_V3}]

    def question(x):
        return [{"solution_id": x["sid"], "conflict_id": CONFLICT,
                 "decision_question_key": QUESTION_KEY}]
    return conflicts, routes, packets, ledger_for, question


# ---------------------------------------------------------------- PG-11 (real diff, hunks, review)
import base64 as _b64
import re as _re

_HUNK = _re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
REVIEWER = "anthropic:claude-opus-5-5-verifier"
BUILDER = {"SOL-001": "anthropic:claude-sonnet-5-5-worker-v0.8",
           "SOL-002": "tool:google-java-format-1.30.0-aosp(gpt-orchestrated)"}


def parse_hunks(diff_text, prefix):
    out, path, cur = [], None, None
    for line in diff_text.splitlines(keepends=True):
        if line.startswith("+++ b/"):
            path = line[6:].strip()
            continue
        m = _HUNK.match(line)
        if m:
            cur = {"path": path, "old_start": int(m.group(1)), "old_count": int(m.group(2) or 1),
                   "new_start": int(m.group(3)), "new_count": int(m.group(4) or 1),
                   "header": line.rstrip("\n"), "body": [line]}
            out.append(cur)
        elif cur is not None and not line.startswith("diff --git"):
            cur["body"].append(line)
        elif line.startswith("diff --git"):
            cur = None
    rows = []
    for i, h in enumerate(out, 1):
        rows.append({"hunk_id": prefix + "-" + str(i), "path": h["path"],
                     "old_start": h["old_start"], "old_count": h["old_count"],
                     "new_start": h["new_start"], "new_count": h["new_count"],
                     "content_sha256": sha_bytes("".join(h["body"]).encode()),
                     "header": h["header"]})
    return rows


def real_hunks():
    v1, _ = worker_cost()
    v3 = load_bundle("lf-evidence-bundle-v3.json", V3_SHA)
    d1 = _b64.b64decode(v1["patch"]["text_base64"]).decode()
    d3 = _b64.b64decode(v3["diff"]["content_base64"]).decode()
    if sha_bytes(d1.encode()) != DIFF_SOL1 or sha_bytes(d3.encode()) != DIFF_SOL2:
        raise AssertionError("EX5C_DIFF_SHA_MISMATCH")
    h1 = parse_hunks(d1, "SOL-001-H")
    reqs = [h["requirements"] for h in v1["patch"]["hunks"]]
    if len(h1) != len(reqs):
        raise AssertionError("EX5C_SOL1_HUNK_COUNT_MISMATCH")
    for h, r in zip(h1, reqs):
        h["requirements"] = r
        h["solution_id"] = "SOL-001"
        h["header_ref"] = "github://" + REPO + "/compare/" + BASE + "..." + N + "#" + h["hunk_id"]
    h3 = parse_hunks(d3, "SOL-002-H")
    for h in h3:
        h["requirements"] = ["FMT-AOSP-1"]
        h["solution_id"] = "SOL-002"
        h["header_ref"] = "github://" + REPO + "/compare/" + N + "..." + N1 + "#" + h["hunk_id"]
    return h1 + h3


def _pg11_fixture(t11):
    def fixture():
        all_files = sorted(set(SOL1_FILES) | set(SOL2_FILES))
        diff = [{"path": f, "change_type": "MODIFIED", "old_path": None} for f in all_files]
        owner = {f: ("SOL-001" if f in SOL1_FILES else "SOL-002") for f in all_files}
        scope = [{**d, "scope_ref": "ex5c://scope/" + owner[d["path"]],
                  "requirement_ref": SPEC + "#" + ("REM-C7" if owner[d["path"]] == "SOL-001" else "FMT-AOSP-1"),
                  "batch_ref": "ex5c://batch/ex5c-" + owner[d["path"]]} for d in diff]
        c1 = t11.prepare_pg11_c1(expected_base_sha=BASE, expected_head_sha=N1,
             declared_diff=diff, authorized_scope=scope, residue_observations=[],
             dependency_observations=[],
             compatibility_observations=[{"surface": "MODULE_CONTRACT",
                 "contract_ref": SPEC + "#lote-a-lote-b", "baseline_ref": gh_blob("apps/time-service/REMINDERS_SPEC.md", BASE),
                 "evidence_ref": RUN_V3 + "#maven-verify-13-tests", "compatible_reported": True}])
        term = [{"path": J + "/reminder/ReminderRepository.java",
                 "symbol_ref": gh_blob(J + "/reminder/ReminderRepository.java", N1) + "#findByTextContaining",
                 "kind": "DOMAIN_IDENTIFIER", "literal_value": "findByTextContaining",
                 "source_ref": SPEC + "@" + N + "#REM-C1", "term_ids": ["REM-C1"],
                 "term_exists_reported": True, "term_matches_reported": True,
                 "literal_match_reported": True, "neighbor_match_reported": True}]
        c2 = t11.prepare_pg11_c2(pg11_c1=c1, declared_changed_paths=all_files,
             terminology_observations=term,
             glossary_snapshot_ref=SPEC + "@" + N1, catalog_snapshot_ref=SPEC + "@" + N1,
             messages_snapshot_ref=SPEC + "@" + N1 + "#REM-B2",
             neighbor_baseline_ref=gh_blob(J, BASE))
        sup, waivers = [], []   # owner chose CHANGE (repair), not a waiver
        c3 = t11.prepare_pg11_c3(pg11_c2=c2, suppression_observations=sup,
            waiver_observations=waivers, std_gen_05_source_ref=SPEC + "@" + N1 + "#norma-de-formato")
        hk = real_hunks()
        traces = []
        for f in all_files:
            links = []
            for h in hk:
                if h["path"] != f:
                    continue
                for r in h["requirements"]:
                    links.append({"requirement_ref": SPEC + "#" + r,
                                  "batch_ref": "ex5c://batch/ex5c-" + h["solution_id"],
                                  "scope_ref": "ex5c://scope/" + h["solution_id"],
                                  "evidence_ref": h["header_ref"],
                                  "change_reason_ref": (RUN_WORKER if h["solution_id"] == "SOL-001" else RUN_V3)})
            traces.append({"path": f, "status_reported": "LINKED", "links": links})
        c4 = t11.prepare_pg11_c4(pg11_c1=c1, pg11_c2=c2, pg11_c3=c3,
            declared_diff=diff, authorized_scope=scope, trace_observations=traces)
        reviews = [{"path": f, "builder_principal_ref": BUILDER[owner[f]],
                    "reviewer_principal_ref": REVIEWER,
                    "reviewer_role_ref": "ex5c://role/independent-verifier",
                    "builder_provenance_ref": RUN_WORKER if owner[f] == "SOL-001" else RUN_V3,
                    "reviewer_provenance_ref": "ex5c://claude-verification/ex5c-hidden-exam-2bf9c94f",
                    "review_scope_ref": "github://" + REPO + "/compare/" + BASE + "..." + N1,
                    "reviewer_is_builder_reported": False, "reviewer_independence_reported": True}
                   for f in all_files]
        c5 = t11.prepare_pg11_c5(pg11_c4=c4, review_observations=reviews,
            review_policy_ref="ex5c://policy/reviewer-distinct-from-builder")
        return locals()

    def hunks():
        return [{k: h[k] for k in ("hunk_id", "path", "old_start", "old_count", "new_start",
                                   "new_count", "content_sha256", "header_ref")} for h in real_hunks()]

    def links():
        out = []
        for h in real_hunks():
            for r in h["requirements"]:
                out.append({"hunk_id": h["hunk_id"], "requirement_ref": SPEC + "#" + r,
                            "batch_ref": "ex5c://batch/ex5c-" + h["solution_id"],
                            "scope_ref": "ex5c://scope/" + h["solution_id"],
                            "evidence_ref": h["header_ref"]})
        return out

    def people(same=False):
        return [{"principal_ref": BUILDER["SOL-001"], "canonical_person_ref": "identity:model-claude-sonnet-5-5",
                 "identity_provider_ref": "anthropic://models"},
                {"principal_ref": BUILDER["SOL-002"], "canonical_person_ref": "identity:tool-google-java-format",
                 "identity_provider_ref": "github://google/google-java-format"},
                {"principal_ref": REVIEWER,
                 "canonical_person_ref": "identity:model-claude-sonnet-5-5" if same else "identity:model-claude-opus-5-5",
                 "identity_provider_ref": "anthropic://models"}]
    return fixture, hunks, links, people


def uninstall():
    """Restore every replaced builder/constant (keeps synthetic suites clean)."""
    while _UNDO:
        mod, attr, old = _UNDO.pop()
        if attr == "__constants__":
            for key, value in old.items():
                cur = getattr(mod, key)
                if isinstance(cur, dict):
                    cur.clear(); cur.update(value)
                elif isinstance(cur, list):
                    cur[:] = value
                else:
                    setattr(mod, key, value)
        else:
            setattr(mod, attr, old)
    OVERRIDES.clear()


def install():
    if OVERRIDES:
        raise AssertionError("EX5C_REAL_WORLD_ALREADY_INSTALLED")
    setup_paths()
    import test_pg04_semantic_partition_candidate_v1 as t4
    import test_pg06_c1_c5_chain_v1 as t6pre
    _UNDO.append((t4, "__constants__", {"STRATEGY": copy.deepcopy(t4.STRATEGY),
                                        "OUTCOMES": copy.deepcopy(t4.OUTCOMES),
                                        "ATOMS": copy.deepcopy(t4.ATOMS)}))
    _UNDO.append((t6pre, "__constants__", {"BASE": t6pre.BASE}))
    t4.STRATEGY.clear(); t4.STRATEGY.update(copy.deepcopy(STRATEGY))
    t4.OUTCOMES[:] = copy.deepcopy(OUTCOMES)
    t4.ATOMS[:] = _atoms(t4)
    OVERRIDES.append("test_pg04_semantic_partition_candidate_v1.{STRATEGY,OUTCOMES,ATOMS} = EX5C")
    import test_pg04_definition_of_done_candidate_v1 as t4dod
    import test_pg04_remaining_edges_v1  # noqa: F401  (registers alias dod_fixtures)
    replace_everywhere(t4dod, "fixtures", _dod_fixtures(t4dod))
    import test_pg05_chain_c1_c5_v1 as t5
    import test_pg06_c1_c5_chain_v1  # noqa: F401
    ex, res, ch, man = _pg05_overrides(t5)
    for name, fn in (("pg04_real_exit", ex), ("resources", res), ("changes", ch), ("manifest", man)):
        replace_everywhere(t5, name, fn)
    import test_pg06_c1_c5_chain_v1 as t6
    t6.BASE = BASE
    OVERRIDES.append("test_pg06_c1_c5_chain_v1.BASE = " + BASE)
    tc, bl = _pg06_overrides(t6)
    replace_everywhere(t6, "toolchain", tc)
    replace_everywhere(t6, "baseline", bl)
    import test_pg07_c1_c6_chain_v1 as t7
    import test_pg08_full_chain_v1  # noqa: F401
    m1, ws, mc = _pg07_overrides(t7)
    for name, fn in (("make_c1", m1), ("worker_spec", ws), ("make_chain", mc)):
        replace_everywhere(t7, name, fn)
    import test_pg08_full_chain_v1 as t8
    import test_pg09_iteration_chain_v1  # noqa: F401
    replace_everywhere(t8, "make_chain", _pg08_make_chain(t8))
    replace_everywhere(t8, "reported_base", _reported_base(t8))
    import test_pg09_iteration_chain_v1 as t9
    import test_pg10_decision_chain_v1  # noqa: F401
    pol, co, ctx = _pg09_overrides(t9)
    for name, fn in (("policy", pol), ("cost_observations", co), ("context", ctx)):
        replace_everywhere(t9, name, fn)
    import test_pg10_decision_chain_v1 as t10
    import test_pg10_pg11_bridge_and_waiver_time_v1  # noqa: F401
    for name, fn in zip(("conflicts", "routes", "packets", "ledger_for", "question"), _pg10_overrides(t10)):
        replace_everywhere(t10, name, fn)
    import test_pg11_integrity_chain_v1 as t11
    import test_pg12_identity_chain_v1  # noqa: F401
    for name, fn in zip(("fixture", "hunks", "links", "people"), _pg11_fixture(t11)):
        replace_everywhere(t11, name, fn)
    return OVERRIDES
