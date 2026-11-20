# IG 2026-11-18 — NIUBIZ correo técnico único por cliente

## Alcance efectivamente preparado

Decisión del dueño: email técnico enviado exclusivamente a Niubiz con patrón `nombre.apellido.lf-codigo@gmail.com`. El correo real del cliente continúa siendo destino del recibo (`R-PAY-043`). Rebotes aceptados como resultado operativo reportado; no se infiere validación del proveedor ni autorización de producción.

Fuente consultada: `public.lf_global_config` (11 filas), `lf_ops.reglas` (579 filas), funciones desplegadas, referencia de arquitectura IG V1.4, y `lf_ig_rule_owner_decide_v2` vigente. HEAD al comienzo de este lote: `d7b86c0bc5feaddca581d96e9b889a2f5d6fd59e`.

**Hallazgo bloqueante verificado:** `R-PAY-040`, `R-PAY-041`, `R-PAY-043`, `R-PAY-045` no existen en `lf_ops.reglas`; tampoco se encontraron códigos `R-PAY-*` en `public.lf_product_rules` ni `public.lf_prevention_rules`. No se puede ejecutar `CORRECT_VIGENTE/FUNCTIONAL` ni obtener MD5 de reglas inexistentes. No se fabricó RUN padre, aprobación V2, recibo del Train ni PASS de sandbox.

## Cambio autorizado de configuración

| Elemento | Antes observado | Después proyectado por migración |
|---|---|---|
| `PAGOS/NIUBIZ_EMAIL_GENERICO` | `niubiz-generico@lf-ficticio.invalid`, `EMAIL/FICTICIO` | **Retirado**, por ser global, no único por cliente y ficticio |
| `PAGOS/NIUBIZ_EMAIL_TEMPLATE` | Ausente | `{nombre}.{apellido}.lf-{codigo}`, `TEXT/REAL` |
| `PAGOS/NIUBIZ_EMAIL_DOMAIN` | Ausente | `gmail.com`, `TEXT/REAL` |
| `lf_global_config` | 11 (AUTH 10, PAGOS 1) | 12 (AUTH 10, PAGOS 2) |
| `lf_ops.reglas` | 579 | 579, sin DML |

`REAL` acredita parámetro decidido, **no** correo entregable, cuenta Gmail creada, ni aprobación Niubiz. El usuario o consumidor final debe conservar separadamente el email real para el recibo. La plantilla no se concatena en el cliente como sustituto de la dirección de recibos.

## Propuesta funcional sin registro V2 (NO EJECUTADA)

- **R-PAY-040 (bloqueada: activo ausente):** para toda operación Niubiz, construir email técnico único estable usando los parámetros `PAGOS/NIUBIZ_EMAIL_TEMPLATE` y `PAGOS/NIUBIZ_EMAIL_DOMAIN`; no reutilizar email global y no reenviar el correo del cliente como identificador Niubiz. Normalizar nombres a minúsculas, sin tildes, espacios ni símbolos inválidos; código debe ser corto, estable y único por cliente, derivado de identidad interna, no del monto ni de cada transacción. El primer carácter debe ser una letra para no provocar el fallo observado con dígitos.
- **R-PAY-041 (bloqueada: activo ausente):** reusar determinísticamente el mismo identificador técnico para el mismo cliente, distinto para clientes distintos, verificando colisiones y longitud válida antes del intento. Si faltan identidad, código o parámetros, bloquear el intento Niubiz con error trazable; no usar email compartido ni inventar códigos. Mantener un campo distinto para `receipt_email=correo_real_cliente`.
- **R-PAY-043 (no intervenida):** los recibos van al email real del cliente. La regla fuente no está registrada aquí; no se declara verificada.
- **R-PAY-045 (pendiente sandbox):** verificar con Niubiz que el guion `-` funciona en el identificador local `lf-codigo` del formulario alojado. Se debe registrar PASS real, rechazo explícito o alternativa autorizada. Actualmente **NOT_TESTED**.

## Restricción externa verificada: Gmail

La [documentación oficial de Gmail](https://support.google.com/mail/answer/9211434?hl=es) indica que los nombres de usuario `@gmail.com` **no pueden contener guiones (-)** y deben tener entre 6 y 30 caracteres. Por tanto, el formato literal solicitado `nombre.apellido.lf-codigo@gmail.com` **no puede registrarse como una cuenta Gmail nueva**; se mantiene como parámetro decidido, **no como dirección entregable ni identidad de buzón real**. Como el dueño acepta rebotes, este hecho no altera el formato aprobado, pero convierte en obligatoria la validación de aceptación del identificador por **Niubiz sandbox** antes de usarlo en checkout; además deben validarse privacidad y límites de longitud. No declarar PASS del proveedor por haber pasado un test PostgreSQL.

## Riesgos no cerrados

1. **Guion sin prueba en Niubiz:** no se declara PASS ni que la interfaz deja de temblar. El fallo de inicio numérico proviene del reporte operativo del dueño, no de un ensayo controlado.
2. **Correo gmail.com no administrado:** el patrón no crea buzones ni acredita titularidad. Una dirección podría pertenecer a otra persona y recibir mensajes de Niubiz; evaluar privacidad, políticas y tratamiento de errores antes de producción.
3. **Colisiones / limitaciones:** si `codigo` no es globalmente único y persistente, la plantilla no garantiza unicidad. Gmail ignora los puntos del nombre de usuario a efectos de recepción. Probar longitudes y normalización, incluso nombres vacíos.
4. **Consumidor no adaptado:** la migración solo cambia configuración; no hay prueba del SDK/checkout ni del tratamiento de rebotes. Se prohíbe afirmar funcionalidad activa en producción.
5. **Ruta V2 pendiente:** para cada regla existente se requiere RUN de Product Director autorizado, Step40/50/60/70, patch exacto `FUNCTIONAL`, evidencia técnica `RULE_CONTRACT_LEVEL` del Train vinculada al snapshot, decisión individual del usuario `Cristhian Lujan`, invocador/hijo oficial, finalizador y readback de SHA. El dueño no autorizó saltarse V2.

## Evidencia y verificación

El workflow dedicado utiliza PostgreSQL 17 y 18 efímeros, checkout en HEAD exacto, `BEGIN` y `ROLLBACK` reales para la migración, cuatro escenarios negativos, SELECT de proyección y una conexión independiente posterior para comprobar restauración total de configuración y 579 reglas. El reporte de CI aporta hashes de origen y prueba; **solo será evidencia de PASS cuando el check termine y el reporte sea legible**. El Merge Train es la única vía de incorporación; no usar merge directo ni tocar `protect-main`.

El readback live posterior al Train debe comprobar la migración aplicada, filas 12, reglas 579 y persistencia/identidad de cada parámetro. Hasta entonces el estado es PREPARADO, NO DESPLEGADO.
