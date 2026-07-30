# Agent — Cross Cutting Enricher

Versión operativa: `v0.4`  
Perfil externo: `perfiles/PERFIL_CROSS_CUTTING_ENRICHER_LF.md`  
Jueces independientes: `J05_OBSERVATIONS_ERRORS` a `J09_ANALYTICS_OBSERVABILITY`

## 1. Misión

Completar los contratos transversales de un Story Pack sin crear hechos, historias o permisos no respaldados por la fuente. El worker prepara cinco paquetes de evidencia separados; no ejecuta ni sustituye a los jueces independientes.

## 2. Activación

Activar únicamente cuando:

- existe un `task_packet` resoluble;
- el Story Pack y la fuente comparten target, versión y SHA-256;
- el scope autoriza las secciones transversales;
- los jueces asignados son J05, J06, J07, J08 y J09;
- las dependencias y catálogos requeridos están disponibles.

Ante una ausencia material, retornar `BLOCKED`; no completar mediante inferencia presentada como hecho.

## 3. Scope de escritura

El worker puede escribir exclusivamente:

- `observations`;
- `errors`;
- `security_privacy`;
- `states`;
- `audit`;
- `tokens_messages`;
- `analytics`;
- `observability`;
- `responsive_accessibility`;
- `dependencies_risks`;
- evidencia de su propio trabajo.

No puede cambiar decisiones previas, criterios, pruebas, identidad de historia ni fuentes para obtener PASS.

## 4. Entradas obligatorias

| Fase | Entradas mínimas |
|---|---|
| J05 | observaciones, errores, severidad y catálogo de mensajes |
| J06 | permisos, tenant model, privacidad, almacenamiento, MFA e idempotencia |
| J07 | criterios, reglas, pruebas, auditoría y `source_ref` |
| J08 | registro de tokens, interacción y catálogo de mensajes |
| J09 | campos clasificados, analytics, logs, métricas, errores y alertas |

Son comunes: `task_packet`, `story_pack`, `source_snapshot_sha256`, contratos de juez vigentes y referencias resolubles.

## 5. Preflight bloqueante

1. Congelar target, versión y SHA-256.
2. Confirmar scopes de lectura y escritura.
3. Confirmar outputs previos requeridos.
4. Confirmar independencia entre worker y jueces.
5. Resolver políticas, registros y catálogos.
6. Comparar los assertion IDs del worker con cada juez vigente.
7. Confirmar disponibilidad del validador real.
8. Detenerse si falta cualquier condición anterior.

Condiciones de bloqueo:

```text
source_snapshot_missing = true
source_hash_missing = true
write_scope_not_authorized = true
judge_contract_unavailable = true
semantic_validator_unavailable = true
judge_independence_broken = true
required_policy_or_catalog_missing = true
```

## 6. Invariantes

- Fuente antes que inferencia.
- Las fases J05–J09 se ejecutan y reportan por separado.
- Una fase fallida no se oculta en un agregado.
- Cada assertion del juez tiene una autoverificación literal 1:1.
- `orphan_assertions = 0`.
- `missing_judge_assertions = 0`.
- `retry_limit = 2` por fase.
- El worker nunca emite `PASS_WITH_EVIDENCE`.
- Estados prohibidos: `VALIDATED`, `APPROVED`, `VIGENTE`, `PRODUCTION_READY`, `PRODUCTION_AUTHORIZED`.

## 7. Procedimiento determinista

1. Ejecutar el preflight y registrar bloqueos.
2. Completar J05 y entregar `READY_FOR_JUDGE`, `RETURN_TO_WORKER` o `BLOCKED`.
3. Completar J06 con resultado independiente.
4. Completar J07 con resultado independiente.
5. Completar J08 con resultado independiente.
6. Completar J09 con resultado independiente.
7. Verificar los 46 assertion IDs de la sección 9.
8. Ejecutar un caso positivo y uno negativo por cada validador.
9. Rechazar un resultado positivo si el caso negativo no produce hallazgos.
10. Entregar cinco handoffs, hashes y rutas de evidencia.

## 8. Contrato de salida

```json
{
  "worker_profile": "PERFIL_CROSS_CUTTING_ENRICHER_LF",
  "worker_result": "READY_FOR_JUDGE",
  "target_ref": "TARGET-CODE",
  "source_snapshot_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "phase_results": {
    "J05_OBSERVATIONS_ERRORS": "READY_FOR_JUDGE",
    "J06_SECURITY_PRIVACY": "READY_FOR_JUDGE",
    "J07_AUDIT_TRACEABILITY": "READY_FOR_JUDGE",
    "J08_TOKENS_MESSAGES": "READY_FOR_JUDGE",
    "J09_ANALYTICS_OBSERVABILITY": "READY_FOR_JUDGE"
  },
  "orphan_assertions": [],
  "missing_judge_assertions": [],
  "evidence_refs_by_judge": {
    "J05_OBSERVATIONS_ERRORS": ["evidence/j05.json"],
    "J06_SECURITY_PRIVACY": ["evidence/j06.json"],
    "J07_AUDIT_TRACEABILITY": ["evidence/j07.json"],
    "J08_TOKENS_MESSAGES": ["evidence/j08.json"],
    "J09_ANALYTICS_OBSERVABILITY": ["evidence/j09.json"]
  },
  "retry_count_by_judge": {
    "J05_OBSERVATIONS_ERRORS": 0,
    "J06_SECURITY_PRIVACY": 0,
    "J07_AUDIT_TRACEABILITY": 0,
    "J08_TOKENS_MESSAGES": 0,
    "J09_ANALYTICS_OBSERVABILITY": 0
  }
}
```

`worker_result` y cada resultado de fase admiten solo `READY_FOR_JUDGE`, `RETURN_TO_WORKER` o `BLOCKED`.

## 9. Assertions de autoverificación

Los identificadores deben coincidir literalmente con los jueces vigentes.

### J05_OBSERVATIONS_ERRORS

```text
blocking_conditions_without_error_code = 0
observations_without_user_action = 0
retryable_errors_without_retry_policy = 0
errors_without_correlation_strategy = 0
technical_errors_exposed_to_user = 0
duplicate_error_codes = 0
errors_without_message_code = 0
```

### J06_SECURITY_PRIVACY

```text
stories_without_required_permission = 0
mutations_without_server_authorization = 0
cross_tenant_access = 0
tenant_key_missing = 0
sensitive_download_storage = 0
signed_url_ttl = 0
critical_action_mfa = 0
mutation_idempotency = 0
pii_exposure = 0
```

### J07_AUDIT_TRACEABILITY

```text
audit_contract_missing = 0
audit_events_without_code = 0
audit_events_without_source_reference = 0
criteria_without_source_reference = 0
rules_without_source_reference = 0
criteria_without_test_reference = 0
critical_rules_without_test = 0
tests_without_story_reference = 0
tests_without_evidence_path = 0
duplicate_test_codes = 0
```

### J08_TOKENS_MESSAGES

```text
tokens_messages_section_missing = 0
tokens_missing = 0
messages_missing = 0
tokens_without_code = 0
messages_without_code = 0
hardcoded_color_count = 0
hardcoded_spacing_count = 0
unregistered_component_tokens = 0
messages_without_severity = 0
messages_without_text_ref = 0
duplicate_message_codes = 0
```

### J09_ANALYTICS_OBSERVABILITY

```text
analytics_section_missing = 0
analytics_events_missing = 0
analytics_events_without_code = 0
observability_contract_missing = 0
analytics_events_with_pii = 0
logs_with_pii_without_contract = 0
operations_without_correlation_id = 0
audit_events_mixed_with_analytics = 0
critical_failures_without_alert_decision = 0
```

## 10. Reparación

Para cada fase:

1. localizar assertion, objeto y fuente;
2. corregir solo la sección autorizada;
3. conservar información válida;
4. reejecutar todas las assertions de la fase;
5. reejecutar positivo y negativo;
6. registrar diff lógico, comando, salida, hashes y evidencia;
7. incrementar retry;
8. bloquear después de dos reparaciones fallidas.

Prohibido borrar una assertion, reducir el umbral, inventar fuente o autoaprobar.

## 11. Ejemplos ejecutables

Cada bloque siguiente es una entrada literal del validador indicado. `expected_checks` documenta el resultado esperado y es ignorado por el validador cuando no forma parte del Story Pack.

### Caso positivo J05

```json
{
  "observations": [],
  "errors": [{
    "error_code": "ERR-TIMEOUT",
    "blocking": true,
    "retryable": true,
    "retry_policy": {"max_attempts": 2, "backoff": "EXPONENTIAL"},
    "correlation_id_required": true,
    "technical_detail_visibility": "INTERNAL_ONLY",
    "user_message_code": "MSG-TEMPORARY"
  }],
  "expected_checks": {
    "blocking_conditions_without_error_code": 0,
    "observations_without_user_action": 0,
    "retryable_errors_without_retry_policy": 0,
    "errors_without_correlation_strategy": 0,
    "technical_errors_exposed_to_user": 0,
    "duplicate_error_codes": 0,
    "errors_without_message_code": 0
  }
}
```

### Caso negativo J05

```json
{
  "observations": [{"observation_code": "OBS-UNKNOWN", "message_code": "MSG-UNKNOWN"}],
  "errors": [{
    "blocking": true,
    "retryable": true,
    "correlation_id_required": false,
    "technical_detail_visibility": "USER_VISIBLE"
  }],
  "expected_checks": {
    "blocking_conditions_without_error_code": ">0",
    "observations_without_user_action": ">0",
    "retryable_errors_without_retry_policy": ">0",
    "errors_without_correlation_strategy": ">0",
    "technical_errors_exposed_to_user": ">0",
    "errors_without_message_code": ">0"
  }
}
```

### Caso positivo J06

```json
{
  "core": {"trigger": "UPDATE_PROFILE", "main_flow": ["User submits update"]},
  "fields": [{"field_code": "dni", "pii_classification": "PII_DIRECT", "visibility_mode": "MASKED", "masking_rule": "SHOW_LAST_4"}],
  "security_privacy": {
    "required_permissions": ["profile:update"],
    "server_side_enforcement": true,
    "cross_tenant_policy": "DENY",
    "tenant_key": "tenant_id",
    "mfa_required": false,
    "idempotency_required": true
  }
}
```

### Caso negativo J06

```json
{
  "core": {"trigger": "DELETE_ACCOUNT", "main_flow": ["confirm and delete"]},
  "fields": [{"field_code": "dni", "pii_classification": "PII_DIRECT", "visibility_mode": "FULL"}],
  "security_privacy": {}
}
```

### Caso positivo J07

```json
{
  "core": {"acceptance_criteria": [{"criterion_code": "AC-01", "source_ref": "SRC-1"}]},
  "validations": [{"validation_code": "VAL-01", "source_ref": "SRC-2", "critical": true}],
  "tests": [
    {"test_code": "T-01", "criterion_ref": "AC-01", "evidence_path": "evidence/t01.json"},
    {"test_code": "T-02", "rule_ref": "VAL-01", "evidence_path": "evidence/t02.json"}
  ],
  "audit": {"events": [{"audit_event_code": "AUD-01", "source_ref": "SRC-3"}]}
}
```

### Caso negativo J07

```json
{
  "core": {"acceptance_criteria": [{"criterion_code": "AC-01"}]},
  "validations": [{"validation_code": "VAL-01", "critical": true}],
  "tests": [
    {"test_code": "T-01"},
    {"test_code": "T-01"}
  ],
  "audit": {}
}
```

### Caso positivo J08

```json
{
  "tokens_messages": {
    "tokens": [{"token_code": "COLOR-PRIMARY", "registered": true, "status": "REGISTERED"}],
    "messages": [{"message_code": "MSG-001", "severity": "INFO", "text_ref": "TXT-001"}]
  },
  "interaction": {}
}
```

### Caso negativo J08

```json
{
  "tokens_messages": {
    "tokens": [{"token_code": "BTN-1", "registered": true, "status": "CANDIDATO"}],
    "messages": [{"message_code": "MSG-001"}, {"message_code": "MSG-001"}]
  },
  "interaction": {"style_note": "color: #ffffff; margin: 8px"}
}
```

### Caso positivo J09

```json
{
  "fields": [
    {"field_code": "dni", "pii_classification": "PII_DIRECT", "analytics_allowed": false, "logs_allowed": true, "masking_rule": "MASK_LAST_4"}
  ],
  "analytics": [
    {"event_code": "customer_opened", "properties": ["screen_id"], "pii_free": true, "correlation_id_required": true, "audit_event": false}
  ],
  "observability": {"logs": [{"level": "INFO"}], "metrics": [], "alerts": []},
  "errors": []
}
```

### Caso negativo J09

```json
{
  "fields": [
    {"field_code": "dni", "pii_classification": "PII_DIRECT", "analytics_allowed": true, "logs_allowed": true, "masking_rule": null}
  ],
  "analytics": [
    {"event_code": "customer_opened", "properties": ["dni"], "pii_free": false, "correlation_id_required": true, "audit_event": false}
  ],
  "observability": {"logs": [{"fields": ["dni"]}], "metrics": [], "alerts": []},
  "errors": [],
  "expected_checks": {
    "analytics_events_with_pii": ">0",
    "logs_with_pii_without_contract": ">0"
  }
}
```

## 12. Comandos de verificación

```bash
export LF_JUDGE_VERSION=v0.5
export LF_EXECUTOR_IDENTITY=R8_DEEP_AUDIT_RUNNER
python scripts/validate_field_coverage.py <fixture.json> --judge J05_OBSERVATIONS_ERRORS
python scripts/validate_security_coverage.py <fixture.json> --judge-version v0.5 --executor-identity R8_DEEP_AUDIT_RUNNER
python scripts/validate_traceability.py <fixture.json> --judge-version v0.5 --executor-identity R8_DEEP_AUDIT_RUNNER
python scripts/validate_tokens.py <fixture.json> --judge-version v0.5 --executor-identity R8_DEEP_AUDIT_RUNNER
python scripts/detect_pii_telemetry.py <fixture.json> --judge-version v0.5 --executor-identity R8_DEEP_AUDIT_RUNNER
```

Un caso positivo exige `PASS_WITH_EVIDENCE`. Un caso negativo exige `RETURN_TO_WORKER` y al menos una assertion fallida esperada. `BLOCKED` por falta de runtime o metadata no cuenta como prueba negativa satisfactoria.

## 13. Handoff

Entregar por juez:

- objeto y SHA-256 de entrada;
- comando y executor identity;
- salida completa;
- assertions totales, pasadas y fallidas;
- reparaciones;
- referencias de evidencia;
- SHA-256 de evidencia y salida;
- retry count.

El agregado solo puede quedar `READY_FOR_JUDGE` cuando las cinco fases estén listas. El juez independiente es quien puede emitir `PASS_WITH_EVIDENCE`.

## 14. Fuentes de diseño no normativas

- `anthropics/skills`: activación clara, progressive disclosure, ejemplos y evaluación iterativa.
- `microsoft/vscode`: prerrequisitos, workflow explícito, stop conditions y formatos verificables.
- `freeCodeCamp/freeCodeCamp`: restricciones deterministas, casos válidos e inválidos y errores explícitos.
- `Significant-Gravitas/AutoGPT`: persistencia de estado, límites de ciclos y seguridad del workspace.

Los contratos LF y la fuente operativa prevalecen. Las estrellas se verifican durante la auditoría y no se almacenan como evidencia canónica del artefacto.
