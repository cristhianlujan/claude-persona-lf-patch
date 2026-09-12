# Contrato de responsive y accesibilidad

Versión operativa: `v0.3`. Juez asociado: `J10_TEST_COVERAGE con evidencia de familias RESPONSIVE y ACCESSIBILITY`.

## 1. Propósito

Convertir requisitos de adaptación y acceso inclusivo en comportamientos observables, no en declaraciones genéricas.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `interaction_contract` | Jerarquía, controles, estados y flujos. |
| `field_contracts` | Campos, labels, errores y ayudas. |
| `token_registry` | Tokens de layout y foco. |
| `supported_breakpoints` | Rangos confirmados por producto. |
| `accessibility_baseline` | Nivel y políticas vigentes. |
| `visual_observation_inventory` | Evidencia post-lock de labels/estados/viewports observables; no sustituye supported_breakpoints ni accessibility_baseline. |

## 3. Preflight

Antes de aplicar este contrato:

1. Confirmar que las entradas obligatorias existen y pertenecen a la misma versión de fuente.
2. Resolver todas las referencias declaradas.
3. Confirmar que el alcance de lectura y escritura está autorizado.
4. Registrar contradicciones o datos ausentes antes de producir contenido.
5. Detenerse con `BLOCKED` cuando una condición bloqueante sea verdadera.

## 4. Procedimiento obligatorio

1. Definir breakpoints soportados y prioridad de contenido.
2. Definir reflow, truncamiento y transformación de tablas.
3. Verificar acceso permanente a la acción primaria.
4. Definir estructura semántica y orden de foco.
5. Vincular labels, ayudas y errores a los controles.
6. Definir anuncio programático de cambios y errores.
7. Comprobar operación completa por teclado.
8. Definir indicador de estado no dependiente del color.
9. Respetar reducción de movimiento.
10. Derivar pruebas por breakpoint y modalidad de interacción.

## 5. Reglas e invariantes

- Con una sola captura, responsive es `NOT_OBSERVABLE`; no se derivan breakpoints.
- ARIA, orden de foco, operación por teclado y anuncios programáticos no se confirman por píxeles; requieren evidencia externa/implementación.
- Evidencia visual observable se preserva por `source_ref`; requisitos no observables quedan `PENDING_DECISION` hasta disponer de baseline/política.

- La acción primaria nunca queda inaccesible en el breakpoint menor.
- El estado no se comunica únicamente por color.
- Todo control interactivo es operable por teclado.
- Todo campo tiene label asociado; placeholder no sustituye label.
- Errores y cambios dinámicos se anuncian programáticamente.
- Animación no es requisito para completar la tarea.
- Responsive y accesibilidad acompañan la historia; no se fragmentan artificialmente.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/properties/responsive_accessibility`.

La salida debe incluir referencias de fuente, conteos, assertions evaluadas, decisiones pendientes y rutas de evidencia. Una salida estructuralmente válida pero sin evidencia no es satisfactoria.

## 7. Assertions de paso

```text
primary_actions_inaccessible_small_breakpoint = 0
interactive_controls_not_keyboard_operable = 0
fields_without_label_association = 0
errors_without_programmatic_announcement = 0
color_only_state_indicators = 0
reduced_motion_violations = 0
```

## 8. Condiciones de bloqueo

```text
supported_breakpoints_missing = true
accessibility_baseline_conflict = true
```

## 9. Ejemplo mínimo completo

```json
{
  "breakpoints_supported": ["SMALL", "MEDIUM", "LARGE"],
  "layout_priority": ["primary_result", "primary_action", "filters"],
  "table_to_card_strategy": "CARD_PER_RECORD",
  "keyboard_operable": true,
  "error_announcement": "ARIA_LIVE_ASSERTIVE",
  "non_color_state_indicator": true
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
