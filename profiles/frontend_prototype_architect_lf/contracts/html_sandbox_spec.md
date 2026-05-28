# Contract — HTML Sandbox Spec

Status: CANDIDATE_READ_ONLY / CONTROLLED_GITHUB_IMPACT
Applies to: `profiles/frontend_prototype_architect_lf/SKILL.md`

## Purpose
Define the required contract for static HTML/CSS sandbox prototypes created from approved Product Director and UI Architect outputs.

## Required behavior
The worker must produce a prototype specification that can create a local, static browser preview without backend, API, database, build system, authentication or deployment.

## Required deliverable_created fields
- prototype_decision
- source_inputs
- files_to_create
- html_structure
- css_structure
- accessibility_baseline
- interaction_states
- forbidden_runtime_scope
- validation_checklist
- local_run_instructions
- handoff_to_next
- traceability

## Local run rule
The default output must be a standalone `index.html` that can be opened directly in a browser unless a separate approval authorizes a build tool.

## Blocking condition
Return `BLOCKED_FRONTEND_SCOPE` if the requested prototype requires production app behavior, backend logic, API calls, real data, deployment, tracking, payment, authentication or database access.