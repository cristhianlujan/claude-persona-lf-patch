# P0 Visual Reading Architecture v1.1 — audit remediation bundle

This directory is a **non-canonical, read-only candidate** for independent review. It does not change `skills/creating-integral-user-stories/`, enable runtime, authorize merge, or claim empirical visual quality.

## Exact validation

Run from this directory:

```bash
python validate_p0_handoff_v1_1.py \
  --root . \
  --phase post-registration \
  --receipt P0_SUPABASE_REGISTRATION_RECEIPT_v1.1.json \
  --readback P0_SUPABASE_READBACK_v1.1.json \
  --attestation P0_SUPABASE_RECEIPT_ATTESTATION_v1.1.json
```

The command must exit `0`, report exactly **26 expected checks**, and set:

```text
all_checks_pass = true
expected_check_set_exact = true
metrics = 26
negatives = 80
audit_controls = 72
research_sources = 11
resolved_errors = 38
audit_followup_corrections = 14
```

Then run the candidate package gate:

```bash
python verify_p0_visual_bundle_v1_1.py
```

The gate verifies the exact file inventory and hashes, rejects Base64/binary archive transport, executes the validator with all required flags, compares its JSON result semantically with the committed validation file, and scans the direct plaintext content.

## Supabase anchors

- Architecture snapshot: `9`
- Registration event: `3248`
- Receipt attestation snapshot: `11`
- Receipt attestation event: `3249`
- Activation event: `3250`
- Receipt SHA-256: `4f1676babb1f15467f957d9ca84e8a4ee7412776528fedfb563b576b8ef57625`

The receipt is stored in Supabase as an exact UTF-8 JSON string. PostgreSQL recomputed the same SHA from that stored string.

## Freeze and publication semantics

The canonical manifest is frozen at `PRE_REGISTRATION`. Therefore its claims about receipt attestation and GitHub publication describe the freeze point, not later events. `P0_SUPABASE_READBACK_v1.1.json` is explicitly a pre-publication readback. The GitHub publication event is recorded separately after the correction commit exists.

## Inventory boundary

The publication root is exactly:

```text
sandbox/story_creator_p0_visual/v1.1/
```

J11 continues to govern only `skills/creating-integral-user-stories/**`. Candidate files remain outside that canonical root until a future authorized P0-7 promotion transaction.
