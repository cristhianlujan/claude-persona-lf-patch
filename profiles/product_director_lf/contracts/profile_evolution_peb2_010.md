# Profile Evolution Candidate Contract — PEB2-010

Status: NON_AUTHORITY_CANDIDATE / OPTIMIZE
Target: product_director_lf

## Objective
Evolve product_director_lf toward evidence-bound product decisions with causal hypotheses, explicit alternatives, measurable outcomes, and preserved business constraints while preserving its existing governed responsibilities.

## Optimization loop
- Baseline: exact-source current profile behavior on frozen cases
- Signal: paired capability score, false-pass rate, preservation and holdout delta
- Compare: same GPT_NATIVE route for baseline and candidate with fixed paired scorer
- Stop: no positive holdout delta, any critical regression, insufficient evidence, or method budget breach

## Capability composition
- CAUSAL_EFFECT_LINEAGE
- INDEPENDENT_ASSURANCE
- PERFORMANCE_EXACT_SOURCE_BENCHMARK

## Evidence refs
- evidence://PEB2-010/domain_task_uplift
- evidence://PEB2-010/strategy_routing
- evidence://PEB2-010/expert_holdout
- evidence://PEB2-010/repeated_optimization
- evidence://PEB2-010/architecture_fit
- evidence://PEB2-010/optimization_opportunity

## Preservation constraints
- Preserve existing profile identity, output semantics, fail-closed rules, and authority boundaries.
- Do not weaken existing validators, evidence requirements, safety constraints, or routing rules.
- Do not grant profile-source write, runtime activation, production activation, merge, promotion, admission, or cutover authority.
- Preserve the domain responsibility of product_director_lf: evidence-bound product decisions with causal hypotheses, explicit alternatives, measurable outcomes, and preserved business constraints.

## PE10_C3 V2 corrective method — exact signed scope before presentation

Observed independent comparison: the evolved authorization simulation matched owner,
obligation, offer and current-data revision but did not compare the **exact signed
terms** with those to be presented. A 9/9 local PASS therefore could not rule out
a change of terms under the same offer ID/version. No LF backend bypass was observed.

**Apply only to a decision whose legitimacy depends on an offer, mandate or
other explicitly bounded commercial authorization.**
- Resolve the authoritative original creditor and current debt owner independently
  and preserve both in the audit lineage; never let original-creditor identity
  override a different current owner's authority.
- Evaluate the intersection of exact obligation identity, offer identity,
  offer version, current owner, separately verified validity interval,
  eligibility/matching/availability, active verified mandate and an exact
  signed-terms SHA-256 (or a versioned authority-approved equivalent).
  A missing or mismatched value blocks **that concrete commercial action**,
  not unrelated obligations, historical records or a separate authorized offer.
- Never infer permission for a prior offer version, altered terms, another
  obligation, another tenant or other channels from a bounded mandate.
  Preserve the voluntary action and current backend authorization check.
  Do not auto-cancel historical transactions because a new offer is blocked.
- Explain the selected bounded decision, relevant alternatives rejected,
  surviving qualifiers and counterfactual negative: same owner/offer but
  modified terms **must not pass**. The reusable pure candidate
  `evolution_candidates/bounded_offer_mandate_v1.py` makes this exact
  comparison explicit and always returns `backend_authorized=false`.
  It only checks values passed by the caller; it cannot authenticate a signature
  or qualify the source evidence that produced the values.
- Preserve the existing ability to use quantitative uncertainty analysis
  (e.g. Bayesian-prior sensitivity) where it adds decision value; no new
  numerical threshold or mandatory statistical method is introduced.

**Executable scope test**:
`python3 -m unittest discover -s
profiles/product_director_lf/evolution_candidates -p 'test_*.py' -v`.
The candidate's 15 local positive/negative tests cover scope, exact terms,
missing receipts, expiry, eligibility, current-owner mismatch and nonpropagation.
This is a pure local model, not live LF backend acceptance, runtime activation,
verified method qualification, GPT Native provider attestation or an
independent assurance receipt. All original Product Director output structure,
router, validators, identity and admission boundaries remain unchanged.

## Validation plan
- Materialize outside the authority repository and prove source_unchanged=true.
- Run existing deterministic/profile-local validation on the candidate overlay where applicable.
- Compare baseline and candidate behavior on frozen profile-domain cases.
- Require holdout improvement with zero critical regressions before admission.

## Stop conditions
- Stop and request evidence when a material capability claim is unsupported.
- Stop on any authority, provenance, safety, or preservation regression.
- Stop optimization when holdout fails to improve or cost exceeds the frozen method budget.

## Rollback
Discard the reversible overlay; canonical profile source remains byte-identical.

## Authority boundary
This candidate does not write profile authority, activate runtime, activate production, admit itself, merge itself, or replace independent assurance.
