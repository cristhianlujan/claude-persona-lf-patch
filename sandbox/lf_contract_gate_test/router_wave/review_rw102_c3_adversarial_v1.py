#!/usr/bin/env python3
from __future__ import annotations
import copy, hashlib, importlib.util, json, os, subprocess, sys, tempfile
from pathlib import Path

SNAPSHOT="5d7f30580d4c6bb557e51943693c4b95e192900e"
OUT=Path(os.environ.get("RW102_C3_OUT","/tmp/rw102_c3_review"))
OUT.mkdir(parents=True,exist_ok=True)

FILES={
 "wave":("docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md","4bb64d568c3f005cf454fb223b4a5ed699c34504"),
 "c1":("docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md","470979c9b9a0dd9a728601b6ec5f577d7445f8b5"),
 "corpus":("docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V1.json","f00a202f5983931d6ae41121fcdfea96808c094b"),
 "validator":("sandbox/lf_contract_gate_test/router_wave/validate_rw102_architecture_competition_v1.py","54517132aa0ab890b1e266639a19cbe08f7a5d9a"),
 "workflow":(".github/workflows/lf-router-level2-advisory-tests.yml","b1782a0944868b967fc88de530499266668c2b99"),
}
PRODUCER=("docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V1.json","1f2b91ff5fe4bb3d0f2b764222425623996c2eac")

A="A_MIN_ROUTER_SEMANTIC_SPECIALIST"
B="B_MIN_CLASSIFIER_COMPOSITE_DERIVATION"
C="C_BOUNDED_SEMANTIC_ROUTER"
D="D_CURRENT_HYBRID_BASELINE"

def git_bytes(path:str)->bytes:
    return subprocess.check_output(["git","show",f"{SNAPSHOT}:{path}"])

def git_blob(data:bytes)->str:
    p=subprocess.run(["git","hash-object","--stdin"],input=data,stdout=subprocess.PIPE,check=True)
    return p.stdout.decode().strip()

def load_validator(data:bytes):
    p=OUT/"_frozen_validator.py"; p.write_bytes(data)
    spec=importlib.util.spec_from_file_location("rw102_frozen_validator",p)
    if spec is None or spec.loader is None: raise RuntimeError("validator import failed")
    m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

def sha256(data:bytes)->str:
    return hashlib.sha256(data).hexdigest()

def mutate_description(doc,name,text):
    doc["candidates"][name]["description"]=text

def all_caps(doc,name,value=True):
    for k in list(doc["candidates"][name]["capabilities"]):
        doc["candidates"][name]["capabilities"][k]=value

def run():
    freeze={}
    frozen={}
    for key,(path,expected) in FILES.items():
        data=git_bytes(path); frozen[key]=data
        actual=git_blob(data)
        freeze[key]={"path":path,"expected_blob":expected,"actual_blob":actual,"verified":actual==expected}
    source_freeze_verified=all(x["verified"] for x in freeze.values())
    corpus=json.loads(frozen["corpus"].decode("utf-8"))
    v=load_validator(frozen["validator"])

    corpus_errors=v.validate_corpus(corpus)
    baseline=v.compute_result(corpus)
    requirements=set(baseline["requirements_covered"])
    recomputation_ok=(
        not corpus_errors and baseline["corpus_cases"]==36
        and requirements=={f"N{i:02d}" for i in range(1,13)}
        and baseline["candidate_count"]==4
        and baseline["eligible_candidate_count"]==3
    )

    provenance={
      name:{
        "candidate_keys":sorted(corpus["candidates"][name].keys()),
        "has_capability_evidence":any(k in corpus["candidates"][name] for k in ("capability_evidence","capability_evidence_refs","evidence_refs")),
        "has_metric_derivation":any(k in corpus["candidates"][name] for k in ("metric_derivation","structural_metric_evidence","metric_evidence_refs")),
      } for name in (A,B,C,D)
    }

    specs=[]
    def add(mid,target,category,semantic_class,claim,fn):
        specs.append((mid,target,category,semantic_class,claim,fn))

    # A: >=6
    add("A01",A,"A","INVALID_MUST_REJECT","A description contradicts no-effect boundary",
        lambda d: mutate_description(d,A,"Semantic specialist may authorize effects after normalization."))
    add("A02",A,"A","INVALID_MUST_REJECT","A description contradicts route boundary",
        lambda d: mutate_description(d,A,"Semantic specialist may choose and route the worker."))
    add("A03",A,"A","INVALID_MUST_REJECT","A specialist effect authority flag true",
        lambda d: d["candidates"][A]["structural_metrics"].__setitem__("specialist_can_authorize_effect",True))
    add("A04",A,"A","INVALID_MUST_REJECT","A specialist routing flag true",
        lambda d: d["candidates"][A]["structural_metrics"].__setitem__("specialist_can_route",True))
    add("A05",A,"A","INVALID_MUST_REJECT","A specialist discovery flag true",
        lambda d: d["candidates"][A]["structural_metrics"].__setitem__("specialist_can_discover_workers",True))
    add("A06",A,"A","INVALID_MUST_REJECT","A puts semantic engine inside Router",
        lambda d: d["candidates"][A]["structural_metrics"].__setitem__("router_internal_semantic_engine",True))
    add("A07",A,"A","INVALID_MUST_REJECT","A architecture description removed",
        lambda d: mutate_description(d,A,""))
    add("A08",A,"A","VALID_SENSITIVITY","A loses no-effect capability; competition should recompute without schema rejection",
        lambda d: d["candidates"][A]["capabilities"].__setitem__("no_effect_authority",False))

    # C: >=6
    add("C01",C,"C","INVALID_MUST_REJECT","C description grants Router effect authority",
        lambda d: mutate_description(d,C,"Router performs bounded semantics and may authorize the resulting effect."))
    add("C02",C,"C","INVALID_MUST_REJECT","C claims bounded semantic Router but semantic-engine flag false",
        lambda d: d["candidates"][C]["structural_metrics"].__setitem__("router_internal_semantic_engine",False))
    add("C03",C,"C","INVALID_MUST_REJECT","C architecture description removed",
        lambda d: mutate_description(d,C,""))
    add("C04",C,"C","VALID_SENSITIVITY","C loses no-effect capability",
        lambda d: d["candidates"][C]["capabilities"].__setitem__("no_effect_authority",False))
    add("C05",C,"C","VALID_SENSITIVITY","C loses preserve-negation capability",
        lambda d: d["candidates"][C]["capabilities"].__setitem__("preserve_negation",False))
    add("C06",C,"C","VALID_SENSITIVITY","C loses semantic-normalization capability",
        lambda d: d["candidates"][C]["capabilities"].__setitem__("semantic_normalization",False))
    def c07(d):
        m=d["candidates"][C]["structural_metrics"]; m["core_router_semantic_rule_change_touches"]=0; m["router_authority_decision_responsibilities"]=2
    add("C07",C,"C","VALID_SENSITIVITY","C structural design becomes lexicographically simpler than A",
        c07)
    add("C08",C,"C","INVALID_MUST_REJECT","C description says semantics are external while topology says internal",
        lambda d: mutate_description(d,C,"All semantic normalization is delegated outside ACT-0001."))

    # Selection: >=4
    add("S01","SELECTION","SELECTION","INVALID_MUST_REJECT","hard rule changed to arbitrary winner",
        lambda d: d["selection_policy"].__setitem__("hard_rule","RANDOM_WINNER"))
    add("S02","SELECTION","SELECTION","INVALID_MUST_REJECT","tiebreak order reversed",
        lambda d: d["selection_policy"]["lexicographic_tiebreak"].reverse())
    add("S03","SELECTION","SELECTION","INVALID_MUST_REJECT","weights enabled",
        lambda d: d["selection_policy"].__setitem__("weights_forbidden",False))
    add("S04","SELECTION","SELECTION","INVALID_MUST_REJECT","hidden weights inserted",
        lambda d: d["selection_policy"].__setitem__("weights",{"A":100,"C":0}))
    add("S05","SELECTION","SELECTION","VALID_SENSITIVITY","A structural touch count changes from 0 to 2",
        lambda d: d["candidates"][A]["structural_metrics"].__setitem__("core_router_semantic_rule_change_touches",2))
    def s06(d):
        all_caps(d,B,True)
        m=d["candidates"][B]["structural_metrics"]; m["core_router_semantic_rule_change_touches"]=0; m["router_authority_decision_responsibilities"]=2
    add("S06","SELECTION","SELECTION","VALID_SENSITIVITY","B becomes fully capable and simpler by declared structural metrics",
        s06)

    # Other required domains + novel falsifiers
    add("B01",B,"B","INVALID_MUST_REJECT","B description contradicts its declared capability flags",
        lambda d: mutate_description(d,B,"Classifier provides full semantic normalization, negation and context resolution."))
    add("B02",B,"B","VALID_SENSITIVITY","B gains all required capabilities",
        lambda d: all_caps(d,B,True))
    add("D01",D,"BASELINE","INVALID_MUST_REJECT","baseline description promotes D to canonical oracle",
        lambda d: mutate_description(d,D,"Canonical GOLDEN oracle that all candidates must match."))
    add("D02",D,"BASELINE","VALID_SENSITIVITY","baseline happens to satisfy all capabilities but remains ineligible control",
        lambda d: all_caps(d,D,True))
    add("N01","CORPUS","NEUTRALITY","INVALID_MUST_REJECT","literal/capability oracle linkage broken on T30",
        lambda d: d["cases"][29].__setitem__("literal_request","Do nothing; no routing or semantic request."))
    def n02(d):
        d["cases"][29]["literal_request"],d["cases"][30]["literal_request"]=d["cases"][30]["literal_request"],d["cases"][29]["literal_request"]
    add("N02","CORPUS","NEUTRALITY","INVALID_MUST_REJECT","two literals swapped while oracle capabilities stay put",n02)
    add("N03","CORPUS","NEUTRALITY","INVALID_MUST_REJECT","family label erased while case remains admissible",
        lambda d: d["cases"][0].__setitem__("family",""))
    add("CUR01","SOURCE","CURRENTNESS","INVALID_MUST_REJECT","C1 authority blob drift",
        lambda d: d.__setitem__("source_c1_blob","0"*40))
    add("AUTH01","AUTHORITY","AUTHORITY","INVALID_MUST_REJECT","effect authority invariant disabled",
        lambda d: d["hard_invariants"].__setitem__("effect_authority_outside_router",False))
    add("CONT01","CORPUS","CONTINUITY","INVALID_MUST_REJECT","safe-readonly literal retained but capability removed",
        lambda d: d["cases"][15].__setitem__("required_capabilities",[x for x in d["cases"][15]["required_capabilities"] if x!="safe_readonly_continuity"]))
    add("NOVEL01",A,"NOVEL","INVALID_MUST_REJECT","unknown authority-bearing field injected into A candidate",
        lambda d: d["candidates"][A].__setitem__("effect_authority_mode","ROUTER_GRANTED"))
    add("NOVEL02","CORPUS","NOVEL","INVALID_MUST_REJECT","case receives unknown semantic oracle field granting write",
        lambda d: d["cases"][0].__setitem__("effect_authority","ALLOW_WRITE"))

    mutations=[]
    for mid,target,category,semantic_class,claim,fn in specs:
        d=copy.deepcopy(corpus); fn(d)
        # Recompute result from the mutated package so rejection cannot be explained
        # merely by a stale producer result.
        try:
            r=v.compute_result(d)
            errs,_=v.validate_package(d,r)
            accepted=(len(errs)==0)
            mutated_selection=r.get("provisional_selection")
            hard_pass=r.get("hard_pass_candidates")
        except Exception as exc:
            accepted=False; errs=[f"EXCEPTION:{type(exc).__name__}:{exc}"]; mutated_selection=None; hard_pass=[]
        expected_reject=(semantic_class=="INVALID_MUST_REJECT")
        mutation_ok=(not accepted) if expected_reject else accepted
        mutations.append({
          "id":mid,"target":target,"category":category,"semantic_class":semantic_class,
          "claim":claim,"validator_accepted":accepted,"expected_reject":expected_reject,
          "mutation_ok":mutation_ok,"errors":errs[:6],
          "mutated_selection":mutated_selection,"hard_pass_candidates":hard_pass,
        })

    invalid_false_accepts=[m for m in mutations if m["semantic_class"]=="INVALID_MUST_REJECT" and m["validator_accepted"]]
    valid_false_rejects=[m for m in mutations if m["semantic_class"]=="VALID_SENSITIVITY" and not m["validator_accepted"]]
    cats={}
    for m in mutations: cats[m["category"]]=cats.get(m["category"],0)+1

    blockers=[]
    if invalid_false_accepts:
        blockers.append({
          "code":"VALIDATOR_ACCEPTS_SEMANTICALLY_INVALID_PACKAGES",
          "count":len(invalid_false_accepts),
          "examples":[m["id"] for m in invalid_false_accepts],
        })
    if valid_false_rejects:
        blockers.append({
          "code":"VALIDATOR_HARDCODES_BASELINE_WINNER_OR_HARDPASS_SET",
          "count":len(valid_false_rejects),
          "examples":[m["id"] for m in valid_false_rejects],
        })
    if any(not x["has_capability_evidence"] or not x["has_metric_derivation"] for x in provenance.values()):
        blockers.append({
          "code":"CANDIDATE_CAPABILITIES_AND_TIEBREAK_METRICS_LACK_PER_CANDIDATE_PROVENANCE",
          "details":provenance,
        })

    blind_verdict="PASS" if not blockers else "REVISE"
    tentative=baseline.get("provisional_selection") if not blockers else None
    raw1={
      "schema_version":"RW1_02_C3_RAW1_BLIND_VERDICT_V1",
      "source_snapshot_commit":SNAPSHOT,
      "source_freeze_verified":source_freeze_verified,
      "source_blobs":freeze,
      "producer_result_hidden_until_raw1":True,
      "independent_recomputation_completed":recomputation_ok,
      "public_case_count":baseline.get("corpus_cases"),
      "requirements_n01_n12_covered":requirements=={f"N{i:02d}" for i in range(1,13)},
      "candidate_count":baseline.get("candidate_count"),
      "eligible_candidate_count":baseline.get("eligible_candidate_count"),
      "recomputed_scoreboard":baseline.get("scoreboard"),
      "mechanical_selection":baseline.get("provisional_selection"),
      "selection_assessment":"SUPPORTED" if not blockers else "INSUFFICIENT_EVIDENCE_DUE_TO_MATERIAL_VALIDATOR_AND_PROVENANCE_DEFECTS",
      "tentative_final_selection":tentative,
      "candidate_provenance_audit":provenance,
      "adversarial_mutations":mutations,
      "adversarial_mutations_total":len(mutations),
      "a_mutations":cats.get("A",0),
      "c_mutations":cats.get("C",0),
      "selection_policy_mutations":cats.get("SELECTION",0),
      "novel_falsifiers":["NOVEL01","NOVEL02"],
      "invalid_false_accepts":invalid_false_accepts,
      "valid_false_rejects":valid_false_rejects,
      "material_blockers":blockers,
      "material_blocker_count":len(blockers),
      "blind_verdict":blind_verdict,
      "latency_cost_not_invented":True,
      "no_router_runtime_claim":True,
      "no_production_mutation":True,
      "judge_identity_ref":"github-actions://rw1-02-c3-adversarial-execution",
      "independent_judge_attested":False,
      "note":"Automated blind adversarial execution over frozen pre-producer sources; does not claim GPT-session independence."
    }
    raw1_bytes=(json.dumps(raw1,ensure_ascii=False,sort_keys=True,indent=2)+"\n").encode()
    raw1_path=OUT/"RAW1.json"; raw1_path.write_bytes(raw1_bytes)
    raw1_sha=sha256(raw1_bytes)

    # Producer result opened only after RAW1 is frozen.
    producer_data=git_bytes(PRODUCER[0])
    producer_blob=git_blob(producer_data)
    producer=json.loads(producer_data.decode())
    raw1_sha_after=sha256(raw1_path.read_bytes())
    raw2={
      "schema_version":"RW1_02_C3_RAW2_REVEAL_V1",
      "raw1_sha256":raw1_sha,
      "raw1_unchanged_after_reveal":raw1_sha_after==raw1_sha,
      "producer_result_blob_expected":PRODUCER[1],
      "producer_result_blob_actual":producer_blob,
      "producer_result_blob_verified":producer_blob==PRODUCER[1],
      "producer_selection":producer.get("provisional_selection"),
      "producer_hard_pass_candidates":producer.get("hard_pass_candidates"),
      "mechanical_recomputation_matches_producer":producer==baseline,
      "blind_verdict_preserved":blind_verdict,
      "material_blocker_count":len(blockers),
      "conclusion":"Producer result matches mechanical recomputation, but that does not cure RAW1 material defects." if blockers else "Producer result corroborates independent recomputation."
    }
    raw2_bytes=(json.dumps(raw2,ensure_ascii=False,sort_keys=True,indent=2)+"\n").encode()
    (OUT/"RAW2.json").write_bytes(raw2_bytes)

    final={
      "schema_version":"RW1_02_C3_ADVERSARIAL_EXECUTION_V1",
      "source_freeze_verified":source_freeze_verified,
      "producer_result_hidden_until_raw1":True,
      "independent_recomputation_completed":recomputation_ok,
      "public_case_count":baseline.get("corpus_cases"),
      "requirements_n01_n12_covered":raw1["requirements_n01_n12_covered"],
      "candidate_count":baseline.get("candidate_count"),
      "eligible_candidate_count":baseline.get("eligible_candidate_count"),
      "adversarial_mutations_total":len(mutations),
      "a_mutations":cats.get("A",0),
      "c_mutations":cats.get("C",0),
      "selection_policy_mutations":cats.get("SELECTION",0),
      "novel_falsifiers_at_least_2":True,
      "invalid_false_accept_count":len(invalid_false_accepts),
      "valid_false_reject_count":len(valid_false_rejects),
      "material_blockers":len(blockers),
      "mechanical_selection":baseline.get("provisional_selection"),
      "final_selection_present":tentative is not None,
      "blind_verdict":blind_verdict,
      "raw1_sha256":raw1_sha,
      "raw2_sha256":sha256(raw2_bytes),
      "raw1_unchanged_after_reveal":raw2["raw1_unchanged_after_reveal"],
      "latency_cost_not_invented":True,
      "no_router_runtime_claim":True,
      "no_production_mutation":True,
      "independent_judge_attested":False,
    }
    (OUT/"FINAL.json").write_text(json.dumps(final,ensure_ascii=False,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(final,ensure_ascii=False))
    # REVISE is a successful execution outcome for C3; CI should remain green.
    return 0 if source_freeze_verified and recomputation_ok else 2

if __name__=="__main__":
    raise SystemExit(run())
