#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, importlib.util, json, sys, tempfile, time
from pathlib import Path
from typing import Any

ROOT=Path(__file__).resolve().parents[3]
VALIDATORS=ROOT/"skills/profile_creator/validators"
ASSESS=ROOT/"sandbox/lf_contract_gate_test/transversal_assets/profile_assessment"
SELECT=ROOT/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"
for p in (VALIDATORS,ASSESS,SELECT):
    if str(p) not in sys.path: sys.path.insert(0,str(p))

from plan_profile_evolution import build_evolution_plan

def load_module(path: Path, name: str):
    spec=importlib.util.spec_from_file_location(name,path)
    if spec is None or spec.loader is None: raise RuntimeError("MODULE_LOAD_FAILED")
    m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

def write_json(p: Path, value: Any):
    p.parent.mkdir(parents=True,exist_ok=True); p.write_text(json.dumps(value,indent=2,sort_keys=True)+"\n",encoding="utf-8")

def make_fixture(repo: Path, slug: str, fixture: str):
    d=repo/"profiles"/slug
    (d/"contracts").mkdir(parents=True,exist_ok=True)
    (d/"schemas").mkdir(parents=True,exist_ok=True)
    (d/"validators").mkdir(parents=True,exist_ok=True)
    (d/"SKILL.md").write_text("# Benchmark Profile\n\n## Purpose\nControlled benchmark fixture.\n\nMaintenance operation: ACTUALIZACION_PERFIL_LF\n",encoding="utf-8")
    schema={"type":"object","properties":{"result":{"type":"string"}}}
    write_json(d/"schemas/runtime_output.schema.json",schema)
    binding={
      "schema":"LF_PROFILE_RUNTIME_BINDING_V1","profile_slug":slug,"profile_code":slug.upper(),
      "runtime_schema":{"default":"schemas/runtime_output.schema.json","output_modes":{}},
      "canonical_validator":{"path":"validators/runtime_validate.py","callable":"validate"},
      "semantic_utility":{"path":"validators/runtime_semantic_utility.py","callable":"evaluate"},
      "governance":{"source_first_required":True,"schema_invention_allowed":False,"fail_closed":True,"exact_head_evidence_required":True,"post_update_baseline_required":True},
      "model_context":{"full_source_to_model":False,"source_projection":{"mode":"MARKDOWN_SECTIONS","include_sections":["Purpose"],"max_chars":512}},
      "execution_partition":{"schema":"LF_PROFILE_EXECUTION_PARTITION_V1","field_classes":{"result":"SEMANTIC"},"deterministic_materialization":{}},
      "execution_budget":{"resource_class":"STANDARD","max_prompt_tokens":2048,"max_output_tokens":1024,"min_available_memory_mb":0,"max_swap_used_pct":100}
    }
    write_json(d/"contracts/runtime_binding.json",binding)
    (d/"validators/runtime_validate.py").write_text("def validate(value):\n    return True\n",encoding="utf-8")
    (d/"validators/runtime_semantic_utility.py").write_text("def evaluate(value):\n    return value\n",encoding="utf-8")
    if fixture=="S26_VALID":
        (d/"validators/validate_pack.py").write_text("def validate_pack():\n    return True\n",encoding="utf-8")

def preflight(slug: str, revision: str):
    codes=["PROFILES-EKB-PREFLIGHT-OMISSION-001","GOV-024","AUD-018","CI-014"]
    rules=[{"code":c,"rule":"benchmark controlled rule","source_ref":f"benchmark://ekb/{c}"} for c in codes]
    checks=[{"code":c,"status":"NOT_APPLICABLE","reason":"Controlled read-only benchmark fixture; no profile write occurs.","source_ref":f"benchmark://check/{c}"} for c in codes]
    target=f"profiles/{slug}"
    return {
      "schema":"S26_PROFILE_UPDATE_LEARNING_PREFLIGHT_V1","profile_slug":slug,"repository":"benchmark-fixture","current_main_sha":revision,
      "ekb_preflight":{"status":"EKB_PREFLIGHT_COMPLETED","source":"public.lf_error_knowledge","matched_error_codes":codes,"matched_prevention_rules":rules,"prevention_checks":checks},
      "execution_binding":{"operation_code":"ACTUALIZACION_PERFIL_LF","target_type":"PERFIL","target_path":target,"execution_id":f"BENCH-{slug}","status":"IN_PROGRESS",
        "step_id":"pre_write_execution_binding_gate","step_status":"STEP_PASS_WITH_EVIDENCE","pre_write_gate_passed":True,"execution_bound_to_target_before_change":True,
        "bound_revision":revision,"server_trust_context_valid":True,"server_trust_context_source":"run-creacion-perfil-lf",
        "server_trust_context":{"resolver":"GITHUB_PUBLIC_API_EXACT_REF_V1","ref":"main","repository":"benchmark-fixture","target_path":target,
          "revision_sha":revision,"bound_revision":revision,"continuity_state":"CURRENT_BOUND","target_blob_sha":"2"*40,"baseline_revision":revision}},
      "authorized_scope":{"allowed_paths":[f"{target}/**"],"automatic_runtime_activation":False,"production_change":False}
    }

CATALOG=[
 {"capability_code":"TARGETED_EVIDENCE_ACQUISITION","signal_type":"evidence_sufficiency","accepted_values":["INSUFFICIENT"],"rank":50,"state":"AVAILABLE"},
 {"capability_code":"CAUSAL_EFFECT_LINEAGE","signal_type":"causal_requirement","accepted_values":["HIGH","REQUIRED"],"rank":40,"state":"AVAILABLE"},
 {"capability_code":"INDEPENDENT_ASSURANCE","signal_type":"risk","accepted_values":["CRITICAL"],"rank":30,"state":"AVAILABLE"},
 {"capability_code":"SAFE_CHANGE_ADMISSION","signal_type":"risk","accepted_values":["HIGH","CRITICAL"],"rank":20,"state":"AVAILABLE"}
]
POLICY={"fallback_capabilities":["PACK_VALIDATION_HARNESS"]}

def action_baseline(raw: dict[str,Any]) -> str:
    d=raw.get("decision")
    if d=="UPDATE_REQUIRED": return "PATCH"
    if d=="NO_UPDATE_REQUIRED": return "NO_CHANGE"
    return "NEEDS_MORE_EVIDENCE"

def action_candidate(raw: dict[str,Any]) -> str:
    a=raw.get("profile_assessment",{})
    if a.get("assessment_status")=="NEEDS_MORE_EVIDENCE": return "NEEDS_MORE_EVIDENCE"
    return raw.get("evolution_mode") or "NEEDS_MORE_EVIDENCE"

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("cases"); ap.add_argument("baseline_source"); ap.add_argument("method_registry"); ap.add_argument("out")
    args=ap.parse_args()
    cases=json.loads(Path(args.cases).read_text(encoding="utf-8"))
    methods=json.loads(Path(args.method_registry).read_text(encoding="utf-8"))
    baseline=load_module(Path(args.baseline_source),"baseline_v01")
    revision="1"*40
    rows=[]
    with tempfile.TemporaryDirectory(prefix="peb-") as td:
      repo=Path(td)
      baseline_contract_src=ROOT/"skills/profile_creator/contracts/s26_profile_baseline_v1.json"
      baseline_contract_dst=repo/"skills/profile_creator/contracts/s26_profile_baseline_v1.json"
      baseline_contract_dst.parent.mkdir(parents=True,exist_ok=True)
      baseline_contract_dst.write_text(baseline_contract_src.read_text(encoding="utf-8"),encoding="utf-8")
      for case in cases["cases"]:
        slug=case["fixture_profile_slug"]; make_fixture(repo,slug,case["structural_fixture"])
        pf=preflight(slug,revision)
        t=time.perf_counter_ns()
        b=baseline.build_plan(repo,slug,pf,current_revision=revision)
        b_ms=(time.perf_counter_ns()-t)/1_000_000
        t=time.perf_counter_ns()
        c=build_evolution_plan(repo,slug,pf,case["case_input"],CATALOG,POLICY,methods,current_revision=revision)
        c_ms=(time.perf_counter_ns()-t)/1_000_000
        rows.append({
          "case_id":case["case_id"],"stratum":case["stratum"],"holdout":case["holdout"],
          "baseline":{"action":action_baseline(b),"decision":b["decision"],"write_allowed":b["write_allowed"],"elapsed_ms":round(b_ms,6)},
          "candidate":{"action":action_candidate(c),"assessment_status":c["profile_assessment"]["assessment_status"],"maturity":c["profile_assessment"]["maturity"],
            "selected_capabilities":c["selection"]["selected_capabilities"],"composition_order":c["selection"]["composition_order"],
            "method_cost_points":c["selection"]["estimated_cost"]["method_cost_points"],"method_budget":c["selection"]["estimated_cost"]["budget_limit"],
            "profile_source_write_allowed":c["profile_source_write_allowed"],"candidate_materialization_allowed":c["candidate_materialization_allowed"],"elapsed_ms":round(c_ms,6)}
        })
    raw={"schema":"PROFILE_EVOLUTION_PAIRED_RAW_V1","benchmark_scope":cases["benchmark_scope"],"oracle_opened":False,
         "case_count":len(rows),"rows":rows}
    payload=json.dumps(raw,sort_keys=True,separators=(",",":")).encode()
    raw["raw_sha256"]=hashlib.sha256(payload).hexdigest()
    write_json(Path(args.out),raw)
    print(json.dumps({"status":"RAW_FROZEN","case_count":len(rows),"raw_sha256":raw["raw_sha256"],"oracle_opened":False},sort_keys=True))

if __name__=="__main__": main()
