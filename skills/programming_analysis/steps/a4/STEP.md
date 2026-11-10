# A4 · Impacto de cambio con fuentes deterministas

**Estado:** implementación candidata. Sin RUN/atestación, sin autorización A5, sin escritura en Supabase. La ejecución real sigue gobernada por Router/perfil/skill.

## Qué recibe y de dónde
Contrato cerrado: `contracts/deterministic_source_set_v1.json`.

| Orden | Fuente existente | Uso | Si falta |
|---|---|---|---|
| S1 | A3 `TARGETED_EVIDENCE_SET_V1` | Inventario vigente, excluidos, políticas, material y AS-IS exacto | `BLOCKED` |
| S2 | A2 `ANALYSIS_CHANGE_CLASSIFICATION_V1` | Operación y objetivo solicitado | `BLOCKED` |
| S3 | `inventory.objects` por `object_ref` **exacto y activo** | Solo para componentes existentes con binding verificado | En pantalla nueva, **no requerido** |
| S4 | `inventory.fn_impact_analysis_v1(object_ref,3,0.80)` | Impactos de componentes existentes; lectura condicional | No se invoca para un destino inexistente |
| S5 | `inventory.fn_dependencies_v1(object_ref,'BOTH',2)` | Dependencias de componentes existentes; lectura condicional | No se invoca para un destino inexistente |

- Los valores 3, 0.80 y 2 reproducen los **defaults observados** de las funciones existentes; no crean heurísticas nuevas.
- **Modo PLANNED_BUILD:** cuando A2 expresa intención de crear/implementar una pantalla nueva, A4 consume S1+S2 y produce obligaciones de implementación desde reglas VIGENTE sin política pendiente y elementos materiales VIGENTE. No exige código actual, archivo destino, repositorio elegido ni binding técnico; la intención no prueba por sí sola que no exista código relacionado.
- **Modo EXISTING_CHANGE:** solo cuando exista binding exacto a un objeto técnico, el host gobernado reúne readbacks S3/S4/S5 bajo `A4_EXISTING_IMPACT_CORE_READBACK_V1`.
- A4 **no realiza búsquedas** (ni GitHub, ni SQL libre, ni similitud textual, ni navegador). La falta de un destino técnico en pantalla nueva **no es un bloqueo**; la cobertura de dependencias existentes queda `UNKNOWN` hasta tener evidencia.
- La lista vacía de S4/S5 no prueba ausencia de impacto; para cambios sobre sistemas existentes devuelve `IMPACT_UNKNOWN`. Para desarrollo nuevo no se consultan S4/S5 sin binding material.
- La salida conserva `direct_impacts[]`, `indirect_impacts[]`, `consumers[]`, `dependency_paths[]`, `evidence_refs[]`, `unresolved_material_impacts[]` y `core_output_contract=SHARED_CHANGE_IMPACT_MAP_V1`.
- El modo nuevo devuelve `PLANNED_BUILD_IMPACT_UNATTESTED`, sin destino, no un delta de código. Solo se proyectan obligaciones fuente, se excluyen candidatas y se conserva el riesgo de dependencias no verificadas. El grafo, cuando hay objeto exacto, es impacto potencial. Ningún modo prueba implementación desplegada o autoridad: `source_attested=false`, `impact_verified=false`, `a5_allowed=false`.
- Un faltante material retorna únicamente el `source_id`, referencia exacta y causa; A8 puede pedir relectura focal a A3, sin reiniciar el inventario.

## Evidencia verificable
Se verificó en PostgreSQL la firma real de ambos proveedores y sus parámetros por defecto. `inventory.objects` tiene 6 671 registros activos y `inventory.dependencies` 14 048 dependencias activas en la lectura de 2026-11-09; no se encontró coincidencia por referencia `B2B-AUTH-001` o `B2B_AUTENTICACION`. Este resultado **no autoriza** afirmar que no existe implementación; tampoco obliga a asignar un destino al código todavía no desarrollado. Las dependencias sobre componentes ya existentes se revisan solo cuando hay binding exacto.

## Código
- `validators/run.py:run` — proyección genérica y cierre de búsqueda.
- `evals/test_a4_deterministic_source_set_v1.py` — trece tests sintéticos creados; ejecución CI exact-head pendiente.
- Manifiesto de la skill única: `skills/programming_analysis/contracts/analysis_skill_manifest_v1.json`.

## No hacer
No crear otro motor de impacto, no sustituir las funciones transversales ni ejecutar sentencias en A4, no consultar indiscriminadamente GitHub, no interpretar coincidencias numéricas o cadenas parciales como binding, no declarar `NO_CHANGE` o `NO_IMPACT` cuando la fuente no demuestra cobertura, no confundir SALY con LF.
