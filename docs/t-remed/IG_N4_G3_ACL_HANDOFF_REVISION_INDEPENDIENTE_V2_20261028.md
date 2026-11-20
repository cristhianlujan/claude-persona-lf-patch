# HANDOFF V2 — LF Input Governance N-4 / G3 ACL — revisión independiente

**Fecha:** 2026-10-28  
**PR:** #3269 (DRAFT, NO-GO)  
**Repositorio:** `cristhianlujan/claude-persona-lf-patch`  
**Rama:** `dev/ig-n4-tremed-cascade-governed-20261028`  
**Snapshot técnico inmediatamente ANTES de agregar este handoff:** `eb7f80dc8203ac8c462b98cd47784ad0185af1bb`.  
**Commit de revisión:** recuperar y congelar el `head_sha` del PR una sola vez; usar ese commit exacto durante TODA la revisión, no un HEAD móvil.

## Motivo de la V2

Sustituye el paquete V1 únicamente para verificar las correcciones de los hallazgos de auditoría H01–H04. No reutilizar los veredictos del productor ni considerar que PASE SUCCESS certifica PostgreSQL o ACL.

## Evidencia de fuente exacta: Git blob SHA

Directorio base: `sandbox/lf_contract_gate_test/input_governance/`.

| Archivo | Git blob SHA |
|---|---|
| `ig_n4_clause_matcher_hardened_candidate_20261028.sql` | `51c8242c99cd09b9f70b879acfe321e6302c7491` |
| `ig_n4_pg17_6_sanitized_fixture_20261028.sql` | `f13a1a00dbd9889eb0f07c076cfa166c62e8c4b1` |
| `ig_n4_preclass_synthetic_matcher_v2_20261028.sql` | `6eea0e09acb81e7b08752c4a73867c6d5b4514f7` |
| `ig_n4_pg17_6_acl_postddl_tests_20261028.sql` | `debe6380af8df01093fa20bbce807ab3d7a46d06` |
| `ig_n4_docker_pg17_6_isolated_20261028.sh` | `0daef2260bcbc4777daa94c68e713ae6c6fe831d` |
| `ig_g3_active_selector_contract_and_consumer_guard_20261028.sql` | `bbc840441026f718057ec54013868785db49359f` |

## Cambios ejecutados en la rama DRAFT

1. **H01** — El runner exige identidad y unicidad de T01–T28, además de `PASS` y forma de salida. Mutación local de 28 repeticiones de T01 rechazada; control de IDs T01–T28 aceptado en prueba local de Bash, **no** PostgreSQL.
2. **H02** — El auditor SELECT inspecciona tipos de consumer_roles, claves inesperadas, rutas, operaciones y valores de cláusulas. En Supabase solo lectura: **CURRENT** `14 ACTIVE / 0 invalid_outer_schema / 0 malformed_clauses / 0 unauthorized_consumer_matches / 17 clauses`. Contraprueba sintética controlada: `1 invalid_outer_schema / 1 malformed_clauses`. No es certificación de aplicación futura.
3. **H03** — Se añadió observación del default `PUBLIC EXECUTE` del helper y **simulación restrictiva separada dentro de ROLLBACK** (`REVOKE FROM PUBLIC`, `GRANT` a rol gobernado). La simulación NO representa permisos que ya estén desplegados; falta ejecutar en PG y acordar política productiva de EXECUTE sin romper consumidores existentes.
4. **H04** — El runner exige observaciones reales por función/rol/SQLSTATE, conserva T01–T28 y logs de error al fallar el SQL, no solo el mensaje final de PASS.

**Commits de reparación:** `375ba9b13db43bee93875089325fb35d39bea843`, `43361184c0614ca630201ede8615f6bb175a4b39`, `28b53f20106581ee96ff1c052b900130506e25ee`, `eb7f80dc8203ac8c462b98cd47784ad0185af1bb`.

**CI del snapshot técnico `eb7f80d`:** run `40765107581` PASE SUCCESS, job `123087027837` SUCCESS, `PASE / MIGRATION_SOURCE_PARITY` job `123087170324` SKIPPED. No atribuir PASS a pruebas omitidas.

## Obligaciones de revisor independiente I01–I14

- **I01:** Recuperar EKB vivo: `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `CI-MIGRATION-SOURCE-PARITY-001`, `IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001`; PR y los seis blobs en el commit exacto.
- **I02:** Leer diff PR completo; buscar modificaciones fuera del sandbox/doc, migraciones, functions, workflows y permisos reales.
- **I03:** Revisar runner Docker sin red `postgres:17.6`, usuario no root, mount readonly, DB `lf_ig_n4_isolated_ci`, sin conexión Supabase.
- **I04:** Revisar código SQL candidato, funciones existentes, helper nuevo, preimage, transacción reversible y no hardcodes de negocio.
- **I05:** Ejecutar `bash -n` y `bash sandbox/lf_contract_gate_test/input_governance/ig_n4_docker_pg17_6_isolated_20261028.sh` en entorno seguro con Docker y la imagen disponible. **Este productor NO lo ejecutó por ausencia de Docker**.
- **I06:** Observar 28 IDs T01–T28 únicos, resultados completos reales; repetir una mutación de duplicación T01.
- **I07:** Comprobar `PARITY|812|52|52|0|14|58` con datos sanitizados y las dos funciones (OLD vs candidate) ejecutadas.
- **I08:** Verificar 3 negativas reales SQLSTATE 42501 y 3 positivas, más allowed=true / cross-consumer=false. Distinguir pruebas con permisos AS-IS del `RESTRICTED_SIM`.
- **I09:** Verificar `prosecdef=false`, `provolatile='i'`, USAGE de esquema, EXECUTE real, default PUBLIC; **no aprobar un cambio a ACL productiva por inferencia**.
- **I10:** En otra conexión posterior a ROLLBACK, exigir hashes preimage iguales, helper ausente, y **tres** roles de ensayo ausentes.
- **I11:** Introducir mutación negativa en copia local descartable, preferiblemente ACL SQL y Txx; verificar fallo efectivo del runner, no solo una condición lógica simulada.
- **I12:** Ejecutar auditor CURRENT en SELECT, casos adversariales y aislamiento cross-consumer; excluir reevaluación histórica de pantallas.
- **I13:** Leer PASE del commit exacto; distinguir SUCCESS entrypoint, `MIGRATION_SOURCE_PARITY SKIPPED` y ejecución real de G3.
- **I14:** Emitir cuatro dictámenes separados: `G3_ISOLATED_ACL`, `G3_INTEGRATION`, `G4_RULE_SCOPE_AUTHORITY`, `G5_RECLASSIFICATION`. NO atribuir PASS a evidencias del productor.

## Límites y estado de liberación

**G3 PostgreSQL/ACL runtime: NO_VERIFICADO. G3 integración: NO_VERIFICADO. G4 autoridad por regla: pendiente. G5 reclasificación: BLOQUEADA.**

No cambios a Supabase, Router, EKB, migraciones, workflows, pantallas o producción. No merge ni deploy. No registrar un PASS sobre un marcador artificial, un test omitido o un reporte del productor. Si falta Docker/PG, declarar NO_VERIFICADO con comando y error literal.
