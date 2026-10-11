# LF D2 — Fachada y recibo gobernado (construcción, sin activación)

**Objetivo transversal:** publicar contratos de preparación de lectura y verificación de evidencia, sin SQL de negocio libre ni tablas por caso; los registros y políticas solo viven en Supabase.

## Componentes de esta entrega

- `private.fn_lf_d2_facade_request_plan_v1(source_ref,projection,filters,row_limit)`: solicita un descriptor de fachada desde el binding VIGENTE, validando previamente JSON, límite, columnas, filtros, read facade SECURITY INVOKER y estado canónico D2. Aun si devuelve descriptor, `execution_authorized=false`, `business_rows_accessed=false`. **No ejecuta** el RPC y nunca eleva privilegios.
- `private.fn_lf_d2_facade_receipt_readback_v1(receipt_id,source_ref,execution_id)`: relee la tabla existente `private.lf_evidence_ledger_v1` y compara estado, digest, política y estructura del recibo. Mantiene `business_answer_authorized=false`; sin readback de identidad/empresa/RLS no declara éxito de negocio. No crea ledger paralelo.

## Evidencia reversible

- Request planner: **9/9** negativos/ausencias de binding y entradas inválidas, ejecutados desde el archivo Git con `BEGIN ... ROLLBACK`. El guard ahora comprueba tipos JSON antes de cardinalidad; rechazo de `NULL`, array vacío, filtros no-objeto, presupuestos fuera de rango.
- Receipt: **2/2** negativas, mismas migraciones en `ROLLBACK`: como postgres, sin registro exacto = `BLOCK_CANONICAL_RECEIPT_NOT_FOUND`; como service_role, ledger sin ACL = `BLOCK_LEDGER_ACL_DENIED`. Ambas sin datos ni autorización.
- Pruebas **positivas reales** quedan pendientes de fuentes/bindings VIGENTE, identidad B2B, asignaciones y permisos (actualmente sin registros en sandbox). No se interpretan estas 11 pruebas como una lectura empresarial exitosa.

## Reglas de autoridad y siguientes dependencias

1. Mantener Supabase como catálogo/autoridad; código no crea bindings VIGENTE, no altera `lf_ops.permisos`, no escribe en `lf_activos`, no concede GRANT de `SELECT`, no modifica RLS.
2. Contrato para una fachada admitida: identidad autentificada, empresa de sesión verificada, denegaciones sobreponen permisos, read-only LIMIT y filtro, RLS aplicado, hashes/recibos exactos del ledger. No permitir SQL dinámico de tabla derivado de consulta textual.
3. Un readback de ledger para ejecución debe ser acotado por ejecución, recibo, actor y empresa, y tener un camino gobernado autorizado; el SELECT global a `service_role` **no** es la solución.
4. El estado de la **unidad 7 no cambia a COMPLETADA** hasta existir binding admisible y lectura positiva autorizada según contrato. Este macrolote solo cierra subcapacidad estructural.
5. El runtime D4 permanece inactivo y no se despliega. Benchmark/E2E pendiente, no probado por fixtures.

Sin Excel como base de información.
