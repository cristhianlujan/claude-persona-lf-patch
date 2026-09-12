# Reference — LF UI Design Laws

Status: GENERIC_REUSABLE_REFERENCE
Applies to: UI Architect and Quality Pack.

## Purpose
Provide reusable UI laws adapted to Libertad Financiera without copying external skill style systems wholesale.

## Scene before style
Before choosing layout, theme or visual intensity, define one concrete scene:
- who uses this screen;
- what emotional state they are in;
- what decision or task they must complete;
- what level of pressure must be avoided.

## Color strategy
Use semantic LF tokens first:
- `warm_surface #F7F5F0`: base background for debt/clarity/stress contexts.
- `green_action #00A32A`: primary CTA, active progress, safe next step.
- `navy_core`: titles, structure, trust.
- `slate_text`: secondary content, inactive states, labels.
- `gold_reward`: sober reward accent only.
- `blue_brand_accent`: minor accent, never dominant.

## Product UI law
A product screen must serve the user's task. It must not become a marketing landing, hero section, poster, dashboard or catalog unless that is the requested register.

## Typography
- Body line length should stay readable, usually 65 to 75 characters maximum.
- Hierarchy must use scale, weight and spacing, not decoration alone.
- Avoid flat typography where titles, labels and body compete.

## Layout
- Do not wrap everything in cards.
- Avoid nested cards unless the hierarchy truly requires it.
- Use spacing rhythm, not identical padding everywhere.
- A guided flow should have one dominant next action and a clear secondary context.

## Motion
- Motion must clarify state or transition.
- No bounce/elastic effects for debt, stress or financial clarity contexts.
- Respect reduced motion when relevant.

## LF anti-patterns
Block these unless explicitly approved:
- cold bank dashboard when the user needs guidance;
- hero metric template;
- generic identical card grid;
- gradient text as decoration;
- glassmorphism by default;
- multiple competing CTAs;
- red/danger debt cues;
- urgency pressure;
- casino/game mechanics;
- unapproved partner logos or buyer imagery.

## AI slop test
Fail or repair if the UI could be described as generic AI output: clean, modern, premium, trustworthy, intuitive, with no component-level evidence.
