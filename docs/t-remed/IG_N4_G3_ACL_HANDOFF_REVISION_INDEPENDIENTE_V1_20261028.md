# HANDOFF — Revisión independiente G3 N-4 / ACL post-DDL (LF Input Governance)

**Fecha:** 2026-10-28  
**Emisor:** sesión productora (NO es revisor independiente)  
**Repositorio:** `cristhianlujan/claude-persona-lf-patch`  
**Rama:** `dev/ig-n4-tremed-cascade-governed-20261028`  
**PR:** [#3269](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3269), **DRAFT**.  
**Snapshot de código auditado inmediatamente ANTES de añadir este handoff:** `43bde01024e7f3ad369a670aa860de69ef9c7736`.  
**Commit exacto que contiene este documento:** consultarlo de nuevo por `get_pr_info` al iniciar la revisión; el usuario también lo facilitará. **No revisar un HEAD móvil**; congelar `commit_sha` y abortar o volver a iniciar si los archivos mutan.

## Mandato para el OTRO chat

Eres **revisor independiente**, NO el productor. **Solo lectura** sobre Supabase y GitHub; puedes ejecutar pruebas en una **base PostgreSQL 17.6 local efímera, completamente separada**, cuyo `Docker --network none` elimina el contenedor al terminar.

- No escribir en Supabase, ni GitHub, ni EKB; no invocar Router; no activar selectores, no mutar pantallas; no crear workflow ordinario en `.github/workflows/`, no elevar roles ni modificar allowlists de PASE.
- No realizar deploy, merge, PASE/Train, registrar recibos falsos ni iniciar reclasificación G5.
- El owner quiere **solo proceso prospectivo**. Diferencias de cobertura o selectores históricos se revisarán después pantalla por pantalla y no forman parte de la revisión.
- Antes de ejecutar, **leer EKB desde fuente viva** (no de memoria): `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `CI-MIGRATION-SOURCE-PARITY-001`, `IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001`.
- **No reutilizar el veredicto del productor.** Obtener los archivos y repetir las comprobaciones por cuenta propia. Si faltan permisos, binarios, contenedor o herramientas: **NO_VERIFICADO**, indicando la prueba exacta y el error, sin atribuir `PASS`.

## Archivos inmovilizados para comparar el contenido (Git blob SHA)

Todos bajo `sandbox/lf_contract_gate_test/input_governance/`:

| Archivo | Blob SHA (Git) |
|---|---|
| `ig_n4_clause_matcher_hardened_candidate_20261028.sql` | `51c8242c99cd09b9f70b879acfe321e6302c7491` |
| `ig_n4_pg17_6_sanitized_fixture_20261028.sql` | `f13a1a00dbd9889eb0f07c076cfa166c62e8c4b1` |
| `ig_n4_preclass_synthetic_matcher_v2_20261028.sql` | `6eea0e09acb81e7b08752c4a73867c6d5b4514f7` |
| `ig_n4_pg17_6_acl_postddl_tests_20261028.sql` | `d6bc1f183d5b8388a78080f75ccc76dfe4c82ebf` |
| `ig_n4_docker_pg17_6_isolated_20261028.sh` | `d446b0ac1f22983a85a620b0ffff0351e943d2b8` |
| `ig_g3_active_selector_contract_and_consumer_guard_20261028.sql` | `b4e69dc9a36ca6559850c9f019903a860523c100` |

**Fuente y permisos AS-IS PostgreSQL remoto (solo SELECT):**
```sql
SELECT
 md5(pg_get_functiondef('programacion.fn_input_rule_selector_matches_v1(jsonb,jsonb)'::regprocedure)) AS selector_md5,
 md5(pg_get_functiondef('programacion.fn_input_rule_selector_clause_matches_v1(jsonb,jsonb)'::regprocedure)) AS clause_md5,
 md5(pg_get_functiondef('programacion.fn_input_effective_rule_links_v1(integer,text)'::regprocedure)) AS effective_md5,
 to_regprocedure('programacion.fn_input_rule_selector_clause_schema_valid_v1(jsonb)') IS NULL AS helper_absent;
```

Readback del productor, **no aceptarlo como prueba independiente**: MD5 `3b912c7872aceff83de24e9e8d1ad934`, `1123257c0c6c7eb1e2aa26783f3ccc0a`, `156247a925d74c6f4accd7a6d2508489` y `helper_absent=true`.

## Cadena de comprobación obligatoria, SIN SALTOS

| ID | Verificación a repetir independientemente | Criterio |
|---|---|---|
| I01 | Recuperar EKB, PR y **HEAD exacto** del usuario; leer seis fuentes por SHA | `PASS` solo si exactas y sin fuente deprecada |
| I02 | Leer el diff completo de PR; buscar `supabase/migrations/`, `supabase/functions/`, `.github/workflows/`, cambios de roles o datos en duro | `PASS` solo si no hay cambios operativos inesperados |
| I03 | Revisar `Docker runner` y fixture: `postgres:17.6`, `--network none`, `--read-only`, `--user postgres`, montaje `readonly`, sin credenciales, SQL sobre DB `lf_ig_n4_isolated_ci` | Fallar si se puede conectar a compartida o hay escritura remota |
| I04 | Inspeccionar candidato: una transacción `BEGIN/ROLLBACK`, dos funciones existentes y un helper; verificar no cambie signatures, `SECURITY INVOKER`, `IMMUTABLE` | No aprobar si cambia contrato o introduce hardcodes |
| I05 | `bash -n` al ejecutor; ejecutar el propio script en runner Docker permitido: `bash sandbox/lf_contract_gate_test/input_governance/ig_n4_docker_pg17_6_isolated_20261028.sh` | **Ejecución REAL obligatoria**; si no hay Docker → `NO_VERIFICADO` |
| I06 | Observar 28 líneas de vectores `Txx|...|PASS`; examinar positivos, negativos y `T28` role type | 28/28 PASS, sin omisiones |
| I07 | Medir paridad OLD vs candidate 14 selectores × 58 contextos sanitizados | `PARITY\|812\|52\|52\|0\|14\|58` |
| I08 | ACL **real** dentro del contenedor: tres invocaciones negativas bajo `SET LOCAL ROLE ig_n4_untrusted_acl_probe`; SQLSTATE 42501; tres positivas bajo `ig_n4_governed_acl_probe`; resultado de selector permitido=true y consumidor ajeno=false | Marcar `PASS` solo si el SQL se ejecutó realmente, no por presencia de permisos catalogados |
| I09 | Revisar `prosecdef=false`, `provolatile='i'`, esquema USAGE, y ausencia de ampliaciones implícitas de privilegios | ACL compatible dentro del entorno aislado |
| I10 | Otra conexión **después de ROLLBACK**: hashes de ambas funciones igual a preimage; helper ausente y los dos roles de prueba ausentes (`to_regrole() IS NULL`) | Cero persistencia de funciones o roles candidatos |
| I11 | Control negativo por mutación en **copia local efímera**: otorgar `USAGE` al rol no autorizado o cambiar un caso Txx esperado; el runner debe fallar, con diagnóstico concreto | Si no detecta mutación: `FAIL` |
| I12 | Repetir lectura de selectores vigentes **sin recorrer pantallas**: estructuras, tipos y cross-consumer del SQL auditor; separar resultados CURRENT de historia | 0 violaciones, no inferir autoridad de alcance |
| I13 | Releer PASE del **commit revisado**: no confundir `PASE SUCCESS` con validación del script ni con `MIGRATION_SOURCE_PARITY` si `skipped` | Informe de CI exact-head y de lo que **no** certifica |
| I14 | Dictamen final: G3-PG anterior, **G3-ACL nueva**, G3-integración, G4 autoridad prospectiva y G5 | No elevar resultados agregados sin evidencia de cada gate |

**No se puede usar** `ig_n4_isolated_pg_verifier_20261028.py` por sí solo para cerrar I08: ese verificador anterior **no incorpora la nueva prueba ACL**. Puede servir únicamente como validación adicional del baseline antiguo.

## Evidencia histórica (NO sustituye la ejecución I05–I11)

- GitHub Actions run `40741198646`, job `123002927376`: `PASS_G3_PG17_6_ISOLATED_28_VECTORS_812_PARITY_ROLLBACK` y `PARITY|812|52|52|0|14|58`. **Es anterior al nuevo test ACL**.
- PASE run `40752765796` de un HEAD previo: SUCCESS en entrypoint, pero el subjob `MIGRATION_SOURCE_PARITY` fue **SKIPPED**. El revisor debe verificar CI del HEAD congelado.
- Auditoría estática del productor sobre archivos del snapshot prehandoff: **15/15 comprobaciones**, incluidas coherencia de marcadores, orden ACL antes de `ROLLBACK`, fixture terminators, número de vectores y control de red. **No es PASS runtime**.
- Read-only vigente: 14 selectores ACTIVE, 17 cláusulas; 0 cláusulas básicas malformadas y 0 coincidencias con consumer ajeno. No constituye evaluación pantalla por pantalla.

## Riesgos específicos que el revisor DEBE intentar falsar

1. **Falso PASS por ACL de catálogo**: `has_function_privilege` puede dar `TRUE` a PUBLIC, pero carecer de `USAGE` del esquema; por eso exigir invocación SQL real como rol.
2. **Mutación del alcance por accidente**: la prueba no tiene permiso para convertir `es_transversal` o `governance_scope` en autorización universal.
3. **Recibos de gobernanza**: rutas G4 para `RULE_APPLICABILITY_CHANGE` no autorizadas, no equiparar `INPUT_GAP_PROPOSAL` a scope.
4. **Integración de 47 familias**: selector de familias distinto del matcher de reglas; no activar selector futuro ni evaluar 47 familias indiscriminadamente.
5. **Hash del live vs fixture**: fixture es snapshot sanitizado, no sustituto de fuente/ACL vivos; si cambian hash/version/selector, `STALE` y regenerar por ruta controlada.
6. **Test positivo o negativo que no llegó a ejecutarse**: evidenciar logs del subgate, no solo el `echo PASS` final. La mutación I11 prueba que el gate no es decorativo.
7. **Mismatches de SQL**: se requiere construir la transacción exacta y no ejecutar el fixture con `DROP TABLE` en una base compartida.

## Formato de devolución esperado al usuario, para devolver al productor

Tabla con `ID | función/comando ejecutado | fuente y evidencia literal | PASS/FAIL/NO_VERIFICADO | primer error | riesgo/regresión`. Incluir:
- SHA exacto revisado y SHA de **cada archivo**.
- Log propio del runner o bloqueo exacto por ausencia de Docker/permisos.
- Resultados ACL positivos/negativos, vector 28/28, paridad 812, rollback y mutation negative.
- Contradicciones entre docs y fuentes reales, con rutas y líneas.
- Dictamen **separado**: `G3_ISOLATED_ACL`, `G3_INTEGRATION`, `G4_RULE_SCOPE_AUTHORITY`, `G5_RECLASSIFICATION`.
- **No reparar ni escribir**: sugerir diff propuesto sin aplicarlo; el productor recibirá tu informe y corregirá. Si algo no verificable, marcar `NO_VERIFICADO`, nunca PASS por falta de error.

## Stop conditions

Interrumpir si: el código del HEAD no coincide con snapshot, se intenta SQL DDL en Supabase real, falta runner aislado autorizado, se intenta modificar roles reales, falla un requisito esencial de seguridad o el acceso al repo está bloqueado. Registrar exactamente la falla y todos los pasos no ejecutados; **no pedir privilegios extra para forzar PASS**.

**Objetivo:** verificar el nuevo test ACL y la integridad del proceso. **No reabrir pantallas históricas ni cerrar G4/G5 por analogía.**
