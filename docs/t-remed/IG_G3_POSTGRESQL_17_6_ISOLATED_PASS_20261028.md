# LF Input Governance — G3 prueba efectiva PostgreSQL 17.6 aislada

**Fecha:** 2026-10-28 · **PR:** #3269 · **Resultado técnico aislado:** `PASS` · **G3 global:** `PARCIAL` · **G4:** `NO_VERIFICADO` · **G5:** `NO_RECLASSIFY`.

## 1. Evidencia externa de ejecución (no solo simulación)

**Ejecución exitosa:** GitHub Actions run `40741198646` / job `123002927376`, commit sujeto `efd74ce63cb4e87e51e091b8772371a9439c7d83`, job `n4-g3-isolated`, conclusión **success**. El log del job registra literalmente:

```
PASS_G3_PG17_6_ISOLATED_28_VECTORS_812_PARITY_ROLLBACK
PARITY|812|52|52|0|14|58
```

- Contenedor `postgres:17.6`, `--network none`, sin credenciales de Supabase, base efímera, directorio de pruebas de solo lectura, `tmpfs`, conexión por socket.
- El SQL original de las **dos funciones** se cargó desde un fixture sanitizado de 14 reglas y 58 pantallas. Se compiló y evaluó el candidato `CREATE OR REPLACE FUNCTION` de N-4 **dentro de la transacción de prueba**.
- Resultado de **28/28 vectores sintéticos**, 812 comparaciones del matcher original y candidato, **52 vs 52**, cero diferencias. El script exige `ROLLBACK` y comprueba, desde otra conexión, los hashes originales y ausencia del helper nuevo.
- La instancia se destruye al terminar. Esta prueba **no ejecuta ninguna DDL en Supabase real**.
- Antes de esta prueba, run `40741032265` / job `123002359210` detectó un defecto real: faltaban los `;` finales de las dos sentencias `CREATE FUNCTION` del fixture. Se corrigieron ambos en commit `efd74ce63cb4e87e51e091b8772371a9439c7d83` y se repitió la prueba hasta `success`.

## 2. Restauración de la política de workflows del repositorio

El workflow de prueba PR `.github/workflows/ig-n4-g3-isolated-pg-pr3269.yml` activó el guard del PASE por **workflow ordinario no incluido en allowlist**: run `40741031917`, fail en `Enforce single ordinary PR entrypoint`. **No se alteró la allowlist, el Router ni los controles del PASE** para forzar su aprobación.

La prueba aislada se ejecutó con éxito y luego **se eliminó el workflow temporal** en commit `be44553235f7340bbda5fbc21a8386675de6c60d`. El PASE posterior, run `40741315498`, mostró `Enforce single ordinary PR entrypoint = success` y completó las etapas normales de preparación sin que este agente ordenara merge ni deploy. **No introducir otro workflow ordinario temporal sin gobernanza.**

El runner `sandbox/lf_contract_gate_test/input_governance/ig_n4_docker_pg17_6_isolated_20261028.sh`, el fixture y el candidato siguen versionados en la rama de desarrollo. Se pueden reutilizar desde un runner autorizado, sin instalar un nuevo workflow.

## 3. Readback de Supabase vigente

Después de la prueba, se ejecutó consulta read-only:

| Función | MD5 vivo |
|---|---|
| `fn_input_rule_selector_matches_v1(jsonb,jsonb)` | `3b912c7872aceff83de24e9e8d1ad934` |
| `fn_input_rule_selector_clause_matches_v1(jsonb,jsonb)` | `1123257c0c6c7eb1e2aa26783f3ccc0a` |
| `fn_input_effective_rule_links_v1(integer,text)` | `156247a925d74c6f4accd7a6d2508489` |

El helper `fn_input_rule_selector_clause_schema_valid_v1(jsonb)` **no existe en producción**, como corresponde a un candidato no desplegado. No hubo cambios en Supabase.

## 4. Qué cierra y qué NO cierra esta evidencia

| Subgate | Dictamen |
|---|---|
| **G3-PG aislado:** compilación del SQL candidato | **PASS** en contenedor PostgreSQL 17.6 desechable |
| **G3-PG aislado:** 28 vectores adversariales | **PASS** |
| **G3-PG aislado:** baseline 14 × 58 y rollback | **PASS** |
| **G3-P07:** consultas `MATERIALIZED` / benchmark read-only | **PASS observacional**, no certificación de p95 |
| **G3 integración:** ACL, contratos de consumidores, 13×47 y revisión independiente | **PENDIENTE** |
| **G4:** autorización funcional de aplicabilidad con firma/recibo legítimos por regla/selector | **NO_VERIFICADO** |
| **G5:** catálogo/reclasificación y cutover | **BLOQUEADO** |

**No usar este PASS técnico para autorizar una ampliación de scope, para activar el helper en producción, para eliminar `DERIVED_GLOBAL` ni para fusionar PR.** Fuente EKB: `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `CI-MIGRATION-SOURCE-PARITY-001`.

## 5. Auditoría adicional de ACL en fuente real (solo lectura)

En Supabase se verificaron `pg_proc.prosecdef/proacl/proconfig`, `pg_namespace.nspacl` y privilegios efectivos. Las funciones selector/clause actuales son `SECURITY INVOKER`, `IMMUTABLE`, dueño `postgres`; no tienen `proacl` explícito. PostgreSQL permite `EXECUTE` por defecto a PUBLIC, **pero** `programacion` tiene `USAGE` restringido. Comprobación `SELECT` por rol:

| Rol | `USAGE(programacion)` | `EXECUTE` matcher |
|---|---|---|
| `anon`, `authenticated`, `service_role` | FALSE | TRUE por grant implícito de función, **sin uso del esquema** |
| `programacion_builder`, `auditor`, `verifier`, `human_authority`, `promoter`, `test_generator` | TRUE | TRUE |

**Implicación:** al introducir el helper candidato debe preservar los límites efectivos de esquema y comportamiento de invocador; conceder o revocar `EXECUTE` arbitrariamente sin análisis podría abrir una superficie o interrumpir al matcher. La compilación aislada se ejecutó como dueño local del contenedor; **no constituye prueba de ACL con todos los roles reales**. Antes de release: comparar `nspacl/proacl/prosecdef/proconfig` pre/post y ejecutar positivos/negativos de permisos con roles equivalentes en ambiente autorizado. `G3_ACL_INTEGRATION=PENDING`.

Este hallazgo tampoco concede permiso de publicar selectores: G4 exige autoridad de scope independientemente de ACL técnica.
