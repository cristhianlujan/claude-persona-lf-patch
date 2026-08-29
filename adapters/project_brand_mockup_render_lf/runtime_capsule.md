# ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF — Runtime Capsule

Use only when Router/orchestrator resolves this adapter as applicable to a governed deliverable containing LF/project UI visuals.

1. Resolve `project -> design_system -> tokens -> screen_visual_specs -> route_theme_tokens` from governed project sources.
2. Existing governed visual sources outrank generic templates or model defaults.
3. Never invent a canonical palette, typography, spacing system, route theme or screen frame.
4. Choose a mockup/template only after project identity and screen frame requirements are resolved.
5. Preserve supplied product/UI semantics; this adapter controls brand/render translation, not product or UI authority.
6. If required brand authority is absent and no governed fallback exists, return `RETURN_TO_ORCHESTRATOR_MISSING_BRAND_AUTHORITY`.
7. If governed visual sources conflict without precedence, return `BLOCKED_VISUAL_SOURCE_CONFLICT`.
8. Output a `render_binding` with canonical refs, resolved tokens/specs, selected template/frame policy, unresolved blockers and visual QA checks.
9. Visual QA must verify project identity, frame integrity, token provenance and absence of unsupported visual invention.
10. Adapter activation must be evidenced in `lf_adapter_invocations`; this capsule does not authorize standalone execution, runtime enablement or production promotion.
