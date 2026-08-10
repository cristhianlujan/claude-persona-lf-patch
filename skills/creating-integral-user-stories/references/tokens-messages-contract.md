# Contrato de tokens y mensajes

Versión operativa: `v0.3`. Juez asociado: `J08_TOKENS_MESSAGES`.

## 1. Propósito

Evitar valores visuales y textos repetidos hardcodeados mediante referencias registradas, estados de candidato y mensajes semánticos, y separar la evidencia observada de la fuente canónica que pertenece al Design System/Brand/Renderer.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `interaction_contract` | Componentes y estados de interacción. |
| `token_registry` | Tokens visuales, formato y componentes. |
| `message_catalog` | Códigos, severidad, audiencia y acciones. |
| `source_copy` | Texto de negocio confirmado cuando exista. |
| `visual_observation_inventory` | Evidencia post-lock v0.2 de copy, iconos y apariencia; cada elemento conserva source_ref y aún no implica token registrado. |
| `canonical_visual_refs` | Referencias post-lock autoritativas disponibles para resolución: tokens, `brand_assets`, `visual_decisions`, `screen_visual_specs` y/o fuentes de iconografía runtime. Puede ser una lista vacía; ausencia de evidencia implica `UNRESOLVED`, nunca inventar. |

## 3. Preflight

Antes de aplicar este contrato:

1. Confirmar que las entradas obligatorias existen y pertenecen a la misma versión de fuente.
2. Resolver todas las referencias declaradas.
3. Confirmar que el alcance de lectura y escritura está autorizado.
4. Registrar contradicciones o datos ausentes antes de producir contenido.
5. Detenerse con `BLOCKED` cuando una condición bloqueante sea verdadera.

## 4. Procedimiento obligatorio

1. Inventariar colores, espacios, tamaños, tipografías, iconos, formatos y componentes requeridos desde fuentes y, cuando exista, desde `visual_observation_inventory` post-lock.
2. Resolver valores tokenizables contra `token_registry`.
3. Declarar tokens inexistentes como CANDIDATO con fallback y source_ref. Una observación blind con `token_relation=CANDIDATE_ONLY|UNRESOLVED_REGISTRY` jamás se transforma en REGISTERED sin evidencia del registry.
4. Resolver cada observación `ICON` contra la fuente visual canónica aplicable. Registrar el resultado en `tokens_messages.visual_references`: `RESOLVED` solo con evidencia autoritativa; de lo contrario `UNRESOLVED`. Un `brand_mark`, logo, ilustración o artwork no se recrea ni se degrada a token genérico para obtener PASS.
5. Inventariar mensajes funcionales, observaciones y errores.
6. Asignar message_code, severidad, audiencia, text_ref y action_token.
7. Detectar textos duplicados y sustituirlos por referencia.
8. Comprobar que el estado no dependa solo del color.
9. Comprobar que mensajes financieros no prometan resultados ni usen urgencia artificial.
10. Derivar pruebas visuales y de mensaje.
11. Entregar conteos y referencias a J08.

## 5. Reglas e invariantes

- Prohibidos HEX, RGB, px, rem, tipografías o iconos literales dentro del Story Pack.
- La presencia visual observada y la implementación visual exacta son dominios distintos: J00 aporta `source_ref`; la resolución post-lock aporta la referencia canónica; Design System/Brand/Renderer conserva el valor o asset exacto.
- `RESOLVED` exige una referencia canónica respaldada por el contexto autoritativo; `UNRESOLVED` no es un permiso para reconstruir el asset.
- Una familia tipográfica exacta observada solo en píxeles no es CONFIRMED; requiere metadata declarada o registry.
- Un token nuevo se marca CANDIDATO; esta skill no puede declararlo vigente.
- Todo mensaje tiene severidad y audiencia.
- Mensajes técnicos no exponen detalles internos.
- Textos iguales deben compartir message_code cuando su semántica sea igual.
- El formato de datos sensibles debe respetar masking_rule.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/properties/tokens_messages`.

La salida debe incluir referencias de fuente, conteos, assertions evaluadas, decisiones pendientes y rutas de evidencia. Una salida estructuralmente válida pero sin evidencia no es satisfactoria.

Cuando existan observaciones `ICON`, `tokens_messages.visual_references` usa este contrato post-lock:

```json
{
  "source_ref": "IMG-001#BRAND-MARK",
  "resolution_status": "RESOLVED",
  "canonical_source_kind": "BRAND_ASSET",
  "canonical_ref": "brand_assets#LOGO_NORMAL",
  "resolution_evidence_ref": "visual_decisions#VD_LOGO_001"
}
```

`canonical_source_kind` admite `TOKEN`, `COMPONENT_TOKEN`, `BRAND_ASSET`, `VISUAL_DECISION`, `SCREEN_VISUAL_SPEC`, `RUNTIME_ICON_SOURCE` o `UNRESOLVED`. Si `resolution_status=UNRESOLVED`, `canonical_source_kind=UNRESOLVED` y `canonical_ref` queda vacío.

## 7. Assertions de paso

```text
hardcoded_color_count = 0
hardcoded_spacing_count = 0
unregistered_component_tokens = 0
duplicate_message_text_without_token = 0
candidate_tokens_without_candidate_status = 0
messages_without_severity = 0
```

Assertions adicionales del bridge visual (`scripts/validate_visual_evidence_bridge.py`), sin alterar las 11 assertions del juez J08:

```text
icon_visual_reference_required = 0
visual_reference_contract_valid = 0
resolved_visual_reference_requires_registry = 0
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
