# IG M10.7 / Lote C — lectura condicionada del grafo

**Objetivo:** evitar reconstruir el grafo canónico en el guard semántico de una familia cuando ese guard no utiliza sus reglas, sin alterar el guard de manifiesto ni los chequeos de origen y vigencia.

## Evidencia previa
- EKB 007: 21 triggers y coste repetido por familia; no extrapolar una pantalla a todas.
- EKB 008: fixture con transacción reversible, 6 triggers de familia y 2 de propuesta.
- EKB 034: una sola evaluación de cada aserción en el guard final, con negativos de resultado y SHA rechazados.
- Lectura de código actual: fn_guard_input_validator_semantic_coherence_v512 construye el grafo incondicionalmente; el objeto v_rules se utiliza solo para las reglas especiales ACCESSIBILITY y MFA_OTP_SSO.
- Pantalla 43, run histórico 933: 47 familias; dos familias especiales, pero ninguna de las otras 45 necesita ese objeto dentro de este guard. El guard final sí verifica todas sus fuentes.

## Contrato de cambio
Mover únicamente la construcción de v_graph y v_rules dentro de una rama por family_code ACCESSIBILITY o MFA_OTP_SSO. Conserva por completo el resto del cuerpo, incluso las verificaciones de otras familias (REDUCED_MOTION, FORCED_COLORS_CONTRAST, THEME_LIGHT_DARK_SYSTEM, SESSION), la rehidratación y la validación final. No cachear nada entre familias, transacciones o triggers.

## Criterio de prueba antes de cierre
Con fuente vigente y fixture reversible, comprobar al menos una familia normal, ACCESSIBILITY y MFA_OTP_SSO, una propuesta, negativos de source SHA/resultado/assertion SHA, y 6+2 triggers activos; registrar solo EKB y revertir filas de prueba. Verificar equivalencia semántica, presencia de las dos reglas especiales y de la comprobación de manifiesto completo. El test no demuestra p90 del Validator ni autoriza CP3.
