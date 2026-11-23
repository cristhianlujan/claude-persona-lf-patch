# SALY · V15 canonical Native render wire (private function)

## Purpose
Continue the user-authorized route after merging queue infrastructure PR #4649.
- Source candidate: `sandbox/creative_factory/queue_v05/001_saly_native_render_wire_candidate.sql`, main blob `579ff19957e782966811df6f58a16b17ec0f1d70`.
- Install private `saly.creative_native_render_wire_v1(uuid,bigint,text)` only. It constructs exact bytes from an existing authenticated, authorized and immutable RUN; it never starts a RUN, calls a provider, or sends a user message.
- No GRANT to service_role, anon or authenticated. Keep both SALY orders REVIEW_ONLY with PENDIENTE items. SQL rejects unverified source, changed SHA, non-Native modes, expired claims and unapproved order flags.
- The function returns `executor_identity_attested=false`, `native_transmitted=false`, `provider_receipt=null`, `db_done_allowed=false` by design.

## PG17 verification
- CI run [45125713051](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/45125713051) SUCCESS, HEAD `26fe928389b01ea40e554e4c0a3cf3480efac7c4`.
- Source V05 synthetics: GPT_NATIVE & CLAUDE_NATIVE, exact wire_base64/hash and source attachments; six exact-code negatives: invalid mode, fake fencing token, REVIEW_ONLY, altered reference, path traversal, missing live policy.
- Assertions: no delivery record and no DONE; whole synthetic RUN transaction rolled back. Real user orders remain PENDIENTE, no new RUN.
- Fixed-data PG17 fixture is not a byte-for-byte Supabase clone. Train preflight + production readback are mandatory.

## Runtime blocker (not solved in SQL)
Image generation and authenticated host callback/readback cannot be fabricated by SQL/Python. Requires a proven current-chat Native bridge with provider delivery identity, verified image bytes and independent QA. Then release a separately governed activation authorizing those specific pending orders. A DB function by itself cannot wake ChatGPT or automatically execute its native image-generation tool.

## Resguardos
B1/B2/B3/B6/B11/B12/B13/B19/B25/B30/B31.
