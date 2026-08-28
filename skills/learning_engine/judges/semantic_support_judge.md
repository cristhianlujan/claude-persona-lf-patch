# Semantic Support Judge — LF Learning Engine

Status: CANDIDATE_READ_ONLY / REQUIRED_FOR_CROSS_PROFILE_SUPPORT

## Purpose

Fail closed when Learning Engine support is structurally plausible but semantically wrong, overclaimed, stale, incomplete or outside its support role.

This judge is a decision contract. Deterministic fixtures can verify that the contract is wired correctly, but fixture/validator PASS is not behavioral or model-semantic evidence.

## Required evidence

For each material support candidate preserve, as applicable:

- raw learning signal / failed trace / caller request;
- caller profile identity and domain boundary;
- explicit defect or improvement target;
- proposed correction and expected postcondition;
- exact evidence refs;
- material upstream refs with current revision/SHA and validator/judge status;
- provenance receipt when execution provenance is claimed;
- semantic judge receipt/result when semantic PASS is claimed;
- evidence ceiling;
- authoritative obligation source and coverage manifest when semantic completeness is claimed;
- known-vs-new classification;
- target eval and fresh holdout evidence when the change is justified by a trace/failure.

## Gate order

1. **Directionality**
   - Normalize `DEFECT -> CORRECTION -> POSTCONDITION`.
   - `correction` and `postcondition` must reduce/eliminate the diagnosed dimension.
   - If they reproduce, invert or amplify it: `RETURN_TO_WORKER_FOR_SELF_REPAIR / DEFECT_DIRECTION_INVERTED`.
   - If the postcondition is materially unknown: `RETURN_TO_ORCHESTRATOR / CORRECTIVE_POSTCONDITION_UNPROVEN`.

2. **Causal support**
   - Separate observation/correlation from causal justification.
   - If a proposed mother rule/change depends on a causal leap not supported by the evidence: `RETURN_TO_WORKER_FOR_SELF_REPAIR / UNSUPPORTED_CAUSAL_LEAP`.

3. **Upstream validity**
   - `exists=true` is not enough.
   - For required upstreams verify currentness, exact SHA/revision binding and current validator/judge state.
   - Missing/stale/hash-mismatched/rejected/unread upstream: `RETURN_TO_ORCHESTRATOR / UPSTREAM_NOT_VALID`.

4. **Provenance**
   - When execution provenance is claimed, receipt must be valid and bound to the exact execution/input/output.
   - Invalid/unverified provenance claim: `BLOCK_PIPELINE / PROVENANCE_NOT_VERIFIED`.

5. **Semantic correctness**
   - An authentic receipt is not semantic proof.
   - Semantic PASS requires the applicable semantic judge and must not be self-certified/correlated with the producer oracle.
   - Receipt-only semantic claim: `BLOCK_PIPELINE / PROVENANCE_IS_NOT_SEMANTIC_PROOF`.
   - Correlated/self-certified semantic oracle: `BLOCK_PIPELINE / SEMANTIC_ORACLE_NOT_INDEPENDENT`.

6. **Evidence ceiling**
   - Allowed order: `STRUCTURAL_ONLY < PROVENANCE_ONLY < SEMANTIC_SUPPORTED < BEHAVIORAL_PROVEN`.
   - A claim above the strongest demonstrated layer: `BLOCK_PIPELINE / EVIDENCE_CEILING_EXCEEDED`.
   - Preserve valid lower-layer evidence when higher layers remain blocked.

7. **Resolved-input preservation**
   - Material values/authority already supplied or resolved in the run must be consumed.
   - Re-asking an already resolved input: `RETURN_TO_WORKER_FOR_SELF_REPAIR / RESOLVED_INPUT_REASKED`.

8. **Coverage completeness**
   - When semantic PASS depends on an enumerable obligation set, derive stable obligation IDs from the authoritative source.
   - Require one unique check ID for every required obligation ID and no missing IDs.
   - A semantic PASS over a partial bundle: `RETURN_TO_ORCHESTRATOR / SEMANTIC_COVERAGE_INCOMPLETE`.

9. **Known vs new**
   - `KNOWN_VALIDATED` may preserve previously proven behavior.
   - `NEW_UNPROVEN` is capability evidence only until its target outcome is proven.
   - Generalizing `NEW_UNPROVEN` as known: `RETURN_TO_WORKER_FOR_SELF_REPAIR / NEW_CAPABILITY_GENERALIZED_AS_KNOWN`.

10. **Domain ownership**
    - Learning Engine support enriches rules, evidence use, safety, messaging and reliability.
    - The caller profile remains domain owner; Quality Pack remains downstream quality authority.
    - Taking over the caller's domain decision: `BLOCK_PIPELINE / DOMAIN_OWNERSHIP_VIOLATION`.

## PASS conditions

Return support candidate as eligible to continue only when every applicable gate above is clean and the proposed next gate remains bounded by the evidence ceiling.

A clean judge result authorizes only the next governed gate. It does not merge, enable runtime, enable production, write official sources or generalize a capability into regression protection.

## Permanent regression examples

- UI duplicate defect -> proposal adds another duplicate: fail directionality.
- Corrective UI input explicitly says `Resumen` is canonical -> worker asks which survivor is authoritative: fail resolved-input preservation.
- Exact `space_24` is supplied -> worker invents unrelated canonical-looking values: fail semantic support / evidence scope.
- Valid MODEL_RUNTIME receipt + wrong receiver interpretation: provenance PASS, semantic FAIL.
- Upstream file exists but exact SHA is stale: upstream FAIL.
- Semantic checks O1/O2 pass while required O3 is omitted: coverage FAIL.
- New cross-profile behavior works once and is reported as general regression-protected behavior: known-vs-new FAIL.
