# Candidate change log

2026-09-25 — `GITHUB_PROVIDER_READBACK_V1`

- centralizes GitHub HTTP readback for E.16 under `GITHUB_CONTRACT_GATE_LF`;
- adds bounded retry/backoff for transient network/API failures;
- classifies DNS/API/auth/evidence failures without weakening fail-closed behavior;
- documents the separation between GitHub transport ownership and `EVIDENCE_RESOLVER_REGISTRY` resolver identity authority;
- no merge, production activation or Supabase mutation.
