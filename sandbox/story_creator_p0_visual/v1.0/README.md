# P0 Visual Reading Architecture v1.0 — candidate bundle

This directory publishes the exact, non-canonical architecture bundle for the P0 visual-reading extension of `creating-integral-user-stories`.

## Scope

- Base repository commit: `45fea04462f70da8ff8c9e89221595b6283faaf4`.
- Branch: `agent/p0-visual-architecture-v1`.
- Storage path: `sandbox/story_creator_p0_visual/v1.0/`.
- The package does **not** modify `skills/creating-integral-user-stories/`.
- The package does **not** enable runtime, merge, deployment, production, or canonical Supabase inventory changes.

## Exact archive

The exact archive is stored as seven ordered Base64 fragments:

- `P0_VISUAL_READING_V1_BUNDLE.tar.gz.b64.part01`
- `P0_VISUAL_READING_V1_BUNDLE.tar.gz.b64.part02`
- `P0_VISUAL_READING_V1_BUNDLE.tar.gz.b64.part03a`
- `P0_VISUAL_READING_V1_BUNDLE.tar.gz.b64.part03b`
- `P0_VISUAL_READING_V1_BUNDLE.tar.gz.b64.part04a`
- `P0_VISUAL_READING_V1_BUNDLE.tar.gz.b64.part04b`
- `P0_VISUAL_READING_V1_BUNDLE.tar.gz.b64.part05`

Reconstructed archive SHA-256: `f84f3e327d99b14091671a462c85dacbffaa3da90e649a7076e12aec2dfcdaac`.

The archive contains ten exact artifacts, including the handoff, canonical manifest, validators, Supabase receipt/attestation/readback, RFC 8785 canonicalizer and dry-run SQL.

## Verification

```bash
python reconstruct_p0_visual_bundle_v1.py
tar -xzf P0_VISUAL_READING_V1_BUNDLE.tar.gz
sha256sum -c P0_VISUAL_READING_V1_SHA256SUMS.txt --ignore-missing
python validate_p0_handoff_v1_0.py
```

Expected validator result:

```text
all_checks_pass = true
metrics = 26
negative_cases = 80
audit_controls = 72
research_sources = 11
resolved_errors = 38
```

## Supabase traceability

- Architecture snapshot: `7`.
- Registration event: `3217`.
- Receipt-attestation snapshot: `8`.
- Receipt-attestation event: `3218`.
- Activation event: `3219`.
- Receipt SHA-256: `af3fddd9b515504d69bc48106907f2b22258c9a4a551d123b3f2c987f50cb615`.

## Status

`CANDIDATO_READ_ONLY`. This bundle is architecture and evidence only. It is not empirical visual-performance evidence and does not authorize implementation or production by itself.
