#!/usr/bin/env python3
"""M9.5 D4 negative test, executed against canonical T-EQUIV source and versioned DB policy."""
import json
import os
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "transversal_assets" / "control_equivalence"))
from control_equivalence_judge_v1 import evaluate

def main():
    contract=json.loads(os.environ["IG_M95_LEVEL_POLICY_JSON"])
    counts=json.loads(os.environ["IG_M95_ASSESSMENT_DISTRIBUTION_JSON"])
    assert contract["schema_version"]=="IG_DIVERGENCE_LEVEL_DECLARATION_V1"
    assert contract["provider_capability"]=="CONTROL_EQUIVALENCE_JUDGE"
    assert contract["global_semantics"]["D0"]=="EXACT_EQUALITY"
    assert contract["global_semantics"]["D4"]=="KNOWN_FALSE_PASS_RISK_ALWAYS_BLOCKING"
    assert contract["declaration_policy"]["selection"]=="DYNAMIC_FROM_CURRENT_VERSIONED_CONSUMER_DECLARATION"
    assert contract["declaration_policy"]["D4_override"]=="ALWAYS_BLOCK"
    assert set(contract["level_codes"])=={"D0","D1","D2","D3","D4","D5"}
    assert all(k in contract["declaration_policy"]["required_per_field"] for k in ("field_path","level_code","meaning","policy_version"))
    actual={(x["validator_outcome"],x["applicability"]): x["n"] for x in counts}
    assert actual.get(("PASS","APPLICABLE"),0)>0 and actual.get(("PENDING","APPLICABLE"),0)>0, "LIVE_DISTRIBUTION_MISSING"

    field_path="assessment.validator_outcome" # Scoped negative fixture, not a global field selection
    current={"assessment":{"validator_outcome":"PENDING","applicability":"APPLICABLE"}}
    candidate={"assessment":{"validator_outcome":"PASS","applicability":"APPLICABLE"}}
    policy={"schema_version":"lf-control-equivalence-policy/v1","consumer_ref":"IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.5/NEGATIVE","field_levels":{
      field_path:{"level":"D4","meaning":"candidate claims validator PASS while baseline remains PENDING","blocking":True}
    }}
    equal=evaluate(current,current,policy)
    assert equal["result"]=="PASS_EQUIVALENT" and equal["comparison_level"]=="D0"
    blocked=evaluate(current,candidate,policy)
    assert blocked["result"]=="BLOCKED_DIVERGENCE" and blocked["comparison_level"]=="D4"
    assert blocked["blocking"] is True and blocked["authoritative_mutation"] is False
    assert blocked["divergence_count"]==1 and blocked["divergences"][0]["field"]==field_path
    invalid=json.loads(json.dumps(policy))
    invalid["field_levels"][field_path]["blocking"]=False
    forbidden=evaluate(current,candidate,invalid)
    assert forbidden["result"]=="BLOCKED" and forbidden["reason_code"].startswith("D4_MUST_BLOCK")
    unmapped=evaluate(current,candidate,{"schema_version":"lf-control-equivalence-policy/v1","consumer_ref":"IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.5/NEGATIVE","field_levels":{}})
    assert unmapped["result"]=="BLOCKED_UNCLASSIFIED_DIVERGENCE" and unmapped["blocking"] is True
    print("PASS_ENG_M9_5_D4_BLOCKS_NEGATIVE tests=4 semantic_authority_bound=true adversarial_case_executed=true")
if __name__=="__main__": main()
