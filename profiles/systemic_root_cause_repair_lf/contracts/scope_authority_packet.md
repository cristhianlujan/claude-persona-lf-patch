# Scope Authority Packet — EJECUCION_PERFIL_LF / Semantic Judge B

Status: SANDBOX_B_EXPERIMENT

## Purpose
Define the existing `input_validate` handoff needed by the semantic judge. This is not a new authority or persistence layer. It is a hash-bound projection of canonical scope/authority already resolved for the exact execution.

## Producer independence
The packet MUST be materialized before `execute_profile`. The producer may consume it but cannot write, widen, replace, or reinterpret its authority precedence.

## Minimum shape
```json
{
  "packet_version": "LF_SCOPE_AUTHORITY_PACKET_V1",
  "execution_id": "...",
  "subject_ref": "...",
  "authorized_requirements": [
    {"id":"REQ-...","statement":"...","source_ref":"...","materiality":"BLOCKING|MATERIAL"}
  ],
  "constraints": [
    {"id":"CON-...","statement":"...","source_ref":"...","materiality":"BLOCKING|MATERIAL"}
  ],
  "forbidden_changes": [
    {"id":"FORBID-...","statement":"...","source_ref":"...","materiality":"BLOCKING|MATERIAL"}
  ],
  "authority_precedence": [
    {"rank":1,"source_ref":"...","reason":"..."}
  ],
  "related_context_refs": ["..."],
  "source_refs": ["..."],
  "compiled_at": "...",
  "sha256": "..."
}
```

The SHA binds the canonical JSON representation selected by the execution protocol. The exact canonicalization rule must be explicit in the receipt.

## Required compilation behavior
- Resolve the exact execution/child scope first.
- Preserve explicit allow/deny/approval/compatibility/sequencing constraints.
- Related parent/context may add evidence, not scope, unless an authority rule explicitly says otherwise.
- A missing material authority is surfaced as an input blocker; it is never replaced with a permissive assumption.
- Each material requirement/constraint receives a stable ID so the semantic judge can prove complete coverage.

## No MR02 hardcoding
The compiler is source-agnostic. Backlog rows are one possible canonical source. Other executions may derive scope from a SPEC, contract, issue, policy binding, explicit user authorization, or another governed source.
