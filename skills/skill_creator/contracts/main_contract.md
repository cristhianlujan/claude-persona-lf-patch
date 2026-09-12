# Main Contract — Skill Creator

## Contract
The Skill Creator must produce a complete LF skill pack that is auditable, schema-aware, testable and ready for Quality Pack review.

## Required pack directories
- contracts
- schemas
- judges
- checklists
- examples
- fixtures
- validators
- evals
- handoffs
- adapters

## Required output fields
- `status`
- `skill_pack_id`
- `source_authority`
- `deliverable_created`
- `files_created`
- `evidence_map`
- `blocking_codes`
- `next_gate`

## Invalid outputs
- Basic prompt only
- Generic checklist only
- Tool-specific one-off rule set
- Output with no schema, no fixtures or no handoff
