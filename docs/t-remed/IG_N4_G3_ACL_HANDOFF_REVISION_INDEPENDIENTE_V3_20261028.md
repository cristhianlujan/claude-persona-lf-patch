# HANDOFF V3 — Revisión independiente LF IG N-4 / G3 ACL

**Fecha:** 2026-10-28 | **PR:** #3269 DRAFT / NO-GO | **Repo:** `cristhianlujan/claude-persona-lf-patch`
**Rama:** `dev/ig-n4-tremed-cascade-governed-20261028`
**Snapshot técnico previo a agregar este handoff:** `23e82006098617f172e1a3b2fbd56977629b2931`.
**Commit exacto a revisar:** obtener el `head_sha` después de incorporar este documento, inmovilizarlo, y verificar los seis blobs listados. No usar HEAD móvil.

## Antecedentes y límites

Esta versión sustituye V2 **para nuevos exámenes** tras corregir H05. No es certificación propia ni revalidación independiente. No escribir GitHub/Supabase/EKB/Router, no producir DDL remoto, workflow, migration, merge, publicación de permisos, reclass o pantalla. Fuera de alcance la revisión histórica de pantallas. Leer primero este paquete entero y luego EKB vivo.

## Six Git blob SHA — fuentes a verificar contra el commit congelado

Todos bajo `sandbox/lf_contract_gate_test/input_governance/`:

| Archivo | Git blob SHA |
|---|---|
| `ig_n4_clause_matcher_hardened_candidate_20261028.sql` | `51c8242c99cd09b9f70b879acfe321e6302c7491` |
| `ig_n4_pg17_6_sanitized_fixture_20261028.sql` | `f13a1a00dbd9889eb0f07c076cfa166c62e8c4b1` |
| `ig_n4_preclass_synthetic_matcher_v2_20261028.sql` | `6eea0e09acb81e7b08752c4a73867c6d5b4514f7` |
| `ig_n4_pg17_6_acl_postddl_tests_20261028.sql` | `debe6380af8df01093fa20bbce807ab3d7a46d06` |
| `ig_n4_docker_pg17_6_isolated_20261028.sh` | `b999ea52bc17d0f17feba3c9ae9b9615f5b3c863` |
| `ig_g3_active_selector_contract_and_consumer_guard_20261028.sql` | `bbc840441026f718057ec54013868785db49359f` |

## EKB vigente de lectura obligatoria

`IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `CI-MIGRATION-SOURCE-PARITY-001`, `IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001` desde `transversal.error_knowledge`. No convertir `es_transversal` en autoridad universal, `INPUT_GAP_PROPOSAL` en recibo scope, ni `PASE SUCCESS` en paridad ejecutada.

## Correcciones ya publicadas para falsar

- H01: conteo único estricto T01–T28 y forma de resultados.
- H02: auditor de selectores revisa estructura y claves/tipos de cláusulas; contraprueba SELECT previa observó malformed=1 e invalid_outer=1 para un fixture sintético adversarial.
- H03: distinguir ACL default PUBLIC EXECUTE del helper frente a `RESTRICTED_SIM` de `REVOKE/GRANT` dentro de transacción ROLLBACK, sin elevar ni mutar permisos remotos.
- H04: observaciones SQL por rol/función/SQLSTATE, sin aceptar el marcador final como única evidencia.
- **H05 nuevo:** se corrigió un falso positivo de evidencia: duplicación de marcadores agregados ACL/PARITY. El runner ahora exige `grep -Fxc ... -eq 1` para **cada** marcador agregado. Código fuente en commit `23e82006098617f172e1a3b2fbd56977629b2931`.
- Validación local efectivamente ejecutada: control Bash equivalente del bloque de salida, un positivo + nueve alteraciones negativas (T01 duplicado, T28 ausente, verdict falso, falta/duplicación ACL, paridad falsa, duplicación de marcador ACL, duplicación de paridad, marcador ACL omitido) => **10/10 expectativas correctas**. **NO** es ejecución del archivo completo, PG 17.6, ACL bajo roles ni mutación SQL.

## Cadena obligatoria I01–I14, sin omitir

| ID | Obligación y PASS requerido |
|---|---|
| I01 | Consultar EKB vivo y PR; congelar commit exacto y comparar 6 blobs SHA |
| I02 | Leer diff PR completo; inspeccionar paths `supabase/migrations/`, `supabase/functions/`, `.github/workflows/` y roles/permisos |
| I03 | Revisar `postgres:17.6`, `--network none`, `--read-only`, `--user postgres`, mount readonly y DB `lf_ig_n4_isolated_ci` |
| I04 | Inspeccionar BEGIN/ROLLBACK, 2 funciones existentes + helper, firmas, IMMUTABLE y SECURITY INVOKER, sin hardcodes de negocio |
| I05 | `bash -n sandbox/lf_contract_gate_test/input_governance/ig_n4_docker_pg17_6_isolated_20261028.sh`; ejecutar **ese** runner en Docker 17.6 aislado, no en Supabase |
| I06 | Verificar 28 observaciones T01–T28 únicas PASS, sin faltantes ni duplicados |
| I07 | Medir `PARITY|812|52|52|0|14|58`, 14 selectores × 58 contextos OLD vs candidate |
| I08 | Realizar 3 negativas 42501 + 3 positivas de invocación, allowed=true, cross-consumer=false; separar ACL base vs simulación restrictiva |
| I09 | Verificar `prosecdef=false`, `provolatile=i`, USAGE, EXECUTE explícito/default y no expansión accidental ACL |
| I10 | En conexión posterior a ROLLBACK confirmar 2 md5 preimage, helper ausente y 3 roles de test ausentes |
| I11 | Mutar copia local SQL (Txx/ACL); verificar que **runner real** rechaza y registrar error literal |
| I12 | Ejecutar auditor CURRENT SELECT, caso adversarial estructural, cross-consumer; sin recorrer pantallas históricas |
| I13 | Releer PASE del commit exacto, diferenciando `SUCCESS` y `MIGRATION_SOURCE_PARITY SKIPPED` |
| I14 | Dictámenes separados G3 isolated ACL, G3 integration, G4 rule scope authority, G5 reclassification; no suplir evidencia |

## Bloqueo local observado por productor

`docker`, `podman`, `postgres`, `psql`, `initdb`, `pg_ctl` ausentes; `unshare --net true` => `Operation not permitted`; `apt-get update` => `Temporary failure resolving 'deb.debian.org'`; descarga externa tarball 17.6 falló. No probar SQL DDL en Supabase ni reemplazar con PostgreSQL de otra versión. Si tampoco hay infraestructura en revisor independiente, declarar I05–I11 NO_VERIFICADO y registrar bloqueo exacto.

## As-IS de sólo lectura en Supabase

SELECT EKB y `pg_roles/pg_proc/has_function_privilege/has_schema_privilege` ejecutados: `prosecdef=false`, `provolatile='i'`, `proacl=NULL` en las 2 funciones actuales; `EXECUTE` vía PUBLIC sin schema USAGE efectivo para ciertos roles públicos. No inferir que esta fotografía represente grants del helper futuro ni el PASS de la simulación.

## Límites de cierre

**G3 PG17.6/ACL runtime NO_VERIFICADO; G3 integración NO_VERIFICADO; G4 autoridad funcional pendiente; G5 RECLASSIFICATION BLOQUEADO.** El resultado del productor y cualquier marcador aislado de éxito no sustituyen observaciones individuales. No merge/deploy.
