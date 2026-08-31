# CARD — Aprendizaje competitivo: Campañas y ofertas

Status: CANDIDATO / READ_ONLY
Card ID: CARD-LF-LEARN-CAMPANAS-Y-OFERTAS-V01
Runtime: DISABLED
Automatic impact: BLOCKED

## Origen y trazabilidad
- Learning: `LRN-LF-BA922671-CAMPANAS_Y_OFERTAS`
- Bridge execution: `LF-AUTOLEARN-BRIDGE-CANARY-20260831-006`
- Card Factory execution: `LF-CARD-CANARY3-CAMPANAS-20260831-001`
- KB: `f67ffccd-e710-41f4-ae8c-eb5579227fc7`
- Fuente: `https://www.finanty.com/assets/archivos/Terminos_y_Condiciones_Campanas.pdf`
- KB status: `GROUNDED`, `consumer_ready=true`, `decision_upstream=ALLOW_PROD_GATE`
- Taxonomy: `LF_LEARNING_CLUSTER_V1 / CAMPANAS_Y_OFERTAS`

## Hipótesis LF
Una oferta de campaña LF debe ser trazable por elegibilidad, vigencia, precedencia, aceptación y conciliación. Las condiciones y tiempos del competidor son evidencia competitiva, no reglas LF.

## Reglas candidatas para sandbox
1. Persistir criterios de elegibilidad y ventana de vigencia de la oferta.
2. Cuando exista una oferta específica verificada para el usuario, no sustituirla por un mensaje genérico de campaña.
3. Persistir evidencia de aceptación por el mecanismo permitido para la oferta.
4. Vincular el cumplimiento a un pago por canal autorizado y a conciliación confirmada; pago recibido sin conciliación no cierra la campaña ni la deuda.

Estas reglas son candidatas. No son regla oficial LF hasta superar revisión, sandbox, judges y aprobación gobernada.

## Guards
- `NO_COPY_COMPETITOR_TERMS`: no copiar texto, condiciones, SLA ni timings del competidor.
- `LEGAL_REVIEW_BEFORE_OFFICIAL_RULE`: cualquier condición contractual o claim legal requiere autoridad independiente/revisión legal antes de oficializarse.
- `NO_COMPETITOR_TIMING_AS_LF_SLA`: el dato competitivo de conciliación no se convierte en SLA LF.
- `NO_RUNTIME`: esta Card no habilita runtime.
- `NO_AUTOMATIC_IMPACT`: esta Card no autoriza impacto automático ni producción.

## Matriz evidencia → regla candidata
| Regla candidata | Evidencia competitiva | Límite de uso |
|---|---|---|
| Elegibilidad + vigencia | La fuente expone criterios y vigencia de campañas | Derivar principio; no copiar T&C |
| Precedencia de oferta específica | La fuente diferencia oferta aplicable/específica | Validar con reglas LF antes de oficializar |
| Evidencia de aceptación | La fuente contempla aceptación por mecanismo de campaña | LF debe definir mecanismos permitidos propios |
| Pago autorizado + conciliación | La fuente vincula oferta, pago y conciliación | No copiar timing del competidor como SLA LF |

## Fixture schema candidato
Entrada mínima de prueba:
- `offer_scope`: `SPECIFIC | GENERIC`
- `eligibility_evidence`: evidencia trazable o `MISSING`
- `validity_status`: `ACTIVE | EXPIRED | UNKNOWN`
- `acceptance_evidence`: evidencia trazable o `MISSING`
- `payment_channel_authorized`: `true | false`
- `reconciliation_status`: `CONFIRMED | PENDING | FAILED`
- `legal_review_status`: `NOT_REQUIRED | REQUIRED | APPROVED | BLOCKED`

No es un schema productivo; solo cierra la prueba de esta Card candidata.

## Ejemplos y anti-ejemplos
### E1 — Activación válida
Input: oferta `SPECIFIC`, elegibilidad acreditada, vigencia `ACTIVE`, aceptación trazable, canal autorizado y conciliación `CONFIRMED`.
Expected output: `CARD_CANDIDATE_PASS`.
Judge: `PASS`.

### E2 — No activación por falta de elegibilidad
Input: oferta con `eligibility_evidence=MISSING`.
Expected output: `RETURN_TO_WORKER`.
Judge: `RETURN_TO_WORKER`.

### E3 — Oferta genérica vs. específica
Input: existen oferta genérica y oferta específica verificadas y vigentes.
Expected output: conservar la específica como candidata prevalente; no reemplazarla por mensaje genérico.
Judge: `PASS`.

### E4 — Pago aún no conciliado
Input: pago recibido por canal autorizado, `reconciliation_status=PENDING`.
Expected output: `DO_NOT_CLOSE`.
Judge: `PASS` si mantiene pendiente; `BLOCKED` si intenta cerrar.

### E5 — Claim legal sin autoridad independiente
Input: condición legal derivada solo de fuente del competidor y `legal_review_status=REQUIRED`.
Expected output: `BLOCKED_LEGAL_REVIEW`.
Judge: `BLOCKED`.

### E6 — Anti-ejemplo: copiar timing competitivo
Input: usar directamente un plazo publicado por el competidor como SLA LF.
Expected output: `DO_NOT_COPY_AS_LF_SLA`.
Judge: `BLOCKED` para oficialización; la evidencia puede conservarse como benchmark.

## Evals ejecutables
| Eval | Assert | Expected |
|---|---|---|
| EV-01 | Una oferta específica verificada no es sustituida por mensaje genérico | `true` |
| EV-02 | Pago pendiente de conciliación no produce cierre | `true` |
| EV-03 | Claim legal sin autoridad independiente queda bloqueado | `true` |
| EV-04 | Timing del competidor no se promueve como SLA LF | `true` |
| EV-05 | Falta de elegibilidad retorna a trabajo, no fabrica aprobación | `true` |

## Judge candidato de la Card
`PASS` requiere simultáneamente:
- fuente `GROUNDED` y `consumer_ready`;
- elegibilidad y vigencia trazables;
- aceptación trazable cuando corresponda;
- canal de pago autorizado;
- guard de conciliación;
- guard legal/copyright activo;
- cero impacto automático.

`BLOCKED` si ocurre cualquiera:
- fuente no grounded;
- copia de T&C/timing del competidor como regla LF;
- claim legal no verificado convertido en regla;
- intento de cierre antes de conciliación;
- intento de runtime, producción o impacto automático.

`RETURN_TO_WORKER` si falta evidencia recuperable como elegibilidad o aceptación.

## Output modes cerrados
- `CARD_CANDIDATE_PASS`
- `RETURN_TO_WORKER`
- `BLOCKED_LEGAL_REVIEW`

No existe output `APPROVED`, `PRODUCTION`, `VALIDATED` ni equivalente desde esta Card.

## Blocking overrides
Los siguientes bloqueos prevalecen sobre cualquier score o señal positiva:
- `LEGAL_REVIEW_REQUIRED`
- `SOURCE_NOT_GROUNDED`
- `RECONCILIATION_NOT_CONFIRMED`
- `COMPETITOR_TERMS_COPY_RISK`
- `RUNTIME_OR_AUTOMATIC_IMPACT_REQUESTED`

## Self-repair
Solo se permite volver al worker para completar evidencia faltante o corregir trazabilidad. Self-repair no puede relajar guards, sustituir revisión legal ni fabricar evidencia/aprobación.

## Resultado esperado
`CARD_CANDIDATE_FOR_SANDBOX`; sin impacto automático, sin runtime y sin producción.
