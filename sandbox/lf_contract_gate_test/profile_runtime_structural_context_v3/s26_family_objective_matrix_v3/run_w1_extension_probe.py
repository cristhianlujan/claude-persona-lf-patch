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

def ecodes(errors):
    return sorted({e.get("code") for e in errors if isinstance(e, dict)})

# --- F05-O5: compatible schema evolution holdout ---
boundary_path = ROOT / "profiles/ui_architect/validators/validate_composer_payload_boundary.py"
boundary = load(boundary_path, "s26_w1_ext_boundary")
raw_path = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005/raw_output.json"
raw = json.loads(raw_path.read_text(encoding="utf-8"))

def make_v6():
    data = copy.deepcopy(raw)
    context = data["deliverable_created"].pop("governance_context")
    data["output_contract_version"] = boundary.VERSION
    data["governance_envelope"] = {"schema": boundary.ENVELOPE_SCHEMA, "render_policy": "NON_RENDER", "context": context}
    data["handoff_to_next"]["payload_ref"] = "composer_payload"
    data["composer_payload"] = boundary.build_composer_payload(data["deliverable_created"])
    return data

def semantic_core(data):
    d = data["deliverable_created"]
    return {
        "screen_definition": copy.deepcopy(d.get("screen_definition")),
        "components": [
            {k: copy.deepcopy(c.get(k)) for k in ("zone_id", "component_id", "component_type", "role", "content", "visual_priority", "state") if k in c}
            for c in d.get("component_tree", []) if isinstance(c, dict)
        ],
    }

base = make_v6()
compatible = copy.deepcopy(base)
compatible["deliverable_created"]["component_tree"][0]["allowed_variants"] = ["DEFAULT", "COMPACT"]
compatible["composer_payload"] = boundary.build_composer_payload(compatible["deliverable_created"])
errs_ok, ms_ok = timed(lambda: boundary.validate(compatible))
semantic_preserved = semantic_core(base) == semantic_core(compatible)
projected_exact = compatible["composer_payload"] == boundary.build_composer_payload(compatible["deliverable_created"])

neighbor = copy.deepcopy(compatible)
neighbor["deliverable_created"]["component_tree"][0]["transport_revision"] = "UNDECLARED_V7"
neighbor["composer_payload"] = boundary.build_composer_payload(neighbor["deliverable_created"])
errs_bad, ms_bad = timed(lambda: boundary.validate(neighbor))
bad_codes = ecodes(errs_bad)
pass_f05 = errs_ok == [] and semantic_preserved and projected_exact and "COMPOSER_COMPONENT_KEY_NOT_ALLOWED" in bad_codes
put(
    "S26V3-F05-O5-COMPATIBLE-EVOLUTION-HOLDOUT",
    pass_f05,
    {
        "compatible_valid": errs_ok == [],
        "compatible_error_codes": ecodes(errs_ok),
        "compatible_field": "component_tree[0].allowed_variants",
        "semantic_core_preserved": semantic_preserved,
        "deterministic_projection_exact": projected_exact,
        "neighbor_incompatible_error_codes": bad_codes,
        "version_guard_unchanged": compatible.get("output_contract_version") == boundary.VERSION,
    },
    ms_ok + ms_bad,
    proxy(compatible) + proxy(neighbor),
    ["validate_composer_payload_boundary.py", "s26_native_golden_005/raw_output.json"],
)

# --- F10-O3: controlled compatible currentness/version delta replay ---
resolver_path = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/runtime_authority_resolver_v1.py"
resolver = load(resolver_path, "s26_w1_ext_resolver")
fixture_dir = ROOT / ".s26_matrix_version_delta"
fixture_dir.mkdir(exist_ok=True)
source_path = fixture_dir / "authority.json"
source_ref = ".s26_matrix_version_delta/authority.json"
semantic = {"requirement": "preserve canonical customer-intent semantics", "scope": "S26_MATRIX"}
request = {"input_literal": "controlled currentness delta replay", "lf_adapter_bindings": []}

def context_for(claimed_sha):
    return {
        "surface_code": "S26_MATRIX_VERSION_DELTA_SURFACE",
        "task_code": "CONTROLLED_REPLAY",
        "current_run_id": "S26-MATRIX-W1-VERSION-DELTA",
        "input_fields": {"profile_slug": "ui_architect", "output_contract_version": "UI_PRODUCTION_SPEC_V6"},
        "card_candidates": [],
        "required_authority_types": ["USER_REQUIREMENT"],
        "authority_sources": [{
            "authority_type": "USER_REQUIREMENT",
            "authority_id": "S26_MATRIX_VERSIONED_AUTHORITY",
            "run_id": "S26-MATRIX-W1-VERSION-DELTA",
            "ref": source_ref,
            "sha256": claimed_sha,
        }],
        "required_adapter_codes": [],
    }

v1_doc = {"schema": "S26_MATRIX_AUTHORITY_V1", "revision": 1, "semantic": semantic}
source_path.write_text(json.dumps(v1_doc, sort_keys=True) + "\n", encoding="utf-8")
v1_sha = sha(source_path)
out_v1, ms1 = timed(lambda: resolver.resolve_runtime_context(context_for(v1_sha), request=request, repo_root=ROOT))

v2_doc = {"schema": "S26_MATRIX_AUTHORITY_V1", "revision": 2, "semantic": semantic, "compatible_metadata": {"readback_epoch": "B"}}
source_path.write_text(json.dumps(v2_doc, sort_keys=True) + "\n", encoding="utf-8")
v2_sha = sha(source_path)
out_v2, ms2 = timed(lambda: resolver.resolve_runtime_context(context_for(v2_sha), request=request, repo_root=ROOT))

try:
    t0 = time.perf_counter()
    resolver.resolve_runtime_context(context_for(v1_sha), request=request, repo_root=ROOT)
    ms3 = (time.perf_counter() - t0) * 1000.0
    stale_code = "NO_EXCEPTION"
except Exception as exc:
    ms3 = (time.perf_counter() - t0) * 1000.0
    stale_code = getattr(exc, "code", None) or str(exc).split(":", 1)[0]

prov1 = out_v1["provenance"]["authorities"][0]
prov2 = out_v2["provenance"]["authorities"][0]
semantic_fields_stable = (
    out_v1["surface_code"] == out_v2["surface_code"]
    and out_v1["task_code"] == out_v2["task_code"]
    and out_v1["input_literal_sha256"] == out_v2["input_literal_sha256"]
    and out_v1["input_fields"] == out_v2["input_fields"]
    and v1_doc["semantic"] == v2_doc["semantic"]
)
provenance_rebound = prov1["sha256"] == v1_sha and prov2["sha256"] == v2_sha and v1_sha != v2_sha
fail_closed = stale_code == "RUNTIME_CONTEXT_PROVENANCE_SHA_MISMATCH"
pass_f10 = semantic_fields_stable and provenance_rebound and fail_closed
put(
    "S26V3-F10-O3-VERSION-DELTA-REPLAY",
    pass_f10,
    {
        "compatible_transition": "revision_1_to_revision_2_same_semantic_authority",
        "semantic_fields_stable": semantic_fields_stable,
        "v1_provenance_sha256": prov1["sha256"],
        "v2_provenance_sha256": prov2["sha256"],
        "provenance_explicitly_rebound": provenance_rebound,
        "typed_context_digest_changed": out_v1["typed_context_sha256"] != out_v2["typed_context_sha256"],
        "stale_claim_expected_code": "RUNTIME_CONTEXT_PROVENANCE_SHA_MISMATCH",
        "stale_claim_observed_code": stale_code,
        "incompatible_transition_fail_closed": fail_closed,
    },
    ms1 + ms2 + ms3,
    proxy(out_v1) + proxy(out_v2),
    ["runtime_authority_resolver_v1.py", source_ref],
)

print(json.dumps({"schema":"S26_MATRIX_V3_W1_EXTENSION_CHILD_RESULTS_V1","results":RESULTS}, sort_keys=True))
'''


def main() -> int:
    ensure_commit()
    recipes_doc = build_recipes()
    recipes = {r["case_id"]: r for r in recipes_doc["recipes"]}
    target_ids = {
        "S26V3-F05-O5-COMPATIBLE-EVOLUTION-HOLDOUT",
        "S26V3-F10-O3-VERSION-DELTA-REPLAY",
    }
    if not target_ids.issubset(recipes):
        raise SystemExit("BLOCK_W1_EXTENSION_RECIPE_MISSING")
    for case_id in target_ids:
        if recipes[case_id]["final_wave"] != "W1_FINAL_DETERMINISTIC":
            raise SystemExit("BLOCK_W1_EXTENSION_NON_W1_RECIPE:" + case_id)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="s26-matrix-w1-ext-") as tmp:
        candidate = Path(tmp) / "candidate"
        added = run(["git", "worktree", "add", "--detach", str(candidate), FINAL_SHA], check=False)
        if added.returncode != 0:
            raise SystemExit("BLOCK_CANDIDATE_WORKTREE:" + added.stderr[-800:])
        try:
            child = run([sys.executable, "-c", CHILD], cwd=candidate, check=False)
            if child.returncode != 0:
                (OUT_DIR / "extension_child_stderr.txt").write_text(child.stderr, encoding="utf-8")
                (OUT_DIR / "extension_child_stdout.txt").write_text(child.stdout, encoding="utf-8")
                raise SystemExit(f"BLOCK_W1_EXTENSION_CHILD_EXECUTION:{child.returncode}")
            lines = [line for line in child.stdout.splitlines() if line.strip()]
            payload = json.loads(lines[-1])
        finally:
            run(["git", "worktree", "remove", "--force", str(candidate)], check=False)

    measured = payload["results"]
    if set(measured) != target_ids:
        raise SystemExit("BLOCK_W1_EXTENSION_CASE_SET_MISMATCH")

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
        "schema": "S26_FAMILY_OBJECTIVE_MATRIX_V3_W1_EXTENSION_RECEIPT_V1",
        "status": "W1_EXTENSION_PASS" if not failed else "W1_EXTENSION_FAIL",
        "claim_ceiling": "TWO_W1_DETERMINISTIC_CASES_ONLY_NOT_FULL_W1_NOT_W2_NOT_W3_NOT_GATE_G_NOT_GOLDEN_NOT_PRODUCTION",
        "final_candidate_sha": FINAL_SHA,
        "case_count": len(receipts),
        "pass_count": sum(r["pass"] for r in receipts),
        "fail_count": len(failed),
        "failed_cases": failed,
        "receipts": receipts,
        "explicit_non_actions": ["NO_GATE_G_EXECUTION","NO_GOLDEN_PROMOTION","NO_PRODUCTION","NO_SUPABASE_WRITE","NO_MODEL_CALL","NO_PAID_FALLBACK","NO_MAIN_MERGE"],
    }
    path = OUT_DIR / "w1_extension_receipt.json"
    path.write_text(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({k: summary[k] for k in ("status","final_candidate_sha","case_count","pass_count","fail_count","failed_cases")}, sort_keys=True))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
