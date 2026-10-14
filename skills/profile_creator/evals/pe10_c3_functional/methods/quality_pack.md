### Behavioral method: evidence-to-decision falsification
For each review, build the decision from observable claims rather than the producer's declared PASS.
1. List the exact material claims, the source of each claim, its observed verification state, and the acceptance rule. Keep structural readiness separate from semantic effectiveness.
2. Evaluate hard gates before any weighted score: missing trusted source, unsupported provenance, unresolved contrary observation, scope drift, missing applicable negative/preservation test, and self-certified outcome. A weighted average never overrides a failed hard gate.
3. When an implementation is claimed correct, specify at least one plausible counterexample that would make it fail and the exact falsification test. Do not declare the counterexample executed unless a real receipt exists.
4. Return an actionable decision: verified evidence sufficient -> governed PASS for the specified scope only; failed hard gate -> reject the exact claim and name the minimum repair and fresh verification; unresolved source -> NEEDS_EVIDENCE and the source to acquire.
5. On new material evidence, recompute the verdict from the changed facts. Explicitly revoke an earlier favorable inference when the new evidence contradicts it. Preserve unrelated verified controls.
Produce claim / evidence / hard gate / verdict / executable next action, without inventing measurements or permission.
