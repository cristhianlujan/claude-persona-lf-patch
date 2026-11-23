# REG_CHK_007 v2 — Selección de ofertas: cambio hasta antes de pagar

**Estado objetivo:** solo CANDIDATA. Fuente: decisión de Cristhian trasladada por Claude el 23/11/2026 17:47 Lima. No acreditar binding ni autorizar promoción sin juicio independiente.

**Condición:** `intento_modificar_seleccion AND violacion_inmutabilidad AND (en_confirmacion OR pago_enviado_no_terminal_seguro)`. Cuatro hechos lógicos booleanos; `checkout_en_confirmacion` ya existía, los otros tres son hechos curados sin tabla/columna física.

**Descripción:** BLOQUEAR únicamente un intento real de modificar la selección de ofertas cuando la modificación constituye una violación y se intenta directamente desde la pantalla de confirmación, que es de solo lectura, o tras enviar un pago cuyo outcome todavía no sea terminal seguro. Para cambiar antes de enviar el pago, el cliente debe usar Volver para regresar al paso de selección, ajustar ofertas y avanzar con un resumen nuevo; navegar Volver o consultar el resumen sin intentar modificar no se bloquea. El pago pendiente sigue bloqueando cambios hasta outcome terminal seguro como supuesto funcional pendiente de decisión de Cristhian. La regla no concede por sí misma permiso para editar tras un outcome terminal ni decide reintentos de pago. Los hechos son lógicos tipados sin binding runtime acreditado de Paulo.

| Caso | Contexto | Intento | Violación | Confirmación | Enviado no terminal | Bloquear |
|---|---|---|---|---|---|---|
| 1 | Confirmación, solo lectura sin intento | false | false | true | false | false |
| 2 | Confirmación, intento modificar ofertas | true | true | true | false | true |
| 3 | Confirmación, intento sin violación acreditada | true | false | true | false | false |
| 4 | Volver desde confirmación sin modificar | false | false | true | false | false |
| 5 | En selección tras Volver, modificación permitida antes de enviar | true | false | false | false | false |
| 6 | Selección antes del pago, intento no viola | true | false | false | false | false |
| 7 | Pago enviado, outcome pendiente, intento cambiar | true | true | false | true | true |
| 8 | Pago enviado sin terminal seguro, intento de cambiar desde confirmación | true | true | true | true | true |
| 9 | Pago enviado no terminal, solo lectura sin intento | false | false | false | true | false |
| 10 | Pago con outcome terminal seguro, sin contexto de bloqueo (no autoriza editar) | true | false | false | false | false |
| 11 | Confirmación, otro intento de cambio tras volver a avanzar | true | true | true | false | true |
| 12 | Estado indefinido sin confirmación ni envío, violación agregada no basta | true | true | false | false | false |

**Diferencias:** REG_CHK_007 protege contra *modificar selección* en confirmación o pago enviado no terminal; REG_CHK_004 bloquea *reintento de pago* hasta outcome seguro + autorización backend + quote original vigente; M2-C05 bloquea *ingreso al checkout* con oferta seleccionada sin modalidad. Ninguna equivale a las otras.

**No decidible aún:** pago pendiente sigue inmóvil hasta outcome terminal como supuesto provisional de producto; Cristhian debe confirmarlo. Nada aquí implica reabrir oferta después de pago terminal. Se requiere binding de Paulo de los tres hechos nuevos, sin inventar fuentes.
