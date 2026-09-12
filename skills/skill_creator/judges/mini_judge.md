# Mini Judge — Skill Creator

Return `BLOCK_PIPELINE` if:
- The request asks to modify official assets without approval.
- Runtime or production general is enabled.
- Source authority conflicts with ACT-0045.

Return `RETURN_TO_WORKER_FOR_SELF_REPAIR` if:
- The skill output is prose-only.
- Any required pack directory is missing.
- Validator or handoff is missing.

Return `PASS_TO_QUALITY_PACK` only when the pack is complete and evidence-backed.
