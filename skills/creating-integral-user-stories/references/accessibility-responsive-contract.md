# Contrato de responsive y accesibilidad

Estos elementos acompanan cada historia. No generan historias propias salvo
que representen una capacidad funcional para un actor real.

## Responsive

```text
breakpoints_supported, layout_priority, content_reflow_rule,
truncation_policy, table_to_card_strategy, sticky_actions_policy
```

Regla: ninguna accion primaria queda inaccesible en el breakpoint menor.

## Accesibilidad

```text
semantic_structure, focus_order, focus_visible, keyboard_operable,
label_association, error_announcement, contrast_baseline,
reduced_motion_respected, non_color_state_indicator
```

## Reglas duras

- El estado no se comunica solo por color.
- Todo campo con error anuncia el error de forma programatica.
- Todo control interactivo es operable por teclado.
- La animacion no es requisito para completar la tarea.

## Pruebas asociadas

Familias `RESPONSIVE` y `ACCESSIBILITY` en la seccion O del Story Pack.
Se derivan del criterio de aceptacion, no se inventan al final.
