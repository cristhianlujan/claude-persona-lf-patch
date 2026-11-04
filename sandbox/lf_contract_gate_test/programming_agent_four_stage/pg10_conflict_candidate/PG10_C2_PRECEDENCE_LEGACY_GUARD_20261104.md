# PG-10_C2 — Precedencia y protección de nombres legados (04/11/2026)

## Criterio canónico
Consulta read-only a `programacion.engineering_work_checkpoints`:
- **PG-10_C2:** «Precedencia de 1.5; nunca renombrar legado sin migración aprobada».
- **Salida:** «Programación nunca redefine unilateralmente el objetivo para poder terminar».

## Fuente candidata
`tools/pg10_c2_precedence_legacy_guard_candidate_v1.py`, función `prepare_pg10_c2(pg10_c1, precedence_observations)`.

Consume el inventario tipado C1 existente, exige esquema/digest/estado de no-admisión y coincidencia exacta del universo de soluciones y conflictos. Rechaza observaciones de acciones con conflictos faltantes, duplicados o desconocidos.

Para `REQUIREMENT_GAP` solo admite `RETURN_PHASE1_A3`; para `EVIDENCE_GAP`, `QUERY_EXACT_MISSING_EVIDENCE`; para `CONFLICT`, únicamente preservación candidata del legado o diferimiento de precedencia. Ninguna de esas opciones cambia requisitos, resuelve un conflicto real ni ejecuta retorno a Análisis.

Para operaciones legadas, `RENAME` genera `BLOCK_UNAPPROVED_LEGACY_RENAME`; una referencia de migración declarada no equivale a aprobación autenticada. Se rechaza incluso una declaración de `migration_approval_authenticated=true` del invocador: la autenticación debe proceder de un mecanismo externo gobernado. `PRESERVE` conserva la intención reportada, sin modificar código.

## Límites
- Los materiales de C1 y las observaciones son declaraciones, **no lecturas de requisitos/estándares/contratos reales**.
- C2 **no determina la precedencia normativa de 1.5** sin obtener el texto aplicable y sus versiones. No crea autoridad ni inventa una jerarquía entre fuentes.
- No ejecuta cambios en repositorios o migraciones, no llama al Worker, no consulta Análisis, no publica a Supabase.
- `pg10_c2_pass=false`, `pg10_c2_admitted=false`, `production_authority=false`, `handoff_allowed=false` en toda salida candidata.

## Deuda técnica diferida
1. Leer y fijar versión/digest del texto auténtico de precedencia 1.5 y de los contratos legados.
2. Ejecutar pruebas positivas/negativas y cadena C1→C2 en HEAD exacto, además de revisión independiente.
3. Integrar consulta gobernada de aprobación de migración para que solo un comprobante auténtico permita un renombrado futuro.
4. Registrar evidencia por solución, verificar rutas hacia PG-10_C3 y no marcar el checkpoint como PASS antes del dictamen.

**Estado:** `PG10_C2_SOURCE_PREPARED / NO_REAL_PRECEDENCE_APPLIED / OFFICIAL_PENDING`.

**Siguiente desarrollo:** PG-10_C3; mantener PR #3528 en draft. Sin escribir Análisis, Supabase ni main.
