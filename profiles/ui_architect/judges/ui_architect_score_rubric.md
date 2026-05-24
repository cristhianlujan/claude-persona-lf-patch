# Judge — UI Architect 25-Point Score Rubric

Status: CANDIDATE_READ_ONLY / SANDBOX

## Rule
No score can be assigned without evidence. If evidence is missing, that criterion scores 0 even when the worker claims compliance.

## Criteria

### 1. Layout precision — 5 points
- 5: zones, proportions, grid, content placement and restrictions are explicit.
- 3: zones exist but proportions or placement are partial.
- 1: only general layout language.
- 0: no layout evidence.

### 2. Visual hierarchy — 5 points
- 5: ranked elements, visual weight and rationale are explicit.
- 3: hierarchy is implied but not fully ranked.
- 1: generic statement about clarity/premium.
- 0: no hierarchy evidence.

### 3. System fidelity — 5 points
- 5: active design-system tokens, safety constraints, blocked patterns and component mapping are explicit.
- 3: some tokens are named but not mapped.
- 1: generic brand alignment.
- 0: no system fidelity evidence.

### 4. State mapping — 5 points
- 5: active/secondary/disabled/hover/informational states are explicit where relevant.
- 3: states are partially listed.
- 1: claims states exist without details.
- 0: no state evidence.

### 5. Handoff quality — 5 points
- 5: composer, prompt worker or next artifact can proceed without inventing structure.
- 3: useful but still requires interpretation.
- 1: mostly recommendations.
- 0: not actionable.

## Render-readiness modifier
When the next downstream step is visual prompt generation, image generation, UI mockup rendering or creative variation, the judge must also check render-readiness.

Render-readiness does not add extra points beyond 25. It modifies Handoff quality:
- Handoff quality can score 5 only if `visual_reference_spec`, `negative_prompt_constraints` and `render_acceptance_criteria` are sufficient for the next visual worker to proceed without inventing composition.
- Handoff quality is capped at 3 if the UI spec is structurally useful but lacks render acceptance criteria.
- Handoff quality is capped at 1 if it only gives adjectives such as modern, premium, clean, beautiful or intuitive.
- Handoff quality is 0 if the render worker would need to invent layout, focal point, hierarchy or constraints.

## Passing gates
- 20/25 minimum to continue to composer.
- Any 0 in Layout precision or Handoff quality blocks the flow.
- Any project safety failure injected by an adapter or contract blocks the flow regardless of total score.

## Evidence requirements
Scores must cite evidence from the output itself:
- component IDs for layout and hierarchy;
- token map or system constraints for system fidelity;
- explicit state names for state mapping;
- prompt constraints, visual reference spec or acceptance criteria for handoff quality.

If evidence is not present in the output, assign 0 for that criterion even if the worker claims compliance.
