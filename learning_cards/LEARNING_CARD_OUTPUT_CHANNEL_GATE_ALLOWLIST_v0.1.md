# LEARNING_CARD_OUTPUT_CHANNEL_GATE_ALLOWLIST_v0.1

Status: CANDIDATE_READ_ONLY / SANDBOX  
Applies to: multi-worker flows, Composer, Quality Pack, Output Gate, image prompts, tool payloads, final user outputs and RCA/audit flows.

## Problem observed

In multi-agent flows, the system can mix internal outputs, user-visible outputs and tool payloads.

Observed failure patterns:

- The user asks for a final prompt and receives RCA/timeline instead.
- The image generator receives QA, audit notes or worker traces.
- Composer receives suggestions instead of executable artifacts.
- Final user receives internal traceability that was not requested.
- The system attempts to solve the issue by creating folders/contracts per output type, which creates unmanageable complexity.

## Learning

The correct solution is not to create one folder, contract or profile for every output type.

The correct solution is:

**central middleware-style decision logic + strict recipient allowlists**

Use `orchestrator/decision_logic.md` as the central Output Channel Gate.

## Core principle

The level of detail depends on the recipient:

- Internal agent: structured traceability is allowed.
- Final user: only useful visible output is allowed.
- Tool/API: only executable payload is allowed.
- Image generator: only clean image prompt is allowed.
- RCA/Audit: timeline, evidence, verdicts and failure points are allowed.

## Auto-activation trigger

This learning card must be automatically consulted by Router/Orchestrator before activating workers, Composer, Quality Pack or Output Gate when any of the following conditions are present:

- the task uses multiple workers, profiles, experts or agents;
- the task includes Composer or consolidated output;
- the task requests a final prompt;
- the task outputs to an image generator;
- the task outputs to a tool, API, SQL, JSON, PATCH or executable payload;
- the task requests or produces RCA, audit, timeline, evidence or traceability;
- the task has a mismatch risk between internal output and final visible output;
- the user requests one final output but the workflow generates multiple internal artifacts;
- a worker returns suggestions, recommendations or commentary instead of an executable artifact.

```text
IF any trigger is true
THEN load OUTPUT_CHANNEL_GATE_ALLOWLIST before distribution and before final emission.

IF not loaded when a trigger is present
THEN BLOCK_PIPELINE_WITH_CODE: OUTPUT_CHANNEL_GATE_NOT_LOADED.
```

## Required consultation point

Before creating new rules, folders, contracts, profiles or schemas for an output-related failure, check whether the failure is already covered by `orchestrator/decision_logic.md`.

Classify the failure under one of:

- recipient mode mismatch;
- output mode mismatch;
- worker output incomplete;
- suggestion-only worker output;
- Composer invention required;
- internal fields leaked to final output;
- tool payload contaminated;
- image prompt not cleaned;
- unresolved blocking risk;
- recipient allowlist violation.

Only propose a new rule if the failure cannot fit any existing category.

## Base pseudocode

```text
IF worker_output == suggestion_only
THEN RETURN_TO_WORKER_FOR_SELF_REPAIR

IF worker_output lacks required artifact
THEN RETURN_TO_WORKER_FOR_SELF_REPAIR

IF Composer receives non-executable worker outputs
THEN RETURN_TO_WORKER_FOR_SELF_REPAIR

IF recipient == FINAL_USER
THEN allow only user-visible fields

IF recipient == IMAGE_GENERATOR
THEN allow only clean_prompt_string

IF recipient == TOOL_PAYLOAD
THEN allow only executable payload fields

IF recipient == INTERNAL_AGENT
THEN allow structured traceability fields

IF recipient == RCA_AUDIT
THEN allow actor timeline, evidence, failure points and repair actions

IF output violates recipient allowlist
THEN CLEAN_ONCE

IF output still violates recipient allowlist
THEN BLOCK_PIPELINE
```

## Recipient allowlists

### FINAL_USER

Allowed:

- title
- final_message
- readable_content
- next_action
- caveats_visible_to_user

Hide:

- worker_receipts
- scores
- internal QA
- RCA
- schemas
- routing notes
- internal evidence maps

### IMAGE_GENERATOR

Allowed:

- clean_prompt_string

Hide:

- conversational filler such as “Here is your prompt”;
- RCA;
- timeline;
- worker notes;
- QA;
- scores;
- post-render checklist;
- alternatives not requested;
- internal metadata.

### TOOL_PAYLOAD

Allowed:

- executable_code
- payload_parameters
- target_id
- operation_type
- validation_requirements

Hide:

- markdown wrappers;
- explanations;
- conversational comments;
- audit trail;
- worker names.

### INTERNAL_AGENT

Allowed:

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

Do not expose private chain-of-thought. Use reasoning summaries and decision basis.

### RCA_AUDIT

Allowed:

- actor_timeline
- evidence
- failure_points
- verdicts
- repair_actions
- blocking_codes
- decision_basis
- metadata

## PASS criteria

PASS if:

- the worker delivers an artifact, not a suggestion;
- Composer does not invent missing structure;
- output matches recipient and output mode;
- final user does not receive internal fields;
- tool receives clean executable payload;
- image generator receives only clean prompt;
- audit receives enough traceability.

## FAIL criteria

FAIL if:

- worker delivers only opinion;
- Composer concatenates notes;
- final prompt includes QA/RCA;
- image generator receives audit content;
- tool payload includes explanation;
- a new folder is proposed per output destination;
- a case-specific rule is added when the central gate already covers the case.

## Status

CANDIDATE / REQUIRES_SANDBOX
