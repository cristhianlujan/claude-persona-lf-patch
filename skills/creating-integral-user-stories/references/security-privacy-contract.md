# Contrato de seguridad y privacidad

Versión operativa: `v0.3`. Juez asociado: `J06_SECURITY_PRIVACY`.

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

Antes de aplicar este contrato:

1. Confirmar que las entradas obligatorias existen y pertenecen a la misma versión de fuente.
2. Resolver todas las referencias declaradas.
3. Confirmar que el alcance de lectura y escritura está autorizado.
4. Registrar contradicciones o datos ausentes antes de producir contenido.
5. Detenerse con `BLOCKED` cuando una condición bloqueante sea verdadera.

## 4. Procedimiento obligatorio

1. Identificar si la historia requiere autenticación.
2. Enumerar perfiles y permisos exactos.
3. Definir enforcement server-side para cada lectura o mutación.
4. Definir tenant_key y política cross-tenant.
5. Decidir necesidad de RLS según almacenamiento y acceso.
6. Decidir MFA o step-up para acciones críticas.
7. Definir rate limiting e idempotencia.
8. Definir almacenamiento privado y TTL de URLs firmadas.
9. Vincular campos sensibles con masking, logs y exportación.
10. Derivar pruebas negativas de permiso, tenant e idempotencia.

## 5. Reglas e invariantes

- Autorización solo cliente es falla.
- cross_tenant_policy admite DENY o EXPLICIT_ALLOW_WITH_AUDIT.
- Toda historia multiempresa con lectura o escritura exige prueba cross-tenant negativa.
- Mutación exige decisión de idempotencia, incluso cuando la decisión sea NO_APPLIES con razón.
- Descarga sensible exige almacenamiento privado y URL firmada con TTL.
- Acción crítica exige decisión explícita de MFA.
- Ausencia de definición material genera PENDING_DECISION, no un valor por defecto.
- PII no se expone en analytics ni logs sin política.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/properties/security_privacy`.

La salida debe incluir referencias de fuente, conteos, assertions evaluadas, decisiones pendientes y rutas de evidencia. Una salida estructuralmente válida pero sin evidencia no es satisfactoria.

## 7. Assertions de paso

```text
stories_without_required_permission = 0
mutations_without_server_side_authorization = 0
cross_tenant_access_allowed = 0
tenant_key_missing = 0
sensitive_download_without_private_storage = 0
signed_url_without_ttl = 0
critical_action_without_mfa_decision = 0
mutation_without_idempotency_decision = 0
```

## 8. Condiciones de bloqueo

```text
permission_source_unavailable = true
tenant_model_undefined_and_blocking = true
privacy_classification_conflict = true
```

## 9. Ejemplo mínimo completo

```json
{
  "authentication_required": true,
  "allowed_profiles": ["OPERATOR"],
  "required_permissions": ["CUSTOMER_READ"],
  "tenant_key": "company_id",
  "cross_tenant_policy": "DENY",
  "server_side_enforcement": true,
  "rls_required": true,
  "mfa_required": false,
  "idempotency_required": false
}
```

## 10. Reparación

Cuando una assertion falle, reparar exclusivamente el objeto asociado; no reducir el umbral, borrar la assertion ni modificar la fuente. Tras `retry_limit = 2`, devolver `BLOCKED` con la evidencia acumulada.

## 11. Handoff

Entregar al juez: versión de fuente, SHA-256, objetos procesados, conteos, assertions, fallas, decisiones pendientes, reparaciones aplicadas y evidence_refs resolubles.

## 12. Fuentes de diseño no normativas

- **microsoft/vscode** (~186,000 estrellas): `extensions/copilot/assets/prompts/skills/chronicle/SKILL.md`; patrones: prerrequisitos, workflows paso a paso, formatos de salida y stop conditions.
- **freeCodeCamp/freeCodeCamp** (~446,000 estrellas): `curriculum/schema/challenge-schema.js`; patrones: validación condicional, campos obligatorios, mensajes de error verificables.
- **Significant-Gravitas/AutoGPT** (~185,000 estrellas): `classic/original_autogpt/CLAUDE.md`; patrones: arquitectura explícita, ciclo operativo, estado, pruebas y gotchas.

Estas fuentes aportan patrones de ejecutabilidad, validación y pruebas. Los contratos LF y la fuente operativa prevalecen ante cualquier diferencia.
