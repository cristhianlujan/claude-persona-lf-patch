# Story Creator — Visual Screen Reading and Auxiliary Context Reconciliation Architecture · Release v1.2

This release belongs only to **Story Creator**. `P0` is an internal pipeline stage code, not the project or package name.

This release now includes the exact, independently reconstructable **v1.1 functional architecture body** that was produced by the audited PR #107 remediation chain. Release `v1.2` is an integrity/publication hardening of that functional source; it does not invent or claim a new semantic v1.2 architecture body.

- source file: `STORY_CREATOR_VISUAL_SCREEN_READING_ARCHITECTURE_SOURCE_v1.1.md`
- source bytes: `67,351`
- source SHA-256: `a8d53b736e7d2d672b0927f7deaca4422f7429fdda0d1997b1eaa54fc06e7531`
- source provenance: PR #107 payload reconstructed from the v1.0 bundle plus the audited v1.1 correction patches
- source validation: 26/26 post-registration checks PASS using validator SHA-256 `41db5bb55bb6676b320c9de0000153d450218a013040086257cd2ed432cbbaa3`
- GitHub source body included: `true`
- Supabase literal body stored: `false`
- source body recoverable from Supabase: `false`

The included body defines the 18-step visual-reading flow and the P0-to-J02 adapter contract. Supabase continues to provide external attestation/state only; no document may infer Supabase body storage from the GitHub copy.

The package remains under the existing CI-approved sandbox prefix; no global allowlist is expanded. The static manifest intentionally does **not** embed a final Git commit SHA, because doing so would be self-referential. The final head, commit count, CI run IDs, receipt, attestation and publication event are bound after commit by independent GitHub/Supabase readback. Missing CI is `BLOCKED_NOT_PASS`.

The remediation is based on the independently audited real pre-remediation head `b5cad6c063e7339a90354bb6f90384da4ea93bde`. That commit is unsigned (`verification.verified=false`); this is explicitly accepted only for the **static candidate** and does not authorize merge, Task Packet, runtime or production.

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python audit_story_creator_visual_screen_reading_release_v1_2.py
sha256sum -c STORY_CREATOR_VISUAL_SCREEN_READING_SHA256SUMS_v1.2.txt
```

Expected static result: `STATIC_SELF_AUDIT_PASS`.

## SHA256SUMS coverage

`STORY_CREATOR_VISUAL_SCREEN_READING_SHA256SUMS_v1.2.txt` intentionally covers **5 of 7** files:

1. `README.md`
2. `STORY_CREATOR_VISUAL_SCREEN_READING_CANONICAL_MANIFEST_v1.2.json`
3. `audit_story_creator_visual_screen_reading_release_v1_2.py`
4. `STORY_CREATOR_VISUAL_SCREEN_READING_RFC8785_CANONICALIZER_v1.2.mjs`
5. `STORY_CREATOR_VISUAL_SCREEN_READING_ARCHITECTURE_SOURCE_v1.1.md`

The two exclusions are explicit and independently compensated:

- `STORY_CREATOR_VISUAL_SCREEN_READING_SHA256SUMS_v1.2.txt` is excluded to avoid self-reference; the auditor validates its exact member set and each listed digest.
- `STORY_CREATOR_VISUAL_SCREEN_READING_SELF_AUDIT_REPORT_v1.2.json` is excluded because including it would create a circular dependency between the report and the hashes that help determine the report. The auditor reconstructs the expected report and compares it byte-for-byte through `committed_report_matches`.

The self-audit is only a static package check. It does not establish GitHub/Supabase parity by itself, and it does not authorize Task Packet, ready-for-review, merge, runtime, acceptance or production.
