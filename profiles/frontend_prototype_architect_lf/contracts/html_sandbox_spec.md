# Contract — HTML Sandbox Spec

Status: CANDIDATE_READ_ONLY / CONTROLLED_GITHUB_IMPACT
Applies to: `profiles/frontend_prototype_architect_lf/SKILL.md`

## Purpose
Define the contract for static HTML/CSS sandbox work created from approved Product Director and UI Architect outputs, while separating implementation advice/specification from claims that a prototype artifact was actually created.

## Execution modes
Every `HTML_SANDBOX_SPEC` must declare exactly one execution mode:

- `ADVISORY_SPEC_ONLY`: implementation guidance/specification only. It may describe files and structure, but it MUST NOT claim that an artifact exists or return `PASS_ARTIFACT_VERIFIED`.
- `CREATE_AND_VERIFY_ARTIFACT`: the worker must create the sandbox artifact and can return `PASS_ARTIFACT_VERIFIED` only after independent deterministic readback.

A specification is not evidence that a file exists.

## Upstream provenance requirement
`source_inputs` must contain current authoritative evidence for both:
- `PRODUCT_DIRECTION`
- `UI_ARCHITECT`

Each source input must include a repo-relative `source_ref`, exact `source_sha256`, `currentness=CURRENT`, and `verdict=PASS|APPROVED`.

The deterministic validator must resolve each `source_ref` from the workspace, read the source bytes and recompute SHA-256. A supplied boolean, label or hash is not proof by itself. Missing, stale, fictitious, traversal, mismatched-SHA or non-PASS upstream evidence blocks artifact PASS.

## Artifact completion requirement
For `CREATE_AND_VERIFY_ARTIFACT`, `files_to_create` must be non-empty and include `index.html`. `artifact_evidence` must cover every declared file and record path, declared SHA, readback SHA, byte count and parse/read status.

`PASS_ARTIFACT_VERIFIED` is valid only when the profile-local deterministic validator independently proves:
1. every declared file exists under an allowed sandbox path;
2. every file was read back from disk;
3. SHA-256 recomputed from disk equals both declared and readback hashes;
4. byte count matches the file readback and is non-zero;
5. `index.html` is structurally parseable as a static HTML document;
6. every declared file is represented by artifact evidence;
7. required Product/UI upstream refs are independently resolved and current.

Declared flags such as `exists=true`, `readback=true`, `receipt_valid=true`, or candidate-provided matching hashes never substitute for external readback.

## Required deliverable fields
- prototype_decision with `execution_mode`
- source_inputs
- files_to_create
- artifact_evidence
- html_structure
- css_structure
- accessibility_baseline
- interaction_states
- forbidden_runtime_scope
- validation_checklist
- local_run_instructions
- handoff_to_next
- traceability

Empty `files_to_create`, empty HTML/CSS structures, generic validation criteria or score without evidence are invalid.

## Local run rule
The default created artifact must include a standalone `index.html` that can be opened directly in a browser unless a separate approval authorizes a build tool.

## Blocking condition
Return `BLOCKED_FRONTEND_SCOPE` if the requested prototype requires production app behavior, backend logic, API calls, real data, deployment, tracking, payment, authentication or database access.
