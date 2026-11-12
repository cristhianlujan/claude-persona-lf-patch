# Lote 16 — Tres referencias VIGENTE → CANDIDATO

**OBJETIVO (origen/campo/destino/estado):** SELECT S03, SHA-256 JSONB `8b70da4a3d3b381620473202de4a569d4b09fcfda6b3973e81661c3d2631b46a` (SQL íntegro en `07_evidencia_select.sql`). **Riesgos/opciones:** REQUIERE_REVISION_SEMANTICA. No se cambió ninguna regla.

## B2B-RULE-AUTH-016 → B2B-RULE-AUTH-012

- **Origen VIGENTE** (`duplicate_submit_rule_id` → id 431): **Timeout y reintento controlado de autenticación**. Texto íntegro: «La autenticación debe consumir una política de timeout centralizada y reutilizable desde lf_ops.politicas_timeout. La regla de Login no almacena segundos, cantidades de reintentos ni backoff. Ante una política que resulte en timeout o indisponibilidad, se mantiene fail-closed y la respuesta funcional se normaliza como SERVICE_UNAVAILABLE.»
- **Destino CANDIDATO**: **Un solo intento de autenticación en vuelo**. Texto íntegro: «El Login aplica un patrón single-flight: mientras exista una solicitud de autenticación pendiente, se ignoran envíos duplicados y el CTA permanece en estado procesando. La regla expresa comportamiento, no un umbral numérico configurable.»
- **Opción A — promover destino.** Riesgo: Solo tras prueba de doble submit, single-flight y reintentos. Riesgo de solicitudes duplicadas/estados huérfanos si se promueve sin QA.
- **Opción B — quitar referencia.** Riesgo: Puede eliminar trazabilidad al control de duplicados y dejar eventos concurrentes sin contrato; exigir sustituto verificado.
- **Opción C — dejar referencia.** Riesgo: Preserva enlace pero puede fingir cobertura operativa con destino no aprobado; tratarlo como dependency gap y mantener fail-closed.
- **SUGERENCIA:** C (dejar dependencia identificada) hasta demostrar prerequisitos y autoridad; sin habilitar producción ni declarar control operando. Si se opta A/B, ejecutar cambio gobernado con pruebas e impacto.

## B2B-RULE-AUTH-022 → B2B-RULE-AUTH-018

- **Origen VIGENTE** (`mfa_gate_rule_id` → id 437): **Creación de sesión únicamente tras autenticación completa**. Texto íntegro: «LF_AUTH_BOUNDARY solo puede crear o confirmar una sesión autenticada cuando el resultado funcional sea AUTHENTICATED. Si el usuario requiere MFA, la sesión completa se mantiene bloqueada hasta que AUTH-018 se complete satisfactoriamente. La creación y rotación de sesión se ejecutan del lado servidor y consumen las políticas centrales de sesión y prevención de session fixation; el cliente no decide TTL, concurrencia, rotación ni elevación de privilegios.»
- **Destino CANDIDATO**: **MFA obligatorio antes de sesión autenticada**. Texto íntegro: «Cuando las credenciales primarias son válidas y la política MFA aplica al profile_id del usuario, LF_AUTH_BOUNDARY debe responder MFA_REQUIRED y detener la autenticación antes de crear una sesión plenamente autenticada. La política central exige MFA a los seis perfiles humanos actuales del Backoffice. Hasta completar satisfactoriamente MFA no se conceden permisos funcionales, no se considera AUTHENTICATED y el cliente no puede promover por sí mismo el estado de autenticación.»
- **Opción A — promover destino.** Riesgo: Requiere validar MFA_REQUIRED, desafío, perfiles y sesión servidor. Promoción sin pruebas puede permitir AUTHENTICATED prematuro.
- **Opción B — quitar referencia.** Riesgo: ALTO: riesgo de bypass del MFA si no hay gate equivalente. No recomendado sin decisión de Seguridad y prueba de regresión.
- **Opción C — dejar referencia.** Riesgo: Dependencia candidata impide asumir que MFA está implementado; mantener denegación de permisos antes de MFA satisfactorio.
- **SUGERENCIA:** C (dejar dependencia identificada) hasta demostrar prerequisitos y autoridad; sin habilitar producción ni declarar control operando. Si se opta A/B, ejecutar cambio gobernado con pruebas e impacto.

## B2B-RULE-THEME-003 → B2B-RULE-THEME-002

- **Origen VIGENTE** (`dark_promotion_gate_rule_id` → id 390): **Resolución de tema System sin flash ni valores visuales duplicados**. Texto íntegro: «El Backoffice B2B resuelve el tema efectivo antes de mostrar la interfaz. Una preferencia explícita persistida del usuario prevalece; si no existe, se respeta la preferencia de color del sistema; si ninguna señal puede resolverse, se usa LIGHT como fallback. El resultado efectivo siempre referencia los theme bindings canónicos LIGHT o DARK y no duplica colores ni medidas. DARK conserva su gate de QA antes de promoción.»
- **Destino CANDIDATO**: **Gate de modo noche**. Texto íntegro: «El tema nocturno no puede pasar a vigente hasta aprobar contraste y tokens dark_mode.»
- **Opción A — promover destino.** Riesgo: Exige contraste, tokens y QA del modo DARK; sin eso se abre un tema visual no validado.
- **Opción B — quitar referencia.** Riesgo: Puede borrar el gate para promoción de DARK y habilitar tema nocturno incorrecto.
- **Opción C — dejar referencia.** Riesgo: Conserva trazabilidad de la deuda, pero el runtime no debe seleccionar DARK por preferencia del sistema antes de gate aprobado.
- **SUGERENCIA:** C (dejar dependencia identificada) hasta demostrar prerequisitos y autoridad; sin habilitar producción ni declarar control operando. Si se opta A/B, ejecutar cambio gobernado con pruebas e impacto.

