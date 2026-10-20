#!/usr/bin/env python3
from __future__ import annotations
import copy, hashlib, importlib.util, json, os, subprocess
from pathlib import Path

SNAPSHOT="469089b796cae8de01c9506c52c9ae9b72d97d0d"
OUT=Path(os.environ.get("RW102_C3_V2_OUT","/tmp/rw102_c3_v2_review"))
OUT.mkdir(parents=True,exist_ok=True)
A="A_MIN_ROUTER_SEMANTIC_SPECIALIST"
B="B_MIN_CLASSIFIER_COMPOSITE_DERIVATION"
C="C_BOUNDED_SEMANTIC_ROUTER"
D="D_CURRENT_HYBRID_BASELINE"
FILES={
 "wave":("docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md","4bb64d568c3f005cf454fb223b4a5ed699c34504"),
 "c1":("docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md","470979c9b9a0dd9a728601b6ec5f577d7445f8b5"),
 "corpus":("docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V2.json","cf22d9889eb008dc7afcf64dd1b3712b9536ec98"),
 "validator":("sandbox/lf_contract_gate_test/router_wave/validate_rw102_architecture_competition_v2.py","3c0a6eb4419574accf2138725ef8cd95d4ef210e"),
 "workflow":(".github/workflows/lf-router-level2-advisory-tests.yml","cb3adc5e050ee5f10b325e6607814319c746dd55"),
 "handoff":("docs/programming-agent/router_wave/RW1_02_C3_BLIND_JUDGE_HANDOFF_V2.md","aa4654dc81dd156198b7a48afaa88efae8df7913"),
}
PRODUCER=("docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V2.json","09d42bd6ebbcb8b140d4abd92802c5be72078fb9")
PRIOR_REVISE=("docs/programming-agent/router_wave/RW1_02_C3_ADVERSARIAL_REVISE_V1.json","90e7db8d03310b9b1b06e61aa07339d5d6021775")

def git_bytes(path:str)->bytes:
    return subprocess.check_output(["git","show",f"{SNAPSHOT}:{path}"])

def git_blob(data:bytes)->str:
    p=subprocess.run(["git","hash-object","--stdin"],input=data,stdout=subprocess.PIPE,check=True)
    return p.stdout.decode().strip()

def sha256(data:bytes)->str:
    return hashlib.sha256(data).hexdigest()

def load_module(data:bytes):
    p=OUT/"_validator_v2.py"; p.write_bytes(data)
    spec=importlib.util.spec_from_file_location("rw102_v2",p)
    if spec is None or spec.loader is None: raise RuntimeError("validator import failed")
    m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

def sync_candidate(v,doc,name):
    dc=doc["candidates"][name]["design_contract"]
    doc["candidates"][name]["capabilities"]=v.derive_capabilities(dc)
    doc["candidates"][name]["structural_metrics"]=v.derive_metrics(dc)

def main()->int:
    frozen={}; freeze={}
    for key,(path,expected) in FILES.items():
        data=git_bytes(path); frozen[key]=data; actual=git_blob(data)
        freeze[key]={"path":path,"expected_blob":expected,"actual_blob":actual,"verified":actual==expected}
    freeze_ok=all(x["verified"] for x in freeze.values())
    v=load_module(frozen["validator"])
    corpus=json.loads(frozen["corpus"].decode())
    corpus_errors=v.validate_corpus(corpus)
    baseline=v.compute_result(corpus) if not corpus_errors else {}
    recomputation_ok=not corpus_errors and baseline.get("corpus_cases")==36 and set(baseline.get("requirements_covered",[]))=={f"N{i:02d}" for i in range(1,13)}
    provenance_ok=all(
        c.get("capability_evidence_mode")=="DERIVED_FROM_STRUCTURED_DESIGN_CONTRACT"
        and isinstance(c.get("capability_evidence"),dict)
        and isinstance(c.get("design_contract"),dict)
        and c.get("capabilities")==v.derive_capabilities(c["design_contract"])
        and c.get("structural_metrics")==v.derive_metrics(c["design_contract"])
        for c in corpus["candidates"].values()
    )

    tests=[]
    def invalid(mid,target,category,mut_doc=None,mut_result=None,novel=False):
        d=copy.deepcopy(corpus)
        if mut_doc: mut_doc(d)
        try:
            r=v.compute_result(d)
            if mut_result: mut_result(r)
            errs,_=v.validate_package(d,r)
            accepted=not errs
        except Exception as ex:
            accepted=False; errs=[f"EXCEPTION:{type(ex).__name__}:{ex}"]
        tests.append({"id":mid,"target":target,"category":category,"semantic_class":"INVALID_MUST_REJECT",
                      "validator_accepted":accepted,"passed":not accepted,"errors":errs[:6],"novel":novel})
    def valid(mid,target,category,mut_doc,expected_winner=None):
        d=copy.deepcopy(corpus); mut_doc(d)
        try:
            r=v.compute_result(d)
            errs,_=v.validate_package(d,r)
            accepted=not errs
            winner=r.get("provisional_selection")
        except Exception as ex:
            accepted=False; errs=[f"EXCEPTION:{type(ex).__name__}:{ex}"]; winner=None
        ok=accepted and (expected_winner is None or winner==expected_winner)
        tests.append({"id":mid,"target":target,"category":category,"semantic_class":"VALID_SENSITIVITY",
                      "validator_accepted":accepted,"passed":ok,"errors":errs[:6],
                      "winner":winner,"expected_winner":expected_winner,"novel":False})

    # A: 8 invalid
    invalid("A01",A,"A",lambda d:d["candidates"][A].__setitem__("effect_authority_mode","ROUTER"),novel=True)
    invalid("A02",A,"A",lambda d:d["candidates"][A]["design_contract"]["specialist"].__setitem__("can_authorize_effect",True))
    invalid("A03",A,"A",lambda d:d["candidates"][A]["design_contract"]["specialist"].__setitem__("can_route",True))
    invalid("A04",A,"A",lambda d:d["candidates"][A]["design_contract"]["specialist"].__setitem__("can_discover_workers",True))
    invalid("A05",A,"A",lambda d:d["candidates"][A]["design_contract"]["semantics"].__setitem__("normalization_provider","ROUTER_BOUNDED"))
    invalid("A06",A,"A",lambda d:d["candidates"][A]["design_contract"].__setitem__("architecture_kind","BOUNDED_SEMANTIC_ROUTER"))
    invalid("A07",A,"A",lambda d:d["candidates"][A]["design_contract"].__setitem__("runtime_evidence_claimed",True))
    invalid("A08",A,"A",lambda d:d["candidates"][A]["capability_evidence"]["no_effect_authority"].__setitem__("basis_ref","description"))

    # C: 8 invalid
    invalid("C01",C,"C",lambda d:d["candidates"][C]["design_contract"]["semantics"].__setitem__("normalization_provider","EXTERNAL_SPECIALIST"))
    invalid("C02",C,"C",lambda d:d["candidates"][C]["design_contract"]["specialist"].__setitem__("present",True))
    invalid("C03",C,"C",lambda d:d["candidates"][C]["design_contract"].__setitem__("architecture_kind","MIN_ROUTER_SEMANTIC_SPECIALIST"))
    invalid("C04",C,"C",lambda d:d["candidates"][C]["design_contract"].__setitem__("runtime_evidence_claimed",True))
    invalid("C05",C,"C",lambda d:d["candidates"][C]["design_contract"].__setitem__("effect_authority_override",True),novel=True)
    invalid("C06",C,"C",lambda d:d["candidates"][C]["structural_metrics"].__setitem__("router_authority_decision_responsibilities",99))
    invalid("C07",C,"C",lambda d:d["candidates"][C]["capabilities"].__setitem__("no_effect_authority",False))
    invalid("C08",C,"C",lambda d:d["candidates"][C]["design_contract"].__setitem__("design_basis_refs",[]))

    # Selection policy: 8 invalid
    invalid("S01","SELECTION","SELECTION",lambda d:d["selection_policy"].__setitem__("hard_rule","RANDOM_WINNER"))
    invalid("S02","SELECTION","SELECTION",lambda d:d["selection_policy"].__setitem__("baseline_eligible",True))
    invalid("S03","SELECTION","SELECTION",lambda d:d["selection_policy"].__setitem__("weights_forbidden",False))
    invalid("S04","SELECTION","SELECTION",lambda d:d["selection_policy"].__setitem__("weights",{"A":1}))
    invalid("S05","SELECTION","SELECTION",lambda d:d["selection_policy"].__setitem__("eligible_candidates",[C,B,A]))
    invalid("S06","SELECTION","SELECTION",lambda d:d["selection_policy"]["lexicographic_tiebreak"].reverse())
    invalid("S07","SELECTION","SELECTION",lambda d:d["selection_policy"].__setitem__("actual_latency",12.5))
    invalid("S08","SELECTION","SELECTION",lambda d:d["selection_policy"].__setitem__("actual_cost",0.01))

    # Authority/currentness/schema/result: 8 invalid
    invalid("X01","SOURCE","CURRENTNESS",lambda d:d.__setitem__("source_c1_blob","0"*40))
    invalid("X02","AUTHORITY","AUTHORITY",lambda d:d["hard_invariants"].__setitem__("effect_authority_outside_router",False))
    invalid("X03","CASE","SCHEMA",lambda d:d["cases"][0].__setitem__("effect_authority","ALLOW_WRITE"))
    invalid("X04","TOP","SCHEMA",lambda d:d.__setitem__("winner_override",A))
    invalid("X05",D,"BASELINE",lambda d:d["candidates"][D].__setitem__("eligible",True))
    invalid("X06",B,"PROVENANCE",lambda d:d["candidates"][B].__setitem__("description_authoritative",True))
    invalid("X07","RESULT","RESULT",mut_result=lambda r:r.__setitem__("provisional_selection",C))
    invalid("X08","RESULT","RESULT",mut_result=lambda r:r.__setitem__("no_router_runtime_claim",False))

    # Valid sensitivity: must be accepted even when ranking or prose changes.
    def v01(d):
        dc=d["candidates"][A]["design_contract"]
        dc["core_router_semantic_rule_families"]=["MINIMAL_CLASSIFICATION","BOUNDED_SEMANTIC_NORMALIZATION"]
        sync_candidate(v,d,A)
    valid("V01",A,"VALID_SENSITIVITY",v01,expected_winner=C)

    def v02(d):
        dc=d["candidates"][C]["design_contract"]
        dc["router_control_responsibilities"].append("COMPOSITION")
        sync_candidate(v,d,C)
    valid("V02",C,"VALID_SENSITIVITY",v02)

    def v03(d):
        dc=d["candidates"][B]["design_contract"]
        dc["router_control_responsibilities"].append("NEGATION")
        sync_candidate(v,d,B)
    valid("V03",B,"VALID_SENSITIVITY",v03)

    def v04(d):
        dc=d["candidates"][D]["design_contract"]
        dc["core_router_semantic_rule_families"]=["LEXICAL_HYBRID"]
        sync_candidate(v,d,D)
    valid("V04",D,"VALID_SENSITIVITY",v04)

    valid("V05",A,"VALID_SENSITIVITY",lambda d:d["candidates"][A].__setitem__("description","Display-only prose may vary without authority."))

    invalid_false_accepts=[x for x in tests if x["semantic_class"]=="INVALID_MUST_REJECT" and not x["passed"]]
    valid_false_rejects=[x for x in tests if x["semantic_class"]=="VALID_SENSITIVITY" and not x["passed"]]
    a_count=sum(1 for x in tests if x["category"]=="A")
    c_count=sum(1 for x in tests if x["category"]=="C")
    selection_count=sum(1 for x in tests if x["category"]=="SELECTION")
    novel_count=sum(1 for x in tests if x["novel"])
    blockers=[]
    if not freeze_ok: blockers.append({"code":"SOURCE_FREEZE_MISMATCH"})
    if not recomputation_ok: blockers.append({"code":"INDEPENDENT_RECOMPUTATION_FAILED"})
    if not provenance_ok: blockers.append({"code":"STRUCTURED_PROVENANCE_NOT_VALID"})
    if invalid_false_accepts: blockers.append({"code":"INVALID_FALSE_ACCEPT","ids":[x["id"] for x in invalid_false_accepts]})
    if valid_false_rejects: blockers.append({"code":"VALID_SENSITIVITY_FALSE_REJECT","ids":[x["id"] for x in valid_false_rejects]})
    if a_count<6 or c_count<6 or selection_count<4 or novel_count<2 or len(tests)<24:
        blockers.append({"code":"ADVERSARIAL_COVERAGE_INSUFFICIENT"})

    mechanical_selection=baseline.get("provisional_selection")
    supported=not blockers and mechanical_selection in (A,B,C)
    raw1={
      "schema_version":"RW1_02_C3_V2_RAW1_BLIND_VERDICT_V1",
      "source_snapshot_commit":SNAPSHOT,
      "source_freeze_verified":freeze_ok,
      "source_blobs":freeze,
      "producer_result_hidden_until_raw1":True,
      "prior_c3_revise_hidden_until_raw1":True,
      "independent_recomputation_completed":recomputation_ok,
      "public_case_count":baseline.get("corpus_cases"),
      "requirements_n01_n12_covered":set(baseline.get("requirements_covered",[]))=={f"N{i:02d}" for i in range(1,13)},
      "candidate_count":baseline.get("candidate_count"),
      "eligible_candidate_count":baseline.get("eligible_candidate_count"),
      "structured_provenance_valid":provenance_ok,
      "recomputed_scoreboard":baseline.get("scoreboard"),
      "mechanical_selection":mechanical_selection,
      "final_selection":mechanical_selection if supported else None,
      "final_selection_present":supported,
      "final_selection_valid":supported,
      "selection_supported_by_evidence":supported,
      "adversarial_tests":tests,
      "adversarial_mutations_total":len(tests),
      "a_mutations":a_count,
      "c_mutations":c_count,
      "selection_policy_mutations":selection_count,
      "novel_falsifiers_at_least_2":novel_count>=2,
      "all_semantically_invalid_mutations_rejected":len(invalid_false_accepts)==0,
      "valid_sensitivity_false_reject_count":len(valid_false_rejects),
      "material_blockers":blockers,
      "material_blocker_count":len(blockers),
      "blind_verdict":"PASS" if not blockers else "REVISE",
      "latency_cost_not_invented":True,
      "no_router_runtime_claim":True,
      "no_production_mutation":True,
      "independent_judge_attested":False,
      "judge_identity_ref":"github-actions://rw1-02-c3-v2-adversarial-execution",
      "note":"Blind deterministic C3 execution. Independent GPT Native attestation remains a separate closure field."
    }
    raw1_bytes=(json.dumps(raw1,ensure_ascii=False,sort_keys=True,indent=2)+"\n").encode()
    raw1_path=OUT/"RAW1.json"; raw1_path.write_bytes(raw1_bytes)
    raw1_sha=sha256(raw1_bytes)

    # Reveal producer and prior C3 evidence only after RAW1 materialization.
    producer_data=git_bytes(PRODUCER[0])
    prior_data=git_bytes(PRIOR_REVISE[0])
    producer_blob=git_blob(producer_data); prior_blob=git_blob(prior_data)
    producer=json.loads(producer_data.decode())
    raw1_after=sha256(raw1_path.read_bytes())
    raw2={
      "schema_version":"RW1_02_C3_V2_RAW2_REVEAL_V1",
      "raw1_sha256":raw1_sha,
      "raw1_unchanged_after_reveal":raw1_after==raw1_sha,
      "producer_result_blob_verified":producer_blob==PRODUCER[1],
      "prior_revise_blob_verified":prior_blob==PRIOR_REVISE[1],
      "producer_result_matches_recomputation":producer==baseline,
      "producer_selection":producer.get("provisional_selection"),
      "blind_verdict_preserved":raw1["blind_verdict"],
      "material_blocker_count":len(blockers)
    }
    raw2_bytes=(json.dumps(raw2,ensure_ascii=False,sort_keys=True,indent=2)+"\n").encode()
    (OUT/"RAW2.json").write_bytes(raw2_bytes)
    final={
      "schema_version":"RW1_02_C3_V2_ADVERSARIAL_EXECUTION_V1",
      "source_freeze_verified":freeze_ok,
      "independent_recomputation_completed":recomputation_ok,
      "public_case_count":raw1["public_case_count"],
      "requirements_n01_n12_covered":raw1["requirements_n01_n12_covered"],
      "candidate_count":raw1["candidate_count"],
      "eligible_candidate_count":raw1["eligible_candidate_count"],
      "adversarial_mutations_total":len(tests),
      "a_mutations_at_least_6":a_count>=6,
      "c_mutations_at_least_6":c_count>=6,
      "selection_policy_mutations_at_least_4":selection_count>=4,
      "novel_falsifiers_at_least_2":novel_count>=2,
      "all_semantically_invalid_mutations_rejected":len(invalid_false_accepts)==0,
      "valid_sensitivity_false_reject_count":len(valid_false_rejects),
      "structured_provenance_valid":provenance_ok,
      "material_blockers":len(blockers),
      "blind_verdict":raw1["blind_verdict"],
      "final_selection":raw1["final_selection"],
      "final_selection_present":raw1["final_selection_present"],
      "final_selection_valid":raw1["final_selection_valid"],
      "selection_supported_by_evidence":raw1["selection_supported_by_evidence"],
      "producer_result_hidden_until_raw1":True,
      "raw1_sha256":raw1_sha,
      "raw2_sha256":sha256(raw2_bytes),
      "raw1_unchanged_after_reveal":raw2["raw1_unchanged_after_reveal"],
      "latency_cost_not_invented":True,
      "no_router_runtime_claim":True,
      "no_production_mutation":True,
      "independent_judge_attested":False,
      "judge_identity_ref_present":True,
      "closure_eligible":False
    }
    (OUT/"FINAL.json").write_text(json.dumps(final,ensure_ascii=False,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(final,ensure_ascii=False))
    return 0 if freeze_ok and recomputation_ok else 2

if __name__=="__main__":
    raise SystemExit(main())
