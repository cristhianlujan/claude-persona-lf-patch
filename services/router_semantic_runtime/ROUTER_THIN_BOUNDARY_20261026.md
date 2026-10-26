# ACT-0001 thin Router boundary — 2026-10-26

This change preserves the existing Router/Profile architecture without adding a new layer.

Boundary:
- ACT-0001 classifies channel, business and minimal scope.
- ACT-0001 performs deterministic profile discovery plus one semantic selection.
- ACT-0001 does not load or diagnose canonical Product context.
- The selected profile investigates Product in READ_ONLY mode.
- Existing `public.lf_profile_execution_channel_context_v1` hydrates the Product context during governed profile execution.
- Any updater/insert remains a separate governed operation and any database mutation continues through LF Migration Merge Train.

Regression target:
`Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.`

Expected boundary:
`Stage1 -> Router derivation -> profile selection -> Gate2 -> READ_ONLY profile investigation -> Router return -> separate governed mutation only if required`.
