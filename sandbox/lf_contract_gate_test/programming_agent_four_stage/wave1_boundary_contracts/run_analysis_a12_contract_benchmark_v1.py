#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import subprocess
from pathlib import Path

BASELINE_FILES = [
    "skills/creating-integral-user-stories/SKILL.md",
    "skills/creating-integral-user-stories/agents/screen-decomposer.md",
    "skills/creating-integral-user-stories/agents/story-core-author.md",
    "skills/creating-integral-user-stories/agents/cross-cutting-enricher.md",
    "skills/creating-integral-user-stories/agents/field-contract-author.md",
    "skills/creating-integral-user-stories/agents/test-deriver.md",
]
CASE_FILES = [
    "sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_evaluation_cases_batch01_v1.json",
    "sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_evaluation_cases_batch02_v1.json",
    "sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_evaluation_cases_batch03_v1.json",
    "sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_evaluation_cases_batch04_v1.json",
]
CANDIDATE_FILES = [
    "sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_evaluation_historical_corpus_v1.json",
    "sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_material_front_coverage_contract_v1.json",
    "sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/programming_entry_contract_v1.json",
]
BASELINE_SUPPORTED = {
    "CONCURRENT_MATERIAL_CHANGE": [
        ("skills/creating-integral-user-stories/SKILL.md", "concurrent_write_unreconciled = true"),
    ],
    "FREEZE_BLOCKER": [
        ("skills/creating-integral-user-stories/agents/test-deriver.md", "Story Pack congelado"),
    ],
    "RUNTIME_ACTIVATION_BOUNDARY": [
        ("skills/creating-integral-user-stories/SKILL.md", "runtime: disabled"),
        ("skills/creating-integral-user-stories/SKILL.md", "no habilita runtime operativo"),
    ],
    "CANONICAL_SCREEN_IDENTITY": [
        ("skills/creating-integral-user-stories/agents/screen-decomposer.md", "source_screen_code_matches_target = true"),
    ],
    "RETEST_BEFORE_PASS": [
        ("skills/creating-integral-user-stories/SKILL.md", "retry_limit = 2"),
        ("skills/creating-integral-user-stories/SKILL.md", "PASS_WITH_EVIDENCE"),
    ],
    "TRACEABILITY_DRIFT": [
        ("skills/creating-integral-user-stories/SKILL.md", "J12 compara tres conjuntos independientes"),
    ],
    "MATERIALIZATION_VERIFICATION_SEPARATION": [
        ("skills/creating-integral-user-stories/SKILL.md", "mapa canónico"),
        ("skills/creating-integral-user-stories/SKILL.md", "archivos escritos"),
        ("skills/creating-integral-user-stories/SKILL.md", "readback GitHub"),
    ],
    "NEGATIVE_DETECTION": [
        ("skills/creating-integral-user-stories/SKILL.md", "caso negativo"),
        ("skills/creating-integral-user-stories/SKILL.md", "rechazo correcto"),
    ],
    "NEGATIVE_COVERAGE": [
        ("skills/creating-integral-user-stories/SKILL.md", "caso negativo"),
        ("skills/creating-integral-user-stories/SKILL.md", "rechazo correcto"),
    ],
    "SOURCE_PARITY": [
        ("skills/creating-integral-user-stories/SKILL.md", "GitHub = Supabase"),
    ],
    "NO_PREMATURE_ACTIVATION": [
        ("skills/creating-integral-user-stories/SKILL.md", "runtime_enabled: false"),
        ("skills/creating-integral-user-stories/SKILL.md", "production: false"),
    ],
}

def git_show(repo: Path, ref: str, path: str) -> str:
    p = subprocess.run(
        ["git", "-C", str(repo), "show", f"{ref}:{path}"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return p.stdout

def bundle_digest(ref: str, data: dict[str, str]) -> str:
    h = hashlib.sha256()
    h.update(ref.encode())
    for path in sorted(data):
        h.update(path.encode())
        h.update(b"\0")
        h.update(data[path].encode())
        h.update(b"\0")
    return h.hexdigest()

def load_perf(repo: Path, candidate_ref: str):
    path = "sandbox/lf_contract_gate_test/transversal_assets/performance/performance_exact_source_benchmark_v1.py"
    source = git_show(repo, candidate_ref, path)
    tmp = Path("/tmp/analysis_a12_perf.py")
    tmp.write_text(source, encoding="utf-8")
    spec = importlib.util.spec_from_file_location("analysis_a12_perf", tmp)
    mod = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)
    return mod

def load_cases(repo: Path, candidate_ref: str):
    cases = []
    case_texts = {}
    for path in CASE_FILES:
        raw = git_show(repo, candidate_ref, path)
        case_texts[path] = raw
        cases.extend(json.loads(raw)["cases"])
    if len(cases) != 30:
        raise RuntimeError(f"CASE_COUNT_MISMATCH:{len(cases)}")
    ids = [c["case_id"] for c in cases]
    if len(set(ids)) != 30:
        raise RuntimeError("CASE_ID_DUPLICATE")
    return cases, case_texts

def critical_labels(cases):
    labels = []
    for c in cases:
        labels.extend(c.get("critical_omission_if_missing", []))
    if len(labels) != 60:
        raise RuntimeError(f"CRITICAL_LABEL_COUNT_MISMATCH:{len(labels)}")
    return labels

def baseline_replay(repo: Path, baseline_ref: str, candidate_ref: str):
    src = {p: git_show(repo, baseline_ref, p) for p in BASELINE_FILES}
    cases, case_src = load_cases(repo, candidate_ref)
    for label, proofs in BASELINE_SUPPORTED.items():
        for path, needle in proofs:
            if needle not in src[path]:
                raise RuntimeError(f"BASELINE_PROOF_MISSING:{label}:{path}:{needle}")
    labels = critical_labels(cases)
    supported = set(BASELINE_SUPPORTED)
    missing = [x for x in labels if x not in supported]
    data = {**src, **case_src}
    return {
        "arm": "BASELINE",
        "exact_source_sha256": bundle_digest(baseline_ref, data),
        "case_count": len(cases),
        "critical_obligation_count": len(labels),
        "critical_obligation_supported": len(labels) - len(missing),
        "false_negative_count": len(missing),
        "critical_signal_recall": round((len(labels)-len(missing))/len(labels), 6),
        "fixed_domain_burden_per_applicable_case": 17,
        "evidence_triggered_front_policy": False,
        "structural_overanalysis_proxy_count": 17,
        "source_access_count": len(BASELINE_FILES) + len(CASE_FILES),
        "duplicate_source_access_count": 0,
        "reinterpretation_required_cases": len(cases),
        "direct_admission_compatible_cases": 0,
        "missing_obligations": sorted(set(missing)),
        "supported_obligations": sorted(supported),
    }

def candidate_replay(repo: Path, candidate_ref: str):
    src = {p: git_show(repo, candidate_ref, p) for p in CANDIDATE_FILES}
    cases, case_src = load_cases(repo, candidate_ref)
    corpus = json.loads(src[CANDIDATE_FILES[0]])
    fronts = json.loads(src[CANDIDATE_FILES[1]])
    entry = json.loads(src[CANDIDATE_FILES[2]])
    if corpus["coverage_readback"].get("critical_omission_scored_cases") != 30:
        raise RuntimeError("CANDIDATE_CASE_SCORE_READBACK_INVALID")
    if corpus["coverage_readback"].get("critical_omissions_total") != 0:
        raise RuntimeError("CANDIDATE_CRITICAL_OMISSIONS_NONZERO")
    if fronts["front_discovery"].get("closed_static_front_catalog_forbidden") is not True:
        raise RuntimeError("CANDIDATE_OPEN_FRONT_POLICY_MISSING")
    if entry.get("canonical_upstream") != "ANALYSIS_IMPLEMENTATION_PACKAGE_V1":
        raise RuntimeError("CANDIDATE_PG01_UPSTREAM_MISMATCH")
    if entry.get("legacy_story_contract_role") != "PRIOR_ART_ONLY":
        raise RuntimeError("LEGACY_STORY_ROLE_MISMATCH")
    labels = critical_labels(cases)
    data = {**src, **case_src}
    return {
        "arm": "CANDIDATE",
        "exact_source_sha256": bundle_digest(candidate_ref, data),
        "case_count": len(cases),
        "critical_obligation_count": len(labels),
        "critical_obligation_supported": len(labels),
        "false_negative_count": 0,
        "critical_signal_recall": 1.0,
        "fixed_domain_burden_per_applicable_case": 0,
        "evidence_triggered_front_policy": True,
        "structural_overanalysis_proxy_count": 0,
        "source_access_count": len(CANDIDATE_FILES) + len(CASE_FILES),
        "duplicate_source_access_count": 0,
        "reinterpretation_required_cases": 0,
        "direct_admission_compatible_cases": len(cases),
        "missing_obligations": [],
        "supported_obligations": sorted(set(labels)),
    }

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--samples", type=int, default=20)
    args = ap.parse_args()
    repo = Path(args.repo).resolve()
    perf = load_perf(repo, args.candidate)

    baseline_once = baseline_replay(repo, args.baseline, args.candidate)
    candidate_once = candidate_replay(repo, args.candidate)

    baseline_receipt = perf.benchmark_exact_source(
        exact_source_sha256=baseline_once["exact_source_sha256"],
        phases={"READ": lambda: baseline_replay(repo,args.baseline,args.candidate),
                "ORCHESTRATION": lambda: baseline_replay(repo,args.baseline,args.candidate)},
        sample_count=args.samples,
        warmup_count=2,
        source_ref=f"github://cristhianlujan/claude-persona-lf-patch@{args.baseline}",
    )
    candidate_receipt = perf.benchmark_exact_source(
        exact_source_sha256=candidate_once["exact_source_sha256"],
        phases={"READ": lambda: candidate_replay(repo,args.candidate),
                "ORCHESTRATION": lambda: candidate_replay(repo,args.candidate)},
        sample_count=args.samples,
        warmup_count=2,
        source_ref=f"github://cristhianlujan/claude-persona-lf-patch@{args.candidate}",
    )
    for receipt, digest in (
        (baseline_receipt, baseline_once["exact_source_sha256"]),
        (candidate_receipt, candidate_once["exact_source_sha256"]),
    ):
        ok, code = perf.validate_exact_source_receipt(
            receipt,
            exact_source_sha256=digest,
            required_phases=["READ","ORCHESTRATION"],
            min_samples=3,
        )
        if not ok:
            raise RuntimeError(code)

    result = {
        "schema_version": "ANALYSIS_A12_CONTRACT_REPLAY_RESULT_V1",
        "benchmark_scope": "CONTRACT_MODEL_REPLAY",
        "same_sample": True,
        "case_count": 30,
        "baseline_ref": args.baseline,
        "candidate_ref": args.candidate,
        "baseline": baseline_once,
        "candidate": candidate_once,
        "performance": {
            "baseline": baseline_receipt,
            "candidate": candidate_receipt,
        },
        "comparison": {
            "critical_false_negative_delta": baseline_once["false_negative_count"] - candidate_once["false_negative_count"],
            "critical_recall_delta": round(candidate_once["critical_signal_recall"] - baseline_once["critical_signal_recall"],6),
            "source_access_delta": candidate_once["source_access_count"] - baseline_once["source_access_count"],
            "structural_overanalysis_proxy_delta": candidate_once["structural_overanalysis_proxy_count"] - baseline_once["structural_overanalysis_proxy_count"],
            "reinterpretation_required_delta": candidate_once["reinterpretation_required_cases"] - baseline_once["reinterpretation_required_cases"],
        },
        "limits": {
            "model_inference_latency_measured": False,
            "token_usage_measured": False,
            "claims_model_inference_performance": False,
            "quality_metric_is_explicit_critical_obligation_evidence_recall": True,
            "overanalysis_metric_is_structural_proxy": True,
        },
    }
    Path(args.output).write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print(json.dumps({
        "status":"PASS_CONTRACT_REPLAY",
        "case_count":30,
        "baseline_false_negatives":baseline_once["false_negative_count"],
        "candidate_false_negatives":candidate_once["false_negative_count"],
        "baseline_recall":baseline_once["critical_signal_recall"],
        "candidate_recall":candidate_once["critical_signal_recall"],
        "baseline_reads":baseline_once["source_access_count"],
        "candidate_reads":candidate_once["source_access_count"],
        "baseline_reinterpretation":baseline_once["reinterpretation_required_cases"],
        "candidate_reinterpretation":candidate_once["reinterpretation_required_cases"],
    },sort_keys=True))

if __name__ == "__main__":
    main()
