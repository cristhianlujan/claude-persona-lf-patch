#!/usr/bin/env python3
"""RW1-01 C3 V3 holdout generator.

Reuses the V2 family generator but deterministically guarantees that the two
FUTURE_CAPABILITY cases exercise both DISCOVER and CAPABILITY_GAP. The holdout
remains private until RAW1 is frozen.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json
from pathlib import Path

HERE=Path(__file__).resolve().parent
V2_PATH=HERE/"generate_rw101_c3_holdout_v2.py"
spec=importlib.util.spec_from_file_location("rw101_holdout_v2",V2_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"cannot load V2 generator: {V2_PATH}")
v2=importlib.util.module_from_spec(spec)
spec.loader.exec_module(v2)

def h(x):
    return hashlib.sha256(x.encode("utf-8")).hexdigest()

def build(seed):
    doc=v2.build(seed)
    future=[c for c in doc["cases"] if c.get("family")=="FUTURE_CAPABILITY"]
    if len(future)!=2:
        raise RuntimeError(f"expected exactly 2 FUTURE_CAPABILITY cases, got {len(future)}")
    for case,step in zip(future,["DISCOVER","CAPABILITY_GAP"]):
        o=case["oracle"]
        o["acceptable_next_steps"]=[step]
        o["acceptable_next_step_sequences"]=[[step]]
        o["discovery_can_be_terminal_only_if_route_unresolved"]=(step=="DISCOVER")
        o["clarification_requires_material_discriminator"]=False
        o["clarification_reason"]=None
        o["clarification_discriminator_contract"]=None
        o["known_responsible_must_not_stall"]=False
        o["partial_progress_required"]=False
        o["partial_progress_completed_goals"]=[]
        o["partial_progress_unresolved_goals"]=[]
        o["responsibility_expectations"]=[]
        case["responsibility_fixture"]=[]
    doc["schema_version"]="RW101_C3_SECRET_HOLDOUT_V3"
    doc["v3_invariants"]={
        "future_capability_modes":["DISCOVER","CAPABILITY_GAP"],
        "critical_free_text_not_security_authority":True,
        "receipt_scope_binding_required_for_capability_gap":True,
    }
    return doc

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--seed",required=True)
    ap.add_argument("--nonce",required=True)
    ap.add_argument("--out",type=Path,required=True)
    args=ap.parse_args()
    doc=build(args.seed)
    canonical=json.dumps(doc,ensure_ascii=False,sort_keys=True,separators=(",",":"))
    commitment=h(args.nonce+"\n"+canonical)
    args.out.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({
        "status":"HOLDOUT_V3_GENERATED_PRIVATE",
        "case_count":doc["case_count"],
        "commitment_sha256":commitment,
        "manifest_sha256":h(canonical),
        "future_capability_modes":["DISCOVER","CAPABILITY_GAP"],
        "reveal_rule":"Reveal seed, nonce and holdout only after RAW1 is frozen.",
    },ensure_ascii=False))

if __name__=="__main__":
    main()
