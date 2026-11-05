#!/usr/bin/env python3
"""No DB writes. Three pack gates + six adversarial cases each + actual PG07 C2 validator."""
import json,sys,copy
from pathlib import Path
ROOT=Path(__file__).resolve().parent
STAGES=ROOT.parent
sys.path.insert(0,str(ROOT))
sys.path.insert(0,str(STAGES/"selector_experimental"/"integration"))
sys.path.insert(0,str(STAGES/"pg07_worker_candidate"/"tools"))
from pack_validation_common import check_pack,evaluate
from selector_descriptor_from_skill import SLUGS,descriptor
from test_pg04_pg07_selector_bridge_v1 import real_producers,real_pg07_validation
from pg07_c2_task_batch_projection_v1 import prepare_pg07_c2

def check(ok,why):
    if not ok:raise AssertionError(why)
def run():
    chain=real_producers()
    c2=chain["c2"];sid=sorted(x["solution_id"] for x in c2["solution_scopes"])[-1]
    baseline,output,c1=real_pg07_validation(chain,c2,sid,return_c1=True)
    for slug in SLUGS:
        pack=ROOT/slug
        blockers=check_pack(pack)
        check(not blockers,slug+" PACK_FAIL "+repr(blockers))
        print("PASS PACK",slug)
        ev=evaluate(pack)
        check(len(ev)==6 and all(ok for _,ok in ev),slug+" EVAL_FAIL "+repr(ev))
        for name,ok in ev:print("PASS EVAL",slug,name)
        d=descriptor(slug)
        check(d["schema_version"]=="LF_PROFILE_SELECTION_DESCRIPTOR_V1" and
              len(d["selection_evidence"])==1,"Descriptor not derived from source")
        print("PASS DESCRIPTOR_FROM_SKILL",slug)
        spec=json.loads((pack/"examples/good_output.json").read_text(encoding="utf-8"))
        projections=[{"solution_id":x["solution_id"],
                      "function_result_ref":x["worker_task_spec_source_ref"],
                      "worker_spec":copy.deepcopy(spec if x["solution_id"]==sid else x["worker_visible_task_spec"]),
                      "source_snapshot_sha256":x["worker_visible_task_spec"]["source_snapshot_sha256"]}
                     for x in output["worker_payloads"]]
        oracles=[{"solution_id":x["solution_id"],"verifier_only_ref":x["verifier_only_ref"],
                  "oracle_subject_sha256":x["oracle_subject_sha256"],"access_policy":x["access_policy"]}
                 for x in output["verifier_only_oracle_envelopes"]]
        qualified=prepare_pg07_c2(pg07_c1=c1,worker_spec_projections=projections,
                                  verifier_oracle_bindings=oracles)
        accepted=[x for x in qualified["worker_payloads"] if x["solution_id"]==sid]
        check(len(accepted)==1 and accepted[0]["worker_visible_task_spec"]==spec
              and qualified["production_authority"] is False
              and qualified["dispatch_allowed"] is False,
              "Real PG07 C2 rejected pack visible spec")
        print("PASS REAL_PG07_C2",slug)
    print("PASS PROGRAMMER_PROFILE_PACKS_CANDIDATE_SANDBOX_ONLY")
if __name__=="__main__":
    try:run()
    except Exception as exc:
        print("FAIL",type(exc).__name__,str(exc),file=sys.stderr)
        raise SystemExit(1)
