# Golden Remediation Examples v0.1

Estos ejemplos enseñan propiedades. Los nombres reales se acompañan por gemelos sintéticos para impedir hardcoding.

---

## G01 — Falso negativo del resolver: FIELDS en REC_001

### Input observado

Assessment actual:

```text
FIELDS — BLOCKED / bootstrap MISSING
```

Readback canónico:

- `REG_CLIENT_RECOVERY_PHONE_CONTROL_001` está `VIGENTE`.
- La regla tiene `target_screen_mapping=REC_001`.
- La regla declara explícitamente `old_phone_otp_field_code=CAMPO_OTP_CODE`.
- `CAMPO_OTP_CODE` existe y está `ACTIVO`.
- Es requerido y sensible.
- `masking_rule=MASK_FULL`.
- `retention_class=TRANSIENT`.
- `analytics_allowed=false` y `logs_allowed=false`.

### Salida esperada antes de modificar el resolver

```yaml
evaluation_outcome: NEGATIVE_CONFIRMED
cause_type: RESOLVER_MISSED_EXPLICIT_REFERENCE
evidence_examined:
  - source_ref: REG_CLIENT_RECOVERY_PHONE_CONTROL_001
    authority_status: VIGENTE
    observed_fact: target_screen_mapping=REC_001 y old_phone_otp_field_code=CAMPO_OTP_CODE
  - source_ref: CAMPO_OTP_CODE
    authority_status: ACTIVO
    observed_fact: campo canónico existente, requerido y sensible
evidence_found:
  - REC_001 posee una referencia explícita resoluble hacia un campo canónico activo
exact_gap: el resolver FIELDS no expande old_phone_otp_field_code desde una regla VIGENTE aplicable a REC_001
remediation_action:
  - extender el resolver FIELDS para seguir referencias explícitas de campo desde reglas VIGENTES con scope verificable
  - reevaluar requisitos de FIELDS después de resolver CAMPO_OTP_CODE
  - ejecutar negative test con referencia inexistente y con regla CANDIDATO
do_not_do:
  - no crear un nuevo campo OTP
  - no pedir Human Decision mientras esta referencia no haya sido evaluada
  - no marcar POSITIVE solo por encontrar el literal CAMPO_OTP_CODE
close_when:
  - la referencia se resuelve semánticamente y el resolver demuestra que no queda otra dimensión obligatoria de FIELDS sin resolver
next_owner: INTERNAL_RESOLVER
human_decision_required: false
```

### Por qué es golden

No convierte prematuramente FIELDS a POSITIVE. Primero identifica que el fallo está en la trayectoria del resolver y exige comprobar suficiencia completa.

---

## G02 — Falso negativo encadenado: VALIDATIONS en REC_001

### Evidencia adicional

`CAMPO_OTP_CODE` tiene cinco validaciones `ACTIVO`, todas blocking ERROR:

- `VAL_OTP_INTENTOS_DISPONIBLES`
- `VAL_OTP_LONGITUD`
- `VAL_OTP_SOLO_NUMERICO`
- `VAL_OTP_DIGITOS_PERMITIDOS`
- `VAL_OTP_NO_VENCIDO`

### Salida esperada

```yaml
evaluation_outcome: NEGATIVE_CONFIRMED
cause_type: RESOLVER_MISSED_EXPLICIT_REFERENCE
evidence_found:
  - REG_CLIENT_RECOVERY_PHONE_CONTROL_001 -> CAMPO_OTP_CODE
  - CAMPO_OTP_CODE -> 5 validaciones ACTIVO
exact_gap: el resolver VALIDATIONS no sigue la cadena regla aplicable -> campo referenciado -> validaciones activas
remediation_action:
  - expandir la cadena de referencia hasta campos_validaciones
  - comprobar que las cinco validaciones cubren el uso OTP de recovery y no pertenecen únicamente a un contexto incompatible
  - mantener cualquier dimensión no cubierta como gap explícito
do_not_do:
  - no crear validaciones nuevas antes de evaluar las existentes
  - no copiar automáticamente semántica ONB_002 solo porque algunos error_code contienen ONB-002
close_when:
  - las validaciones existentes quedan verificadas como aplicables al uso recovery o se identifica exactamente la validación adicional faltante
next_owner: INTERNAL_RESOLVER
human_decision_required: false
```

---

## G03 — Negativo real: UI_MESSAGES sin catálogo aplicable

```yaml
evaluation_outcome: NEGATIVE_CONFIRMED
cause_type: CANONICAL_SOURCE_ABSENT
evidence_found:
  - outcomes de recovery definidos: VERIFIED, RETRYABLE_FAILURE, DENIED, RISK_BLOCKED, SERVICE_UNAVAILABLE
exact_gap: no existe mensaje canónico vigente vinculado a cada outcome requerido para REC_001
remediation_action:
  - buscar mensajes Client existentes por referencia semántica y scope explícito
  - si no existe reutilización válida, preparar propuesta UX/Product por outcome con trazabilidad a la regla de outcome
do_not_do:
  - no inventar copy final
  - no reutilizar mensajes B2B o de otra pantalla por semejanza textual sin scope
authority_ref: null
close_when:
  - cada outcome requerido posee message_id/message_code canónico vigente y aplicable, o queda una decisión UX/Product mínima explícita
next_owner: UX_PRODUCT
human_decision_required: false
```

El `next_owner` indica la autoridad de la fuente faltante; no significa que el usuario deba ser interrumpido inmediatamente. Primero se agota reutilización.

---

## G04 — NOT_APPLICABLE con autoridad positiva

```yaml
evaluation_outcome: NOT_APPLICABLE
positive_authority_ref: DECISION_EXAMPLE_PREAUTH_PERMISSION_NA
scope_match: true
reason: la pantalla opera antes de autenticación y una autoridad explícita prohíbe acceso operacional/permisos hasta completar recovery
```

Hard rule: si se elimina `positive_authority_ref`, el mismo output debe fallar aunque no existan perfiles/permisos en el grafo.

---

## G05 — Stale no puede dominar current

### Evidencia

- Fuente A: PASS antiguo para SHA `aaa...`, estado histórico.
- Fuente B: FAIL posterior para SHA vigente `bbb...`.

### Esperado

```yaml
evaluation_outcome: NEGATIVE_CONFIRMED
cause_type: STALE_EVIDENCE
evidence_found:
  - PASS histórico existe pero no corresponde al SHA vigente
exact_gap: no existe evidencia PASS current para el sujeto vigente
remediation_action:
  - ejecutar/readback de evidencia exact-head para bbb...
do_not_do:
  - no usar PASS de aaa... como evidencia efectiva
close_when:
  - existe evidencia current autoritativa para bbb...
next_owner: INTERNAL_RESOLVER
human_decision_required: false
```

---

## G06 — Gemelo sintético de FIELDS para evitar hardcoding

### Grafo

```text
SCREEN_X
  -> RULE_VERIFY_TOKEN (ACTIVE, scope=SCREEN_X)
      -> verification_field_code=FIELD_VERIFICATION_TOKEN
FIELD_VERIFICATION_TOKEN (ACTIVE)
```

### Esperado

El comportamiento debe ser equivalente a G01 aunque no aparezcan `REC_001`, `OTP` ni `CAMPO_OTP_CODE`.

Si `FIELD_VERIFICATION_TOKEN` cambia a `INACTIVE`, el resultado no puede seguir siendo POSITIVE.
Si `RULE_VERIFY_TOKEN` cambia a `CANDIDATE`, la referencia no puede tratarse como autoridad vigente.
Si la regla cambia `scope=SCREEN_Y`, SCREEN_X no puede heredarla.

---

## G07 — Human Decision legítima, después de agotar resolución

```yaml
evaluation_outcome: HUMAN_DECISION_REQUIRED
cause_type: HUMAN_AUTHORITY_REQUIRED
evidence_found:
  - todos los providers canónicos candidatos y restricciones técnicas fueron resueltos
exact_gap: la selección entre dos providers válidos depende de costo/riesgo/estrategia no derivable de reglas existentes
remediation_action:
  - presentar únicamente la decisión discrecional restante con opciones, impactos y evidencia
do_not_do:
  - no pedir al owner investigar fuentes técnicas
  - no esconder un resolver defectuoso detrás de Human Decision
close_when:
  - existe decisión canónica positiva para la propiedad discrecional
authority_ref: <decision-request-authority>
next_owner: OWNER
human_decision_required: true
```

---

## G08 — Source conflict

```yaml
evaluation_outcome: NEGATIVE_CONFIRMED
cause_type: SOURCE_CONFLICT
evidence_found:
  - RULE_A VIGENTE exige timeout=30s
  - CONTRACT_B VIGENTE exige timeout=60s para el mismo scope y etapa
exact_gap: dos autoridades vigentes incompatibles gobiernan la misma propiedad
remediation_action:
  - resolver precedencia/obsolescencia mediante la autoridad de gobernanza correspondiente
  - preservar ambas referencias en la evidencia
  - reevaluar después de la resolución
do_not_do:
  - no elegir silenciosamente el valor más reciente por timestamp
  - no promediar valores
close_when:
  - una autoridad explícita resuelve la contradicción o una fuente queda formalmente superseded
next_owner: CURATOR
human_decision_required: false
```
