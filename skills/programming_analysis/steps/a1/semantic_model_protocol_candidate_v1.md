# A1 semantic producer / reviewer protocol — SOURCE_CANDIDATE

Purpose: model-provider-neutral semantic reasoning protocol for A1. It does not create a model call, verify provider identity, or authorize downstream actions. No literal keyword dictionary.


## Native executor transport — canonical mode selection

The semantic author executes through the **existing native conversation**, with
executor_mode chosen by its calling context: GPT_NATIVE / OPENAI_CHATGPT_NATIVE /
CHATGPT_CURRENT_CONVERSATION or CLAUDE_NATIVE / ANTHROPIC_CLAUDE_NATIVE /
CLAUDE_CURRENT_CONVERSATION. These are modes of the same LF generic Native
pattern, **not new model engines**. Never create or call LlamaHTTPClient or any
REMOTE_API alternative for this A1 implementation.

The source-only A1 transport adapter freezes prompt bytes, protocol/schema
hashes and mode/provider pairs; the native conversation authors raw candidate
content and a separate reviewer must review it. The adapter itself does NOT
invoke either GPT or Claude, authenticate author identity, prove independent
review, open an execution, or authorize the next governed stage.

Cross-provider captures are rejected. A source-bound candidate is
SOURCE_BOUND_NATIVE_CHAT_RAW_UNATTESTED, even if its content later passes
local deterministic validation. A callback supplied in tests is never
evidence of a real native execution.

## Semantic producer
Input: original user sentence (unaltered), authenticated business context from caller, schema intent_analysis_candidate_v1.schema.json, and optionally approved prior-scope references.
Output: ONLY JSON satisfying that schema. Do not hardcode catalog entries to login, auth, UI, or example phrases.

Interpret the requested operation by meaning rather than verb match. Distinguish IMPLEMENT (delivery of an as-yet-unverified capability), CREATE (explicit create new artifact), MODIFY, REBUILD, REPAIR, REMOVE and REVIEW. A stated assumption that code does not exist is a user hypothesis, NOT verified repository state.
Identify artifact kind and functional archetype separately. Infer canonical capability as a proposal, not an authoritative registry result. Separate business/actor scope from artifact name. Never manufacture repository IDs or source authorities.
Keep raw mentions solely for subsequent inventory lookup. Provide exact verbatim text spans with Python code-point start/end offsets for OPERATION, ARTIFACT, CAPABILITY, and actor/assumption when applicable. An inferential capability may be supported by a whole descriptive clause, not necessarily a keyword.
Preserve explicitly stated restrictions verbatim as constraints, each literally present in the user text. Capture negation scope and mutually incompatible requests as material ambiguities when not resolvable from the input.
List dimensions to investigate based on capabilities and impacts, not on a screen-specific fixed checklist. The fact that the user did not specify a policy is a reason to SEARCH existing definitions, never proof that the policy is absent.
Do not mark code NEW, deployed, verified, CURRENT, READY, authority SUFFICIENT, or materially LOW without source resolution.
If operation or target is genuinely unclear, use UNKNOWN/material_ambiguities; do not invent certainty. Context may be inferred but source/authority remains candidate.

## Independent semantic reviewer
Read original text and proposed candidate independently; do not trust the producer's explanation or self-declared confidence.
Check semantic fidelity including negation, request type (implement vs create from zero), actor context, artifact-vs-capability, expressed constraints, invented requirements or repository truth, and whether proposed missing dimensions are research tasks rather than claims of missing policies.
A valid substring and numeric offset establish only text provenance, NOT correctness of interpretation.
Return verdict PASS/FAIL and issues. Separate deterministic host code binds the reviewer decision to candidate SHA-256; the model must NOT invent the digest or its own verified identity.
FAIL on unsupported interpretations, ignored material ambiguity, negation drift, or materially altered scope. No fabricated review PASS if no actual reviewer call occurred.

## Safety and qualifications
Two callback functions may be different objects and still be controlled by the same actor. Therefore reviewer identity, model independence, and external attestation remain FALSE until a governed receipt verifies them.
The nine A2 depth signals are evidence-derived from appropriate authorities; hints from A1 do not replace or auto-grade them.
QA corpus must include paraphrases, implied intent without keyword, unrelated archetypes, negation, mixed operations, previously documented but not implemented work, and insufficient requests.
Do not touch Router, RUN, parent/child operations, Supabase, source-of-truth rules or A3/A9 in this development phase.