# CARD — Aprendizaje competitivo: Autogestión digital

Status: CANDIDATO / READ_ONLY
Card ID: CARD-LF-LEARN-AUTOGESTION-DIGITAL-V01
Runtime: DISABLED
Automatic impact: BLOCKED

## Origen y trazabilidad
- Learning: `LRN-LF-BA922671-AUTOGESTION_DIGITAL`
- Bridge execution: `LF-AUTOLEARN-BRIDGE-CANARY-20260831-006`
- Card Factory execution: `LF-CARD-FANOUT-AUTOGESTION-20260831-001`
- KB: `35cfab0c-1d91-4aa4-9761-f8af91181e17`
- Fuente: `https://mi.finanty.com/registro`
- KB status: `GROUNDED`, `consumer_ready=true`, `decision_upstream=ALLOW_PROD_GATE`
- Taxonomy: `LF_LEARNING_CLUSTER_V1 / AUTOGESTION_DIGITAL`

## Hipótesis LF
La autogestión LF puede reducir fricción si une autenticación, contexto de deuda/oferta, pago y escalamiento conservando privacidad y trazabilidad. La experiencia del competidor es evidencia competitiva, no diseño ni regla oficial LF.

## Reglas candidatas para sandbox
1. Exigir autenticación antes de mostrar deuda u oferta personalizada.
2. Mostrar el contexto verificable de deuda/oferta antes de cualquier CTA de pago.
3. Mantener una ruta explícita de escalamiento para excepciones sin perder el contexto de la sesión.
4. Persistir evidencia de consentimiento cuando corresponda a registro o comunicaciones.

Estas reglas son candidatas y no se oficializan sin revisión, sandbox, judges y aprobación gobernada.

## Guards
- `NO_PERSONAL_DATA_PRE_AUTH`: no exponer deuda/oferta personalizada antes de autenticar.
- `NO_COPY_COMPETITOR_UX_COPY`: no copiar copy, secuencia ni UI del competidor.
- `CONSENT_TRACE_REQUIRED`: cuando aplique consentimiento, debe existir evidencia trazable.
- `NO_RUNTIME`: esta Card no habilita runtime.
- `NO_AUTOMATIC_IMPACT`: esta Card no autoriza impacto automático ni producción.

## Matriz evidencia → regla candidata
| Regla candidata | Evidencia competitiva | Límite de uso |
|---|---|---|
| Autenticación previa | La fuente usa onboarding hacia autogestión | Derivar principio de privacidad; no copiar flujo |
| Contexto antes de pago | La propuesta conecta gestión de deuda y pagos | Validar contra producto LF antes de oficializar |
| Escalamiento | La fuente menciona asesores especializados | LF define sus propios triggers y canales |
| Consentimiento | Registro digital implica tratamiento de datos | Requiere política LF aplicable y evidencia propia |

## Fixture schema candidato
- `authenticated`: `true | false`
- `personalized_debt_present`: `true | false`
- `offer_context_verified`: `true | false`
- `payment_cta_requested`: `true | false`
- `exception_detected`: `true | false`
- `escalation_context_preserved`: `true | false`
- `consent_required`: `true | false`
- `consent_evidence`: evidencia trazable o `MISSING`

No es schema productivo; solo soporta la prueba sandbox de esta Card.

## Ejemplos y anti-ejemplos
### E1 — Activación válida
Input: usuario autenticado, contexto verificable y CTA de pago solicitado.
Expected: `CARD_CANDIDATE_PASS`.
Judge: `PASS`.

### E2 — No activación por sesión anónima
Input: `authenticated=false` y deuda personalizada disponible.
Expected: `BLOCK_PERSONAL_DATA`.
Judge: `BLOCKED`.

### E3 — Excepción con escalamiento limpio
Input: usuario autenticado, excepción detectada, contexto preservado.
Expected: `ESCALATE_WITH_CONTEXT`.
Judge: `PASS`.

### E4 — Consentimiento faltante
Input: `consent_required=true`, `consent_evidence=MISSING`.
Expected: `RETURN_TO_WORKER`.
Judge: `RETURN_TO_WORKER`.

### E5 — Anti-ejemplo: copiar onboarding competitivo
Input: replicar secuencia/copy de registro del competidor como diseño LF.
Expected: `DO_NOT_COPY_COMPETITOR_FLOW`.
Judge: `BLOCKED` para oficialización.

### E6 — CTA de pago sin contexto
Input: `payment_cta_requested=true`, `offer_context_verified=false`.
Expected: `DO_NOT_ENABLE_PAYMENT_CTA`.
Judge: `BLOCKED`.

## Evals ejecutables
| Eval | Assert | Expected |
|---|---|---|
| EV-01 | Sesión anónima no expone deuda personalizada | `true` |
| EV-02 | CTA de pago exige contexto verificable | `true` |
| EV-03 | Excepción conserva contexto al escalar | `true` |
| EV-04 | Consentimiento requerido sin evidencia no avanza | `true` |
| EV-05 | Flujo competitivo no se copia como diseño LF | `true` |

## Judge candidato de la Card
`PASS` requiere: fuente grounded/consumer-ready, autenticación antes de datos personalizados, contexto verificable antes de pago, guard de privacidad activo y cero impacto automático.

`BLOCKED` si: se exponen datos antes de autenticación, se habilita pago sin contexto, se copia el flujo competitivo, o se intenta runtime/producción/impacto automático.

`RETURN_TO_WORKER` si falta evidencia recuperable de consentimiento o contexto.

## Output modes cerrados
- `CARD_CANDIDATE_PASS`
- `RETURN_TO_WORKER`
- `BLOCK_PERSONAL_DATA`
- `ESCALATE_WITH_CONTEXT`

No existe output `APPROVED`, `PRODUCTION`, `VALIDATED` ni equivalente desde esta Card.

## Blocking overrides
- `PERSONAL_DATA_PRE_AUTH`
- `PAYMENT_WITHOUT_CONTEXT`
- `CONSENT_REQUIRED_MISSING`
- `COMPETITOR_FLOW_COPY_RISK`
- `RUNTIME_OR_AUTOMATIC_IMPACT_REQUESTED`

## Self-repair
Solo puede completar evidencia o trazabilidad. No puede relajar privacidad, consentimiento, guards ni fabricar aprobación.

## Resultado esperado
`CARD_CANDIDATE_FOR_SANDBOX`; sin impacto automático, sin runtime y sin producción.
