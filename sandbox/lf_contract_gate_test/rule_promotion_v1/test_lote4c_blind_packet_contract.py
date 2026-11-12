#!/usr/bin/env python3
"""Static anti-leak/novelty/minimum-case checks. No semantic PASS implied."""
import collections
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent

def load(name):
    return json.loads((HERE/name).read_text(encoding="utf-8"))

def main():
    blind=load("lote4c_fresh_blind_v1.json")
    key=load("lote4c_fresh_answer_key_v1.json")
    core=load("lote4_semantic_mutations_labeled_v1.json")
    adv=load("lote4_adversarial_mutations_labeled_v1.json")
    assert blind["schema_version"]=="LF_L4C_BLIND_PACKET_V1"
    assert key["schema_version"]=="LF_L4C_PRIVATE_ANSWER_KEY_V1"
    assert len(blind["cases"])==len(key["cases"])==154
    old_descriptions={c["mutated_description"] for c in core["cases"]+adv["cases"]}
    case_ids=[x["id"] for x in blind["cases"]]
    answer_ids=[x["id"] for x in key["cases"]]
    assert len(set(case_ids))==154 and set(case_ids)==set(answer_ids)
    assert case_ids==answer_ids, "Answer key and blind ordering drifted"
    assert len({x["proposal"]["description"] for x in blind["cases"]})==154
    assert not (old_descriptions & {x["proposal"]["description"] for x in blind["cases"]})
    for case in blind["cases"]:
        assert set(case.keys()) <= {"id","base_rule","proposal","related_rule"}
        assert len(case["id"])>=8 and case["id"].startswith("K")
        assert "description" in case["base_rule"]
        assert "description" in case["proposal"]
        assert "configuration" in case["base_rule"]
        assert "config_patch" in case["proposal"]
        assert case["proposal"]["operation"] in {"CREATE","MODIFY"}
    forbidden={"label","expected","family","transformation","mutation_index","answer","ground_truth","truth"}
    def scan(node):
        if isinstance(node,dict):
            assert forbidden.isdisjoint(node), f"Sensitive key leaked: {forbidden & set(node)}"
            for value in node.values(): scan(value)
        elif isinstance(node,list):
            for value in node: scan(value)
    scan(blind)
    counts=collections.Counter(x["family"] for x in key["cases"])
    labels=collections.Counter(x["expected"] for x in key["cases"])
    assert labels["BLOCK"]==130 and labels["ALLOW"]==24
    assert counts["HEALTHY_CONTROL"]==24
    defect_families={k:v for k,v in counts.items() if k!="HEALTHY_CONTROL"}
    assert len(defect_families)==13
    assert all(n>=10 for n in defect_families.values())
    assert all(x["provenance"] in
               {"INJECTED_KNOWN_DEFECT","CONTROL_PRESERVING_PARAPHRASE"}
               for x in key["cases"])
    # Each case's base rule must be one of the six known frozen baselines.
    bases={b["codigo"]:b for b in core["baselines"]}
    for c in blind["cases"]:
        src=bases[c["base_rule"]["code"]]
        assert c["base_rule"]["description"]==src["descripcion"]
        assert c["base_rule"]["configuration"]==src["valor_config"]
    print("RAW_L4C_BLIND_CONTRACT "+json.dumps({
        "total":len(case_ids),"defect_families":len(defect_families),
        "defects":labels["BLOCK"],"healthy":labels["ALLOW"],
        "minimum_defects_per_family":min(defect_families.values()),
        "opaque_ids":True,"labels_absent_from_blind":True,
        "reused_descriptions":0,"review_model_invoked":False,
        "blind_fingerprint":blind["integrity_fingerprint_fnv32"]
    },sort_keys=True),flush=True)
    print("PASS_L4C_BLIND_PACKET_STRUCTURE_NOT_SEMANTIC_QUALITY",flush=True)

if __name__=="__main__":
    main()
