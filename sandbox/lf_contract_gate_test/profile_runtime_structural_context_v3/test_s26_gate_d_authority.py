#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path

from s26_hp001.gate_a_admission import admit_input
from s26_hp001.gate_b_governance import evaluate_governance
from s26_hp001.gate_c_card_selection import evaluate_card_selection
from s26_hp001.gate_d_authority import GateDAuthorityBlocked, evaluate_authority_resolution, validate_authority_output

HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "s26_hp001"
CONTRACT_PATH = FIXTURE / "preexecution_contract.json"

def must_block(name, mutator, payload, gate_c, contract):
    case = copy.deepcopy(payload); mutator(case)
    try: validate_authority_output(case, gate_c, contract)
    except GateDAuthorityBlocked as exc: return {"case":name,"blocked":True,"code":str(exc)}
    raise RuntimeError(f"{name}_DID_NOT_BLOCK")

def main() -> int:
    gate_a=admit_input(); gate_b=evaluate_governance(gate_a); gate_c=evaluate_card_selection(gate_b); gate_d=evaluate_authority_resolution(gate_c)
    payload=gate_d["output"]; contract=json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    if payload.get("status") != "PASS": raise RuntimeError("GATE_D_POSITIVE_NOT_PASS")
    if gate_d.get("authority_count") != 4: raise RuntimeError("GATE_D_POSITIVE_AUTHORITY_COUNT")
    if payload.get("next_gate") != "E_ADAPTER_TYPED_CONTEXT": raise RuntimeError("GATE_D_POSITIVE_NEXT_GATE")
    negatives=[]
    negatives.append(must_block("wrong_upstream_sha",lambda p:p["upstream"].update({"source_output_sha256":"0"*64}),payload,gate_c,contract))
    negatives.append(must_block("missing_required_authority",lambda p:p["authority_resolution"].pop(),payload,gate_c,contract))
    negatives.append(must_block("wrong_authority_sha",lambda p:p["authority_resolution"][0].update({"sha256":"0"*64}),payload,gate_c,contract))
    negatives.append(must_block("unknown_extra_authority",lambda p:p["authority_resolution"].append({"authority_type":"INVENTED_AUTHORITY","authority_id":"S26_HP001_INVENTED_AUTHORITY","run_id":"S26-HP-001","cross_run_declared":False,"cross_run_authorization":None,"ref":"sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/input.txt","sha256":"fdfb12f2c8c5313fef5152e1f6b6689ccae78ed94170358cf065bb02649135a1"}),payload,gate_c,contract))
    negatives.append(must_block("cross_run_authority",lambda p:p["authority_resolution"][0].update({"run_id":"OTHER-RUN","cross_run_declared":True}),payload,gate_c,contract))
    negatives.append(must_block("semantic_invention_enabled",lambda p:p["decision"].update({"semantic_authority_invention_allowed":True}),payload,gate_c,contract))
    print(json.dumps({"gate":"S26_GATE_D_AUTHORITY_MATRIX_V1","result":"PASS","positive":{"status":payload["status"],"authority_count":gate_d["authority_count"],"authority_types":sorted(item["authority_type"] for item in payload["authority_resolution"]),"next_gate":payload["next_gate"],"output_sha256":gate_d["output_sha256"]},"negative_cases":negatives,"negative_case_count":len(negatives),"production_effect":False},ensure_ascii=False,sort_keys=True)); return 0

if __name__ == "__main__": raise SystemExit(main())
