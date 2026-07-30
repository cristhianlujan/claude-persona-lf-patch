# Contrato de responsive y accesibilidad

Versión operativa: `v0.5`. Juez asociado: `J10_TEST_COVERAGE` con familias `RESPONSIVE` y `ACCESSIBILITY`.

## 1. Propósito

Convertir requisitos de adaptación y acceso inclusivo en comportamientos observables y pruebas exactas, no en declaraciones genéricas.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `interaction_contract` | Jerarquía, controles, estados y flujos. |
| `field_contracts` | Campos, labels, errores y ayudas. |
| `token_registry` | Tokens de layout y foco. |
| `supported_breakpoints` | Rangos confirmados por producto. |
| `accessibility_baseline` | Nivel y políticas vigentes. |

## 3. Preflight

1. Confirmar entradas, versión y referencias.
2. Confirmar breakpoints y baseline de accesibilidad.
3. Confirmar que los casos derivados poseen fixtures exactos y evidencia.
4. Detener con `BLOCKED` ante breakpoints ausentes, conflicto de baseline o fuente irresoluble.

## 4. Procedimiento obligatorio

1. Definir breakpoints soportados y prioridad de contenido.
2. Definir reflow, truncamiento y transformación de tablas.
3. Verificar acceso permanente a la acción primaria.
4. Definir estructura semántica y orden de foco.
5. Vincular labels, ayudas y errores a controles.
6. Definir anuncio programático de cambios y errores.
7. Comprobar operación completa por teclado.
8. Definir indicador de estado no dependiente del color.
9. Respetar reducción de movimiento.
10. Derivar pruebas exactas `RESPONSIVE` y `ACCESSIBILITY` para J10.

## 5. Reglas e invariantes

- La acción primaria permanece accesible en `SMALL`.
- Todo control interactivo es operable por teclado.
- Todo campo tiene label asociado.
- Errores y cambios dinámicos se anuncian programáticamente.
- El estado no depende solo del color.
- La tarea no depende de animación y respeta reducción de movimiento.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/properties/responsive_accessibility` y pruebas J10 con fixture exacto.

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
exact_fixture_missing = true
```

## 9. Caso positivo ejecutable

```json
{
  "breakpoints_supported": ["SMALL", "MEDIUM", "LARGE"],
  "primary_action_accessible_small": true,
  "keyboard_operable": true,
  "fields_have_labels": true,
  "error_announcement": "ARIA_LIVE_ASSERTIVE",
  "non_color_state_indicator": true,
  "reduced_motion_supported": true
}
```

Resultado esperado: todas las assertions en cero.

## 10. Caso negativo ejecutable

```json
{
  "breakpoints_supported": ["LARGE"],
  "primary_action_accessible_small": false,
  "keyboard_operable": false,
  "fields_have_labels": false,
  "error_announcement": null,
  "non_color_state_indicator": false,
  "reduced_motion_supported": false
}
```

Resultado esperado: `RETURN_TO_WORKER` con seis hallazgos.

## 11. Reparación y handoff

Reparar únicamente la propiedad o prueba fallida; no borrar assertions, reducir umbrales ni autoaprobar. Tras `retry_limit = 2`, devolver `BLOCKED`. Entregar fixtures, expected results, hashes y `evidence_refs`.

## 12. Fuentes de diseño no normativas

- **anthropics/skills:** ejemplos realistas y evals objetivas.
- **microsoft/vscode:** workflows y stop conditions.
- **freeCodeCamp/freeCodeCamp:** constraints y rechazo determinista.
- **Significant-Gravitas/AutoGPT:** ejecución reproducible y límites.

Los contratos LF prevalecen.
