# LF Profile & Skill Pack Standard v0.1 CANDIDATO

Status: CANDIDATE_READ_ONLY / SANDBOX  
Patch ID: PATCH_LF_SKILL_PROFILE_PACK_STANDARD_001  
Operational authority: Supabase `public.v_lf_fuente_operativa` under ACT-0001 Router  
Factory governing asset: ACT-0045 — SKILL_CREADORA_PERFILES_Y_CARDS_LF_v0.1_CANDIDATO  
Created at: 2026-05-23T05:13:22.144126+00:00

## Purpose

Prevent LF skills and profiles from producing basic, incomplete, non-testable outputs by requiring every reusable profile/skill to be packaged as a GitHub-ready, auditable, testable pack.

## Minimum pack structure

Every mature LF profile or skill must include:

```text
SKILL.md
README.md
contracts/
schemas/
judges/
checklists/
examples/
fixtures/
validators/
evals/
handoffs/
adapters/
```

## Non-negotiable rule

A skill/profile is not considered ready if it only contains instructions. It must contain contracts, machine-checkable schemas, quality gates, examples, fixtures, validators, evals, handoffs and adapters.

## Required lifecycle

```text
CANDIDATE
→ EN_REVISION
→ PRUEBA_SANDBOX
→ APROBADO
→ IMPACTO_CONTROLADO
→ VERIFICADO
→ CERRADO
```

## Mandatory gates

- No official impact without Router.
- Supabase `public.v_lf_fuente_operativa`, plus the Supabase registries/contracts it resolves, is the only operational authority.
- ACT-0045 governs Skill/Profile Factory behavior only after resolution from Supabase.
- GitHub stores technical implementation packs; operational use requires an explicit Supabase binding and GitHub is not an independent operational authority.
- Google Drive, Google Docs and Google Sheets are storage/human-readable mirror layers only. They must never be read or hydrated to determine operational state, authority, rules, routing or permissions.
- A Google Drive/Docs/Sheets URL may be retained only as a storage reference or lineage value in Supabase; it is not an operational source.
- Python may prepare and validate, but not write official artifacts without the applicable governed operation.
- n8n or Drive API may handle approved file-storage metadata operations such as move/archive/delete when needed; those operations do not confer operational authority on Drive.

## Pack readiness definition

A pack is READY_FOR_SANDBOX when:

1. SKILL.md defines purpose, activation, limits and output modes.
2. contracts/ contains operational contract and missing-input policy.
3. schemas/ validates machine-readable outputs.
4. judges/ contains scoring rubric and mini-judge.
5. checklists/ contains preflight and priority checks.
6. examples/ contains good, bad and self-repair outputs.
7. fixtures/ contains happy path, missing input, unsafe/block and self-repair cases.
8. validators/ can execute at least schema and contract validation.
9. evals/ defines pass thresholds and regression cases.
10. handoffs/ defines payloads to Quality Pack, Composer, Final Judge or next worker.
11. adapters/ defines output adaptation without creating infinite tool-specific rules.


## Sandbox repair note

Before PR, validators must check the full 22-file minimum structure and validate good/self-repair examples against `schemas/output.schema.json`. Bad examples must intentionally fail schema validation when they represent prose-only outputs.
