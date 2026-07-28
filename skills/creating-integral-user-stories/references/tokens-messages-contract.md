# Contrato de tokens y mensajes

Versión operativa: `v0.3`. Juez asociado: `J08_TOKENS_MESSAGES`.

## 1. Propósito

Evitar valores visuales y textos repetidos hardcodeados mediante referencias registradas, estados de candidato y mensajes semánticos.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `interaction_contract` | Componentes y estados de interacción. |
| `token_registry` | Tokens visuales, formato y componentes. |
| `message_catalog` | Códigos, severidad, audiencia y acciones. |
| `source_copy` | Texto de negocio confirmado cuando exista. |

## 3. Preflight

Antes de aplicar este contrato:

1. Confirmar que las entradas obligatorias existen y pertenecen a la misma versión de fuente.
2. Resolver todas las referencias declaradas.
3. Confirmar que el alcance de lectura y escritura está autorizado.
4. Registrar contradicciones o datos ausentes antes de producir contenido.
5. Detenerse con `BLOCKED` cuando una condición bloqueante sea verdadera.

## 4. Procedimiento obligatorio

1. Inventariar colores, espacios, tamaños, tipografías, iconos, formatos y componentes requeridos.
2. Resolver cada valor contra token_registry.
3. Declarar tokens inexistentes como CANDIDATO con fallback y source_ref.
4. Inventariar mensajes funcionales, observaciones y errores.
5. Asignar message_code, severidad, audiencia, text_ref y action_token.
6. Detectar textos duplicados y sustituirlos por referencia.
7. Comprobar que el estado no dependa solo del color.
8. Comprobar que mensajes financieros no prometan resultados ni usen urgencia artificial.
9. Derivar pruebas visuales y de mensaje.
10. Entregar conteos y referencias a J08.

## 5. Reglas e invariantes

- Prohibidos HEX, RGB, px, rem, tipografías o iconos literales dentro del Story Pack.
- Un token nuevo se marca CANDIDATO; esta skill no puede declararlo vigente.
- Todo mensaje tiene severidad y audiencia.
- Mensajes técnicos no exponen detalles internos.
- Textos iguales deben compartir message_code cuando su semántica sea igual.
- El formato de datos sensibles debe respetar masking_rule.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/properties/tokens_messages`.

La salida debe incluir referencias de fuente, conteos, assertions evaluadas, decisiones pendientes y rutas de evidencia. Una salida estructuralmente válida pero sin evidencia no es satisfactoria.

## 7. Assertions de paso

```text
hardcoded_color_count = 0
hardcoded_spacing_count = 0
unregistered_component_tokens = 0
duplicate_message_text_without_token = 0
candidate_tokens_without_candidate_status = 0
messages_without_severity = 0
```

## 8. Condiciones de bloqueo

```text
token_registry_required_but_unavailable = true
message_policy_conflict = true
```

## 9. Ejemplo mínimo completo

```json
{
  "token_code": "color.action.primary",
  "token_type": "COLOR",
  "registered": true,
  "status": "REGISTERED",
  "source_ref": "TOKEN-REGISTRY#color.action.primary"
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
