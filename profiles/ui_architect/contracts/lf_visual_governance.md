# Contract — LF Visual Governance

Status: CANDIDATE_READ_ONLY / SANDBOX
Applies to: UI Architect outputs for MarketPlace Libertad Financiera and debt-related experiences.

## Non-negotiable LF rules
- Prioritize clarity over aggressive conversion.
- The experience must feel like guidance/accompaniment, not cold banking or collections.
- No red as debt alarm, danger or pressure color.
- No aggressive urgency, shame, fear, countdowns or false scarcity.
- No guaranteed debt elimination promises.
- No cold banking dashboards when the goal is emotional clarity.

## Semantic tokens
- `warm_surface`: default base for debt/clarity experiences; use for calm background and anxiety reduction.
- `navy_core`: titles, structure, trust and hierarchy.
- `green_action`: primary CTA, active positive progress and safe next step.
- `gold_reward`: minimal sober reward/clarity accent only.
- `slate_text`: secondary text, inactive steps, borders and labels.
- `blue_brand_accent`: minor brand accent; never dominant.

## LF Shell adapter — obligatorio para pantallas LF
When the target is an LF screen, load and apply:

`adapters/lf_shell_profile_adapter/ADAPTER.md`

Before a production UI spec or remediation decision is considered executable:
- resolve `pantalla -> módulo -> app_shell` from the canonical LF source;
- resolve applicable variants/elements and Design System tokens;
- classify every material execution target as `SHELL_LOCKED`, `SCREEN_SLOT` or `SCREEN_COMPONENT`;
- preserve the Shell when the target is `SHELL_LOCKED` and return `RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED` instead of altering it from a screen remediation;
- preserve `Production UI Spec`, `remediation_actions`, `precision_basis`, semantic authority and Router/direct consistency requirements from the existing UI Architect contracts.

The adapter limits where a UI decision may be applied; it does not replace UI Architect visual authority.

## Debt-context UI safety
When financial stress or debt appears, UI Architect must explicitly check:
- Does any element feel like collections pressure?
- Does the UI push the user to buy/contract before understanding their situation?
- Does the color system increase anxiety?
- Does the layout create too many decisions?
- Is the next step clear and non-coercive?

## Hard fail
Fail if the UI uses red alert debt patterns, aggressive conversion, misleading certainty, excessive KPIs, creditor-pressure language, or visual shame cues.

For an LF screen, also fail if the Shell adapter is skipped when the canonical Shell relationship is available, if a `SHELL_LOCKED` target is modified as a normal screen delta, or if an invented value is represented as canonical.