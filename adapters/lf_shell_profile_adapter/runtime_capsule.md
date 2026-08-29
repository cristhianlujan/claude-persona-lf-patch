# ADAPTER_LF_SHELL_PROFILE — Runtime Capsule

Use only when Router/orchestrator resolves this adapter as applicable to the current LF profile execution.

1. Resolve target screen from governed LF sources; then resolve `screen -> module -> app_shell`.
2. Supabase LF operational/design sources outrank inherited Drive metadata.
3. Preserve specialist authority: profile decides the semantic delta; Shell/Design System governs structure/tokens; this adapter limits where the delta may apply.
4. Classify every target as `SHELL_LOCKED`, `SCREEN_COMPONENT`, or `SCREEN_SLOT`.
5. Never mutate `SHELL_LOCKED` through a normal profile delta; return `RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED`.
6. Never invent canonical tokens, product rules, claims, CTA intent, routes or financial meaning.
7. If material authority is missing, return `RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY`.
8. If canonical sources conflict without resolvable precedence, return `BLOCKED_SOURCE_CONFLICT`.
9. Output a `shell_binding` that identifies canonical refs, protected targets, writable targets, normalized profile delta, precision basis, blockers and allowed handoff.
10. Adapter activation must be evidenced in `lf_adapter_invocations`; this capsule does not authorize standalone execution, runtime enablement or production promotion.
