# Decision Logic — Output Channel Gate

Status: CANDIDATE_READ_ONLY / SANDBOX  
Applies to: Orchestrator, Composer, Worker Output Gate, Quality Pack and Output Gate.

## Purpose

Define the shared middleware logic for validating, routing and cleaning outputs.

Output behavior is controlled by this central logic. Do not create separate folders, contracts or profiles for every output destination.

## Core Principle

The system enforces a 2-stage gate pattern:

1. Validating Gate — before Composer:
   Reject incomplete, suggestive or non-executable worker outputs before they enter Composer.

2. Emission Gate — before final output:
   Apply strict recipient allowlists to prevent internal leakage and tool contamination.

Use allowlists, not blacklists.

Only fields explicitly allowed for the recipient may pass.

## Recipient modes

Allowed recipient modes:

- FINAL_USER
- IMAGE_GENERATOR
- TOOL_PAYLOAD
- INTERNAL_AGENT
- RCA_AUDIT

## Output modes

Allowed output modes:

- FINAL_ANSWER
- FINAL_PROMPT
- IMAGE_PROMPT
- STRUCTURED_DATA
- WORKER_ARTIFACT
- RCA_REPORT
- PATCH
- SQL
- DOCUMENT_DRAFT

## Gate 1 — Worker Output Gate

Run before Composer accepts a worker payload.

```text
IF worker_output == suggestion_only
OR worker_output == recommendation_only
THEN RETURN_TO_WORKER_FOR_SELF_REPAIR

IF worker_output contains recommendations but no executable artifact
THEN RETURN_TO_WORKER_FOR_SELF_REPAIR

IF worker_output lacks the required artifact for its profile
THEN RETURN_TO_WORKER_FOR_SELF_REPAIR

IF worker_output is free-form commentary when a structured artifact is required
THEN RETURN_TO_WORKER_FOR_SELF_REPAIR

IF worker identifies a blocking risk but still marks PASS
THEN RETURN_TO_WORKER_FOR_SELF_REPAIR

IF worker cannot define safely without inventing
THEN RETURN_TO_ORCHESTRATOR

IF worker asks the final user for inputs during automated/headless execution
THEN RETURN_TO_ORCHESTRATOR

IF worker returns unclear handoff to Composer
THEN RETURN_TO_WORKER_FOR_SELF_REPAIR
```

## Gate 2 — Final Emission Gate

Run before sending the final payload to the destination.

Strict allowlist policy applies.

### RECIPIENT: FINAL_USER

Allowed output modes:

- FINAL_ANSWER
- FINAL_PROMPT
- DOCUMENT_DRAFT

Allowlist fields:

- title
- final_message
- readable_content
- next_action
- caveats_visible_to_user

Action:

- Format as human-readable Markdown or text.
- Strip worker traces, scores, raw evidence maps, log evidence, schemas, internal routing notes and RCA-only data.
- Do not expose internal agent material unless the user explicitly requested an audit/RCA.

### RECIPIENT: IMAGE_GENERATOR

Allowed output modes:

- IMAGE_PROMPT

Allowlist fields:

- clean_prompt_string

Action:

- Return only the raw prompt needed by the image generator.
- Strip conversational filler.
- Strip RCA, timeline, worker notes, scores, QA, post-render checklist, audit headings, alternatives not requested and implementation traces.
- Fail if output contains phrases like “Here is your prompt”, “Prompt final:”, “I recommend”, “QA”, “PASS”, “RCA” or worker names.

### RECIPIENT: TOOL_PAYLOAD

Allowed output modes:

- STRUCTURED_DATA
- JSON_PAYLOAD
- SQL
- PATCH

Allowlist fields:

- executable_code
- payload_parameters
- target_id
- operation_type
- validation_requirements

Action:

- Ensure strict executable format.
- Strip Markdown wrappers such as ```json or ```sql before emission.
- Strip explanation, commentary, worker names, PASS/FAIL labels and audit trail.
- Fail if payload is not parseable or executable for the target tool.

### RECIPIENT: INTERNAL_AGENT

Allowed output modes:

- WORKER_ARTIFACT
- STRUCTURED_DATA
- RCA_REPORT

Allowlist fields:

- worker_receipts
- assumptions
- evidence
- risks
- decisions
- self_verdict
- handoff
- blocking_codes
- next_gate
- reasoning_summary
- decision_basis
- metadata

Action:

- Preserve full operational traceability required for downstream agents.
- Do not expose private chain-of-thought.
- Use summaries, evidence maps and decision basis instead.

### RECIPIENT: RCA_AUDIT

Allowed output modes:

- RCA_REPORT
- STRUCTURED_DATA

Allowlist fields:

- actor_timeline
- evidence
- failure_points
- verdicts
- repair_actions
- blocking_codes
- decision_basis
- metadata

Action:

- Preserve audit traceability.
- Do not emit final prompt, image prompt or executable tool payload unless explicitly requested as a separate output.

## Recipient / output compatibility

```text
IF recipient == FINAL_USER
AND output_mode NOT IN [FINAL_ANSWER, FINAL_PROMPT, DOCUMENT_DRAFT]
THEN RETURN_TO_COMPOSER_FOR_CLEANUP

IF recipient == IMAGE_GENERATOR
AND output_mode != IMAGE_PROMPT
THEN BLOCK_PIPELINE

IF recipient == TOOL_PAYLOAD
AND output_mode NOT IN [STRUCTURED_DATA, JSON_PAYLOAD, SQL, PATCH]
THEN BLOCK_PIPELINE

IF recipient == INTERNAL_AGENT
AND output_mode NOT IN [WORKER_ARTIFACT, STRUCTURED_DATA, RCA_REPORT]
THEN RETURN_TO_ORCHESTRATOR

IF recipient == RCA_AUDIT
AND output_mode NOT IN [RCA_REPORT, STRUCTURED_DATA]
THEN RETURN_TO_ORCHESTRATOR
```

## Composer Gate

Composer must compile executable outputs, not concatenate worker notes.

```text
IF Composer receives non-executable worker outputs
THEN RETURN_TO_WORKER_FOR_SELF_REPAIR

IF Composer receives conflicting worker outputs
THEN RETURN_TO_ORCHESTRATOR

IF Composer must invent missing structure to complete the final output
THEN RETURN_TO_WORKER_FOR_SELF_REPAIR

IF Composer output mixes internal spec, QA and final answer
THEN RETURN_TO_COMPOSER_FOR_CLEANUP

IF Composer output does not match requested output_mode
THEN RETURN_TO_ORCHESTRATOR

IF final user requested one output
THEN Composer must emit one output only
```

## Hard fail

Fail if:

- a worker returns only advice when an artifact is required;
- Composer must invent missing structure;
- output recipient and output mode are incompatible;
- final user receives internal agent material without asking for audit;
- image generator receives audit, RCA, worker notes, scores, QA or post-render checklist;
- tool payload contains explanation instead of executable payload;
- output relies on blacklist cleanup instead of recipient allowlist;
- a case-specific rule is added when an existing gate already covers the failure.

## Maintenance rule

Do not create a new folder for every output type.

Create folders by capability or profile, not by output destination.

Use this central decision logic for channel behavior and keep profile folders focused on their specialized artifacts.

## Anti-infinite-rules rule

Do not add case-specific rules to this file.

If a new failure appears, classify it under one of these existing gates:

- recipient mode mismatch
- output mode mismatch
- worker output incomplete
- suggestion-only worker output
- Composer invention required
- internal fields leaked to final output
- tool payload contaminated
- image prompt not cleaned
- unresolved blocking risk
- recipient allowlist violation

Only add a new condition if the failure cannot be classified under the existing gates.
