# CARD — Aprendizaje competitivo: Campañas y ofertas

Status: CANDIDATO / READ_ONLY
Card ID: CARD-LF-LEARN-CAMPANAS-Y-OFERTAS-V01
Runtime: DISABLED
Automatic impact: BLOCKED

## Origen
Learning: LRN-LF-BA922671-CAMPANAS_Y_OFERTAS
Bridge execution: LF-AUTOLEARN-BRIDGE-CANARY-20260831-006
Taxonomy: LF_LEARNING_CLUSTER_V1

## Hipótesis LF
Una oferta de campaña debe ser trazable por elegibilidad, vigencia, precedencia, aceptación y conciliación antes de considerarse cumplida.

## Reglas candidatas para sandbox
- Persistir criterios de elegibilidad y ventana de vigencia.
- Si existe oferta específica para el usuario, no sustituirla por mensaje genérico de campaña.
- Persistir evidencia de aceptación por el mecanismo permitido.
- Vincular cumplimiento a pago autorizado y conciliación confirmada.

## Guards
No copiar T&C ni timings del competidor. Requiere revisión legal antes de cualquier regla oficial. Producción y aprobación automática bloqueadas.

## Ejemplos de profundidad
1. Oferta elegible y vigente: mostrar monto, vigencia y canal autorizado; conservar receipt de aceptación.
2. Oferta genérica vs específica: prevalece la específica si ambas están activas y verificadas.
3. Pago recibido pero no conciliado: mantener estado pendiente; no cerrar campaña ni deuda.
4. Fuente con claim no verificable: bloquear promoción y conservar solo como evidencia competitiva.

## Resultado esperado
CARD_CANDIDATE_FOR_SANDBOX; sin impacto automático.