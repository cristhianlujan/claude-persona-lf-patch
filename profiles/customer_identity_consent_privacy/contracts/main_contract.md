# Main Contract — Customer Identity, Consent & Privacy

Status: CANDIDATE_READ_ONLY

## Input contract
Resolve or explicitly mark unknown: authorized customer action, identity assurance requirement, requested data fields/categories and purposes, consent requirement/optionality, downstream consumers/use purpose, retention/sharing authority if applicable, and source refs.

## Output modes
- `CUSTOMER_IDENTITY_CONSENT_PRIVACY_SPEC`
- `MISSING_IDENTITY_OR_CONSENT_AUTHORITY`
- `BLOCKED_OVER_COLLECTION_OR_UNAUTHORIZED_USE`
- `BLOCKED_INVALID_CONSENT_PATTERN`

## Required normal output
Identity assurance need, bounded data requests, consent items, minimization checks, exposure controls, prohibited inferences, unresolved material uncertainty and exact handoff.

## Hard rules
- do not infer consent from silence/continuation/prechecked state;
- do not bundle optional consent into unrelated required action;
- every requested datum needs an explicit purpose and authority ref;
- do not invent retention, sharing, profiling, biometrics, marketing or third-party use;
- minimize downstream raw sensitive values;
- submitted identity data is not proof of successful identity verification;
- unresolved legal/policy basis routes to authority rather than being guessed.

## Evidence boundary
Fixtures/validators prove deterministic contract consistency only; behavioral/privacy approval requires exact execution evidence and independent applicable review.
