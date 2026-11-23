# REG_CHK_007 v3 — Casos únicos para juicio independiente

**Único cambio sobre v2:** descripción operativa y pruebas; condición, efecto, título, aplicación, familia y hechos sin modificaciones. Condición exacta: intento AND violación AND (confirmación OR pago enviado sin outcome terminal seguro). Pago pendiente/ambiguo es definición operativa, no decisión de negocio.

| Caso | Intento | Violación | Confirmación | Enviado no terminal | Bloquear |
|---|---:|---:|---:|---:|---:|
| Confirmación lectura, sin intento | false | false | true | false | false |
| Modificar directamente en confirmación | true | true | true | false | true |
| Volver sin intento de cambio | false | false | false | false | false |
| Editar al regresar a selección antes del envío | true | false | false | false | false |
| Intento verdadero sin violación, pago ya enviado | true | false | false | true | false |
| Pago pendiente: intento violatorio desde selección | true | true | false | true | true |
| Pago ambiguo: intento violatorio en confirmación, cuatro hechos true | true | true | true | true | true |
| Confirmación con intento sin violación (operación permitida) | true | false | true | false | false |
| En selección, intento y violación señalada, sin contexto confirmado ni pago | true | true | false | false | false |
| Pago enviado no terminal, sin intento de cambio | false | false | false | true | false |
| Solo lectura en confirmación con pago no terminal | false | false | true | true | false |

No duplicados por tupla de los cuatro hechos. No se autoriza edición después de outcome terminal; solo se define el bloqueo mientras no hay terminal seguro. Binding real de Paulo pendiente.
