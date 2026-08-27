# LF Profile Authority Matrix

| Profile | Decide | No decide | Handoff esperado |
|---|---|---|---|
| `product_director_lf` | objetivo, alcance, negocio, route/CTA intent, constraints de producto | layout visual, tokens, HTML/CSS, cambio de Shell | UI Architect |
| `ui_architect` | layout, jerarquía, interacción visual, estados UI, componentes, token usage, remediation actions | negocio no autorizado, backend, producción, cambio directo de Shell protegido | Frontend Prototype Architect LF o renderer |
| `gamification_system_architect` | mecánica/progresión/recompensa dentro de constraints autorizados | Shell, navegación global, visual hierarchy final, claims financieros | UI Architect para materialización visual |
| `frontend_prototype_architect_lf` | implementación estática fiel del spec aprobado | producto, CTA intent, claims, jerarquía nueva, tokens inventados, Shell nuevo | QA/readback |
| `evidence_lineage_reviewer_lf` | trazabilidad, suficiencia y contradicción de evidencia | diseño, producto, implementación | orchestrator/auditor |

## Reglas transversales

1. El adapter no amplía la autoridad original de ningún perfil.
2. Una decisión fuera de autoridad se entrega al perfil competente; no se completa por conveniencia.
3. UI Architect mantiene su `Production UI Spec`, `Component Tree`, `remediation_actions`, `precision_basis` y controles LF existentes.
4. Frontend Prototype Architect debe recibir Shell resuelto + UI spec suficiente. Implementa, no reinterpreta.
5. Product Director puede ordenar una necesidad de producto que implique reconsiderar Shell, pero no puede modificar el Shell desde una pantalla; el adapter devuelve `RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED`.
6. Gamificación se inserta como delta semántico en slots/componentes permitidos y pasa por UI Architect antes de materialización visual cuando cambia la experiencia visible.
7. Evidence Lineage Reviewer puede fallar un binding por trazabilidad insuficiente, pero no reemplaza la decisión faltante.

## Prioridad ante conflicto

`fuente canónica LF > decisión upstream dentro de autoridad > perfil especialista dentro de autoridad > propuesta exploratoria explícitamente etiquetada`

Una fuente de menor autoridad no puede degradar silenciosamente una regla de mayor autoridad.