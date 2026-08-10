#!/usr/bin/env python3
"""J11 v1.3 wrapper that classifies empirical runtime evidence semantically.

The legacy v1.2 package gate remains untouched. A JSON fixture declaring
`evidence_kind=REAL_SCREEN_RUN` is audited as RUNTIME_EVIDENCE (1–50 KB,
NUCLEO); synthetic fixtures keep the original 120–8000 byte band.
"""
from __future__ import annotations
import json
from pathlib import Path
import validate_package as legacy
from lf_common import ValidationInputError, failure

VERSION="v1.3"
legacy.GATE_VERSION=VERSION
legacy.BANDS["RUNTIME_EVIDENCE"]=(1000,50000)
_orig_audit=legacy.audit_artifact
_orig_self_test=legacy.self_test
_orig_type=legacy.artifact_type
_orig_tier=legacy.artifact_tier
_orig_structured=legacy.structured_dimensions
def structured_dimensions(rel,kind,body,parsed):
    if kind != "RUNTIME_EVIDENCE": return _orig_structured(rel,kind,body,parsed)
    data=parsed if isinstance(parsed,dict) else {}
    isolation=data.get("context_isolation") if isinstance(data.get("context_isolation"),dict) else {}
    coverage=data.get("coverage_evidence") if isinstance(data.get("coverage_evidence"),dict) else {}
    images=data.get("source_images") if isinstance(data.get("source_images"),list) else []
    return [
      legacy.Dimension("purpose_scope",data.get("evidence_kind")=="REAL_SCREEN_RUN","empirical run identity"),
      legacy.Dimension("input_contract",bool(images) and bool(data.get("source_snapshot_sha")),"source binding metadata"),
      legacy.Dimension("deterministic_procedure",data.get("locked") is True and coverage.get("full_viewport_scanned") is True,"locked full-viewport run"),
      legacy.Dimension("output_contract",all(data.get(k) for k in ("blind_read_id","execution_id","reader_identity")),"run identity tuple"),
      legacy.Dimension("positive_behavior",set(coverage.get("images_scanned") or [])=={str(x.get("image_ref")) for x in images if isinstance(x,dict)},"declared images scanned"),
      legacy.Dimension("negative_behavior",isolation.get("auxiliary_context_before_lock") is False and isolation.get("action_tools_enabled") is False and isolation.get("network_egress")=="DENY_BY_DEFAULT","blind isolation guards"),
    ]
legacy.structured_dimensions=structured_dimensions

def is_runtime(root:Path, rel:str)->bool:
    if not rel.startswith("evals/fixtures/") or not rel.endswith(".json"): return False
    try: value=json.loads((root/rel).read_text(encoding="utf-8"))
    except Exception: return False
    return isinstance(value,dict) and value.get("evidence_kind")=="REAL_SCREEN_RUN"

def audit_artifact(root:Path, rel:str, actual:set[str]):
    if not is_runtime(root,rel): return _orig_audit(root,rel,actual)
    old_type,old_tier=legacy.artifact_type,legacy.artifact_tier
    legacy.artifact_type=lambda r: "RUNTIME_EVIDENCE" if r==rel else _orig_type(r)
    legacy.artifact_tier=lambda r: "NUCLEO" if r==rel else _orig_tier(r)
    try: return _orig_audit(root,rel,actual)
    finally: legacy.artifact_type,legacy.artifact_tier=old_type,old_tier
legacy.audit_artifact=audit_artifact

def self_test():
    base=_orig_self_test()
    semantic=is_runtime(Path(__file__).resolve().parent.parent,"evals/fixtures/real_screen_onboarding_step1_blind_run.json")
    synthetic=not is_runtime(Path(__file__).resolve().parent.parent,"evals/fixtures/screen_ingestion_dense.json")
    ok=base==0 and semantic and synthetic
    print(json.dumps({"judge_code":legacy.JUDGE,"quality_gate_version":VERSION,"runtime_evidence_semantic_classification":semantic,"synthetic_fixture_preserved":synthetic,"self_test_pass":ok},sort_keys=True)); return 0 if ok else 1
legacy.self_test=self_test

def main(): return legacy.main()
if __name__=="__main__": raise SystemExit(legacy.main_guard(legacy.JUDGE,main))
