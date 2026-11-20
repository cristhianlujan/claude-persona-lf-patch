"""Offline examples: no authority or run in these fixtures is real."""


def broken_independence_gate(evaluation, policy, evidence):
    return {"promotion_authorized": evaluation["context_pass"] and
            evidence["independence_verified"]}


def broken_authority_gate(evaluation, policy, evidence):
    return {"promotion_authorized": evaluation["context_pass"]}


def correct_gate(evaluation, policy, evidence):
    valid = all(evaluation[k] is True for k in ("context_pass", "spec_pass", "eval_pass"))
    independent = (evidence["independence_verified"] is True and
                   evidence["isolated_context_verified"] is True and bool(evidence["independence_ref"]))
    bound = all(policy[k] == evidence[k] for k in ("actor", "object_id", "effect", "scope_sha256"))
    authorized = policy["verified"] is True and policy["current"] is True and bound
    judge_allowed = independent or (policy["allow_contextual"] is True and
                                    policy["requires_independence"] is False)
    return {"promotion_authorized": valid and authorized and judge_allowed and
            bool(evaluation["evidence_refs"]) and evidence["material_blockers"] == []}


def origin_context():
    return {"trace": "producer -> transport -> apply_contract",
            "location": "consumer.py:apply_contract", "source_code": "apply_contract(variable1)",
            "spec": {"required": ["variable1", "variable2"]}}


def broken_context_transport():
    data = origin_context()
    return {"spec": data["spec"]}


def correct_context_transport():
    return origin_context()
