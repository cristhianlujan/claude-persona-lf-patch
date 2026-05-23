# Patch — Skill/Profile Creator Output Upgrade

## Problem

The current Skill/Profile Creator can produce useful but basic outputs when it only generates narrative instructions. That is insufficient for controlled LF operations.

## Required behavior after patch

When asked to create a skill or profile, the creator must generate a complete GitHub-ready pack, not only a prompt/instruction document.

## Required output

The creator must return:

1. `SKILL.md`
2. `README.md`
3. `contracts/main_contract.md`
4. `contracts/missing_input_policy.md`
5. `schemas/output.schema.json`
6. `schemas/missing_input.schema.json`
7. `judges/score_rubric.md`
8. `judges/mini_judge.md`
9. `checklists/preflight_checklist.md`
10. `checklists/priority_checklist.md`
11. `examples/good_output.json`
12. `examples/bad_output.json`
13. `examples/self_repair_output.json`
14. `fixtures/happy_path/input.json`
15. `fixtures/missing_inputs/input.json`
16. `fixtures/unsafe_or_blocked/input.json`
17. `fixtures/self_repair/bad_output.json`
18. `validators/validate_pack.py`
19. `evals/eval_matrix.json`
20. `handoffs/to_quality_pack.handoff.json`
21. `adapters/github_pack_adapter.md`
22. `adapters/document_patch_adapter.md`

## Blocking rule

If the creator produces only prose, it must self-repair.

Blocking code:

```text
BASIC_SKILL_OUTPUT_NOT_ACCEPTABLE
```

## Self-repair action

Return a complete pack structure with all required folders and files.


## Sandbox self-repair requirement

The self-repair example must itself be schema-valid under `schemas/output.schema.json` while preserving `BASIC_SKILL_OUTPUT_NOT_ACCEPTABLE` as the blocking code.
