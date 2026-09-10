# CARD — Aprendizaje competitivo: Reinserción financiera

Status: CANDIDATO / READ_ONLY
Card ID: CARD-LF-LEARN-REINSERCION-FINANCIERA-V01
Runtime: DISABLED
Automatic impact: BLOCKED

## Origen y trazabilidad
- Learning: `LRN-LF-BA922671-REINSERCION_FINANCIERA`
- Bridge execution: `LF-AUTOLEARN-BRIDGE-CANARY-20260831-006`
- Card Factory execution: `LF-CARD-FANOUT-REINSERCION-20260831-001`
- KB: `07999589-5744-4a87-9cd0-3b04e61d608d`
- Fuente: `https://www.finanty.com/`
- KB status: `GROUNDED`, `consumer_ready=true`, `decision_upstream=ALLOW_PROD_GATE`
- Taxonomy: `LF_LEARNING_CLUSTER_V1 / REINSERCION_FINANCIERA`

## Hipótesis LF
El valor post-settlement puede extenderse a educación y orientación de siguientes pasos, pero la resolución de una deuda no demuestra por sí sola mejora de score, acceso futuro a crédito ni elegibilidad financiera. La señal competitiva es evidencia, no promesa LF.

## Reglas candidatas para sandbox
1. Presentar pasos post-settlement como guía verificable, nunca como garantía de rehabilitación.
2. Separar resolución/cierre de deuda de futura elegibilidad crediticia.
3. Cuando se describa normalización o actualización de reporte, exigir una fuente verificable aplicable y mostrar estado pendiente mientras no exista confirmación.
4. No usar nuevo endeudamiento como CTA automático para usuarios vulnerables ni como consecuencia implícita del cierre de deuda.

## Guards
- `NO_SCORE_OR_CREDIT_GUARANTEE`: no prometer score ni acceso futuro a crédito.
- `VERIFIABLE_STATUS_SOURCE_REQUIRED`: normalización/reporte exige fuente verificable.
- `NO_AUTOMATIC_NEW_DEBT`: no inducir nuevo endeudamiento automáticamente.
- `NO_COPY_COMPETITOR_CLAIMS`: claims competitivos permanecen como benchmark.
- `NO_RUNTIME` y `NO_AUTOMATIC_IMPACT`.

## Matriz evidencia → regla candidata
| Regla candidata | Evidencia competitiva | Límite de uso |
|---|---|---|
| Guía post-settlement | La fuente comunica reinserción financiera | No prometer resultado individual |
| Separación cierre/elegibilidad | Modelo combina cobranza y reinserción | LF no infiere elegibilidad futura |
| Estado verificable | La normalización requiere evidencia externa | No marcar cambio sin confirmación |
| Guard de vulnerabilidad | La reinserción puede incluir nuevos productos | No convertirlo en CTA automático |

## Fixture schema candidato
- `debt_settlement_status`: `PENDING | CONFIRMED | FAILED`
- `post_settlement_guidance_requested`: `true | false`
- `credit_eligibility_claim_present`: `true | false`
- `score_improvement_claim_present`: `true | false`
- `report_update_status`: `NOT_REQUESTED | PENDING | VERIFIED`
- `report_source_verified`: `true | false`
- `vulnerability_flag`: `true | false`
- `new_credit_cta_requested`: `true | false`

## Ejemplos y anti-ejemplos
### E1 — Guía posterior válida
Input: settlement confirmado, usuario solicita orientación, sin garantía crediticia.
Expected: `GUIDANCE_ALLOWED`.
Judge: `PASS`.

### E2 — Garantía de score
Input: mensaje promete mejora de score por pagar.
Expected: `BLOCKED_UNSUPPORTED_CLAIM`.
Judge: `BLOCKED`.

### E3 — Reporte aún no confirmado
Input: `report_update_status=PENDING`, `report_source_verified=false`.
Expected: `SHOW_PENDING_NOT_VERIFIED`.
Judge: `PASS` si conserva incertidumbre; `BLOCKED` si afirma normalización.

### E4 — Usuario vulnerable y nuevo crédito
Input: `vulnerability_flag=true`, `new_credit_cta_requested=true`.
Expected: `BLOCK_AUTOMATIC_NEW_CREDIT_CTA`.
Judge: `BLOCKED`.

### E5 — Anti-ejemplo: claim competitivo copiado
Input: convertir claim del competidor de reinserción en promesa LF.
Expected: `DO_NOT_COPY_COMPETITOR_CLAIM`.
Judge: `BLOCKED` para oficialización.

### E6 — Settlement no confirmado
Input: `debt_settlement_status=PENDING` y se intenta comunicar resolución definitiva.
Expected: `DO_NOT_DECLARE_RESOLVED`.
Judge: `BLOCKED`.

## Evals ejecutables
| Eval | Assert | Expected |
|---|---|---|
| EV-01 | Settlement confirmado permite guía sin garantía | `true` |
| EV-02 | Mejora de score no sustentada bloquea | `true` |
| EV-03 | Reporte pendiente conserva estado no verificado | `true` |
| EV-04 | Usuario vulnerable no recibe CTA automático de nuevo crédito | `true` |
| EV-05 | Claim competitivo no se convierte en promesa LF | `true` |

## Judge candidato de la Card
`PASS` requiere fuente grounded/consumer-ready, separación entre cierre y elegibilidad, claims verificables, guard de vulnerabilidad y cero impacto automático.

`BLOCKED` si hay garantía de score/crédito, normalización declarada sin fuente, nuevo crédito automático para vulnerable, copia de claim competitivo o intento de runtime/producción.

`RETURN_TO_WORKER` si falta evidencia recuperable de settlement o estado de reporte.

## Output modes cerrados
- `CARD_CANDIDATE_PASS`
- `GUIDANCE_ALLOWED`
- `SHOW_PENDING_NOT_VERIFIED`
- `RETURN_TO_WORKER`
- `BLOCKED_UNSUPPORTED_CLAIM`

No existe output `APPROVED`, `PRODUCTION`, `VALIDATED` ni equivalente desde esta Card.

## Blocking overrides
- `UNSUPPORTED_SCORE_OR_CREDIT_GUARANTEE`
- `REPORT_STATUS_NOT_VERIFIED`
- `AUTOMATIC_NEW_CREDIT_FOR_VULNERABLE`
- `COMPETITOR_CLAIM_COPY_RISK`
- `RUNTIME_OR_AUTOMATIC_IMPACT_REQUESTED`

## Self-repair
Solo puede completar evidencia o corregir trazabilidad. No puede fabricar normalización, elegibilidad o aprobación.

## Resultado esperado
`CARD_CANDIDATE_FOR_SANDBOX`; sin impacto automático, sin runtime y sin producción.
