# Contrato de seguridad y privacidad

Versión operativa: `v0.5`. Juez asociado: `J06_SECURITY_PRIVACY`.
Validador: `scripts/validate_security_coverage.py`.

## 1. Propósito

Convertir riesgos de acceso, aislamiento, mutación y tratamiento de datos en decisiones explícitas y verificables del Story Pack.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `permission_matrix` | Perfiles, permisos y alcance por recurso. |
| `tenant_model` | Clave y reglas de aislamiento por empresa. |
| `field_contracts` | Clasificación de privacidad y reglas de exposición. |
| `state_and_actions` | Acciones críticas, mutaciones y descargas. |
| `storage_contract` | Privacidad, URLs firmadas y retención. |

## 3. Preflight

1. Confirmar entradas, versión y referencias resolubles.
2. Confirmar independencia entre worker y J06.
3. Confirmar `judge_version`, `executor_identity` y SHA-256 de entrada.
4. Detener con `BLOCKED` ante fuente de permisos ausente, conflicto tenant/privacidad o metadata faltante.

## 4. Procedimiento obligatorio

1. Identificar lecturas, mutaciones, descargas y campos PII.
2. Enumerar permisos y enforcement server-side.
3. Definir `tenant_key` y política cross-tenant.
4. Definir almacenamiento privado y TTL cuando exista descarga sensible.
5. Definir MFA para acción crítica e idempotencia para mutación.
6. Aplicar masking a PII visible.
7. Ejecutar caso positivo, negativo y metadata ausente contra el validador real.

## 5. Reglas e invariantes

- Autorización solo cliente es falla.
- `cross_tenant_policy` admite `DENY` o `EXPLICIT_ALLOW_WITH_AUDIT`.
- Toda mutación exige decisión booleana de idempotencia.
- Toda acción crítica exige decisión booleana de MFA.
- PII visible usa masking o queda `HIDDEN`.
- No se reducen assertions ni clasificación PII para obtener PASS.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/properties/security_privacy` y envelope `schemas/judge-result.schema.json` v0.5.

## 7. Assertions de paso

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

## 8. Condiciones de bloqueo

```text
permission_source_unavailable = true
tenant_model_undefined_and_blocking = true
privacy_classification_conflict = true
metadata_or_evidence_unavailable = true
retry_limit_exhausted = true
```

## 9. Caso positivo ejecutable

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

Resultado esperado: `PASS_WITH_EVIDENCE`.

## 10. Caso negativo ejecutable

```json
{
  "core": {"trigger": "DELETE_ACCOUNT", "main_flow": ["confirm and delete"]},
  "fields": [{"field_code": "dni", "pii_classification": "PII_DIRECT", "visibility_mode": "FULL"}],
  "security_privacy": {}
}
```

Resultado esperado: `RETURN_TO_WORKER` con hallazgos de permisos, autorización, tenant, MFA, idempotencia y PII.

## 11. Reparación y handoff

Reparar exclusivamente los objetos indicados; no borrar assertions, reducir umbrales, inventar permisos ni autoaprobar. Tras `retry_limit = 2`, devolver `BLOCKED`. Entregar comando, ejecutor, conteos, fallas, hashes y `evidence_refs` resolubles.

## 12. Fuentes de diseño no normativas

- **anthropics/skills:** `skills/skill-creator/SKILL.md`; casos realistas, grading programático y reparación iterativa.
- **microsoft/vscode:** skills con prerrequisitos, workflows, salidas y stop conditions.
- **freeCodeCamp/freeCodeCamp:** constraints condicionales y rechazo determinista.
- **Significant-Gravitas/AutoGPT:** estado reproducible y límites operativos.

Los contratos LF prevalecen.
