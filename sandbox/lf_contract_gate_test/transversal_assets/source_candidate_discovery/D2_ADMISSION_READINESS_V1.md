# D2 — Diagnóstico canónico de admisión y acceso (sin lecturas empresariales)

Función `private.fn_lf_d2_admission_readiness_v1(text)`. Composición de contratos existentes de D2, generador de candidatos, `pg_catalog`, metadatos RLS y contexto JWT. **No reemplaza un permiso efectivo ni ejecuta una lectura de filas.**

## Resultado
Para cualquier referencia `db://schema.object`, indica:
- fuente física exacta, RLS, FORCE RLS y existencia de GRANT SELECT para `authenticated`;
- número de definiciones de política aplicables, incluyendo políticas estáticas con `qual=false`, sin confundirlas con autorización efectiva;
- estado real del binding D2 y posibilidad de generar un candidato no admitido;
- presencia de sesión autenticada; falta de comprobación de empresa/permiso bajo identidad real;
- falta de readback gobernado de recibos si `service_role` no puede consultar el ledger.

Los códigos de salida distinguen `BLOCK_INVALID_CANONICAL_SOURCE_REF`, `BLOCK_EXACT_PHYSICAL_SOURCE_NOT_IN_CURRENT_CATALOG` y `REQUIRES_GOVERNED_SOURCE_AND_ACTOR_ADMISSION`. **La ausencia del objeto exacto no agota el descubrimiento global.**

## Pruebas y límites
Suite SQL read-only con ROLLBACK: 6/6 PASS, incluyendo dos fuentes de cargas, otra familia, objeto ausente, URI obsoleta y NULL. Se comprueba `business_data_access_authorized=false`, `business_rows_accessed=false`, `runtime_enabled=false`, `effects_executed=false`, `global_discovery_exhausted=false`.

No modifica `lf_ops`, no concede permisos, no altera RLS, no inserta bindings y no activa el worker. `service_role` solo puede ejecutar el **diagnóstico** privado; jamás se interpreta eso como permiso empresarial.

### Cierre pendiente
La unidad 7 exige un binding legítimo `VIGENTE` y al menos una fachada aprobada bajo autorización real. Sin usuarios empresariales activos/asignados no existe prueba positiva/negativa fiable de empresa. La unidad 8 requiere demostrar SELECT parametrizado con sesión real y RLS sin bypass; la 9 requiere readback del ledger por ruta gobernada, no GRANT global.

No usar Excel para almacenar o decidir políticas.
