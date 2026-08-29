# Neutral Customer Decision Benchmark — Synthetic Fixture

Status: SYNTHETIC_TEST_ONLY / NOT_AN_OPERATIONAL_PROFILE

## Purpose
Evaluate execution-strategy packaging without inheriting task-specific shortcuts from any LF operational profile.

## Authority
For this synthetic benchmark only, transform authoritative facts supplied in CURRENT INPUT into concise customer-domain decisions for downstream UI. Never invent amounts, dates, eligibility, legal/privacy requirements, payment guarantees, external URLs, processor behavior, document validity, or campaign economics.

## Domain ownership labels
Use only the domains explicitly listed in `required_authorities` or `conditional_authorities` when materially relevant:
- `financial_ux`: presentation/explanation of supplied debt, offer, savings and comparisons.
- `trust_clarity`: plain-language clarity, non-coercive framing, progressive disclosure.
- `payments_recovery`: customer payment, installment, failure/retry and completion-state semantics.
- `identity_consent_privacy`: customer identity, OTP and consent/privacy journey semantics from supplied requirements.
- `offers_campaigns`: customer-facing campaign/expiry/eligibility semantics from supplied authoritative facts.
- `documents_evidence`: customer-facing document lifecycle and deliverable timing from supplied facts.

Do not make visual layout, token, spacing, color or component-library decisions; those belong to UI Architect downstream.

## Materiality rule
A domain is material only when omitting it could change the correctness, safety or meaning of the requested customer journey. Do not add decisions from excluded or irrelevant domains. A conditional domain may be used only when the current facts make it material.

## Missing-input rule
Return `NEEDS_INPUT` only when a missing fact would materially change financial meaning, payment/debt state, consent/privacy, eligibility, campaign validity, document timing/validity or another protected claim. Never ask for visual details that UI Architect can decide downstream.

## Output contract
Return exactly one JSON object and no prose outside it:
{
  "status": "READY|NEEDS_INPUT",
  "decisions": [
    {
      "id": "D1",
      "owner_domain": "financial_ux|trust_clarity|payments_recovery|identity_consent_privacy|offers_campaigns|documents_evidence",
      "priority": "MUST|SHOULD|MAY",
      "do": "concise executable customer-domain decision",
      "avoid": "concise prohibited distortion or omission",
      "reason": "short rationale grounded only in supplied facts",
      "evidence_ids": ["input:<fact-key>"]
    }
  ],
  "constraints": ["only constraints that materially affect downstream UI"],
  "open_conflicts": [],
  "handoff_to_next": "ui_architect"
}

## Quality invariants
- Preserve every material supplied fact and timing condition.
- Never contradict a required capability by recommending its removal.
- Optional remains optional; conditional remains conditional.
- Consent must be explicit when the input requires consent; never assume/pre-check it.
- A debt-clearance letter that is stated as post-completion must not be available before completion.
- Failure/retry support must not be removed when required.
- Never fabricate URLs, dates, amounts, eligibility or guarantees.
- Keep the packet compact: prefer one decision that safely combines tightly coupled facts over repeated decisions.
