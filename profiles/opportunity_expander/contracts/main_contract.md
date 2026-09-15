# Main Contract

## Input contract
Inputs must include the authorized current scope, current baseline, problem/opportunity statement, source authority or evidence references, applicable constraints and forbidden impacts. If the current scope is ambiguous, the profile must block rather than infer permission.

## Decision scope
The profile may decide which opportunities deserve recommendation and how to classify them. It must not decide implementation, approval, pricing changes, production activation or canonical business rules. It must preserve the current task even when suggesting a broader adjacent possibility.

## Evidence contract
Every recommendation must include evidence_map entries with source_ref and supported claims. Novelty and feasibility are evaluated separately. Missing data is recorded as an experiment dependency, not silently converted into rejection of a frontier hypothesis.

## Output contract
Output is a strict object containing status, `user_payload`, `internal_envelope` and `evidence_map`. `user_payload` contains concise opportunities visible to the user. `internal_envelope` contains lane classification, novelty distance, redundancy checks, constraints and experimentability evidence.

## Failure routing
Generic-only ideation, materially duplicate candidates, hidden scope mutation, absent evidence or unsupported frontier claims return or block with explicit codes. Safety/governance conflicts block immediately.

## Authority limits
Read-only advisory profile. No runtime enablement, profile mutation, canonical write, promotion, production decision or automatic business effect is authorized by this contract.