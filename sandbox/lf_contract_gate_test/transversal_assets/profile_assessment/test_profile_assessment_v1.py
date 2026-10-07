from profile_assessment_v1 import assess_profile


def proof(status, ref="evidence://case"):
    return {"status": status, "refs": [ref] if status == "PASS" else []}


def base():
    return {
        "evidence": {
            "structural_compatibility": proof("PASS"),
            "domain_task_uplift": proof("FAIL"),
            "strategy_routing": proof("FAIL"),
            "expert_holdout": proof("FAIL"),
            "repeated_optimization": proof("FAIL"),
            "architecture_fit": proof("PASS"),
            "optimization_opportunity": proof("FAIL"),
        },
        "signals": {
            "task_family": "PROFILE_EVOLUTION",
            "complexity": "MEDIUM",
            "novelty": "LOW",
            "uncertainty": "LOW",
            "causal_requirement": "LOW",
            "risk": "MEDIUM",
            "repeated_pattern": False,
            "evidence_sufficiency": "SUFFICIENT",
        },
    }


def run():
    p = base()
    r = assess_profile(p)
    assert r["maturity"] == "GENERIC" and r["evolution_mode"] == "SPECIALIZE"

    p = base()
    p["evidence"]["structural_compatibility"] = proof("FAIL")
    assert assess_profile(p)["evolution_mode"] == "PATCH"

    p = base()
    p["evidence"]["architecture_fit"] = proof("FAIL")
    assert assess_profile(p)["evolution_mode"] == "REARCHITECT"

    p = base()
    p["evidence"]["domain_task_uplift"] = proof("PASS")
    r = assess_profile(p)
    assert r["maturity"] == "SPECIALIZED" and r["evolution_mode"] == "ADAPT"

    p["evidence"]["strategy_routing"] = proof("PASS")
    p["evidence"]["optimization_opportunity"] = proof("PASS")
    r = assess_profile(p)
    assert r["maturity"] == "ADAPTIVE" and r["evolution_mode"] == "OPTIMIZE"

    p["evidence"]["expert_holdout"] = proof("PASS")
    p["evidence"]["repeated_optimization"] = proof("PASS")
    p["evidence"]["optimization_opportunity"] = proof("FAIL")
    r = assess_profile(p)
    assert r["maturity"] == "EVIDENCE_OPTIMIZED" and r["evolution_mode"] == "NO_CHANGE"

    p = base()
    p["evidence"]["domain_task_uplift"] = {"status": "PASS", "refs": []}
    assert assess_profile(p)["maturity"] == "GENERIC"

    assert r["write_authorized"] is False and r["admission_required"] is True
    print("PASS_PROFILE_ASSESSMENT_V1 cases=7 maturity_states=5 modes=6 authority=0")


if __name__ == "__main__":
    run()
