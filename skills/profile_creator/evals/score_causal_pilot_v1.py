#!/usr/bin/env python3
"""Independent, deterministic, narrow scorer for a frozen two-arm causal pilot.

This is a factual provenance-reason check, NOT an expert-uplift benchmark.
"""
from pathlib import Path
import hashlib,json

ROOT=Path(__file__).resolve().parents[3]
PRODUCER=ROOT/"pe_causal_pilot_producer_raw_v1.json"
R3=ROOT/"pexp_r3_producer_raw.json"
PROVIDER=ROOT/"pe_causal_provider_liveness_raw_v1.json"
OUT=ROOT/"pe_causal_pilot_independent_score_v1.json"
RAW_SHA="b93ae56041779aba0f0c2ad32ea29e93ba3f92f6ee988114a1c1df6c5b786f37"
R3_SHA="8f891da0aa4a3056a60924ce56458e2dbca2cfb040599e708224893c1d5b83a2"
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def score():
    assert digest(PRODUCER)==RAW_SHA and digest(R3)==R3_SHA
    p=json.loads(PRODUCER.read_text())
    assert p["raw_frozen"] is True and p["evaluator_opened"] is False
    assert {r["arm"] for r in p["candidate_arms"]}=={"D1_STATIC","D3_WITH_VERIFIED_LINEAGE"}
    raw=json.loads(R3.read_text())
    parent=next(b["profile_execution_receipt"] for b in raw["batches"]
       if b["profile_slug"]=="systemic_root_cause_repair_lf"
       and b["batch_index"]==1 and b["arm"]=="A_ORIGINAL")
    case=next(x for x in raw["cases"] if x["case_id"]=="PEXR-001")
    ch=case["arms"]["B_UPDATER_V01"]["case_execution_receipt"]
    assert ch["case_id"]==case["case_id"]=="PEXR-001"
    assert ch["parent_profile_execution_receipt_sha256"]!=parent["receipt_sha256"]
    l=json.loads(PROVIDER.read_text())
    detected=next(t for t in l["tests"] if t["case"]=="CROSS_EXECUTION_ACTUAL_CHILD")
    assert detected["state"]=="UNLINKED"
    assert detected["reasons"]==["RECEIVER_DOES_NOT_CROSSLINK_PRODUCER"]
    scored=[]
    for arm in p["candidate_arms"]:
        assert arm["attestation"]["verified"] is True
        a=arm["answer"]
        decision_correct=a["causal_state"]=="UNLINKED" and a["decision"]=="REJECT_AND_RECONCILE"
        specific_reason=a["reason"]=="RECEIVER_DOES_NOT_CROSSLINK_PRODUCER"
        unsupported_case_mismatch=("case identifier does not match" in a["reason"].lower())
        scored.append({"arm":arm["arm"],"correct_decision":decision_correct,
          "evidence_specific_reason":specific_reason,
          "unsupported_case_id_mismatch_claim":unsupported_case_mismatch,
          "observed_wall_ms":arm["wall_ms"],
          "prompt_tokens":arm["usage"]["prompt_tokens"],
          "completion_tokens":arm["usage"]["completion_tokens"],
          "receipt_sha256":arm["execution_receipt_sha256"]})
    assert all(x["correct_decision"] for x in scored)
    assert scored[0]["unsupported_case_id_mismatch_claim"]
    assert not scored[1]["unsupported_case_id_mismatch_claim"]
    assert scored[1]["evidence_specific_reason"] and not scored[0]["evidence_specific_reason"]
    summary={"schema":"PE_CAUSAL_PILOT_INDEPENDENT_NARROW_SCORE_V1",
      "result":"DECISION_TIED_EVIDENCE_GROUNDING_DIFFERENT",
      "sample_count":1,"arm_count":2,
      "producer_sha256":digest(PRODUCER),
      "source_r3_sha256":digest(R3),
      "method_liveness_sha256":digest(PROVIDER),
      "proof":"Cross-run receipt hash does not match its claimed parent although case identifier matches",
      "arms":scored,
      "independent_semantic_assurance":"NOT_EXECUTED",
      "causal_effect_on_overall_quality":"NOT_ESTABLISHED",
      "latency_uplift_statistical":"NOT_ESTABLISHED",
      "cutover_eligible":False,
      "next_step":"FREEZE_MULTIPLE_NEW_INDEPENDENT_DISRUPTIVE_CASES"}
    if OUT.exists():raise SystemExit("ALREADY_SCORED")
    OUT.write_text(json.dumps(summary,sort_keys=True,indent=2)+"\n")
    print(json.dumps({"status":summary["result"],"scores":scored,"score_sha256":digest(OUT)},sort_keys=True))
if __name__=="__main__":score()
