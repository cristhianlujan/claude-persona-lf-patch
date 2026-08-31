# CARD — Aprendizaje competitivo: Negociación de deuda

Status: CANDIDATO / READ_ONLY
Card ID: CARD-LF-LEARN-NEGOCIACION-DEUDA-V01
Runtime: DISABLED
Automatic impact: BLOCKED

## Origen
Learning: LRN-LF-BA922671-NEGOCIACION_DEUDA
Bridge execution: LF-AUTOLEARN-BRIDGE-CANARY-20260831-006
Taxonomy: LF_LEARNING_CLUSTER_V1

## Hipótesis LF
La negociación debe transparentar acreedor, monto, vigencia, canal y efecto esperado sin prometer rehabilitación o resultados no demostrados.

## Reglas candidatas para sandbox
- Mostrar acreedor/origen, monto negociado, vigencia y canal autorizado antes del pago.
- Separar monto de deuda de cualquier fee LF.
- Explicar efecto post-pago con limitaciones explícitas.
- Claims de prescripción, embargo, aval o cobranza requieren autoridad legal independiente.

## Guards
No copiar lenguaje ni fees del competidor. No prometer score, acceso futuro a crédito ni resultados legales.

## Ejemplos de profundidad
1. Negociación completa: acreedor, monto, vigencia y canal verificables permiten avanzar a sandbox.
2. Fee ambiguo: bloquear hasta separar deuda y servicio.
3. Claim legal desde FAQ competidora: conservar evidencia, exigir revisión independiente.
4. Mensaje de restauración garantizada: rechazar por claim no sustentado.

## Resultado esperado
CARD_CANDIDATE_FOR_SANDBOX; sin impacto automático.