# Contrato integral por campo

Versión operativa: `v0.3`. Juez asociado: `J04_FIELD_CONTRACTS`.

## 1. Propósito

Asignar a cada campo un contrato explícito de origen, tipo, visibilidad, edición, validación, privacidad, auditoría, telemetría y retención.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `screen_fields` | Inventario completo de campos visible y no visible asociado a la historia. |
| `field_inventory` | Metadatos fuente por campo y contexto. |
| `permission_matrix` | Perfiles autorizados para ver o editar. |
| `privacy_rules` | Clasificación y restricciones de tratamiento. |
| `token_registry` | Tokens de componente y formato disponibles. |

## 3. Preflight

Antes de aplicar este contrato:

1. Confirmar que las entradas obligatorias existen y pertenecen a la misma versión de fuente.
2. Resolver todas las referencias declaradas.
3. Confirmar que el alcance de lectura y escritura está autorizado.
4. Registrar contradicciones o datos ausentes antes de producir contenido.
5. Detenerse con `BLOCKED` cuando una condición bloqueante sea verdadera.

## 4. Procedimiento obligatorio

1. Conciliar screen_fields contra field_inventory y detectar faltantes o duplicados.
2. Copiar field_code, context_code, entity_code y source_type desde fuente.
3. Asignar data_type, required y reglas de validación.
4. Definir editable, editable_by, viewable_by y visibility_mode.
5. Clasificar privacidad y definir masking_rule cuando corresponda.
6. Definir analytics_allowed, logs_allowed y export_allowed mediante política explícita.
7. Definir audit_required y estrategias de valor previo/nuevo para campos editables.
8. Asignar retención, códigos de validación, observación, error y mensaje.
9. Asignar component_token y format_token registrados o candidatos.
10. Emitir evidencia de cobertura 1:1 y entregar a J04.

## 5. Reglas e invariantes

- fields_in_story debe ser igual a field_contracts_count.
- Campo editable exige audit_required=true y estrategias de cambio.
- PII_DIRECT, PII_SENSITIVE y PII_FINANCIAL no pueden viajar a analytics.
- logs_allowed=true para PII requiere masking_rule explícita.
- visibility_mode MASKED exige masking_rule.
- Un campo no confirmado se bloquea o se marca PENDING_DECISION; no se completa por intuición.
- Los códigos asociados deben existir o declararse como candidatos, nunca hardcodearse.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/definitions/field_contract`.

La salida debe incluir referencias de fuente, conteos, assertions evaluadas, decisiones pendientes y rutas de evidencia. Una salida estructuralmente válida pero sin evidencia no es satisfactoria.

## 7. Assertions de paso

```text
fields_in_story = field_contracts_count
fields_without_visibility_rule = 0
fields_without_editability_rule = 0
editable_fields_without_audit_strategy = 0
pii_fields_without_classification = 0
pii_fields_with_analytics_allowed = 0
pii_fields_with_logs_allowed_without_rule = 0
fields_without_validation_mapping = 0
```

## 8. Condiciones de bloqueo

```text
field_inventory_missing = true
permission_matrix_missing_and_required = true
field_source_conflict = true
```

## 9. Ejemplo mínimo completo

```json
{
  "field_code": "document_number",
  "data_type": "string",
  "required": true,
  "editable": false,
  "viewable_by": ["CUSTOMER_READ"],
  "visibility_mode": "MASKED",
  "pii_classification": "PII_DIRECT",
  "masking_rule": "SHOW_LAST_4",
  "analytics_allowed": false,
  "logs_allowed": false,
  "export_allowed": false,
  "audit_required": false,
  "validation_codes": ["VAL-DOCUMENT-FORMAT"]
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
