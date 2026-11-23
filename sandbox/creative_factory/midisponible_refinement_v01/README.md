# SALY · Refinamiento aislado «Mi disponible» + readback de tokens

**Autorizado por usuario:** 23/11/2026; crear pedido **nuevo** SOLO para convertir «Mi disponible» en un acceso a «Cómo se calcula». Revisar uso de tokens en skill, sin modificar esta skill, otros copys, layouts ni colores en este lote.

## Estado del origen observado
- Orden #7 `SALY_HOME_V015_SINGLE_20261123` / ítem #10 `HOME`: `PLANIFICADO/PENDIENTE`, `review_only=true`, `render_authorized=false`, `rendering_authority=false`, `MISSING_VERIFIED_USER_VISUAL_REQUEST`.
- Orden #8 / ítem #11 `SOLICITAR_ADELANTO`: también pendiente y depende de HOME.
- Imagen **sí generada en chat**, fuera del run de Supabase; verificada localmente en la conversación, PNG 1086×1448 y SHA-256 `8854a525b61d5642b3e864d5f35dbd9e3fdaf1bab83754ddeaa884eaf90f52d0`. No hay verificación de entrega Native V06, RUN ni QA persistidos. No confundir archivo chat con cierre gobernado.
- Defecto visible: en el resumen, «Mi disponible» aparece con un valor «S/ 800» inventado; debe ser **entrada navegable** que indique «Cómo se calcula», sin inventar monto.

## Nueva solicitud
- Nuevo código: `SALY_HOME_MIDISPONIBLE_REFINEMENT_20261123`.
- Un solo ítem `HOME_MIDISPONIBLE`, estado `BORRADOR/PENDIENTE`, vinculado mediante dependencia a HOME #7.
- `literal_request`: excerpt exacto del mensaje actual del usuario (se conservan errores ortográficos; NO para render).
- `interpretation`: solo reemplazar un supuesto dato monetario por texto de acceso «Cómo se calcula» con chevron. Mantener el resto íntegro. No crear otra pantalla ni afectar #7/#8.
- Contexto: mismo SEALED context de HOME #7 y su identity snapshot; no aprobación de CANDIDATE.
- `intake_semantic_qa.verdict=PENDING`, sin message-id/recibo ficticio; `render_authorized=false`, `review_only=true`, `rendering_authority=false`. No proponer fin por simplemente generar chat PNG.

## Auditoría sobre la skill, sin modificarla
Fuente: `skills/creative_factory/SKILL.md` en main (SHA del archivo: `1a76789dbd644928c4146475b8be658e3e0f1fbe`). Declara:
- Descubrimiento de tokens y cadenas de versión; distinguir `APPROVED`/`CANDIDATE`.
- Color y superficies: cada elemento cumple función (acción, selección, información, categoría), comparar neutral/tono/acento, verificar contraste.
- QA de coherencia token / copy / imagen; no inventar ni elevar candidate al usarlo.
- Logo oficial `logo.primary.transparent` v1, SHA `5573f0503ddb3dd1029221a9ee336d0e28155c392598286628dbf294da146995`.

Readback real Supabase:
| Rol | Token | Valor | Estado |
|---|---|---|---|
| CTA fondo con texto blanco | color.action.primary.bg | #008200 | APPROVED |
| Identidad marca | color.brand.primary | #00C853 | APPROVED |
| Navy texto/cifras | candidate.saly_ds_v1.color.ink.navy.900 | #081631 | CANDIDATE |
| Fondo superficie | candidate.saly_ds_v1.color.surface.white | #FFFFFF | CANDIDATE |
| Saly Plus suave | candidate.saly_ds_v1.color.surface.mint | #EAF9EE | CANDIDATE |
| Rewards | candidate.saly_ds_v1.color.surface.reward | #FFF9E9 | CANDIDATE |
| Beneficios | candidate.saly_home_v3.color.surface.benefits | #F4E7FD | CANDIDATE |

La imagen directa muestra predominantemente acentos verdes en las tres tarjetas, lo que no evidencia diferenciación de tonos. **No hay evidencia de compilación usando el trace de tokens del skill al invocar ImageGen**, así que no atribuir el incumplimiento a una función interna del skill. Próxima prueba reproducible: producir handoff congelado con `trace` de tokens por componente, contrastarlo con mensaje real y comprobar imagen resultante. Esto es observación, no cambio de alcance del nuevo pedido.

## Controles
- PG17 aislado: aplicar fuentes aprobadas de seed/guard PR #4648 y corrección #4660 sobre fixture, aplicar nuevo seed; verificar un nuevo BORRADOR, un ítem pendiente, dependencia a #7, QA y autorización bloqueados, 0 RUN.
- Negativos: segundo ítem rechazado, render sin QA rechazado, ejecución anticipada rechazada.
- PASE → Train → readback, sin SQL directo, sin IDs supuestos, no tocar #7 ni #8.
