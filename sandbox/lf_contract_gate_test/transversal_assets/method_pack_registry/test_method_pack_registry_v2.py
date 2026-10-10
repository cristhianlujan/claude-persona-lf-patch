import json
from pathlib import Path
P=Path(__file__).with_name("method_pack_registry_v2.json")
def run():
    x=json.loads(P.read_text())
    assert x["schema_version"]=="METHOD_PACK_REGISTRY_V2"
    assert x["execution_permission"] is False
    ids=[m["method_id"] for m in x["methods"]]
    assert len(ids)==len(set(ids))>=12
    required={"signals","preconditions","precondition_contract","cost_model","effectiveness_contract","retirement_conditions","availability_state","auto_select","stop_conditions","validation_method"}
    for m in x["methods"]:
        assert required <= set(m)
        assert m["precondition_contract"] or not m["preconditions"]
        assert m["cost_model"]["observed_cost_preferred"] is True
        assert m["effectiveness_contract"]["causal_attribution_required"] is True
        assert m["retirement_conditions"]
    experiments=[m for m in x["methods"] if m["availability_state"]=="EXPERIMENTAL_NOT_ADMITTED"]
    assert {m["method_id"] for m in experiments}=={"REASONING_COMPOSITION_SEARCH","TEXTUAL_FEEDBACK_OPTIMIZATION","WORKFLOW_SEARCH","EXPERIENCE_REUSE"}
    assert all(m["auto_select"] is False for m in experiments)
    assert x["dynamic_policy"]["replan_allowed"] is True
    assert x["learning_policy"]["auto_promote"] is False
    print(f"PASS_METHOD_PACK_REGISTRY_V2 methods={len(ids)} experiments={len(experiments)} verified_preconditions=1 observed_cost=1 causal_learning=1")
if __name__=="__main__": run()
