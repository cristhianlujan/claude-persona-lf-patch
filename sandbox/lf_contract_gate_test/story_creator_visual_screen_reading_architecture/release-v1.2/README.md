# Story Creator — Visual Screen Reading and Auxiliary Context Reconciliation Architecture · Release v1.2

This release belongs only to **Story Creator**. `P0` is an internal pipeline stage code, not the project or package name.

The architecture source is represented here and in Supabase by an **external-source cryptographic descriptor only**:

- bytes: `69,556`
- SHA-256: `6f07df8c0e26626749847b0a3286ed331b3f365e3aa43d0b14b506f503991160`
- storage claim: `EXTERNAL_SOURCE_HASH_DESCRIPTOR_ONLY`
- Supabase literal body stored: `false`
- source body recoverable from Supabase: `false`

No document in this release may infer source-body storage or recoverability from the descriptor or its hash.

The package remains under the existing CI-approved sandbox prefix; no global allowlist is expanded. The static manifest intentionally does **not** embed a final Git commit SHA, because doing so would be self-referential. The final head, commit count, CI run IDs, receipt, attestation and publication event are bound after commit by independent GitHub/Supabase readback. Missing CI is `BLOCKED_NOT_PASS`.

The remediation is based on the independently audited real pre-remediation head `b5cad6c063e7339a90354bb6f90384da4ea93bde`. That commit is unsigned (`verification.verified=false`); this is explicitly accepted only for the **static candidate** and does not authorize merge, Task Packet, runtime or production.

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python audit_story_creator_visual_screen_reading_release_v1_2.py
sha256sum -c STORY_CREATOR_VISUAL_SCREEN_READING_SHA256SUMS_v1.2.txt
```

Expected static result: `STATIC_SELF_AUDIT_PASS`.

## SHA256SUMS coverage

`STORY_CREATOR_VISUAL_SCREEN_READING_SHA256SUMS_v1.2.txt` intentionally covers **4 of 6** files:

1. `README.md`
2. `STORY_CREATOR_VISUAL_SCREEN_READING_CANONICAL_MANIFEST_v1.2.json`
3. `audit_story_creator_visual_screen_reading_release_v1_2.py`
4. `STORY_CREATOR_VISUAL_SCREEN_READING_RFC8785_CANONICALIZER_v1.2.mjs`

The two exclusions are explicit and independently compensated:

- `STORY_CREATOR_VISUAL_SCREEN_READING_SHA256SUMS_v1.2.txt` is excluded to avoid self-reference; the auditor validates its exact member set and each listed digest.
- `STORY_CREATOR_VISUAL_SCREEN_READING_SELF_AUDIT_REPORT_v1.2.json` is excluded because including it would create a circular dependency between the report and the hashes that help determine the report. The auditor reconstructs the expected report and compares it byte-for-byte through `committed_report_matches`.

The self-audit is only a static package check. It does not establish GitHub/Supabase parity by itself, and it does not authorize Task Packet, ready-for-review, merge, runtime, acceptance or production.
