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
    probe = run(["git", "cat-file", "-e", f"{FINAL_SHA}^{{commit}}"], check=False)
    if probe.returncode == 0:
        return
    fetched = run(["git", "fetch", "origin", FINAL_SHA, "--no-tags"], check=False)
    if fetched.returncode != 0:
        raise SystemExit("BLOCK_FINAL_CANDIDATE_NOT_FETCHABLE:" + fetched.stderr[-500:])
    probe = run(["git", "cat-file", "-e", f"{FINAL_SHA}^{{commit}}"], check=False)
    if probe.returncode != 0:
        raise SystemExit("BLOCK_FINAL_CANDIDATE_NOT_AVAILABLE")


CHILD = r'''
from __future__ import annotations
import contextlib
import copy
import hashlib
import importlib
import importlib.util
import io
import json
import sys
import time
from pathlib import Path

ROOT = Path.cwd()
RESULTS = {}

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def proxy(value) -> int:
    return len(json.dumps(value, ensure_ascii=False, sort_keys=True, default=str).encode("utf-8"))

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

def timed(fn):
    t0 = time.perf_counter()
    out = fn()
    return out, (time.perf_counter() - t0) * 1000.0

def load_file_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"MODULE_LOAD_FAILED:{path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

resolver_path = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/runtime_authority_resolver_v1.py"
resolver = load_file_module(resolver_path, "s26_matrix_exact_candidate_resolver")

# Temporary holdout material exists only in this detached exact-candidate worktree.
card_dir = ROOT / "cards"
card_dir.mkdir(exist_ok=True)
adapter_dir = ROOT / "adapters"
adapter_dir.mkdir(exist_ok=True)
fixture_dir = ROOT / ".s26_matrix_holdout"
fixture_dir.mkdir(exist_ok=True)

base_request = {"input_literal": "S26 Matrix v3 deterministic holdout", "lf_adapter_bindings": []}
base_fields = {"profile_slug": "ui_architect", "task_mode": "CREATE_NEW", "output_contract_version": "UI_PRODUCTION_SPEC_V6", "domain_scope": "MATRIX_HOLDOUT"}

def base_context(**overrides):
    d = {
        "surface_code": "S26_MATRIX_HOLDOUT_SURFACE",
        "task_code": "CREATE_NEW",
        "current_run_id": "S26-MATRIX-W1-HOLDOUT",
        "input_fields": dict(base_fields),
        "card_candidates": [],
        "required_authority_types": [],
        "authority_sources": [],
        "required_adapter_codes": [],
    }
    d.update(overrides)
    return d

def expect_code(code, fn):
    try:
        fn()
    except Exception as exc:
        actual = getattr(exc, "code", None) or str(exc).split(":", 1)[0]
        return actual == code, actual
    return False, "NO_EXCEPTION"

# F03-O2: positive applicable Card, exact provenance binding.
card_path = card_dir / "s26_matrix_holdout_card.json"
card_path.write_text(json.dumps({"schema":"S26_MATRIX_CARD_V1","purpose":"positive applicable holdout"}, sort_keys=True), encoding="utf-8")
card_ref = "cards/s26_matrix_holdout_card.json"
card_candidate = {
    "card_id": "S26_MATRIX_APPLICABLE_CARD",
    "surface_codes": ["S26_MATRIX_HOLDOUT_SURFACE"],
    "task_codes": ["CREATE_NEW"],
    "ref": card_ref,
    "sha256": sha(card_path),
    "required_input_fields": ["profile_slug", "output_contract_version"],
}
ctx = base_context(card_candidates=[card_candidate])
out, ms = timed(lambda: resolver.resolve_runtime_context(ctx, request=base_request, repo_root=ROOT))
cr = out["card_resolution"]
ok = cr.get("status") == "RESOLVED" and cr.get("mode") == "CARD_BOUND" and cr.get("card_id") == card_candidate["card_id"] and cr.get("card_sha256") == card_candidate["sha256"] and cr.get("schema_invention_allowed") is False
put("S26V3-F03-O2-POSITIVE-CARD", ok, {"status":cr.get("status"),"mode":cr.get("mode"),"card_id":cr.get("card_id"),"card_sha256":cr.get("card_sha256"),"schema_invention_allowed":cr.get("schema_invention_allowed")}, ms, proxy(ctx), ["runtime_authority_resolver_v1.py", card_ref])

# Shared authority fixture for cross-run negatives.
auth_path = fixture_dir / "authority.txt"
auth_path.write_text("matrix authority fixture\n", encoding="utf-8")
auth_source = {
    "authority_type":"USER_REQUIREMENT",
    "authority_id":"S26_MATRIX_CROSSRUN_AUTH",
    "run_id":"S26-OTHER-RUN",
    "cross_run_declared":False,
    "ref":".s26_matrix_holdout/authority.txt",
    "sha256":sha(auth_path),
}
ctx_cross = base_context(required_authority_types=["USER_REQUIREMENT"], authority_sources=[auth_source])
(ok, actual), ms = timed(lambda: expect_code("RUNTIME_CROSS_RUN_REFERENCE_UNDECLARED", lambda: resolver.resolve_runtime_context(ctx_cross, request=base_request, repo_root=ROOT)))
put("S26V3-F03-O4-CROSSRUN-AUTHORITY", ok, {"expected_code":"RUNTIME_CROSS_RUN_REFERENCE_UNDECLARED","observed_code":actual,"typed_context_materialized":False}, ms, proxy(ctx_cross), ["runtime_authority_resolver_v1.py", ".s26_matrix_holdout/authority.txt"])

# F03-O5: applicable but unknown/unresolvable Card cannot be auto-canonicalized.
unknown = {
    "card_id":"S26_MATRIX_UNKNOWN_CARD",
    "surface_codes":["S26_MATRIX_HOLDOUT_SURFACE"],
    "task_codes":["CREATE_NEW"],
    "ref":"cards/s26_matrix_unknown_card_does_not_exist.json",
    "sha256":"0"*64,
    "required_input_fields":[],
}
ctx_unknown = base_context(card_candidates=[unknown])
(ok, actual), ms = timed(lambda: expect_code("RUNTIME_CONTEXT_REF_NOT_FOUND", lambda: resolver.resolve_runtime_context(ctx_unknown, request=base_request, repo_root=ROOT)))
put("S26V3-F03-O5-UNKNOWN-CARD-HOLDOUT", ok, {"expected_code":"RUNTIME_CONTEXT_REF_NOT_FOUND","observed_code":actual,"autocanonicalized":False}, ms, proxy(ctx_unknown), ["runtime_authority_resolver_v1.py"])

# F04-O1: exact-candidate typed-context positive replay and timing.
sys.path.insert(0, str(ROOT))
hp_prefix = "sandbox.lf_contract_gate_test.profile_runtime_structural_context_v3.s26_hp001"
gate_e = importlib.import_module(hp_prefix + ".gate_e_context")
gate_d = importlib.import_module(hp_prefix + ".gate_d_authority")
bootstrap_mod = importlib.import_module(hp_prefix + ".bootstrap_context")
resolved_e, ms = timed(lambda: gate_e.evaluate_typed_context())
typed = resolved_e["output"]["typed_context"]
ok = typed.get("schema") == "LF_RUNTIME_TYPED_CONTEXT_V1" and resolved_e.get("adapter_binding_count") == 0 and bool(resolved_e.get("typed_context_sha256"))
put("S26V3-F04-O1-FINAL-PERF-REBIND", ok, {"schema":typed.get("schema"),"typed_context_sha256":resolved_e.get("typed_context_sha256"),"adapter_binding_count":resolved_e.get("adapter_binding_count")}, ms, proxy(typed), ["s26_hp001/gate_e_context.py", "s26_hp001/gate_e_output.json"])

# F04-O2: material required typed-context field omitted before runtime.
missing_ctx = base_context()
missing_ctx.pop("current_run_id")
(ok, actual), ms = timed(lambda: expect_code("RUNTIME_CONTEXT_FIELD_MISSING", lambda: resolver.resolve_runtime_context(missing_ctx, request=base_request, repo_root=ROOT)))
put("S26V3-F04-O2-MISSING-TYPED-FIELD", ok, {"expected_code":"RUNTIME_CONTEXT_FIELD_MISSING","observed_code":actual,"runtime_execution_performed":False}, ms, proxy(missing_ctx), ["runtime_authority_resolver_v1.py"])

# F04-O3: incompatible materialized typed schema cannot be silently coerced.
d_eval = gate_d.evaluate_authority_resolution()
b_eval = bootstrap_mod.evaluate_bootstrap()
payload = json.loads(gate_e.OUTPUT_PATH.read_text(encoding="utf-8"))
payload["typed_context"]["schema"] = "LF_RUNTIME_TYPED_CONTEXT_V0_INCOMPATIBLE"
try:
    t0 = time.perf_counter(); gate_e._validate_payload(payload, d_eval, b_eval); ms = (time.perf_counter()-t0)*1000.0
    ok, actual = False, "NO_EXCEPTION"
except Exception as exc:
    ms = (time.perf_counter()-t0)*1000.0
    actual = str(exc).split(":",1)[0]
    ok = actual == "GATE_E_TYPED_CONTEXT_NOT_RESOLVER_EXACT"
put("S26V3-F04-O3-INCOMPATIBLE-TYPED-VERSION", ok, {"expected_code":"GATE_E_TYPED_CONTEXT_NOT_RESOLVER_EXACT","observed_code":actual,"implicit_coercion":False}, ms, proxy(payload.get("typed_context")), ["s26_hp001/gate_e_context.py", "s26_hp001/gate_e_output.json"])

# F04-O4: cross-run metadata is blocked before executable context exists.
(ok, actual), ms = timed(lambda: expect_code("RUNTIME_CROSS_RUN_REFERENCE_UNDECLARED", lambda: resolver.resolve_runtime_context(ctx_cross, request=base_request, repo_root=ROOT)))
put("S26V3-F04-O4-TYPED-CONTAMINATION", ok, {"expected_code":"RUNTIME_CROSS_RUN_REFERENCE_UNDECLARED","observed_code":actual,"prohibited_metadata_entered_typed_context":False}, ms, proxy(ctx_cross), ["runtime_authority_resolver_v1.py"])

# F04-O5: unseen adapter-required context resolves exactly one SHA-bound adapter.
adapter_path = adapter_dir / "s26_matrix_holdout_adapter.json"
adapter_path.write_text(json.dumps({"schema":"S26_MATRIX_ADAPTER_V1","transform":"identity"}, sort_keys=True), encoding="utf-8")
adapter_ref = "adapters/s26_matrix_holdout_adapter.json"
req_adapter = {
    "input_literal": base_request["input_literal"],
    "lf_adapter_bindings": [{
        "canonical_adapter_id":"S26_MATRIX_ADAPTER",
        "current_path":adapter_ref,
        "binding_ref":"S26_MATRIX_BINDING_V1",
        "sha256":sha(adapter_path),
    }],
}
ctx_adapter = base_context(required_adapter_codes=["S26_MATRIX_ADAPTER"])
out, ms = timed(lambda: resolver.resolve_runtime_context(ctx_adapter, request=req_adapter, repo_root=ROOT))
ad = out["adapter_binding"]
ok = len(ad)==1 and ad[0].get("adapter_code")=="S26_MATRIX_ADAPTER" and ad[0].get("current_path")==adapter_ref and ad[0].get("sha256")==sha(adapter_path) and len(out["provenance"]["adapters"])==1
put("S26V3-F04-O5-ADAPTER-HOLDOUT", ok, {"adapter_count":len(ad),"adapter":ad[0] if ad else None,"overfetch_detected":len(ad)!=1}, ms, proxy(ctx_adapter)+proxy(req_adapter), ["runtime_authority_resolver_v1.py", adapter_ref])

# Composer/schema boundary exact-candidate helpers.
boundary_path = ROOT / "profiles/ui_architect/validators/validate_composer_payload_boundary.py"
boundary = load_file_module(boundary_path, "s26_matrix_exact_boundary")
raw_path = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005/raw_output.json"
raw = json.loads(raw_path.read_text(encoding="utf-8"))
def make_v6():
    data = copy.deepcopy(raw)
    context = data["deliverable_created"].pop("governance_context")
    data["output_contract_version"] = boundary.VERSION
    data["governance_envelope"] = {"schema":boundary.ENVELOPE_SCHEMA,"render_policy":"NON_RENDER","context":context}
    data["handoff_to_next"]["payload_ref"] = "composer_payload"
    data["composer_payload"] = boundary.build_composer_payload(data["deliverable_created"])
    return data

def ecodes(errors):
    return sorted({e.get("code") for e in errors if isinstance(e, dict)})

bad_env = make_v6(); bad_env["governance_envelope"] = "malformed"
errs, ms = timed(lambda: boundary.validate(bad_env)); codes = ecodes(errs)
put("S26V3-F05-O3-MALFORMED-ENVELOPE", "GOVERNANCE_ENVELOPE_MISSING" in codes, {"error_codes":codes,"accepted":not bool(errs)}, ms, proxy(bad_env), ["validate_composer_payload_boundary.py", "s26_native_golden_005/raw_output.json"])

bad_version = make_v6(); bad_version["output_contract_version"] = "UI_PRODUCTION_SPEC_V5_INCOMPATIBLE"
errs, ms = timed(lambda: boundary.validate(bad_version)); codes = ecodes(errs)
put("S26V3-F05-O4-INCOMPATIBLE-SCHEMA-VERSION", "COMPOSER_BOUNDARY_VERSION_INVALID" in codes, {"error_codes":codes,"silent_downgrade":False}, ms, proxy(bad_version), ["validate_composer_payload_boundary.py", "s26_native_golden_005/raw_output.json"])

# F07-O1: positive Composer boundary timing.
good = make_v6(); errs, ms = timed(lambda: boundary.validate(good))
put("S26V3-F07-O1-FINAL-PERF-REBIND", errs == [], {"valid":errs==[],"error_codes":ecodes(errs)}, ms, proxy(good), ["validate_composer_payload_boundary.py", "s26_native_golden_005/raw_output.json"])

# F07-O4: active injection/internal metadata path must fail.
injected = make_v6()
injected["deliverable_created"]["component_tree"][0]["content"]["runtime_source_context"] = {"routing":"attacker-controlled", "worker":"spoof"}
injected["composer_payload"] = boundary.build_composer_payload(injected["deliverable_created"])
errs, ms = timed(lambda: boundary.validate(injected)); codes = ecodes(errs)
put("S26V3-F07-O4-INJECTION", "COMPOSER_INTERNAL_KEY_LEAK" in codes, {"error_codes":codes,"injection_passed":not bool(errs)}, ms, proxy(injected), ["validate_composer_payload_boundary.py"])

# F07-O5: a new structure using only explicit allowlisted component keys passes;
# neighboring internal key fails without widening the allowlist.
allowed = make_v6()
new_component = {
    "zone_id":"matrix-holdout-zone",
    "component_id":"matrix-holdout-component",
    "component_type":"info_panel",
    "role":"supporting_information",
    "content":{"title":"Matrix holdout","body":"Allowed structure only"},
    "visual_priority":"secondary",
    "state":"default",
}
allowed["deliverable_created"]["component_tree"].append(new_component)
allowed["composer_payload"] = boundary.build_composer_payload(allowed["deliverable_created"])
errs_allowed, ms1 = timed(lambda: boundary.validate(allowed))
neighbor = copy.deepcopy(allowed)
neighbor["deliverable_created"]["component_tree"][-1]["internal_trace_context"] = {"opaque":"x"}
neighbor["composer_payload"] = boundary.build_composer_payload(neighbor["deliverable_created"])
errs_neighbor, ms2 = timed(lambda: boundary.validate(neighbor)); neighbor_codes = ecodes(errs_neighbor)
ok = errs_allowed == [] and "COMPOSER_COMPONENT_KEY_NOT_ALLOWED" in neighbor_codes and "COMPOSER_INTERNAL_KEY_LEAK" in neighbor_codes
put("S26V3-F07-O5-ALLOWED-STRUCTURE-HOLDOUT", ok, {"allowed_valid":errs_allowed==[],"allowed_errors":ecodes(errs_allowed),"neighbor_error_codes":neighbor_codes,"allowlist_expanded":False}, ms1+ms2, proxy(allowed)+proxy(neighbor), ["validate_composer_payload_boundary.py"])

# F10-O2: deterministic replay of exact-candidate Composer suite; this is replay only,
# never independent semantic review.
runner_path = ROOT / "profiles/ui_architect/evals/composer_payload_boundary_20260909/run_cases.py"
runner = load_file_module(runner_path, "s26_matrix_exact_composer_cases")
buf = io.StringIO()
t0 = time.perf_counter()
try:
    with contextlib.redirect_stdout(buf):
        runner.main()
    replay_ok = "UI_COMPOSER_BOUNDARY_TESTS_PASS 13/13" in buf.getvalue()
    replay_error = None
except Exception as exc:
    replay_ok = False; replay_error = repr(exc)
ms = (time.perf_counter()-t0)*1000.0
put("S26V3-F10-O2-FINAL-REPLAY-PERF", replay_ok, {"stdout":buf.getvalue().strip(),"error":replay_error,"independent_review":False}, ms, raw_path.stat().st_size, ["composer_payload_boundary_20260909/run_cases.py", "validate_composer_payload_boundary.py", "s26_native_golden_005/raw_output.json"])

print(json.dumps({"schema":"S26_MATRIX_V3_W1_CHILD_RESULTS_V1","results":RESULTS}, sort_keys=True))
'''


def main() -> int:
    ensure_commit()
    recipes_doc = build_recipes()
    recipes = {r["case_id"]: r for r in recipes_doc["recipes"]}
    w1 = {cid: r for cid, r in recipes.items() if r["final_wave"] == "W1_FINAL_DETERMINISTIC"}

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="s26-matrix-w1-") as tmp:
        candidate = Path(tmp) / "candidate"
        add = run(["git", "worktree", "add", "--detach", str(candidate), FINAL_SHA], check=False)
        if add.returncode != 0:
            raise SystemExit("BLOCK_CANDIDATE_WORKTREE:" + add.stderr[-800:])
        try:
            child = run([sys.executable, "-c", CHILD], cwd=candidate, check=False)
            if child.returncode != 0:
                (OUT_DIR / "child_stderr.txt").write_text(child.stderr, encoding="utf-8")
                (OUT_DIR / "child_stdout.txt").write_text(child.stdout, encoding="utf-8")
                raise SystemExit(f"BLOCK_W1_CHILD_EXECUTION:{child.returncode}")
            lines = [line for line in child.stdout.splitlines() if line.strip()]
            payload = json.loads(lines[-1])
        finally:
            run(["git", "worktree", "remove", "--force", str(candidate)], check=False)

    measured = payload["results"]
    receipts = []
    unexpected = sorted(set(measured) - set(w1))
    if unexpected:
        raise SystemExit("BLOCK_NON_W1_CASE_EMITTED:" + ",".join(unexpected))

    for case_id, observed in sorted(measured.items()):
        recipe = w1[case_id]
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

    pending = sorted(set(w1) - set(measured))
    failed = [r["case_id"] for r in receipts if not r["pass"]]
    summary = {
        "schema": "S26_FAMILY_OBJECTIVE_MATRIX_V3_W1_PROBE_RECEIPT_V1",
        "status": "PARTIAL_W1_PROBE" if pending or failed else "W1_PROBE_COMPLETE",
        "claim_ceiling": "W1_DETERMINISTIC_EVIDENCE_ONLY_NOT_W2_NOT_W3_NOT_GATE_G_NOT_GOLDEN_NOT_PRODUCTION",
        "final_candidate_sha": FINAL_SHA,
        "source_authority_commit": recipes_doc["recipes"][0]["source_authority_commit"],
        "w1_recipe_count": len(w1),
        "executed_count": len(receipts),
        "pass_count": sum(r["pass"] for r in receipts),
        "fail_count": len(failed),
        "pending_count": len(pending),
        "failed_cases": failed,
        "pending_cases": pending,
        "receipts": receipts,
        "explicit_non_actions": [
            "NO_GATE_G_EXECUTION",
            "NO_GOLDEN_PROMOTION",
            "NO_PRODUCTION",
            "NO_SUPABASE_WRITE",
            "NO_MODEL_CALL",
            "NO_PAID_FALLBACK",
            "NO_MAIN_MERGE",
        ],
    }
    (OUT_DIR / "w1_probe_receipt.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({k: summary[k] for k in ("status","final_candidate_sha","w1_recipe_count","executed_count","pass_count","fail_count","pending_count","failed_cases","pending_cases")}, sort_keys=True))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
