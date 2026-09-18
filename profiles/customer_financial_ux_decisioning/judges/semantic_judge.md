# Semantic Judge — Customer Financial UX & Decisioning

Purpose: decide whether a structurally valid output demonstrates expert financial decision quality rather than merely reproducing terms safely.

## Inputs to the judge
Review together:
- exact current profile source revision;
- exact governed input/current authority;
- RAW profile output;
- deterministic/schema validation result;
- evidence/source refs used by the output;
- route identity when Router/direct equivalence is under review.

Do not infer missing evidence and do not use historical fixtures as proof of the RAW output.

## Result vocabulary
Exactly one:
- `PASS`
- `NEEDS_REPAIR`
- `BLOCKED`

## Hard BLOCK conditions
Return `BLOCKED` when any material instance occurs:
- invented or strengthened savings, amount, fee, deadline, eligibility, payment success, debt closure, credit effect, legal release or guarantee;
- current authority conflict is silently resolved without an authority/currentness rule;
- a supplied material term/qualifier is dropped or contradicted;
- incomparable alternatives are represented as economically equivalent;
- coercive/conversion-pressure framing hides downside or substitutes business preference for customer decision logic;
- evidence/source refs are fabricated or do not support the material claim;
- downstream handoff changes financial meaning or loses a blocking uncertainty.

## PASS dimensions
All dimensions below must pass substantively.

### 1. Authority fidelity
- Material terms and claims bind to current authoritative refs.
- Conditional/referential/estimated values remain conditional/referential/estimated.
- Historical/contextual evidence never silently overrides current authority.

### 2. Economic normalization
- Alternatives share a valid monetary/time basis, or the output explicitly declares material non-comparability.
- Lower immediate payment is not confused with lower total cost.
- Savings are only stated from an authoritative baseline and calculation inputs.

### 3. Causal consequence depth
For each material option, the output makes clear:
- customer action;
- immediate financial/timing state change;
- resulting obligation/effect;
- material condition/downside;
- what remains unchanged or unresolved.

Generic adjectives or copied terms are insufficient.

### 4. Trade-off / objective quality
- `key_tradeoff` explains why the choice matters.
- Recommendation/ranking exists only when a governed objective/preference makes it defensible.
- Without such an objective, the output exposes the decision boundary instead of inventing a best option.

### 5. Counterfactual decision boundary
The judge can identify from output + authority at least one plausible material change that would reverse or materially alter the decision/recommendation, such as fee, total cost, timing, eligibility, authority, customer objective or protected constraint.

The output also rejects or distinguishes at least one plausible alternative interpretation. If the same conclusion would be emitted regardless of material variable changes, the reasoning is too shallow.

### 6. Uncertainty / autonomy
- Known truth, unresolved material truth and nonmaterial proposal are not conflated.
- Missing material information fails closed.
- Business conversion preference does not override customer financial consequence.

### 7. Downstream postcondition
The handoff preserves stable option IDs, exact current terms/authority, decision boundaries, guardrails and unresolved material uncertainties. The next worker can act without inventing financial truth, and a materially different downstream interpretation would violate the handoff.

### 8. Router/direct consistency
When both routes receive the same governed input, compare material decision semantics only: option meaning, comparison basis, consequences, trade-offs, blockers, preserved qualifiers and handoff effect. Runtime metadata differences do not count.

## NEEDS_REPAIR conditions
Return `NEEDS_REPAIR` rather than PASS when the result is safe but one or more depth dimensions are weak, including:
- causal consequences are generic;
- trade-offs merely repeat source terms;
- counterfactual boundary is absent or not defensible;
- recommendation lacks an objective but can safely be reframed;
- downstream postcondition is vague;
- evidence is nominal rather than substantive;
- self-repair should have caught a material reasoning weakness but did not.

## Counterfactual challenge procedure
Before PASS, challenge the output with at least one near-neighbor variation that changes exactly one material variable. Ask whether the decision boundary should change. A PASS requires either:
- a justified change in decision/recommendation; or
- a justified reason the decision remains unchanged.

Do not require the RAW output to contain a field literally named `counterfactual`; the boundary may be recoverable from existing comparison, consequence, trade-off, uncertainty and handoff fields.

## Claim ceiling
A semantic PASS proves only that the reviewed RAW output is substantively strong under the reviewed input and exact source revision. It does not authorize runtime, Golden, production, automatic promotion or generalize to unseen tasks without holdout evidence.
