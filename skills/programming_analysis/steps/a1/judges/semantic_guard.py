"""Deterministic output self-consistency, NOT independent semantic attestation."""
from hashlib import sha256


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
    raw = source.get("original_request")
    expected_digest = sha256(raw.encode("utf-8")).hexdigest() if isinstance(raw, str) and raw.strip() else None
    if output.get("original_request_sha256") != expected_digest:
        faults.append("ORIGINAL_REQUEST_PROVENANCE_MISMATCH")
    if output.get("semantic_review_required") is not bool(expected_digest):
        faults.append("SEMANTIC_REVIEW_FLAG_MISMATCH")
    payload = output.get("payload")
    if payload is not None:
        if payload.get("no_solution_inferred") is not True:
            faults.append("INFERRED_SOLUTION_CLAIM")
        if set(payload.get("source_refs", [])) - {ref.strip() for ref in source.get("source_refs", [])}:
            faults.append("SOURCE_REF_INVENTED")
        if set(payload.get("target_hints", [])) - {ref.strip() for ref in source.get("target_hints", [])}:
            faults.append("TARGET_INVENTED")
        prompt = output.get("normalized_prompt")
        if not isinstance(prompt, str):
            faults.append("NORMALIZED_PROMPT_MISSING")
        else:
            if any(payload.get("objective", {}).get(field, "") not in prompt
                   for field in ("problem_statement", "desired_outcome")):
                faults.append("NORMALIZED_PROMPT_OBJECTIVE_MISMATCH")
            if any(code not in prompt for code in payload.get("target_hints", [])):
                faults.append("NORMALIZED_PROMPT_TARGET_MISSING")
        for field in ("problem_statement", "desired_outcome"):
            if payload.get("objective", {}).get(field) != source.get("objective", {}).get(field, "").strip():
                faults.append("OBJECTIVE_REWRITTEN")
    return sorted(set(faults))
