#!/usr/bin/env python3
"""GPT_NATIVE handoff for Profile Evolution; no model inference in Python.

Reuses the canonical LF execution contract and selected-method/evidence assets.
Producer GPT executions and independent GPT reviews MUST happen in governed
native contexts and supply observable receipts; no fake native completion.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any, Callable

ROOT=Path(__file__).resolve().parents[3]
RUNTIME=ROOT/"sandbox/lf_contract_gate_test/profile_execution_runtime"
sys.path.insert(0,str(RUNTIME))
from profile_execution_contract import build_execution_contract,canonical_json_sha256,validate_execution_contract
from validate_profile_execution import validate_receipt
from semantic_obligation_manifest import validate_obligation_manifest

CODE="PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF"
PROFILE="profiles/systemic_root_cause_repair_lf/SKILL.md"
CORPUS="skills/profile_creator/evals/profile_causal_unseen_holdout_remaining_v1.json"
SELECTOR="skills/profile_creator/evals/results/pe_causal_v3_selector_real_receipts_v1.json"
CARDS="skills/profile_creator/evals/results/pe_causal_unseen_remaining_cards_v1.json"
ADAPTER="skills/profile_creator/evals/prepare_profile_evolution_gpt_native_v1.py"
REVIEW_CONTRACT="profiles/quality_pack/contracts/independent_chat_semantic_review_contract.md"
QUALITY_GATE="sandbox/lf_contract_gate_test/profile_execution_runtime/validate_semantic_quality.py"
ARMS=("D1_STATIC","D2_SELECTOR_ONLY","D3_TYPED_METHOD")
RUN_PREFIX="PE-GPT-NATIVE-TRANSPORT-CALIBRATION-V1"

class HandoffError(ValueError):
    pass

def sha(data:bytes)->str:
    return hashlib.sha256(data).hexdigest()

def load(path:str)->dict:
    p=ROOT/path
    if not p.is_file():
        raise HandoffError("SOURCE_MISSING:"+path)
    return json.loads(p.read_text(encoding="utf-8"))

def ref(path:str)->dict[str,str]:
    return {"path":path,"sha256":sha((ROOT/path).read_bytes())}

def package()->dict[str,Any]:
    corpus,selector,cards=load(CORPUS),load(SELECTOR),load(CARDS)
    if corpus.get("case_count")!=4 or len(corpus.get("cases",[]))!=4:
        raise HandoffError("CORPUS_NOT_FROZEN_FOUR_CASES")
    if selector.get("status")!="FROZEN_NON_AUTHORITY_SELECTION" or cards.get("status")!="FROZEN_SUBSET_FROM_PRIOR_SOURCE":
        raise HandoffError("SOURCE_STATUS_NOT_FROZEN")
    if selector.get("count")!=4 or selector.get("method_invocations")!=0 or selector.get("authority_activation") is not False:
        raise HandoffError("SELECTOR_NOT_NON_AUTHORITY")
    if cards.get("case_count")!=4 or cards.get("cutover_eligible") is not False:
        raise HandoffError("METHOD_CARD_NOT_NON_AUTHORITY")
    cases=corpus["cases"]
    bysel={x["case_id"]:x for x in selector["receipts"]}
    bycard={x["case_id"]:x for x in cards["cards"]}
    ids=[x["case_id"] for x in cases]
    if len(set(ids))!=4 or set(ids)!=set(bysel) or set(ids)!=set(bycard):
        raise HandoffError("CASE_SET_MISMATCH")
    sources={name:ref(name) for name in
             (PROFILE,CORPUS,SELECTOR,CARDS,ADAPTER,REVIEW_CONTRACT,QUALITY_GATE)}
    source_manifest=[{"ref":PROFILE,"content_sha256":sources[PROFILE]["sha256"]}]
    profile_source_sha256=canonical_json_sha256(source_manifest)
    outputs=[]
    for case in cases:
        cid=case["case_id"]
        selection=bysel[cid]
        card=bycard[cid]
        if selection.get("method_id")!="CAUSAL_ANALYSIS":
            raise HandoffError("SELECTOR_METHOD_MISMATCH:"+cid)
        if (selection.get("source_registry_execution_permission") is not False or
            selection.get("method_execution")!="NOT_EXECUTED" or
            selection["selection"].get("execution_authorized") is not False or
            canonical_json_sha256(selection["selection"])!=selection["selection_sha256"]):
            raise HandoffError("SELECTOR_RECEIPT_INVALID:"+cid)
        if selection.get("source_evidence_refs")!=[x["evidence_ref"] for x in case["observations"]]:
            raise HandoffError("SELECTOR_PROVENANCE_MISMATCH:"+cid)
        if (card.get("source_attestation")!="TEST_NON_AUTHORITY" or
            card.get("method_decision") not in
             ("COLLECT_MORE_EVIDENCE","INVESTIGATE_H1","INVESTIGATE_H2","INVESTIGATE_H3") or
            card.get("causality_proven") is not False):
            raise HandoffError("METHOD_CARD_NOT_ADMITTED:"+cid)
        source_refs=[x["evidence_ref"] for x in case["observations"]]
        for arm in ARMS:
            runid=RUN_PREFIX+":"+cid+":"+arm
            payload={"case_id":cid,"scenario":case["scenario"],
                     "hypotheses":case["hypotheses"],"observations":case["observations"],
                     "instruction":"Identify refuted hypotheses, choose next action, do not claim causality proven. Return JSON with case_id, decision, falsified, causality_proven, reason_claim_ids."}
            if arm=="D2_SELECTOR_ONLY":
                payload["selector_result"]={
                   "method_id":selection["method_id"],
                   "selection_sha256":selection["selection_sha256"],
                   "method_executed":False,"method_result_present":False,
                   "execution_authorized":False}
            if arm=="D3_TYPED_METHOD":
                payload["tool_result"]={
                   "method_id":"CAUSAL_ANALYSIS",
                   "source_attestation":card["source_attestation"],
                   "method_receipt_sha256":card["method_receipt_sha256"],
                   "recommended_action":card["method_decision"],
                   "falsified_hypotheses":card["falsified_hypotheses"],
                   "causality_proven":False,
                   "supported_claims":card["supported_claims"],
                   "governed_method_admission":False}
            literal=json.dumps(payload,ensure_ascii=False,sort_keys=True,separators=(",",":"))
            payload_sha=sha(literal.encode("utf-8"))
            obligations=[
              {"obligation_id":"PROFILE_NO_CAUSAL_OVERCLAIM","rule":"No unsupported proof of causality",
               "check_type":"EXACT_VALUE","evidence_pointer":"/causality_proven",
               "authority_ids":["PROFILE-CONTRACT"],"expected_value":"false"},
              {"obligation_id":"PROFILE_GROUNDED_CLAIMS","rule":"Every explanation claim must be supported or explicitly uncertain",
               "check_type":"SEMANTIC_RELATION","evidence_pointer":"/reason_claim_ids",
               "authority_ids":["PROFILE-CONTRACT"],
               "question":"Are all cited claims supported by verified provenance, with unresolved evidence identified?"},
              {"obligation_id":"INPUT_CASE_ID","rule":"Must answer the frozen case, not a substituted task",
               "check_type":"EXACT_VALUE","evidence_pointer":"/case_id",
               "authority_ids":["EXECUTION-INPUT"],"expected_value":cid},
              {"obligation_id":"INPUT_DECISION_PROVENANCE","rule":"Decision must respect independently verified inputs and method limits",
               "check_type":"SEMANTIC_RELATION","evidence_pointer":"/decision",
               "authority_ids":["EXECUTION-INPUT"],
               "question":"Does the decision follow verified observations, and preserve uncertainty when evidence is insufficient?"},
              {"obligation_id":"INPUT_FALSIFICATION_PROVENANCE","rule":"Falsification must cite actual verified contradictory observations",
               "check_type":"SEMANTIC_RELATION","evidence_pointer":"/falsified",
               "authority_ids":["EXECUTION-INPUT"],
               "question":"Are exactly the refuted hypotheses listed, with verified contradictory evidence?"}
            ]
            manifest=validate_obligation_manifest({
                "schema":"PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1",
                "execution_id":runid,"profile_code":CODE,
                "profile_source_sha256":profile_source_sha256,
                "input_sha256":payload_sha,
                "authority_sources":[
                  {"authority_id":"PROFILE-CONTRACT","authority_type":"PROFILE_CONTRACT",
                   "source_ref":PROFILE,"source_sha256":profile_source_sha256,
                   "required_obligation_ids":["PROFILE_NO_CAUSAL_OVERCLAIM","PROFILE_GROUNDED_CLAIMS"]},
                  {"authority_id":"EXECUTION-INPUT","authority_type":"EXECUTION_INPUT",
                   "source_ref":"payload-sha256:"+payload_sha,"source_sha256":payload_sha,
                   "required_obligation_ids":["INPUT_CASE_ID","INPUT_DECISION_PROVENANCE","INPUT_FALSIFICATION_PROVENANCE"]}
                ],
                "obligations":obligations,
            },expected_execution_id=runid,expected_profile_code=CODE,
              expected_profile_source_sha256=profile_source_sha256,
              expected_input_sha256=payload_sha)
            manifest_sha=canonical_json_sha256(manifest)
            binding={"profile_source":profile_source_sha256,
                     "task_sha256":payload_sha,"case_id":cid,
                     "arm":arm,"run_id":runid,
                     "obligation_manifest_sha256":manifest_sha,
                     "selector_sha256":selection["selection_sha256"] if arm!="D1_STATIC" else None,
                     "method_receipt_sha256":card["method_receipt_sha256"] if arm=="D3_TYPED_METHOD" else None}
            contract=build_execution_contract(
                run_id=runid,profile_code=CODE,
                profile_version="resolved:"+profile_source_sha256[:16],
                objective="Evaluate known causal scenarios through the LF GPT_NATIVE lane (test only).",
                authorized_scope=["PROFILE_EVOLUTION_CANDIDATE",cid,arm,"SYNTHETIC_CALIBRATION_ONLY"],
                current_gate="PE10E_C4_GPT_NATIVE_CALIBRATION",
                allowed_actions=["MODEL_RUNTIME_EXECUTE","RAW_CAPTURE","INDEPENDENT_REVIEW_HANDOFF"],
                forbidden_actions=["PROFILE_AUTHORITY_WRITE","PRODUCTION_ACTIVATION",
                                   "CAPABILITY_PROMOTION","CUTOVER","PAID_MODEL_API"],
                required_checks=["GPT_NATIVE_SOURCE_BINDING","RECEIPT_ATTESTATION",
                                 "SCOPED_SEMANTIC_OBLIGATION_COVERAGE",
                                 "INDEPENDENT_SEMANTIC_REVIEW"],
                required_evidence=["profile_execution","runtime_attestation","raw_output",
                                   "scoped_semantic_manifest","independent_quality_review"],
                closure_conditions=["FROZEN_RAW","INDEPENDENT_SEMANTIC_REVIEW_VALIDATED","NO_PRODUCTION"],
                input_governance_ref="profile-evolution://known-case-candidate-calibration",
                card_refs_and_hashes=[],
                adapter_ref="GPT_NATIVE:"+ADAPTER+"@sha256:"+sources[ADAPTER]["sha256"],
                context_fingerprint=canonical_json_sha256(binding),
                tool_permissions=["READ_GITHUB","READ_SUPABASE"],
                executor_mode="GPT_NATIVE",
                card_resolution={"mode":"GENERIC_SAFE","critical_authority_missing":False,
                  "unresolved_capabilities":[],
                  "core_policy_ref":REVIEW_CONTRACT,
                  "core_policy_sha256":sources[REVIEW_CONTRACT]["sha256"],
                  "fallback_reason":"No profile-specific card; existing LF native contract and review boundary."})
            assert validate_execution_contract(contract,expected_executor_mode="GPT_NATIVE")==[]
            outputs.append({"run_id":runid,"case_id":cid,"arm":arm,
                            "profile_source_manifest":source_manifest,
                            "profile_source_sha256":profile_source_sha256,
                            "input_literal":literal,"input_sha256":payload_sha,
                            "execution_contract":contract,
                            "scoped_semantic_obligation_manifest":manifest,
                            "scoped_semantic_obligation_manifest_sha256":manifest_sha,
                            "semantic_obligation_scope":"FIVE_TEST_CASE_OBLIGATIONS_NOT_COMPLETE_EXPERTISE",
                            "producer_status":"PENDING_GPT_NATIVE_EXECUTION",
                            "producer_receipt":None,"review_status":"PENDING_INDEPENDENT_CHAT_CONTEXT"})
    return {"schema":"PROFILE_EVOLUTION_GPT_NATIVE_HANDOFF_V1",
       "scope":"KNOWN_SYNTHETIC_CALIBRATION_NOT_BLIND_HOLDOUT",
       "operation":"ACTUALIZACION_PERFIL_LF",
       "resolver":"GPT_RUNTIME_WITH_SUPABASE_CONTEXT",
       "runtime_mode":"GPT_NATIVE",
       "semantic_review_mode":"INDEPENDENT_CHAT_CONTEXT",
       "semantic_gate_ref":QUALITY_GATE,
       "semantic_review_contract_ref":REVIEW_CONTRACT,
       "sources":sources,
       "runs":outputs,
       "run_count":len(outputs),"case_count":len(cases),
       "gpt_model_invocations":0,
       "independent_review_invocations":0,
       "model_runtime_costs":"NOT_OBSERVED",
       "producer_status":"NOT_EXECUTED",
       "profile_authority_write":False,
       "production_activation":False,
       "cutover_eligible":False}

def verify_candidate_receipt(
    bundle:dict,receipt:Any,raw_output:Any=None,
    *, independent_attestation_verifier:Callable[[dict,Any],bool]|None=None,
)->list[str]:
    """Canonical structural proof + REQUIRED independent provider attestation.

    Passing this test-only preflight is NOT downstream semantic authorization.
    The callback must be implemented by the governed native runtime/verifier,
    never by a producer self-declaration or a synthetic adapter.
    """
    if not isinstance(receipt,dict):
        return ["GPT_NATIVE_RECEIPT_MISSING"]
    runs={r["run_id"]:r for r in bundle.get("runs",[])}
    run=runs.get(receipt.get("execution_id"))
    if run is None:
        return ["UNKNOWN_EXECUTION_ID"]
    errors=validate_receipt(
        receipt,
        expected_profile_code=CODE,
        expected_input_literal=run["input_literal"],
        expected_raw_output=raw_output,
        expected_profile_source_sha256=run["profile_source_sha256"],
    )
    if raw_output is None:
        errors.append("RAW_OUTPUT_REQUIRED_FOR_VERIFICATION")
    attestation=receipt.get("runtime_attestation",{})
    if not isinstance(attestation,dict):
        attestation={}
    if attestation.get("executor_mode")!="GPT_NATIVE":
        errors.append("GPT_NATIVE_ATTESTATION_MODE_INVALID")
    if not callable(independent_attestation_verifier):
        errors.append("INDEPENDENT_NATIVE_ATTESTATION_VERIFIER_REQUIRED")
    else:
        try:
            if independent_attestation_verifier(receipt,raw_output) is not True:
                errors.append("INDEPENDENT_NATIVE_ATTESTATION_NOT_VERIFIED")
        except Exception:
            errors.append("INDEPENDENT_NATIVE_ATTESTATION_NOT_VERIFIED")
    return sorted(set(errors))

def main()->int:
    p=argparse.ArgumentParser()
    p.add_argument("--output",type=Path)
    p.add_argument("--check-placeholder-receipt",action="store_true")
    args=p.parse_args()
    b=package()
    if args.check_placeholder_receipt:
        assert "INDEPENDENT_NATIVE_ATTESTATION_VERIFIER_REQUIRED" in verify_candidate_receipt(
            b,{"execution_id":b["runs"][0]["run_id"],"executor_mode":"GPT_NATIVE"})
    encoded=json.dumps(b,ensure_ascii=False,indent=2,sort_keys=True)+"\n"
    if args.output:
        if args.output.exists():
            if args.output.read_text(encoding="utf-8")!=encoded:
                raise SystemExit("FROZEN_GPT_HANDOFF_DRIFT")
        else:
            args.output.parent.mkdir(parents=True,exist_ok=True)
            args.output.write_text(encoded,encoding="utf-8")
    print(json.dumps({"status":"GPT_NATIVE_HANDOFF_PREPARED_NOT_EXECUTED",
           "runs":b["run_count"],"cases":b["case_count"],
           "native_model_calls":b["gpt_model_invocations"],
           "bundle_sha256":sha(encoded.encode()),"cutover_eligible":False},sort_keys=True))
    return 0

if __name__=="__main__":
    raise SystemExit(main())
