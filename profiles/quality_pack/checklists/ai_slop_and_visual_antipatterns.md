# Checklist — AI Slop and Visual Anti-Patterns

Status: GENERIC_REUSABLE_CHECKLIST
Applies to: Quality Pack review of UI specs, prompts and renders.

## Purpose
Detect generic AI-looking UI and common visual shortcuts before they reach Composer or generation.

## AI slop signals
Block or repair if the output relies on:
- clean, modern, premium, intuitive, trustworthy, beautiful, sleek, elegant, without component evidence;
- generic cards with icon + title + text repeated as the main design;
- heroic marketing layout when the task is a product screen;
- dashboard/KPI layout when the task is guidance or onboarding;
- decoration that does not support the user journey;
- vague color words without semantic token mapping;
- states claimed but not listed;
- score claimed but not evidenced.

## Visual anti-patterns
- Gradient text as decoration.
- Glassmorphism by default.
- Hero metric template.
- Identical card grids.
- Modal as first thought.
- Side-stripe card accents.
- Multiple competing CTAs.
- Red alarm cues in debt contexts.
- Cold banking aesthetic for stress-reduction flows.
- Casino/game mechanics in financial stress contexts.

## Required repair
When detected, Quality Pack must return:
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`
- specific anti-pattern code;
- exact component or zone affected;
- required replacement structure.

## Example blocking codes
- `AI_SLOP_GENERIC_ADJECTIVES`
- `AI_SLOP_IDENTICAL_CARD_GRID`
- `WRONG_REGISTER_MARKETING_HERO`
- `WRONG_REGISTER_DASHBOARD`
- `TOKEN_MAPPING_MISSING`
- `STATE_MAPPING_MISSING`
- `DARK_PATTERN_VISUAL_PRESSURE`
