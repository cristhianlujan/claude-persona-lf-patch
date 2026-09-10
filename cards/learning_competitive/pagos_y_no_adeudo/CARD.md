# CARD — Aprendizaje competitivo: Pagos y no adeudo

Status: CANDIDATO / READ_ONLY
Card ID: CARD-LF-LEARN-PAGOS-Y-NO-ADEUDO-V01
Runtime: DISABLED
Automatic impact: BLOCKED

## Origen y trazabilidad
- Learning: `LRN-LF-BA922671-PAGOS_Y_NO_ADEUDO`
- Bridge execution: `LF-AUTOLEARN-BRIDGE-CANARY-20260831-006`
- Card Factory execution: `LF-CARD-FANOUT-PAGOS-20260831-001`
- KB: `bd2a3a05-b53b-400c-846d-3634e422a500`
- Fuente: `https://www.finanty.com/preguntas-frecuentes`
- KB status: `GROUNDED`, `consumer_ready=true`, `decision_upstream=ALLOW_PROD_GATE`
- Taxonomy: `LF_LEARNING_CLUSTER_V1 / PAGOS_Y_NO_ADEUDO`

## Hipótesis LF
Pago, conciliación y constancia de no adeudo deben formar una cadena auditable: una recepción de pago no equivale por sí sola a conciliación ni autoriza constancia. Los canales y SLA del competidor son evidencia, no reglas LF.

## Reglas candidatas para sandbox
1. Validar que exista negociación/oferta activa y trazable antes de habilitar pago.
2. Permitir únicamente canales registrados/autorizados y bloquear instrucciones hacia cuentas no verificadas.
3. Separar `PAYMENT_RECEIVED` de `RECONCILIATION_CONFIRMED`; no cerrar deuda mientras la conciliación esté pendiente o fallida.
4. Emitir constancia de no adeudo solo después de settlement/conciliación confirmada y evidencia de cierre aplicable.

## Guards
- `AUTHORIZED_CHANNEL_ONLY`: cuentas/canales no registrados bloquean el flujo.
- `NO_CLOSE_BEFORE_RECONCILIATION`: pago recibido no implica deuda liquidada.
- `NO_COMPETITOR_SLA_AS_LF_RULE`: tiempos del competidor no se convierten en SLA LF.
- `NO_RUNTIME` y `NO_AUTOMATIC_IMPACT`.

## Matriz evidencia → regla candidata
| Regla candidata | Evidencia competitiva | Límite de uso |
|---|---|---|
| Validación previa | FAQ conecta negociación y pago | LF define validaciones propias |
| Canal autorizado | FAQ advierte canales válidos/antifraude | No copiar instrucciones operativas del competidor |
| Conciliación separada | Pago y constancia aparecen como etapas diferenciadas | LF define estados y responsables propios |
| Constancia post-settlement | La fuente contempla no adeudo descargable | No emitir sin evidencia LF de cierre |

## Fixture schema candidato
- `negotiation_active`: `true | false`
- `payment_channel_authorized`: `true | false`
- `payment_status`: `NOT_RECEIVED | RECEIVED | FAILED`
- `reconciliation_status`: `PENDING | CONFIRMED | FAILED`
- `settlement_evidence`: evidencia trazable o `MISSING`
- `certificate_requested`: `true | false`
- `certificate_issued`: `true | false`

## Ejemplos y anti-ejemplos
### E1 — Pago confirmado y conciliado
Input: negociación activa, canal autorizado, pago recibido, conciliación confirmada.
Expected: `READY_FOR_POST_SETTLEMENT_REVIEW`.
Judge: `PASS`.

### E2 — Cuenta no autorizada
Input: instrucción de transferencia a canal no registrado.
Expected: `BLOCK_UNAUTHORIZED_CHANNEL`.
Judge: `BLOCKED`.

### E3 — Pago recibido aún pendiente
Input: `payment_status=RECEIVED`, `reconciliation_status=PENDING`.
Expected: `DO_NOT_CLOSE`.
Judge: `PASS` si conserva pendiente; `BLOCKED` si cierra.

### E4 — Constancia sin settlement
Input: `certificate_requested=true`, `settlement_evidence=MISSING`.
Expected: `DO_NOT_ISSUE_CERTIFICATE`.
Judge: `BLOCKED`.

### E5 — Anti-ejemplo: SLA competitivo
Input: copiar tiempo de conciliación del competidor como SLA LF.
Expected: `DO_NOT_COPY_AS_LF_SLA`.
Judge: `BLOCKED` para oficialización.

### E6 — Negociación inexistente
Input: `negotiation_active=false` y pago solicitado.
Expected: `RETURN_TO_WORKER`.
Judge: `RETURN_TO_WORKER`.

## Evals ejecutables
| Eval | Assert | Expected |
|---|---|---|
| EV-01 | Canal no autorizado bloquea pago | `true` |
| EV-02 | Pago pendiente de conciliación no cierra deuda | `true` |
| EV-03 | Constancia exige settlement trazable | `true` |
| EV-04 | SLA competitivo no se convierte en regla LF | `true` |
| EV-05 | Pago exige negociación/oferta activa | `true` |

## Judge candidato de la Card
`PASS` requiere fuente grounded/consumer-ready, negociación activa, canal autorizado, estados separados y constancia condicionada a settlement.

`BLOCKED` si existe canal no autorizado, cierre antes de conciliación, emisión sin settlement, copia de SLA competitivo o intento de runtime/producción.

`RETURN_TO_WORKER` si falta evidencia recuperable de negociación o settlement.

## Output modes cerrados
- `CARD_CANDIDATE_PASS`
- `READY_FOR_POST_SETTLEMENT_REVIEW`
- `RETURN_TO_WORKER`
- `BLOCK_UNAUTHORIZED_CHANNEL`
- `DO_NOT_ISSUE_CERTIFICATE`

No existe output `APPROVED`, `PRODUCTION`, `VALIDATED` ni equivalente desde esta Card.

## Blocking overrides
- `UNAUTHORIZED_PAYMENT_CHANNEL`
- `RECONCILIATION_NOT_CONFIRMED`
- `SETTLEMENT_EVIDENCE_MISSING`
- `COMPETITOR_SLA_COPY_RISK`
- `RUNTIME_OR_AUTOMATIC_IMPACT_REQUESTED`

## Self-repair
Solo puede completar evidencia faltante o corregir trazabilidad. No puede marcar conciliado ni emitir constancia sin evidencia.

## Resultado esperado
`CARD_CANDIDATE_FOR_SANDBOX`; sin impacto automático, sin runtime y sin producción.
