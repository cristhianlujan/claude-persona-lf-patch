# LEARNING_CARD_OUTPUT_CHANNEL_GATE_ALLOWLIST_v0.1

Status: CANDIDATE_READ_ONLY / SANDBOX  
Applies to: multi-worker flows, Composer, Quality Pack, Output Gate, image prompts, tool payloads, final user outputs, visual choices and RCA/audit flows.

## Problem observed

In multi-agent flows, the system can mix internal outputs, user-visible outputs and tool payloads.

Observed failure patterns:

- The user asks for a final prompt and receives RCA/timeline instead.
- The image generator receives QA, audit notes or worker traces.
- Composer receives suggestions instead of executable artifacts.
- Final user receives internal traceability that was not requested.
- The user asks for a decision and receives a concept or advice instead of an executable specification.
- The user asks to explore visual direction and receives a long internal report instead of selectable options.
- The system attempts to solve the issue by creating folders/contracts per output type, which creates unmanageable complexity.

## Learning

The correct solution is not to create one folder, contract or profile for every output type.

The correct solution is:

**central middleware-style decision logic + strict recipient allowlists + intent clarification before workers**

Use `orchestrator/decision_logic.md` as the central Output Channel Gate.

## Core principle

The level of detail depends on the recipient and the interaction mode:

- Internal agent: structured traceability is allowed.
- Final user: only useful visible output is allowed.
- Tool/API: only executable payload is allowed.
- Image generator: only clean image prompt is allowed.
- RCA/Audit: timeline, evidence, verdicts and failure points are allowed.
- Visual exploration: show compact selectable options, not internal analysis.
- Concrete decision: emit one executable decision, not alternatives.

The user does not need to know internal terms such as artifact, output_mode, DECISION_SPEC or allowlist.

The Orchestrator must translate user language into the correct internal mode.

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
- the user asks for a visual exploration, visual alternatives, options or direction;
- the user asks for one decision, one definition or one concrete output;
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

- ambiguous intent before workers;
- visual exploration requested;
- decision requested but alternatives emitted;
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

## Gate 0 base pseudocode

```text
IF user_request is ambiguous
AND different interpretations would produce materially different outputs
AND the user did not provide enough fields to decide safely
THEN ASK_ONE_QUESTION

IF user_request asks to explore, compare, review options, find direction, choose visual direction, or evaluate alternatives
THEN PRESENT_VISUAL_OPTIONS

IF user_request asks for one decision, one definition, one final prompt, one output, or says no options/no suggestions
AND context is sufficient
THEN DECIDE_AND_EXECUTE

IF user_request already specifies required fields, output format, exact scope or mandatory output sections
THEN DECIDE_AND_EXECUTE
```

## User-facing visual choice pattern

Use this when the mode is `PRESENT_VISUAL_OPTIONS`.

```text
Selecciona una opción:

( ) A · <option_name>
    <one-line description>
    Recomendado para: <best_use>
    Riesgo: <main_risk>

( ) B · <option_name>
    <one-line description>
    Recomendado para: <best_use>
    Riesgo: <main_risk>

( ) C · <option_name>
    <one-line description>
    Recomendado para: <best_use>
    Riesgo: <main_risk>

( ) Otro:
    [Escribe tu idea o referencia]

Prioridad principal:
[ ] Más premium
[ ] Más cálido
[ ] Más financiero
[ ] Más gamificado
[ ] Más limpio
[ ] Otro: [escribir]

Acción:
[Confirmar opción]
[Prefiero que tú decidas]
```

## Visual choice rules

```text
IF mode == PRESENT_VISUAL_OPTIONS
THEN present 3 options maximum by default.

IF the user asks for more breadth
THEN present 4 options maximum.

Each option must include:
- option_name
- visual_base
- structure
- visual_weight
- best_use
- main_risk

After presenting options, ask the user to choose one, write Otro, or select “Prefiero que tú decidas”.

Do not implement multiple directions.
Once the user chooses, implement only the selected direction.

IF the user selects “Otro”
THEN translate the user's natural language into the required internal artifact without asking for technical terms.

IF the user selects “Prefiero que tú decidas”
THEN choose the strongest option and emit a concrete executable decision.
```

## Decision execution rule

When the user asks for a concrete decision and context is sufficient, do not present alternatives.

For UI decisions, return concrete selected values:

- selected visual type
- base color or surface
- size or coverage
- density
- depth
- visual weight
- position behavior
- relationship to main element
- implementation format
- hard exclusions
- final prompt if requested

```text
IF output contains only concept name, rationale or recommendation
THEN RETURN_TO_WORKER_FOR_SELF_REPAIR
```

## Base output-channel pseudocode

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
- selection_options
- selected_decision
- short_prompt

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
- audit receives enough traceability;
- visual exploration is shown as compact selectable options;
- concrete decision requests produce one executable decision.

## FAIL criteria

FAIL if:

- worker delivers only opinion;
- Composer concatenates notes;
- final prompt includes QA/RCA;
- image generator receives audit content;
- tool payload includes explanation;
- visual exploration is shown as long internal report;
- concrete decision request receives multiple options or a vague concept;
- a new folder is proposed per output destination;
- a case-specific rule is added when the central gate already covers the case.

## Status

CANDIDATE / REQUIRES_SANDBOX
