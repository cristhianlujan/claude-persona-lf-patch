# CARD — Aprendizaje competitivo: Autogestión digital

Status: CANDIDATO / READ_ONLY
Card ID: CARD-LF-LEARN-AUTOGESTION-DIGITAL-V01
Runtime: DISABLED
Automatic impact: BLOCKED

## Origen
Learning: LRN-LF-BA922671-AUTOGESTION_DIGITAL
Bridge execution: LF-AUTOLEARN-BRIDGE-CANARY-20260831-006
Taxonomy: LF_LEARNING_CLUSTER_V1

## Hipótesis LF
Un flujo de autogestión puede unir consulta, oferta, pago y escalamiento sin perder privacidad ni contexto de deuda.

## Reglas candidatas para sandbox
- Autenticar antes de exponer deuda u oferta personalizada.
- Mostrar contexto de deuda/oferta antes del CTA de pago.
- Combinar self-service con escalamiento explícito para excepciones.
- Persistir consentimiento y privacidad en registro/comunicaciones.

## Guards
No copiar UI/copy del competidor. No exponer información sensible sin autenticación y consentimiento aplicable.

## Ejemplos de profundidad
1. Usuario autenticado con oferta válida: mostrar contexto antes de pago.
2. Sesión no autenticada: no mostrar deuda personalizada.
3. Excepción de pago: derivar a especialista preservando contexto y receipt.
4. Registro sin consentimiento requerido: bloquear comunicaciones posteriores.

## Resultado esperado
CARD_CANDIDATE_FOR_SANDBOX; sin impacto automático.