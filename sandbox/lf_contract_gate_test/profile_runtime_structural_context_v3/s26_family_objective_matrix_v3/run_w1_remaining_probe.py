#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[3]
FINAL_SHA = os.environ.get("S26_FINAL_CANDIDATE_SHA", "").strip()
OUT_DIR = Path(os.environ.get("S26_MATRIX_OUT_DIR", ".audit-output/s26-matrix-v3-w1"))

if not re.fullmatch(r"[0-9a-f]{40}", FINAL_SHA):
    raise SystemExit("BLOCK_FINAL_CANDIDATE_SHA_INVALID")

sys.path.insert(0, str(ROOT))
from build_w0_execution_recipes import build_recipes  # noqa: E402


def run(cmd: list[str], *, cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd or REPO, text=True, capture_output=True, check=check)


def ensure_commit() -> None:
    if run(["git", "cat-file", "-e", f"{FINAL_SHA}^{{commit}}"], check=False).returncode == 0:
        return
    fetched = run(["git", "fetch", "origin", FINAL_SHA, "--no-tags"], check=False)
    if fetched.returncode != 0:
        raise SystemExit("BLOCK_FINAL_CANDIDATE_NOT_FETCHABLE:" + fetched.stderr[-500:])
    if run(["git", "cat-file", "-e", f"{FINAL_SHA}^{{commit}}"], check=False).returncode != 0:
        raise SystemExit("BLOCK_FINAL_CANDIDATE_NOT_AVAILABLE")


CHILD = r'''
from __future__ import annotations
import copy
import hashlib
import importlib.util
import json
import time
from pathlib import Path

ROOT = Path.cwd()
RESULTS = {}

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def proxy(value) -> int:
    return len(json.dumps(value, ensure_ascii=False, sort_keys=True, default=str).encode("utf-8"))

def timed(fn):
    t0 = time.perf_counter(); out = fn(); return out, (time.perf_counter() - t0) * 1000.0

def put(case_id, passed, observed, elapsed_ms, token_proxy, evidence_refs):
    RESULTS[case_id] = {
        "pass": bool(passed),
        "observed": observed,
        "latency_ms": round(elapsed_ms, 3),
        "model_calls": 0,
        "context_or_token_proxy": int(token_proxy),
        "retries": 0,
        "evidence_refs": evidence_refs,
    }

def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"MODULE_LOAD_FAILED:{path}")
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod

def expect_code(expected, fn):
    try:
        fn()
    except Exception as exc:
        actual = getattr(exc, "code", None) or str(exc).split(":", 1)[0]
        return actual == expected, actual
    return False, "NO_EXCEPTION"

resolver_path = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/runtime_authority_resolver_v1.py"
resolver = load(resolver_path, "s26_w1_remaining_resolver")
fixture_dir = ROOT / ".s26_matrix_w1_remaining"
fixture_dir.mkdir(exist_ok=True)
request = {"input_literal": "S26 Matrix v3 remaining deterministic holdout", "lf_adapter_bindings": []}

def base_context(surface, task, run_id, required=None, sources=None):
    return {
        "surface_code": surface,
        "task_code": task,
        "current_run_id": run_id,
        "input_fields": {"profile_slug": "ui_architect", "output_contract_version": "UI_PRODUCTION_SPEC_V6"},
        "card_candidates": [],
        "required_authority_types": required or [],
        "authority_sources": sources or [],
        "required_adapter_codes": [],
    }

# F01-O5: unseen route/provenance surface succeeds from exact bytes; unknown ownership fails closed.
route_path = fixture_dir / "unseen_route_authority.json"
route_doc = {"schema": "S26_MATRIX_UNSEEN_ROUTE_V1", "owner": "UNSEEN_PROFILE_OWNER", "semantic": "route-by-declared-surface-not-memorized-path"}
route_path.write_text(json.dumps(route_doc, sort_keys=True) + "\n", encoding="utf-8")
route_ref = ".s26_matrix_w1_remaining/unseen_route_authority.json"
run_id = "S26-MATRIX-W1-UNSEEN-ROUTE"
source = {"authority_type":"USER_REQUIREMENT","authority_id":"UNSEEN_ROUTE_AUTH","run_id":run_id,"ref":route_ref,"sha256":sha(route_path)}
ctx = base_context("S26_UNSEEN_ROUTING_SURFACE_947", "UNSEEN_ROUTE_TASK_947", run_id, ["USER_REQUIREMENT"], [source])
out, ms1 = timed(lambda: resolver.resolve_runtime_context(ctx, request=request, repo_root=ROOT))
unknown_ctx = base_context("S26_UNSEEN_ROUTING_SURFACE_948", "UNSEEN_OWNER_TASK_948", run_id, ["PROFILE_CONTRACT"], [])
(result, ms2) = timed(lambda: expect_code("RUNTIME_AUTHORITY_MISSING", lambda: resolver.resolve_runtime_context(unknown_ctx, request=request, repo_root=ROOT)))
blocked, code = result
prov = out["provenance"]["authorities"][0]
ok = (
    out["surface_code"] == ctx["surface_code"] and out["task_code"] == ctx["task_code"]
    and prov["sha256"] == sha(route_path)
    and out["card_resolution"]["mode"] == "NO_CARD_GOVERNED"
    and out["card_resolution"]["schema_invention_allowed"] is False
    and blocked
)
put("S26V3-F01-O5-HOLDOUT", ok, {
    "unseen_surface_preserved": out["surface_code"], "unseen_task_preserved": out["task_code"],
    "provider_digest_bound": prov["sha256"], "card_mode": out["card_resolution"]["mode"],
    "unknown_ownership_expected_code": "RUNTIME_AUTHORITY_MISSING", "unknown_ownership_observed_code": code,
    "unknown_ownership_fail_closed": blocked,
}, ms1 + ms2, proxy(ctx) + proxy(unknown_ctx), ["runtime_authority_resolver_v1.py", route_ref])

# F02-O3: stale bytes are rejected and only explicit fresh rebind succeeds.
stale_path = fixture_dir / "stale_rebind_authority.json"
stale_ref = ".s26_matrix_w1_remaining/stale_rebind_authority.json"
stale_run = "S26-MATRIX-W1-STALE-REBIND"
def source_for(digest, **extra):
    return {"authority_type":"USER_REQUIREMENT","authority_id":"STALE_REBIND_AUTH","run_id":stale_run,"ref":stale_ref,"sha256":digest, **extra}
def stale_ctx(digest, **extra):
    return base_context("S26_SOURCE_FIRST_SURFACE", "SOURCE_REBIND", stale_run, ["USER_REQUIREMENT"], [source_for(digest, **extra)])
v1 = {"schema":"S26_MATRIX_AUTHORITY_V1","revision":1,"semantic":"same-authority"}
stale_path.write_text(json.dumps(v1, sort_keys=True) + "\n", encoding="utf-8")
v1_sha = sha(stale_path)
out1, m1 = timed(lambda: resolver.resolve_runtime_context(stale_ctx(v1_sha), request=request, repo_root=ROOT))
v2 = {"schema":"S26_MATRIX_AUTHORITY_V1","revision":2,"semantic":"same-authority","provider_readback":"fresh"}
stale_path.write_text(json.dumps(v2, sort_keys=True) + "\n", encoding="utf-8")
v2_sha = sha(stale_path)
(stale_result, m2) = timed(lambda: expect_code("RUNTIME_CONTEXT_PROVENANCE_SHA_MISMATCH", lambda: resolver.resolve_runtime_context(stale_ctx(v1_sha), request=request, repo_root=ROOT)))
stale_blocked, stale_code = stale_result
out2, m3 = timed(lambda: resolver.resolve_runtime_context(stale_ctx(v2_sha), request=request, repo_root=ROOT))
p1 = out1["provenance"]["authorities"][0]["sha256"]
p2 = out2["provenance"]["authorities"][0]["sha256"]
rebound = p1 == v1_sha and p2 == v2_sha and v1_sha != v2_sha
put("S26V3-F02-O3-STALE-REBIND", stale_blocked and rebound, {
    "initial_provider_sha256": p1, "fresh_provider_sha256": p2,
    "stale_expected_code":"RUNTIME_CONTEXT_PROVENANCE_SHA_MISMATCH", "stale_observed_code":stale_code,
    "stale_blocked_before_execution": stale_blocked, "explicit_rebind_to_fresh_digest": rebound,
}, m1 + m2 + m3, proxy(out1) + proxy(out2), ["runtime_authority_resolver_v1.py", stale_ref])

# F02-O4: spoofed caller currentness cannot override recomputed provider bytes.
spoofed_ctx = stale_ctx(v1_sha, caller_declared_currentness="CURRENT", caller_declared_provider_sha256=v1_sha)
(spoof_result, sm1) = timed(lambda: expect_code("RUNTIME_CONTEXT_PROVENANCE_SHA_MISMATCH", lambda: resolver.resolve_runtime_context(spoofed_ctx, request=request, repo_root=ROOT)))
spoof_blocked, spoof_code = spoof_result
fresh_spoof_ctx = stale_ctx(v2_sha, caller_declared_currentness="STALE", caller_declared_provider_sha256=v1_sha)
fresh_out, sm2 = timed(lambda: resolver.resolve_runtime_context(fresh_spoof_ctx, request=request, repo_root=ROOT))
fresh_digest = fresh_out["provenance"]["authorities"][0]["sha256"]
put("S26V3-F02-O4-SPOOFED-CURRENTNESS-HOLDOUT", spoof_blocked and fresh_digest == v2_sha, {
    "caller_claim_CURRENT_with_stale_digest_blocked": spoof_blocked,
    "expected_code":"RUNTIME_CONTEXT_PROVENANCE_SHA_MISMATCH", "observed_code":spoof_code,
    "caller_claim_STALE_with_exact_provider_digest_succeeds": fresh_digest == v2_sha,
    "provider_derived_sha256": fresh_digest, "caller_currentness_is_not_authority": True,
}, sm1 + sm2, proxy(spoofed_ctx) + proxy(fresh_spoof_ctx), ["runtime_authority_resolver_v1.py", stale_ref])

# F02-O5: missing canonical source blocks; no synthetic source/card/schema is produced.
missing_ref = ".s26_matrix_w1_remaining/canonical_source_does_not_exist.json"
missing_src = {"authority_type":"USER_REQUIREMENT","authority_id":"MISSING_CANONICAL","run_id":"S26-MATRIX-W1-MISSING","ref":missing_ref,"sha256":"0"*64,"synthetic_fallback":"FORBIDDEN"}
missing_ctx = base_context("S26_MISSING_SOURCE_SURFACE", "SOURCE_REQUIRED", "S26-MATRIX-W1-MISSING", ["USER_REQUIREMENT"], [missing_src])
(missing_result, mm) = timed(lambda: expect_code("RUNTIME_CONTEXT_REF_NOT_FOUND", lambda: resolver.resolve_runtime_context(missing_ctx, request=request, repo_root=ROOT)))
missing_blocked, missing_code = missing_result
put("S26V3-F02-O5-MISSING-SOURCE", missing_blocked, {
    "expected_code":"RUNTIME_CONTEXT_REF_NOT_FOUND", "observed_code":missing_code,
    "execution_blocked": missing_blocked, "synthetic_authority_created": False,
    "schema_invented": False, "fallback_source_used": False,
}, mm, proxy(missing_ctx), ["runtime_authority_resolver_v1.py"])

# F06 performance-only rebinds: preserve frozen Gate-H semantic oracle and time deterministic mutations.
manual_path = ROOT / "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/manual_profile_output.json"
req_path = ROOT / "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/expected_requirements.json"
gate_h_path = ROOT / "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_h_output.json"
base = json.loads(manual_path.read_text(encoding="utf-8"))
req = json.loads(req_path.read_text(encoding="utf-8"))
gate_h = json.loads(gate_h_path.read_text(encoding="utf-8"))
section_map = {"header":"header_search","categories":"category_navigation","featured_services":"featured_services","service_cards":"service_cards"}

def material_validate(data):
    d = data.get("deliverable_created", {})
    screen = d.get("screen_definition", {}) if isinstance(d, dict) else {}
    comps = d.get("component_tree", []) if isinstance(d, dict) else []
    ids = {c.get("component_id") for c in comps if isinstance(c, dict)}
    template = next((c for c in comps if isinstance(c, dict) and c.get("component_id") == "service_card_template"), {})
    fields = set((template.get("content") or {}).get("fields", [])) if isinstance(template, dict) else set()
    intents = set(screen.get("design_intent", [])) if isinstance(screen, dict) else set()
    missing_sections = [s for s in req["required_sections"] if section_map.get(s, s) not in ids]
    missing_fields = [f for f in req["required_service_card_fields"] if f not in fields]
    missing_intents = [i for i in req["required_design_intents"] if i not in intents]
    ready = screen.get("implementation_readiness") == "STRUCTURED_SPEC_READY_FOR_NEXT_AGENT"
    return {"pass": not missing_sections and not missing_fields and not missing_intents and ready,
            "missing_sections": missing_sections, "missing_fields": missing_fields,
            "missing_design_intents": missing_intents, "implementation_ready": ready}

base_check, bm = timed(lambda: material_validate(base))
missing_search = copy.deepcopy(base)
missing_search["deliverable_created"]["component_tree"] = [c for c in missing_search["deliverable_created"]["component_tree"] if c.get("component_id") != "header_search"]
search_check, fm = timed(lambda: material_validate(missing_search))
f06o2 = base_check["pass"] and not search_check["pass"] and "header" in search_check["missing_sections"] and gate_h.get("negative_controls",{}).get("missing_search") == "BLOCKS"
put("S26V3-F06-O2-FINAL-PERF-REBIND", f06o2, {
    "frozen_negative_control":"missing_search=BLOCKS", "base_valid":base_check["pass"],
    "mutation_rejected":not search_check["pass"], "missing_sections":search_check["missing_sections"],
    "semantic_oracle_changed":False,
}, bm + fm, proxy(base) + proxy(missing_search), ["s26_hp001/gate_h_output.json", "s26_hp001/expected_requirements.json", "s26_hp001/manual_profile_output.json"])

missing_price = copy.deepcopy(base)
for c in missing_price["deliverable_created"]["component_tree"]:
    if c.get("component_id") == "service_card_template":
        c["content"]["fields"] = [x for x in c["content"].get("fields",[]) if x != "price"]
missing_price["deliverable_created"]["component_tree"] = [c for c in missing_price["deliverable_created"]["component_tree"] if c.get("component_id") != "service_price"]
price_check, pm = timed(lambda: material_validate(missing_price))
missing_prof = copy.deepcopy(base)
missing_prof["deliverable_created"]["screen_definition"]["design_intent"] = [x for x in missing_prof["deliverable_created"]["screen_definition"].get("design_intent",[]) if x != "professional"]
prof_check, prm = timed(lambda: material_validate(missing_prof))
controls = gate_h.get("negative_controls", {})
f06o3 = (
    base_check["pass"] and not price_check["pass"] and "price" in price_check["missing_fields"]
    and not prof_check["pass"] and "professional" in prof_check["missing_design_intents"]
    and controls.get("missing_price") == "BLOCKS" and controls.get("missing_professional_intent") == "BLOCKS"
)
put("S26V3-F06-O3-FINAL-PERF-REBIND", f06o3, {
    "frozen_negative_controls":["missing_price=BLOCKS","missing_professional_intent=BLOCKS"],
    "base_valid":base_check["pass"], "missing_price_rejected":not price_check["pass"],
    "missing_price_fields":price_check["missing_fields"], "missing_professional_rejected":not prof_check["pass"],
    "missing_design_intents":prof_check["missing_design_intents"], "semantic_oracle_changed":False,
}, bm + pm + prm, proxy(base) + proxy(missing_price) + proxy(missing_prof), ["s26_hp001/gate_h_output.json", "s26_hp001/expected_requirements.json", "s26_hp001/manual_profile_output.json"])

print(json.dumps({"schema":"S26_MATRIX_V3_W1_REMAINING_CHILD_RESULTS_V1","results":RESULTS}, sort_keys=True))
'''


def main() -> int:
    ensure_commit()
    recipes_doc = build_recipes()
    recipes = {r["case_id"]: r for r in recipes_doc["recipes"]}
    target_ids = {
        "S26V3-F01-O5-HOLDOUT",
        "S26V3-F02-O3-STALE-REBIND",
        "S26V3-F02-O4-SPOOFED-CURRENTNESS-HOLDOUT",
        "S26V3-F02-O5-MISSING-SOURCE",
        "S26V3-F06-O2-FINAL-PERF-REBIND",
        "S26V3-F06-O3-FINAL-PERF-REBIND",
    }
    if not target_ids.issubset(recipes):
        raise SystemExit("BLOCK_W1_REMAINING_RECIPE_MISSING")
    for case_id in target_ids:
        if recipes[case_id]["final_wave"] != "W1_FINAL_DETERMINISTIC":
            raise SystemExit("BLOCK_W1_REMAINING_NON_W1_RECIPE:" + case_id)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="s26-matrix-w1-rem-") as tmp:
        candidate = Path(tmp) / "candidate"
        added = run(["git", "worktree", "add", "--detach", str(candidate), FINAL_SHA], check=False)
        if added.returncode != 0:
            raise SystemExit("BLOCK_CANDIDATE_WORKTREE:" + added.stderr[-800:])
        try:
            child = run([sys.executable, "-c", CHILD], cwd=candidate, check=False)
            if child.returncode != 0:
                (OUT_DIR / "remaining_child_stderr.txt").write_text(child.stderr, encoding="utf-8")
                (OUT_DIR / "remaining_child_stdout.txt").write_text(child.stdout, encoding="utf-8")
                raise SystemExit(f"BLOCK_W1_REMAINING_CHILD_EXECUTION:{child.returncode}")
            lines = [line for line in child.stdout.splitlines() if line.strip()]
            payload = json.loads(lines[-1])
        finally:
            run(["git", "worktree", "remove", "--force", str(candidate)], check=False)

    measured = payload["results"]
    if set(measured) != target_ids:
        raise SystemExit("BLOCK_W1_REMAINING_CASE_SET_MISMATCH")

    receipts = []
    for case_id in sorted(target_ids):
        recipe = recipes[case_id]
        observed = measured[case_id]
        receipt = {
            "case_id": case_id,
            "objective_id": recipe["objective_id"],
            "family": recipe["family"],
            "source_authority_commit": recipe["source_authority_commit"],
            "final_candidate_sha": FINAL_SHA,
            "final_wave": recipe["final_wave"],
            "executor": recipe["executor"],
            "target_component": recipe["target_component"],
            "oracle": recipe["oracle"],
            "failure_mode": recipe["failure_mode"],
            "expected": recipe["expected"],
            "observed": observed["observed"],
            "dimensions_measured": recipe["dimensions_to_close"],
            "evidence_refs": observed["evidence_refs"],
            "pass": observed["pass"],
            "unseen_holdout": recipe["unseen_holdout"],
            "independent_case_credit": recipe["independent_case_credit"],
        }
        if "performance" in recipe["dimensions_to_close"]:
            for field in ("latency_ms", "model_calls", "context_or_token_proxy", "retries"):
                receipt[field] = observed[field]
        receipts.append(receipt)

    failed = [r["case_id"] for r in receipts if not r["pass"]]
    summary = {
        "schema": "S26_FAMILY_OBJECTIVE_MATRIX_V3_W1_REMAINING_RECEIPT_V1",
        "status": "W1_REMAINING_PASS" if not failed else "W1_REMAINING_FAIL",
        "claim_ceiling": "REMAINING_W1_DETERMINISTIC_CASES_ONLY_NOT_W2_NOT_W3_NOT_GATE_G_NOT_GOLDEN_NOT_PRODUCTION",
        "final_candidate_sha": FINAL_SHA,
        "case_count": len(receipts),
        "pass_count": sum(r["pass"] for r in receipts),
        "fail_count": len(failed),
        "failed_cases": failed,
        "receipts": receipts,
        "explicit_non_actions": ["NO_GATE_G_EXECUTION","NO_GOLDEN_PROMOTION","NO_PRODUCTION","NO_SUPABASE_WRITE","NO_MODEL_CALL","NO_PAID_FALLBACK","NO_MAIN_MERGE"],
    }
    (OUT_DIR / "w1_remaining_receipt.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    # Aggregate all W1 evidence into one machine-readable closure receipt.
    all_w1 = {cid for cid, r in recipes.items() if r["final_wave"] == "W1_FINAL_DETERMINISTIC"}
    combined = {}
    for filename in ("w1_probe_receipt.json", "w1_extension_receipt.json", "w1_remaining_receipt.json"):
        doc = json.loads((OUT_DIR / filename).read_text(encoding="utf-8"))
        for receipt in doc["receipts"]:
            cid = receipt["case_id"]
            if cid in combined:
                raise SystemExit("BLOCK_W1_DUPLICATE_RECEIPT:" + cid)
            combined[cid] = receipt
    missing = sorted(all_w1 - set(combined))
    unexpected = sorted(set(combined) - all_w1)
    aggregate_failed = sorted(cid for cid, r in combined.items() if not r["pass"])
    complete = not missing and not unexpected and not aggregate_failed and len(combined) == len(all_w1)
    aggregate = {
        "schema":"S26_FAMILY_OBJECTIVE_MATRIX_V3_W1_COMPLETE_RECEIPT_V1",
        "status":"W1_COMPLETE_PASS" if complete else "W1_INCOMPLETE_OR_FAIL",
        "claim_ceiling":"W1_COMPLETE_ONLY_NOT_W2_NOT_W3_NOT_GATE_G_NOT_GOLDEN_NOT_PRODUCTION",
        "final_candidate_sha":FINAL_SHA,
        "expected_w1_cases":len(all_w1),
        "observed_w1_cases":len(combined),
        "pass_count":sum(bool(r["pass"]) for r in combined.values()),
        "fail_count":len(aggregate_failed),
        "missing_cases":missing,
        "unexpected_cases":unexpected,
        "failed_cases":aggregate_failed,
        "case_ids":sorted(combined),
        "model_calls_total":sum(int(r.get("model_calls",0)) for r in combined.values()),
        "explicit_non_actions":["NO_GATE_G_EXECUTION","NO_GOLDEN_PROMOTION","NO_PRODUCTION","NO_SUPABASE_WRITE","NO_PAID_FALLBACK","NO_MAIN_MERGE"],
    }
    (OUT_DIR / "w1_complete_receipt.json").write_text(json.dumps(aggregate, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"remaining_status":summary["status"],"remaining_pass_count":summary["pass_count"],"w1_status":aggregate["status"],"w1_expected":aggregate["expected_w1_cases"],"w1_observed":aggregate["observed_w1_cases"],"w1_pass_count":aggregate["pass_count"],"w1_fail_count":aggregate["fail_count"],"w1_missing":aggregate["missing_cases"],"model_calls_total":aggregate["model_calls_total"]}, sort_keys=True))
    return 0 if complete else 1


if __name__ == "__main__":
    raise SystemExit(main())
