# RW1-06_C1 — Clean independent reviewer protocol V1

## Finding and state
The previous GPT_NATIVE_NEW_CHAT reviewer explicitly returned
`RW106_C1_REVIEWER_IDENTITY_DIAGNOSTIC_V1` / `GAP`.
It had no stable chat reference, and its shared-project context could not be shown
to be materially separate from the producer. Its historical commitment
(13 valid, 26 invalid, 2 falsifiers; manifest `a9bf6f0ee9b9b92838eeb2eebf7a585ba87169bf196c8ed21c0ede84a6dd4158`;
content `d615d0ad986835f6486752934c90ec979975f8c4213ec7060ce6a34fbbadcd48`)
is RETAINED as **UNATTESTED HISTORICAL EVIDENCE**, not admitted as an independent holdout.
Do not edit the original digests/timestamp or claim it met C1.

## Boundary and authority
- Plan `LF_ROUTER_ARCHITECTURE_WAVE_V1`, checkpoint `RW1-06_C1`; repository `cristhianlujan/claude-persona-lf-patch`.
- Source snapshot `ec5d8ce5637c2d118941cfe4b3c88ae4fd325024` and policy blob `138efc3285ee5226c107827c66f84ced6be4afcb`. Confirm applicability/currentness at review time; if canonical Router ABI hashes drift, STOP as source GAP and reanchor by governance.
- Owner-approved full C3 tier is documented in `docs/programming-agent/ROUTER_WAVE_C3_PROPORTIONAL_TIER_DECISION_V1.md`. A separate GPT Native chat can support an approved in-chat equivalent when separately documented, but `provider_attested=false` and `independent_review=false` until genuine provider attestation. This process cannot prove cryptographic isolation.
- This protocol does not authorize C1 DONE, C2 work, migrations, Train apply, new Router, runtime/production activation or GOLDEN promotion.

## Clean reviewer acquisition
1. Open a **new ordinary ChatGPT conversation outside the LF project**, with Memory/past-chat personalization disabled for the review. Do not use this producer chat, the prior reviewer chat, or a project chat that injects shared history. A temporary chat may lack a persistent reference; use a normal chat if a stable URL is required.
2. The owner records a non-public, stable chat URL or identifier from the interface (e.g. browser address bar), along with a signed or otherwise accountable declaration that the reviewer was isolated from producer messages, keys, previous corpus and answer keys. **Do not publish a chat-share URL containing sealed case bodies**.
3. The reviewer receives only the frozen policy/handoff and public normative source references. It must not be provided previous holdout counts/content hashes as a template to reuse except the stipulated minima of 12 valid + 24 invalid + 2 novel falsifiers; do not expose old case bodies.
4. Reviewer independently generates a **new** sealed corpus, expected outcomes and nonce/seed, never shown to producer. The previous untrusted corpus may remain archived but does not count.
5. Before any producer RAW or C2 evaluation, persist an exact commitment for new manifest/content digests, source SHA, cases/minima, actual independently recorded timestamp, separate reviewer reference and isolation declaration. Preserve proof of the commitment's ordering (trusted git commit, exact blob, relevant UI or equivalent receipts). The reviewer may use the same receipt schema when fields are supported.
6. Mechanically validate through `sandbox/lf_contract_gate_test/router_wave/validate_rw106_c1_holdout_commitment_v1.py`. `STRUCTURAL_PASS_INDEPENDENCE_NOT_PROVEN` is not material independence proof; policy-authorized human owner may assess the accountable separation evidence separately. Keep `independent_review=false` and `provider_attested=false`.
7. Register bounded assertion + DB metadata through governed Migration Train only after all material prerequisites and exact-main revalidation. Maintain C1 PENDING otherwise.

## Stop gates
- If the only evidence of isolation is the reviewer's unsupported self-description, keep GAP.
- If the same or shared project context is exposed, invalidate the reviewer as independent; no reuse of its hidden cases for new holdout.
- If no stable private reference can be obtained, do not invent one.
- If source hashes, migration version, ledger or PASE parity drift, stop and remediate independently.
- Never claim holdout digest content verification without the actual sealed content under a trusted comparison procedure. Never leak private keys, holdout answers, seed/nonce.
