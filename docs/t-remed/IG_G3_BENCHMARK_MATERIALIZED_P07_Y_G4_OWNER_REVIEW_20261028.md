# LF Input Governance — G3 benchmark MATERIALIZED y revisión G4 de ownership
**Fecha 2026-10-28 · PR #3269 (draft) · Solo lectura Supabase · No Router/DDL/G5.**

## 1. Referencias exactas y método reproducible

- EKB leído antes de pruebas: `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `CI-MIGRATION-SOURCE-PARITY-001`.
- SQL **anterior**, blob Git SHA `1a07b9d415aa8f36a1cf9820e068ea0e2485d741`: `sandbox/lf_contract_gate_test/input_governance/ig_lote_a_p07_alcance_readonly_20261028.sql` anterior a optimización. Dos sentencias independientes, cada una recorre 58 pantallas mediante `fn_input_effective_rule_links_v1`.
- SQL **optimizado**, mismo archivo, blob Git SHA `59cfc560e39e57d3d03acec82e9405f2f14fe16a`: una sola sentencia con `targets`, `source_shells`, `derived`, `classified`, `groups`, `totals` `AS MATERIALIZED`. Las funciones vigentes de LF no fueron modificadas.
- Métrica obtenida usando PostgreSQL `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON, TIMING OFF)` sobre **consultas SELECT**; `Execution Time` de cada sentencia. Para legado se suma el tiempo de sus dos SELECT. Esta medición añade tiempo real de ejecución del lado PostgreSQL, **no** latencia de red/cliente ni tráfico concurrente representativo.
- La prueba alternó el orden de optimizado y legado en tres rondas para reducir el sesgo de caché. Valores de lecturas son `Shared Hit Blocks` observados; indican accesos a buffers, **no** lecturas físicas de disco.
- Solo 58 pantallas/241 reglas/8.852 enlaces heredados en corte; el resultado no certifica escalabilidad con catálogo significativamente mayor.

## 2. Resultados, medidos realmente

| Ronda | Orden | Legado: dos SELECT, ms | Optimizado: un SELECT, ms | Loops resolvedor antiguo/nuevo | Shared buffer hits antiguo/nuevo | Temp writes |
|---|---|---:|---:|---|---|---|
| 1 | legado-1 → nuevo → legado-2 | 2.418,390 | 1.218,332 | 116 / 58 | 213.692 / 106.719 | 0 / 0 |
| 2 | nuevo → legado-1 → legado-2 | 2.435,210 | 1.239,352 | 116 / 58 | 213.692 / 106.719 | 0 / 0 |
| 3 | legado-1 → nuevo → legado-2 | 2.417,786 | 1.234,079 | 116 / 58 | 213.692 / 106.719 | 0 / 0 |

Media de tres rondas: legado **2.423,795 ms**, nuevo **1.230,588 ms**, descenso observado de **49,23 %**. Medianas: legado **2.418,390 ms**, nuevo **1.234,079 ms**. Llamadas al resolvedor **-50 %**. No hubo spill a archivos temporales en estas pruebas. Un ensayo previo de una ronda adicional obtuvo legado 2.554,967 ms vs nuevo 1.514,577 ms; no se incluye en las medias para mantener rondas apareadas.

**No inferir** un ahorro garantizado del 49% en producción: el experimento no es una carga concurrente, no tiene múltiples tamaños de catálogo ni controla toda la actividad del servidor. Tampoco ejecutar migraciones o reclasificar por esta mejora.

## 3. Corrección y paridad, no solo velocidad

- La consulta optimizada retorna cuatro buckets excluyentes: **2.201 + 42 + 5.230 + 1.379 = 8.852**, 241 reglas y 58 pantallas; `partition_ok=true`. En el corte observado había 785 enlaces a pantallas inactivas. **Es dato de inventario, no decisión de eliminar/reglar.**
- Paridad N-4 de contexto materializado: **14 × 58 = 812**, **52 vs 52** coincidencias, cero diferencias. El SQL reproducible está en `ig_n4_active_selector_parity_readonly_20261028.sql`.
- La sombra SQL de validación usa MATERIALIZED para datos reutilizados y pasa **28/28** vectores en lectura; las funciones originales pasan **18/28** del nuevo contrato de diseño. No se ejecutaron las DDL del candidato.

## 4. Hallazgo G4: qué owner/registry existe realmente

Inspección **SELECT de metadatos**:
- `public.lf_capability_registry` contiene `owner_scope` (la capacidad `INPUT_GOVERNANCE` está bajo `LF_GOVERNANCE`), pero no una columna que vincule `rule_sha + selector_sha + competence_scope + receipt`.
- `public.lf_policy_versions` guarda `policy_sha/status/effective_at/source_ref`; `lf_operation_policy_bindings` guarda operación/política/rol de política, **no** un recibo de gerencia por regla/selector N-4.
- `programacion.input_governance_cohort_types/memberships` tiene `authority_ref` pero gobierna cohortes de pantallas de IG, no autoridad de herencia de regla.
- `programacion.fn_source_rule_authority` solo comprueba autorización **de estado/fuente de regla**; no cobertura.
- `programacion.fn_input_owner_decision_assertions` contiene rutas/reglas específicas B2B por código y pantalla, y rebind de assertions de runs; **no es** motor genérico de aprobación de scope. No reutilizar ni copiar sus hardcodes.
- Sin esquema demostrado para receipt individual de scope en las fuentes consultadas: `G4_AUTHORITY_BINDING_NO_VERIFICADO`. No se creó tabla nueva ni se adaptó guard técnico de `programacion` a otro repositorio por el nombre.

## 5. Salidas y gates

| Gate | Resultado real |
|---|---|
| P07 materialización y benchmark de solo lectura | **VERIFICADO**, menos loops y menor latencia en esta muestra |
| G3 paridad de selectores activos | **VERIFICADA en lectura**; no valida la DDL candidata |
| G3 compilación+ejecución candidato en PostgreSQL aislado | **NO_VERIFICADO**, binarios `psql/postgres` ausentes en entorno actual |
| G3 integración E2E, ACL, tests 13×47 | **PENDIENTES** |
| G4 vinculación owner/competencia/recibo reales | **NO_VERIFICADO** |
| G5 reclasificación | **BLOQUEADA**, no correr SQL que retire `DERIVED_GLOBAL` |

El reporte es evidencia de diagnóstico/performance. Se mantiene el SQL de sandbox reversible y fuera de `supabase/migrations`; no autoriza merge o deploy.
