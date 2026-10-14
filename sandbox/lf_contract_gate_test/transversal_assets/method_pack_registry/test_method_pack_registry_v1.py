import json
from pathlib import Path

P = Path(__file__).with_name("method_pack_registry_v1.json")


def run():
    x = json.loads(P.read_text(encoding="utf-8"))
    assert x["schema_version"] == "METHOD_PACK_REGISTRY_V1"
    assert x["execution_permission"] is False
    ids = [m["method_id"] for m in x["methods"]]
    assert len(ids) == len(set(ids)) >= 8
    required = {"signals","preconditions","problem_classes","cost_points","risk","evidence_required","compatible_capabilities","stop_conditions","escalation","validation_method"}
    for m in x["methods"]:
        assert required <= set(m)
        assert m["cost_points"] > 0
        assert m["stop_conditions"]
    assert x["learning_policy"]["auto_promote"] is False
    assert x["srcr_relationship"]["copy_srcr_methods"] is False
    for gated in ("EVALUATOR_OPTIMIZER","PROMPT_OPTIMIZATION"):
        m = next(v for v in x["methods"] if v["method_id"] == gated)
        assert "benchmark_exists" in m["preconditions"]
    print(f"PASS_METHOD_PACK_REGISTRY_V1 methods={len(ids)} expensive_default_enabled=0")


if __name__ == "__main__":
    run()
