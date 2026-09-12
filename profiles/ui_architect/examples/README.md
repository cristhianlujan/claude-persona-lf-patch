# UI Architect Examples

Status: GENERIC_REUSABLE_EXAMPLES

## Purpose
Examples in this folder must be generic and reusable. They must not use a business case as profile structure, file path or primary example identity.

## Good examples
- `good_component_tree_web_product_screen.json`
  - Production-grade Component Tree example for a generic web product screen.
  - Shows layers, typography, color tokens, states, spacing, risk controls and prompt constraints.

## Bad examples
- `bad_generic_output.json`
  - Fails because it gives generic advice instead of an executable UI spec.

- `bad_case_specific_leakage.json`
  - Fails because it uses a business case, persona or case-specific progress as reusable profile structure.

## Rules
- Do not create examples named after a project case.
- Do not hardcode unvalidated personas, partner names or case-specific step counts in generic examples.
- Route, marketplace or product-specific cases belong in sandbox runs metadata, not in reusable profile examples.
- A good UI Architect example must use Component Tree structure and must map tokens, states, spacing, typography and risk controls by component.
