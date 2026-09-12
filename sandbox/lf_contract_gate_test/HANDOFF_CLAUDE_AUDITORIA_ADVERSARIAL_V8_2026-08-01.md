# HANDOFF — Auditoría adversarial independiente · PR #93 · Lote A V7

Fecha: 2026-08-01
Repositorio: `cristhianlujan/claude-persona-lf-patch`
PR objetivo: `#93`
Rama: `lf/architecture-v7-hardening`
Supabase producción: `mhwmirqcgxxukpctffuv`

## Estado que no debe confundirse

- El Lote A V7 está versionado en GitHub.
- Ningún objeto, migración, clave o Edge V7 está desplegado en producción.
- Producción continúa con Edge V6 y cierre `NOT_READY`.
- No existe una rama Supabase preview porque el owner no autorizó acciones con costo.
- Los checks de GitHub están verdes, pero no prueban que las migraciones puedan aplicarse ni que los controles funcionen en runtime.

## Mandato

Realizar una auditoría adversarial independiente del código actual del PR. No aceptar la descripción del PR, vistas, eventos, baseline, comentarios o estados almacenados como evidencia.

El objetivo es intentar demostrar que todavía existe una ruta para:

- fabricar reconciliaciones o gates autoritativos;
- obtener PASS/promoción con evidencia histórica;
- reutilizar nonces;
- acceder a la clave HMAC con un rol API;
- ocultar reconciliaciones compensatorias;
- declarar cierre mediante métricas heredadas de V5/V6;
- conservar privilegios temporales o memberships después de las migraciones;
- alterar evidencia append-only;
- falsear branch protection, despliegue Edge o baseline.

## Fuente principal

Auditar literalmente el `head_sha` vigente del PR #93. No usar hashes antiguos citados en conversaciones anteriores.

Revisar especialmente:

1. `supabase/migrations/20260801175950_prepare_v7_object_owners.sql`
2. `supabase/migrations/20260801180000_writer_hmac_nonce_v7.sql`
3. `supabase/migrations/20260801180100_quarantine_compensating_evidence_v7.sql`
4. `supabase/migrations/20260801180150_trusted_v7_readback_grants.sql`
5. `supabase/migrations/20260801180200_governance_role_and_rls_v7.sql`
6. `supabase/migrations/20260801180300_static_audit_corrections_v7.sql`
7. `supabase/migrations/20260801180305_prepare_idempotency_owner_context.sql`
8. `supabase/migrations/20260801180310_v7_idempotency_guards.sql`
9. `supabase/migrations/20260801180315_v7_row_integrity_guards.sql`
10. `supabase/migrations/20260801180320_cleanup_idempotency_owner_context.sql`
11. `supabase/migrations/edge_functions/lf-github-reconcile-v3-v7/index.ts`
12. `sandbox/lf_contract_gate_test/PR93_WRITER_V7_ADVERSARIAL_TESTS.sql`
13. `sandbox/lf_contract_gate_test/PR93_V7_READBACK.sql`
14. `sandbox/lf_contract_gate_test/RUNBOOK_PR93_LOTE_A_V7.md`
15. `.github/workflows/lf-github-reconcile-v3.yml`

## Diseño declarado que debe intentarse refutar

### Identidad

- La Edge acepta únicamente OIDC de GitHub Actions.
- Debe verificar repositorio, repository ID, audiencia, workflow, ref `main`, evento y run identity.
- `service_role` es necesario para llamar los RPC, pero no debe ser suficiente para fabricar evidencia.

### HMAC

- La Edge usa `LF_RECONCILIATION_WRITER_HMAC_V7`.
- PostgreSQL verifica contra una única fila activa de `private.lf_writer_hmac_keys_v7`.
- Esa tabla debe ser propiedad de `postgres`, tener RLS/FORCE RLS y cero privilegios para `anon`, `authenticated`, `service_role`, `lf_governance_owner_v3` y `lf_writer_verifier_v7`.
- No se utiliza Vault porque actualmente `service_role` puede leer y modificar secretos de Vault.
- La clave nunca debe aparecer en eventos, payloads, logs, vistas, baseline, respuestas RPC o GitHub.

### Nonce

- Formato UUID v4 + expiración Unix.
- Ventana máxima de seis minutos.
- Consumo único mediante PK de `nonce_sha256`.
- Un control positivo debe aceptar una firma válida antes de interpretar los controles negativos.
- Replay, expirado, futuro, firma incorrecta, claims ausentes y claims `anon` deben ser rechazados.

### Evidencia

- Writers V5/V6 no deben ser ejecutables por roles API después del cutover.
- PASS exige protección nativa `VERIFIED` y `actual_branch_protection_status=VERIFIED`.
- Gate PASS exige reconciliación V7 correspondiente.
- Reconciliaciones compensatorias y PASS pre-V7 deben estar en cuarentena append-only.
- Promoción solo acepta V7 no cuarentenado, misma ejecución, commit, workflow y gates.

### Idempotencia

- Una fuente `artifact_id + workflow_run_id + merge_commit_sha` solo puede producir una reconciliación V7.
- Un reintento con el mismo preimage debe devolver la fila existente.
- Un preimage diferente para la misma fuente debe generar conflicto.
- Los gate tests aplican el mismo criterio sobre su clave natural existente.

### Cierre

- `v_lf_architecture_closure_v8` debe reconstruir métricas desde evidencia primaria V7.
- No debe depender de `token_control_ready`, writer V5/V6 ni PASS almacenado.
- Debe bloquear por:
  - evidencia V7 incompleta;
  - clave ausente o accesible por API;
  - membresías residuales;
  - Edge V7 sin readback de control plane;
  - ruleset ausente;
  - grants API en `net`;
  - drift/baseline;
  - notificaciones o hallazgos internos abiertos.

## Auditoría estática obligatoria

Sin modificar producción:

1. Validar orden e idempotencia de todas las migraciones V7.
2. Identificar operaciones que requieren ownership, `SET ROLE`, `CREATE`, grantor específico o BYPASSRLS.
3. Confirmar que todo privilegio temporal se revoca incluso ante reejecución.
4. Revisar `SECURITY DEFINER` y `search_path=''`.
5. Revisar RLS/FORCE RLS y policies de todas las tablas nuevas y V4 auditadas.
6. Revisar triggers `ENABLE ALWAYS` y su interacción con triggers append-only existentes.
7. Confirmar que los writers no realizan UPDATE sobre tablas append-only.
8. Comparar preimages Edge/SQL/validadores campo por campo y orden por orden.
9. Revisar SQL three-valued logic, casts, NULL, timestamps, regex y errores atrapados.
10. Revisar deduplicación, locks, unique indexes y comportamiento ante concurrencia.
11. Verificar que la cuarentena capture las 192 reconciliaciones compensatorias conocidas y cualquier PASS pre-V7.
12. Revisar si una fila histórica posterior puede bloquear o suplantar promoción V7.
13. Verificar que V8 no herede semántica V5/V6.
14. Revisar si la evidencia de despliegue Edge puede ser fabricada desde PostgreSQL.
15. Confirmar que el workflow solo reconcilia un commit fusionado y validado por `lf-contract-check`.

## Pruebas runtime requeridas cuando exista entorno aislado

No ejecutar estas pruebas en producción.

Usar:

- `PR93_WRITER_V7_ADVERSARIAL_TESTS.sql`
- `PR93_V7_READBACK.sql`

Agregar pruebas nuevas para:

1. Aplicación completa de migraciones desde un clon limpio del esquema actual.
2. Reaplicación/idempotencia donde corresponda.
3. Control positivo HMAC.
4. Replay exacto.
5. Nonce expirado y futuro.
6. Firma incorrecta.
7. Sin claims, claims `anon`, `authenticated` y claims manipulados.
8. Acceso directo a tabla de clave y nonces desde roles API.
9. Writer V5/V6 desde `service_role`.
10. Retry de reconciliación idéntica.
11. Payload conflictivo para el mismo workflow.
12. Gate conflictivo con evidencia histórica.
13. Inserción directa de fila V7 incompleta intentando evadir los writers.
14. PASS con `VERIFIED_COMPENSATING_CONTROLS`.
15. Promoción con reconciliación/gate de distintas ejecuciones.
16. Promoción con evidencia más reciente conflictiva.
17. Mutación de tablas append-only.
18. Eliminación o desactivación de triggers.
19. Cierre sin Edge V7/readback/ruleset/clave/baseline.
20. Extracción de la clave por vistas, funciones, errores o logs.

## Estado esperado de producción durante esta auditoría

Verificar independientemente:

| Métrica | Esperado |
|---|---:|
| V7 writer key table | inexistente |
| V7 reconciliation writer | inexistente |
| V7 gate writer | inexistente |
| artifact_count | 64 |
| pass_v3_count | 0 |
| judge_count | 13 |
| judges_pass_v3 | 0 |
| github_pass_count | 0 |
| passed_gate_tests | 0 |
| failed_gate_tests | 64 |
| branch_protection_gaps | 64 |
| schema_drift_gaps | 7 |
| closure_ready | false |
| computed_closure_status | `NOT_READY` |
| Edge activa | V6 |

Una diferencia favorable no implica PASS; debe reconstruirse y explicarse.

## Bloqueos externos conocidos

1. No existe prueba SQL en un entorno aislado.
2. GitHub `main` no tiene ruleset nativo válido.
3. PR #93 no tiene aprobación independiente.
4. `supabase_admin` conserva una membresía residual de `postgres` sobre `lf_governance_owner_v3`.
5. Las funciones `net` conservan ejecución para roles API mediante grants administrados.
6. No debe generarse baseline nuevo antes del merge y reconciliación post-merge.
7. No debe desplegarse ni fusionarse durante esta auditoría.

## Criterios de resultado

- `AUDIT_PASS`: no se encontró defecto bloqueante en el código y las pruebas runtime aisladas también pasaron. No equivale a autorización de merge si quedan controles externos.
- `AUDIT_FAIL`: existe una ruta explotable, una migración inoperante, una dependencia circular, un cierre falseable o una prueba requerida falló.
- `NOT_AUDITABLE`: falta una superficie imprescindible para emitir conclusión.

## Formato obligatorio de salida

1. Veredicto: `AUDIT_PASS`, `AUDIT_FAIL` o `NOT_AUDITABLE`.
2. Resumen ejecutivo, máximo 15 líneas.
3. Matriz CA-N01 a CA-N28:
   - `RESOLVED_WITH_EVIDENCE`
   - `PARTIALLY_RESOLVED`
   - `STILL_OPEN`
   - `NOT_AUDITABLE`
4. Hallazgos nuevos CA-N29+ con severidad, evidencia, reproducción, impacto y corrección mínima.
5. Tabla de revisión estática por archivo.
6. Tabla de pruebas runtime ejecutadas/no ejecutadas.
7. Readback independiente de producción.
8. Blockers exactos antes del merge.
9. Recomendación: `NO_MERGE`, `MERGE_AFTER_FIXES` o `MERGE_ALLOWED`.

## Prohibiciones

- No aceptar la descripción del PR como evidencia.
- No aceptar checks verdes como prueba runtime.
- No aceptar una revisión del autor como independiente.
- No usar Vault como almacén independiente mientras `service_role` pueda leerlo.
- No considerar controles compensatorios equivalentes a branch protection.
- No fusionar, desplegar, regenerar baseline ni modificar producción.
- No revelar claves, tokens, JWT completos o valores sensibles.

## Resultado correcto de esta etapa

Sin entorno aislado y sin controles administrativos, un `MERGE_ALLOWED` global sería improcedente. La auditoría puede validar estáticamente el diseño y enumerar defectos, pero debe mantener `NO_MERGE` o `MERGE_AFTER_FIXES` hasta completar pruebas runtime, ruleset, revisión independiente, remediación administrativa y reconciliación post-merge.
