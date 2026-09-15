# Strategy S37 — LF Decision & Discovery Intelligence

Status: CANDIDATE / NON_PRODUCTION / NO_RUNTIME_ACTIVATION
Version: v0.1
Date: 2026-09-13

## 1. Objective

Convert LF's governed context, operational history and business evidence into better decisions and differentiated business hypotheses, not merely correct or generic answers.

S37 does not replace S26/S30/S31. It consumes governed context and evidence from existing LF capabilities and adds a separate discovery/decision layer.

## 2. North-star invariant

A proposal does not earn a differentiated PASS because it is plausible, well written, innovative-sounding or structurally valid.

A differentiated PASS requires observable evidence that the proposal:

1. preserves LF domain truth and authority boundaries;
2. changes a concrete decision, causal mechanism, economic logic, information advantage, product logic or network effect;
3. uses at least one LF-specific or LF-compounding asset when claiming differentiation;
4. is materially different from the other candidates, not cosmetic false variety;
5. defines a measurable business outcome and a falsifiable experiment;
6. declares unknowns and assumptions instead of inventing facts;
7. explains why an average competitor could not copy the proposal unchanged;
8. creates a learning loop so LF becomes better after real outcomes are observed.

## 3. Why a single innovation prompt is forbidden

Canary S37-CANARY-001 demonstrated that a single prompt saying "do not be generic" was insufficient. The baseline produced unsupported discounts/bonuses/guarantees. The single S37 prompt reduced those unsafe inventions but collapsed all three hypotheses into variants of the same single-payment idea and confused creditor/debtor roles.

Therefore S37 requires staged discovery, criticism and evolution. No one-shot prompt may be promoted as the S37 architecture.

## 4. Architecture

```text
GOVERNED LF CONTEXT
        |
        v
A. DOMAIN INTELLIGENCE
   facts / actors / constraints / decisions / unknowns / compounding assets
        |
        v
B. OPPORTUNITY DISCOVERY
   multiple mechanism classes through reusable Innovation Cards
        |
        v
C. ANTI-GENERIC + FALSE-VARIETY JUDGE
   reject portable, cosmetic, non-causal or non-falsifiable ideas
        |
        v
D. HYPOTHESIS EVOLVER
   repair/combine survivors into CONSERVATIVE / DIFFERENTIATED / TEN_X
        |
        v
E. BUSINESS VALUE JUDGE
   economic metric / test cost / expected decision value / risk / moat
        |
        v
F. INDEPENDENT HOLDOUT
   frozen unseen cases; baseline vs S37; no expected verdict supplied
        |
        v
G. HUMAN DECISION
   LF decides what to test; agents never self-authorize business truth
        |
        v
H. OUTCOME LEARNING
   hypothesis -> experiment -> observed result -> calibration -> memory
```

## 5. Innovation Card families

Initial reusable lenses:

- PRICE_OPTIMIZATION
- NEXT_BEST_ACTION
- NEGOTIATION_SEQUENCE
- CROSS_PORTFOLIO_LEARNING
- CAUSAL_EXPERIMENTATION
- CREDITOR_DECISION_SUPPORT
- CUSTOMER_FRICTION_MINING
- NETWORK_EFFECT_DATA_MOAT
- PROPENSITY_TO_PAY
- OFFER_SEQUENCE_OPTIMIZATION
- DATA_PRODUCT_FOR_CREDITORS
- CONTRARIAN_BUSINESS_MODEL

Cards are lenses, not answers. Presence of a Card never proves differentiation.

## 6. Three required hypothesis tiers

### CONSERVATIVE
Uses known operating patterns and should be relatively easy to test. It may be useful without being a moat.

### DIFFERENTIATED
Must use LF-specific context, data, workflow or accumulated marketplace history to improve a concrete decision in a way that is not portable unchanged to any fintech.

### TEN_X
Must change the economic, informational, product or network-effect logic. Adding more UI, automation, personalization or generic AI does not satisfy TEN_X.

## 7. Anti-generic gate

For DIFFERENTIATED and TEN_X the semantic judge must answer all of these:

- Competitor substitution: could "LF" be replaced with another fintech name without materially changing the proposal?
- Decision delta: exactly which decision becomes different or better?
- Causal delta: what mechanism causes the expected effect?
- LF asset: what LF-specific or compounding asset is used?
- False variety: is this genuinely a different mechanism, or the same idea with different wording?
- Falsifiability: what observable result would make LF reject the hypothesis?
- Copyability: what must a competitor possess or learn to copy it?
- Learning: what new signal is accumulated if the experiment runs?

If competitor substitution is YES and no material LF asset/decision delta exists, the candidate is `GENERIC_SOLUTION`.

## 8. Proof standard

S37 is not proven by one attractive example. Promotion from candidate requires a frozen A/B holdout campaign.

For each holdout case:

- identical business context for baseline and S37;
- same underlying model family/settings where feasible;
- baseline receives normal problem-solving instruction;
- S37 receives the staged architecture;
- raw outputs are frozen before judging;
- deterministic contract validation is separate from semantic judging;
- independent semantic reviewer receives no expected winner;
- reviewer must detect genericity, false variety, domain loss, unsupported claims and role confusion;
- all receipts are source/hash bound.

## 9. Initial promotion criteria

These are candidate acceptance thresholds to be calibrated with the first holdout bank, not production truth:

- zero hard domain/safety inventions in candidates counted as PASS;
- every final portfolio contains exactly CONSERVATIVE, DIFFERENTIATED and TEN_X;
- DIFFERENTIATED and TEN_X each bind to an authorized LF source/asset;
- at least two final hypotheses are materially distinct causal mechanism classes;
- every final hypothesis has metric, experiment and falsification condition;
- independent reviewer rejects false variety and generic portability;
- S37 must outperform baseline on differentiation without degrading domain fidelity or unsupported-claim rate;
- at least three unseen problem families must pass before any broad claim; one canary is never sufficient.

## 10. Claim ceilings

Allowed during bootstrap:

- `STRUCTURAL_CONTRACT_PASS`
- `CANARY_EXECUTED`
- `CANARY_FAIL`
- `CANDIDATE_ARCHITECTURE_READY_FOR_HOLDOUT`

Forbidden until independent holdouts succeed:

- `S37_PROVEN`
- `INNOVATION_ENGINE_VALIDATED`
- `BUSINESS_MOAT_PROVEN`
- `PRODUCTION_READY`
- any claim that generated hypotheses will increase revenue/recovery

## 11. Integration boundary

S37 should consume, not duplicate:

- S26 Typed Context / provenance / Profile Runtime evidence;
- S30 governed strategy execution/broker capabilities where applicable;
- S31 reusable capability/currentness contracts;
- Quality Pack resolver-backed evidence and independent semantic review patterns;
- EKB preflight and recurrence prevention.

No runtime, Golden, production, automatic business action, pricing decision or creditor decision is authorized by this strategy.

## 12. Next work packages

WP-A: formal Domain Intelligence contract and actor/decision preservation tests.

WP-B: Innovation Card registry + applicability selector.

WP-C: Anti-Generic / False-Variety semantic judge benchmark with positive, negative and uncertain cases.

WP-D: Hypothesis Evolver and three-tier portfolio contract.

WP-E: Business Value judge with evidence-bound metrics and explicit unknowns.

WP-F: A/B holdout harness against baseline across real LF problem families.

WP-G: outcome-learning receipt linking hypothesis, experiment, observed result and calibration without rewriting history.
