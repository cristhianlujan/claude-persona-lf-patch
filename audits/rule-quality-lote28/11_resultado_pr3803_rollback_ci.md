# L28 — PR #3803: resultado rollback PG18/PG17.6 y CI

**Estado de evidencia:** PASS en GitHub Actions aislado **para los tests descritos**, PR sigue **DRAFT / NO-GO / SIN MERGE**. No se acredita cambio o restauración sobre base actual o producción futura.

## Identidad y SHA
- PR: https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3803
- HEAD verificado: `607880071ffef18071d92f1979a93e270502e8b8` (PR abierto, DRAFT).
- **Un solo archivo migración original en PR**, sin cambios respecto al blob base: `supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql` blob `3b447b35f5aaad9d548e20255256513d9f27c19f`.
- Script inverso manual y **NO autopromovible**: `sandbox/lf_contract_gate_test/input_governance_lifecycle/rollback_ig_rule_lifecycle_writer_v2.sql` blob `841f6b26ecbddfe8c797be9b6398f8f6920e0308`.
- Test aislado: `sandbox/lf_contract_gate_test/edge_function_operation/test_ig_rule_lifecycle_rollback_pg18_pg176.py` blob `5ad2d1ac190d5e496a78a4a7fc3a88ff04760e96`.
- Manifiesto changeset clasifica ambos archivos nuevos: `sandbox/lf_contract_gate_test/changesets/LF-IG-RULE-WRITERS-PG18-V2.json`.

## Readback de GitHub Actions en HEAD final
| Control | Workflow run | Resultado verificado |
|---|---|---|
| LF Edge Operation R17 Tests | [43363123119](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43363123119) | **SUCCESS**, job `131681069596` |
| Rollback en PostgreSQL 17.6 | Mismo job | `PASS_PR3803_REVERSE_postgres_17.6 version=170006`, test `test_pg17_6 ... ok` |
| Rollback en PostgreSQL 18.7 | Mismo job | `PASS_PR3803_REVERSE_postgres_18 version=180007`, test `test_pg18 ... ok` |
| Suite R17 total | Mismo job | `Ran 211 tests in 25.808s` → `OK` (211 NO son solo rollback) |
| PASE | [43363122819](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43363122819) | **SUCCESS** |
| LF migration name classification | [43363122964](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43363122964) | **SUCCESS** |

## Qué probó el test inverso
1. Levanta contenedor PostgreSQL `postgres:18` y `postgres:17.6` por separado (sin proyecto Supabase ni credenciales).
2. Carga subconjunto SQL capturado de Supabase y aplica migración forward del PR.
3. Inserta un owner de prueba en tabla V2; verifica que el rollback **falla con `IG_ROLLBACK_NONEMPTY_V2_TABLES`** y no elimina el dato.
4. Retira la fila **solo en contenedor de prueba**, ejecuta rollback y compara el catálogo de las dos skills con su preimagen; verifica MD5 de seis funciones V1, que tablas nuevas y registry de promoción no permanezcan, y permisos restaurados a `service_role`.
5. Repetir rollback tras ya revertir debe fallar por ausencia de objetos. **Nada ejecutado en Supabase live**.

## Limitaciones relevantes al GO
- Es un subconjunto de tablas/funciones y roles simulado; no acredita backup físico, PITR, restore total, RPO/RTO, Edge/GitHub OIDC real, JWT firmado, juez independiente ni los 11 pasos E2E oficiales.
- El script **se bloquea deliberadamente con datos V2**; no es reversión post-operación con cambios irreversibles ni reemplaza preimagen SHA específica por cambio.
- El pase de Input Governance en base temporal continúa **Motor 0/7**, Contenido 0/5 e Infraestructura final 0/2. **Ningún bloqueo cerrado ni firma acreditada**.
- No activar etiqueta `ready-to-merge`, no merge, no autorizar producción con este lote.

**Conclusión verificable:** rollback PG18/17.6 en CI **PASS** y plan actualizado; el alcance de producción sigue **NO-GO**.
