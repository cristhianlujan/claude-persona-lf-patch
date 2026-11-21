# F4 — Tipos y constantes generados desde el registro LF

**Criterio literal del plan:** `F4 · Del registro al código — Tipos y constantes generados desde el registro`. Un solo criterio, sin consumidores obligados a importar el nuevo artefacto. No se presenta como conformidad de implementación ni entrega de runtime de Paulo.

## Procedencia

- Fuente única de generación: `lf_ops.f4_tipos_catalogo_v1()`, función `STABLE SECURITY INVOKER` restringida a `service_role`, consulta `lf_ops.nucleo_familias` y `lf_ops.f0_valores_vocabulario_v1`.
- Artefacto: `sdk/lf_nucleo_catalog.generated.ts`, con tipos y constantes `as const` de los 64 códigos y tipos de familia, y 25 grupos de valores permitidos (94 literales) que derivan de `CHECK` ya registrados. No ediciones manuales.
- Generador determinista: `sandbox/lf_contract_gate_test/nucleo_ci/f4_codegen.py`, contrato JSON `LF_NUCLEO_TYPED_CATALOG_V1`, valida forma, unicidad y orden; falla cerrado ante tipo o enum inválido. El archivo de SDK se compara byte a byte con la salida de la BD real en PG17 aislado.
- No supone que los hechos lógicos tengan binding runtime, que las 14 SALY sean publicables, que exista programación cliente, o que una app consuma ya este archivo.

## Prueba obligatoria

- PG17 real en contenedor aislado y sin red: aplicar migración original con fixture de fuentes; leer catálogo; generar TS y cotejar el archivo versionado.
- Negativo causal: dentro de `BEGIN; INSERT` de familia `F4_MUTANTE_PG17`; la generación no debe coincidir; `ROLLBACK;` y verificar ausencia del mutante y coincidencia restaurada.
- Regresión: 17/17 autopruebas reales LF/SALY, mutante de puerta detectado, 17/17 tras rollback, paridad de `v_reglas_compat_v1` con legadas.
- Train y readback: PR fusionado con SHA; función con fuente y grants idénticos; 64/25/94 sin drift en catálogo; legadas/candidatas intactas.

## Fuera de alcance

A4/IG, juez/casuísticas F2b, los 150 vínculos ambiguos, lecturas runtime de Paulo, bindings por hecho propuestos, publicaciones, cierre de puertas, redirecciones de escritor o lector, F6.
