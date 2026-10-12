# IG M10.0 — Retiro de fuente Git nunca aplicada (candidato acotado)

**Estado: DRAFT, sin autorización para merge/aplicación fuera de carril Train.**  
**Issue:** #2344 · **Unidad:** M10.0 / PAULO-159 / work_item_id=472.  
**Ámbito:** únicamente fuente técnica de M10.0, sin tocar otros productos, unidades, ni SQL de EKB.

## Identidad inmutable

| Control | Evidencia |
|---|---|
| Repositorio | `cristhianlujan/claude-persona-lf-patch` |
| PR de introducción incorrecto | #2340 (merge directo, fuera de Train) |
| Path de fuente histórica | `supabase/migrations/20261012223000_ig_m100_sandbox_technical_vs_operational_authority_v1.sql` |
| Blob Git exacto | `dbe466b827f10c257dba6449d65d6750f2328057` |
| Versión/nombre | `20261012223000` / `ig_m100_sandbox_technical_vs_operational_authority_v1` |
| Readback Supabase | **0 filas** para la versión o nombre exactos en `supabase_migrations.schema_migrations`; validador correspondiente no desplegado |
| Main Git de preflight | `4bfcc8816b7604393ca6d3136faa5469a2f4f152` |
| Sustituto candidato | PR #2355, `lf_ig_m100_sandbox_admission_coherent_v2` (DRAFT) |

El contenido anterior permanece íntegro y verificable en el commit de introducción #2340 y en el Git blob indicado. Retirar un archivo de `main` **no borra historia, no significa DDL replay y no certifica ledger**. No borrar ni tocar versiones aplicadas.

## Motivo de retiro

La fuente original no puede aplicarse como está porque:
1. Contrato, work item `PAULO-159` y gobernanza tienen criterios contrapuestos: ingeniería sandbox versus aprobación humana operativa.
2. Crea validador `SECURITY INVOKER` sin un rol lector con ambos permisos necesarios; ofrece un `REVOKE` sin `GRANT` de lectura verificable.
3. Se fusionó sin Train; el timestamp `20261012223000` quedó por debajo del máximo actual del ledger.
4. La política de Git exige no duplicar o reestampar migración ausente del ledger.

El sustituto de #2355 reutiliza el verificador canónico, prueba el snapshot M9.0 #187 y readiness M9.12 #1667, y corrige de forma atómica contrato + gobernanza + CP5–CP7, sin autoridad humana falsa ni funciones adicionales.

## Carril obligatorio de esta retirada

El Merge Train actual `.github/workflows/lf-migration-merge-train.yml` **no acepta** fuentes `status=removed` en los cambios del PR: termina `FAIL_TRAIN_MIGRATION_CHANGE_NOT_NEW:removed`. Por tanto este PR debe permanecer DRAFT **hasta que el responsable de Train tenga habilitada y autorice** una reconciliación source-only de identidad exacta dentro de la ruta canónica. No usar un merge directo o un segundo ejecutor como sustituto; no cambiar workflows que leen secretos desde un agente.

Precondiciones de dicho carril:
- Resolver ACT-0001 / `ACTUALIZACION_DB_LF`, consulta EKB; retener el Git blob exacto y la evidencia de owner.
- Releer versión/nombre ausentes del ledger inmediatamente antes del merge de retiro.
- Confirmar el path archivado en historial, el nuevo `main` sin esa fuente y sin alteración de otras migraciones.
- Registrar `SOURCE_ONLY_RETIRE_NO_SQL_EXECUTION` y `ledger_mutated=false`; no afirmar `migration_applied`.
- Nunca retirar un archivo con versión ya aplicada ni cerrar M10.0 por este PR.

## Secuencia exigida

1. Cerrar este retiro gobernado (sin efectos SQL) y demostrar Git main + ledger sin el viejo archivo.
2. Solo después admitir PR #2355 al Train como **única** nueva migración; Train asigna versión, prueba y aplica en la transacción gobernada, registra ledger y hace readback.
3. Rebootstrapping M10.0, completar CP5/CP6/CP7 solo con evidencia real.
4. EKB #2311 (otro source premargeado) se tramita en **una operación aparte**, nunca como efecto colateral.
5. Cutover productivo permanece `BLOCKED_PENDING_GOVERNED_HUMAN_AUTHORITY`.

### Prohibiciones

No `apply_migration` manual, ni psql, ni SQL Editor, ni `supabase db push` por el agente, ni inserción directa al ledger, ni bypass de paridad, ni doble fuente viva, ni desactivar límites del workflow, ni crear aprobaciones humanas.
