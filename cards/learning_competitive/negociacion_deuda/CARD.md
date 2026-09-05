# CARD — Aprendizaje competitivo: Negociación de deuda

Status: CANDIDATO / READ_ONLY
Card ID: CARD-LF-LEARN-NEGOCIACION-DEUDA-V01
Runtime: DISABLED
Automatic impact: BLOCKED

## Origen y trazabilidad
- Learning: `LRN-LF-BA922671-NEGOCIACION_DEUDA`
- Bridge execution: `LF-AUTOLEARN-BRIDGE-CANARY-20260831-006`
- Card Factory execution: `LF-CARD-FANOUT-NEGOCIACION-20260831-001`
- KB: `8b744f07-75f6-4332-9df5-12e7c6914bf1`
- Fuente: `https://cdn.reevalua.com/terms-25-jun-2025.pdf`
- KB status: `GROUNDED`, `consumer_ready=true`, `decision_upstream=ALLOW_PROD_GATE`
- Evidencia: documento histórico fechado; `pdf_pages=11`
- Taxonomy: `LF_LEARNING_CLUSTER_V1 / NEGOCIACION_DEUDA`

## Hipótesis LF
Una negociación LF debe hacer trazables acreedor/origen, monto negociado, vigencia, canal autorizado y límites del resultado esperado, separando deuda de cualquier fee. La estructura comercial del competidor es evidencia histórica, no autoridad contractual ni legal para LF.

## Reglas candidatas para sandbox
1. Mostrar acreedor/origen, monto negociado, vigencia y canal autorizado antes de habilitar pago.
2. Separar explícitamente monto de deuda y cualquier fee/servicio LF.
3. Explicar el efecto post-pago con limitaciones; no prometer score, acceso futuro a crédito ni resultado legal.
4. Claims de prescripción, embargo, aval o cobranza requieren autoridad legal independiente antes de convertirse en regla o mensaje oficial.

Estas reglas son candidatas y no se oficializan sin revisión, sandbox, judges y aprobación gobernada.

## Guards
- `NO_COPY_COMPETITOR_TERMS_OR_FEES`: no copiar T&C, fee ni condiciones del competidor.
- `LEGAL_AUTHORITY_REQUIRED`: claim legal requiere fuente/autoridad independiente aplicable a LF.
- `NO_REHABILITATION_GUARANTEE`: no prometer rehabilitación, score ni crédito futuro.
- `HISTORICAL_SOURCE_DATE_GUARD`: la evidencia fechada no se trata como condición vigente actual.
- `NO_RUNTIME` y `NO_AUTOMATIC_IMPACT`.

## Matriz evidencia → regla candidata
| Regla candidata | Evidencia competitiva | Límite de uso |
|---|---|---|
| Transparencia de negociación | La fuente describe asesoría/negociación | Derivar principio, no copiar contrato |
| Separación deuda/fee | La fuente histórica explicita cobros | LF define pricing propio y gobernado |
| Límites del resultado | La fuente limita su rol y no promete resultados | No extrapolar resultado legal/crediticio |
| Claim legal independiente | T&C contienen lenguaje contractual | Revisión legal LF obligatoria antes de oficializar |

## Fixture schema candidato
- `creditor_verified`: `true | false`
- `negotiated_amount`: número o `MISSING`
- `fee_amount`: número, `0`, o `MISSING`
- `validity_status`: `ACTIVE | EXPIRED | UNKNOWN`
- `authorized_channel`: `true | false`
- `legal_claim_present`: `true | false`
- `legal_authority_status`: `NOT_REQUIRED | VERIFIED | MISSING`
- `rehabilitation_guarantee_present`: `true | false`

## Ejemplos y anti-ejemplos
### E1 — Negociación completa
Input: acreedor verificado, monto, fee separado, vigencia activa y canal autorizado.
Expected: `CARD_CANDIDATE_PASS`.
Judge: `PASS`.

### E2 — Fee ambiguo
Input: deuda y servicio mezclados sin separación trazable.
Expected: `RETURN_TO_WORKER`.
Judge: `RETURN_TO_WORKER`.

### E3 — Claim legal sin autoridad
Input: claim de prescripción derivado solo del competidor, `legal_authority_status=MISSING`.
Expected: `BLOCKED_LEGAL_REVIEW`.
Judge: `BLOCKED`.

### E4 — Garantía de restauración crediticia
Input: mensaje garantiza mejora de score o crédito futuro.
Expected: `BLOCKED_UNSUPPORTED_CLAIM`.
Judge: `BLOCKED`.

### E5 — Fuente histórica usada como precio actual
Input: fee 2025 del competidor convertido en pricing LF vigente.
Expected: `DO_NOT_PROMOTE_HISTORICAL_TERM`.
Judge: `BLOCKED`.

### E6 — Canal no autorizado
Input: negociación válida, `authorized_channel=false`.
Expected: `DO_NOT_ENABLE_PAYMENT`.
Judge: `BLOCKED`.

## Evals ejecutables
| Eval | Assert | Expected |
|---|---|---|
| EV-01 | Deuda y fee quedan separados antes de pago | `true` |
| EV-02 | Claim legal sin autoridad independiente bloquea | `true` |
| EV-03 | No se promete score/crédito futuro | `true` |
| EV-04 | Fuente histórica no se promueve como condición LF vigente | `true` |
| EV-05 | Canal no autorizado no habilita pago | `true` |

## Judge candidato de la Card
`PASS` requiere fuente grounded/consumer-ready, acreedor/monto/vigencia/canal trazables, separación deuda/fee, claims compatibles con guards y cero impacto automático.

`BLOCKED` si hay claim legal no verificado, garantía de rehabilitación, copia de términos/fees, uso de condición histórica como vigente o intento de runtime/producción.

`RETURN_TO_WORKER` si falta evidencia recuperable de monto, fee, vigencia o acreedor.

## Output modes cerrados
- `CARD_CANDIDATE_PASS`
- `RETURN_TO_WORKER`
- `BLOCKED_LEGAL_REVIEW`
- `BLOCKED_UNSUPPORTED_CLAIM`

No existe output `APPROVED`, `PRODUCTION`, `VALIDATED` ni equivalente desde esta Card.

## Blocking overrides
- `LEGAL_AUTHORITY_MISSING`
- `UNSUPPORTED_REHABILITATION_CLAIM`
- `DEBT_FEE_AMBIGUITY`
- `HISTORICAL_TERM_PROMOTION`
- `RUNTIME_OR_AUTOMATIC_IMPACT_REQUESTED`

## Self-repair
Solo puede completar evidencia/trazabilidad o corregir separación de conceptos. No puede fabricar autoridad legal ni aprobación.

## Resultado esperado
`CARD_CANDIDATE_FOR_SANDBOX`; sin impacto automático, sin runtime y sin producción.
