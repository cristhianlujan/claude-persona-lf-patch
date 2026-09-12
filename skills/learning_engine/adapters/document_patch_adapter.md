# Document Patch Adapter — LF Learning Engine

## Purpose

Translate approved learning candidates into human documentation patch proposals only after review gates pass.

## Document layer

Google Docs remains the human-readable documentation layer. GitHub remains the technical pack layer. Supabase remains the operational source of state.

## Rules

- Do not patch documents before approval.
- Do not create duplicate learning documentation.
- Use controlled patch flow with clear anchors and verification.
- Keep technical source in GitHub and human documentation in Google Docs aligned only after approval.

## Blockers

- Missing approval.
- Missing source authority.
- Duplicate active asset.
- Runtime or production general enablement request.
- Supabase write request without explicit approval.
