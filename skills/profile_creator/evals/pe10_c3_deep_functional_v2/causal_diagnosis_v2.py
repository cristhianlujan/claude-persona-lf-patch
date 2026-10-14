"""Sequential evidence-bound Bayesian diagnosis for a non-authority shadow.

NOT a proof of causation. Likelihood independence is an explicit model
assumption. No provider receipt verification or policy write occurs here.
"""
from __future__ import annotations
import math

def entropy(ps):
    return -sum(p*math.log2(p) for p in ps if p>0)

def validate_hypotheses(hypotheses):
    if not isinstance(hypotheses,list) or len(hypotheses)<2 or len(hypotheses)>20:
        raise ValueError("HYPOTHESES_INVALID")
    ids=[h.get("id") for h in hypotheses]
    ps=[h.get("prior") for h in hypotheses]
    if len(set(ids))!=len(ids) or any(not isinstance(x,str) or not x.strip() for x in ids):
        raise ValueError("HYPOTHESIS_IDS_INVALID")
    if any(type(x) not in (float,int) or not math.isfinite(x) or x<=0 for x in ps) or abs(sum(ps)-1)>1e-9:
        raise ValueError("PRIORS_NOT_NORMALIZED")
    return ids,ps

def update_diagnosis(hypotheses,observations,probes=None):
    ids,probs=validate_hypotheses(hypotheses)
    if not isinstance(observations,list):raise ValueError("OBSERVATIONS_INVALID")
    refs=set()
    history=[]
    for obs in observations:
        if not isinstance(obs,dict):raise ValueError("EVIDENCE_ROW_INVALID")
        ref=obs.get("evidence_ref");origin=obs.get("origin_id")
        if not isinstance(ref,str) or not ref or not isinstance(origin,str) or not origin:
            raise ValueError("EVIDENCE_PROVENANCE_MISSING")
        if origin in refs:raise ValueError("CORRELATED_SOURCE_DOUBLE_COUNT")
        refs.add(origin)
        likelihood=obs.get("likelihood_by_hypothesis")
        if not isinstance(likelihood,dict) or set(likelihood)!=set(ids):
            raise ValueError("EVIDENCE_LIKELIHOODS_INCOMPLETE")
        if any(type(v) not in (int,float) or not math.isfinite(v) or not 0<=v<=1 for v in likelihood.values()):
            raise ValueError("EVIDENCE_LIKELIHOOD_INVALID")
        # Given explicitly independent origins, apply conditional likelihood;
        # this does not itself verify statistical conditional independence.
        weights=[probs[i]*likelihood[h] for i,h in enumerate(ids)]
        z=sum(weights)
        if z<=0:raise ValueError("EVIDENCE_MODEL_INCONSISTENT")
        probs=[x/z for x in weights]
        history.append({"evidence_ref":ref,"origin_id":origin,
                        "posterior":dict(zip(ids,probs))})
    ranked=sorted(zip(ids,probs),key=lambda hp:(-hp[1],hp[0]))
    proposals=[]
    for probe in probes or []:
        if not isinstance(probe,dict) or not isinstance(probe.get("probe_id"),str):
            raise ValueError("PROBE_INVALID")
        conditional=probe.get("pr_positive_given_hypothesis")
        if not isinstance(conditional,dict) or set(conditional)!=set(ids):
            raise ValueError("PROBE_MODEL_INCOMPLETE")
        if any(type(v) not in (int,float) or not math.isfinite(v) or not 0<=v<=1 for v in conditional.values()):
            raise ValueError("PROBE_PROB_INVALID")
        positive=sum(probs[i]*conditional[h] for i,h in enumerate(ids))
        current_entropy=entropy(probs)
        expected_entropy=0.0
        if positive>0:
            yes=[probs[i]*conditional[h]/positive for i,h in enumerate(ids)]
            expected_entropy+=positive*entropy(yes)
        if positive<1:
            no=[probs[i]*(1-conditional[h])/(1-positive) for i,h in enumerate(ids)]
            expected_entropy+=(1-positive)*entropy(no)
        proposals.append({"probe_id":probe["probe_id"],
                          "expected_information_gain_bits":max(0.0,current_entropy-expected_entropy),
                          "predicted_positive_probability":positive,
                          "probe_executed":False})
    proposals.sort(key=lambda x:(-x["expected_information_gain_bits"],x["probe_id"]))
    return {"status":"HYPOTHESIS_PRIORITIZATION_NOT_CAUSAL_PROOF",
            "posterior":dict(zip(ids,probs)),
            "ranking":[{"id":h,"posterior":p} for h,p in ranked],
            "evidence_history":history,"next_probes":proposals,
            "assumptions":["Conditional independence of distinct evidence origins is unverified",
                           "Likelihoods and priors are declared model inputs, not observed ground truth"],
            "root_cause_certified":False,"external_falsification_required":True,
            "provider_attestation_verified":False,"cutover_eligible":False}
