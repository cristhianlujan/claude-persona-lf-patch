# A4 · Impacto de cambio con fuentes deterministas

**Estado:** implementación candidata. Sin RUN/atestación, sin autorización A5, sin escritura en Supabase. La ejecución real sigue gobernada por Router/perfil/skill.

## Qué recibe y de dónde
Contrato cerrado: `contracts/deterministic_source_set_v1.json`.

| Orden | Fuente existente | Uso | Si falta |
|---|---|---|---|
| S1 | A3 `TARGETED_EVIDENCE_SET_V1` | Inventario vigente, excluidos, políticas, material y AS-IS exacto | `BLOCKED` |
| S2 | A2 `ANALYSIS_CHANGE_CLASSIFICATION_V1` | Operación y objetivo solicitado | `BLOCKED` |
| S3 | `inventory.objects` por `object_ref` **exacto y activo** | Vincular objetivo canónico A3 a identidad técnica | `IMPACT_UNKNOWN`, nunca «sin impacto» |
| S4 | `inventory.fn_impact_analysis_v1(object_ref,3,0.80)` | Impactos directos e indirectos | Gap específico |
| S5 | `inventory.fn_dependencies_v1(object_ref,'BOTH',2)` | Dependencias entrantes/salientes y consumidores | Gap específico |

- Los valores 3, 0.80 y 2 reproducen los **defaults observados** de las funciones existentes; no crean heurísticas nuevas.
- El host gobernado reúne readbacks existentes bajo `A4_EXISTING_IMPACT_CORE_READBACK_V1` con la identidad exacta de S3 y parámetros completos S4/S5.
- A4 **no realiza búsquedas** (ni GitHub, ni SQL libre, ni similitud textual, ni navegador). Si `A3.target_ref` no está vinculado de forma exacta a `inventory.objects.object_ref`, devuelve `IMPACT_UNKNOWN`.
- La lista vacía de S4/S5 no prueba ausencia de impacto; también devuelve `IMPACT_UNKNOWN` hasta acreditar cobertura/frescura.
- La salida conserva `direct_impacts[]`, `indirect_impacts[]`, `consumers[]`, `dependency_paths[]`, `evidence_refs[]`, `unresolved_material_impacts[]` y `core_output_contract=SHARED_CHANGE_IMPACT_MAP_V1`.
- El cálculo del grafo es **impacto potencial**: no prueba cambio conductual, implementación desplegada ni autoridad. `source_attested=false`, `impact_verified=false`, `a5_allowed=false`.
- Un faltante material retorna únicamente el `source_id`, referencia exacta y causa; A8 puede pedir relectura focal a A3, sin reiniciar el inventario.

## Evidencia verificable
Se verificó en PostgreSQL la firma real de ambos proveedores y sus parámetros por defecto. `inventory.objects` tiene 6 671 registros activos y `inventory.dependencies` 14 048 dependencias activas en la lectura de 2026-11-09; no se encontró coincidencia por referencia `B2B-AUTH-001` o `B2B_AUTENTICACION`. Este resultado **no autoriza** afirmar que no existe implementación: hay una brecha de binding entre identidad funcional y técnica, no una prueba negativa de código.

## Código
- `validators/run.py:run` — proyección genérica y cierre de búsqueda.
- `evals/test_a4_deterministic_source_set_v1.py` — ocho tests sintéticos creados; ejecución CI exact-head pendiente.
- Manifiesto de la skill única: `skills/programming_analysis/contracts/analysis_skill_manifest_v1.json`.

## No hacer
No crear otro motor de impacto, no sustituir las funciones transversales ni ejecutar sentencias en A4, no consultar indiscriminadamente GitHub, no interpretar coincidencias numéricas o cadenas parciales como binding, no declarar `NO_CHANGE` o `NO_IMPACT` cuando la fuente no demuestra cobertura, no confundir SALY con LF.
