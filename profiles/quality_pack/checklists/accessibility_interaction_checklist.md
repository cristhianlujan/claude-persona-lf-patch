# Checklist — Accessibility and Interaction

Status: GENERIC_REUSABLE_CHECKLIST
Applies to: Quality Pack and UI Architect.

## Purpose
Ensure core usability and interaction quality before a UI spec proceeds downstream.

## Accessibility checks
- Text contrast must be sufficient for body, labels and CTA text.
- Information cannot rely on color alone.
- Interactive elements must have visible enabled, hover/focus and disabled states when relevant.
- Inputs must have labels, helper text and error states when forms are present.
- Icons need text labels or accessible meaning when they carry important information.
- Reduced motion must be considered when motion is used.

## Interaction checks
- One dominant CTA only unless multiple actions are explicitly required.
- Primary CTA must be visually distinct and semantically safe.
- Secondary actions must not compete with the primary action.
- Touch/click targets should be comfortable, generally near 44px minimum when applicable.
- Loading and empty states should be defined when the screen depends on async data.
- Error states should guide recovery, not blame the user.

## Financial-stress context
- Avoid pressure language.
- Avoid urgent visual alarms.
- Avoid shame, blame or fear in error states.
- Prefer guidance, explanation and next-step clarity.

## Blocking codes
- `A11Y_CONTRAST_UNSPECIFIED`
- `A11Y_COLOR_ONLY_MEANING`
- `INTERACTION_STATE_MISSING`
- `CTA_COMPETITION`
- `ERROR_STATE_BLAME_OR_PRESSURE`
- `FINANCIAL_STRESS_ALARM_PATTERN`
