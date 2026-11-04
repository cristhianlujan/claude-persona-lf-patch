"""Deterministic self-consistency checks only. Independent semantic judge remains external."""


def check(source, output):
    faults = []
    if not isinstance(source, dict) or not isinstance(output, dict):
        return ["INPUT_OR_OUTPUT_INVALID"]
    if output.get("external_authority_verified") is not False:
        faults.append("FALSE_AUTHORITY_VERIFICATION")
    if output.get("effects_executed") is not False or output.get("operationally_integrated") is not False:
        faults.append("FALSE_RUNTIME_OR_EFFECTS")
    if output.get("business") != source.get("business"):
        faults.append("BUSINESS_DRIFT")
    payload = output.get("payload")
    if payload is not None:
        if payload.get("no_solution_inferred") is not True:
            faults.append("INFERRED_SOLUTION_CLAIM")
        if set(payload.get("source_refs", [])) - set(source.get("source_refs", [])):
            faults.append("SOURCE_REF_INVENTED")
        if set(payload.get("target_hints", [])) - set(source.get("target_hints", [])):
            faults.append("TARGET_INVENTED")
        for field in ("problem_statement", "desired_outcome"):
            if payload.get("objective", {}).get(field) != source.get("objective", {}).get(field, "").strip():
                faults.append("OBJECTIVE_REWRITTEN")
    return sorted(set(faults))
