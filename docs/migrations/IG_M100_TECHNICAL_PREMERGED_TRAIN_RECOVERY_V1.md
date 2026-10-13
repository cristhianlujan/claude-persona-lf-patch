# IG M10.0 — contrato de recuperación de fuente premargeada por Merge Train (candidato)

**Estado: DISEÑO Y PREFLIGHT; NO HABILITADO PARA APPLY.**
**Ámbito:** `LF_SUPABASE_SANDBOX`, `IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.0` (`PAULO-159`).
**Registro:** GitHub issue #2344. La aprobación del usuario cubre la solución de recuperación gobernada, **no** una excepción al transporte exclusivo Train ni activación de producción.

## 1. Identidad cerrada de esta operación (solo CP5–CP7)

| Campo | Valor inmutable |
|---|---|
| Repository | `cristhianlujan/claude-persona-lf-patch` |
| Unidad | `M10.0`, `work_item_id=472` |
| PR que incorporó fuente por ruta incorrecta | `#2340` |
| Source path | `supabase/migrations/20261012223000_ig_m100_sandbox_technical_vs_operational_authority_v1.sql` |
| Git blob SHA-1 | `dbe466b827f10c257dba6449d65d6750f2328057` |
| Nombre de migración | `ig_m100_sandbox_technical_vs_operational_authority_v1` |
| Modo autorizado para escrituras | `ACT-0001 -> ACTUALIZACION_DB_LF -> DB_WRITE_TRANSPORT -> LF Migration Merge Train` |
| Estado de DB observado | Migración sin fila en `supabase_migrations.schema_migrations`; validador `fn_ig_m100_sandbox_guard_matrix_v1()` ausente; M10.0 al 60% (4/7) |

El PR #2342 corrigió solo la clasificación exacta y terminó por Train (run #38319151074). **No aplicó** el SQL del PR #2340.

**FUERA DE ALCANCE:** la migración EKB `20261012120000_ig_m100_ekb_signed_release_snapshot_learnings.sql`, blob `032468a44ed74dde4ef79a0b7edbbe3df4f0100d`. Requiere su propio caso/operación y no se combina con el SQL técnico. Tampoco se toca M9.9, M9.10, otros proyectos ni sus recibos.

## 2. Causa raíz verificada

`lf-migration-merge-train.yml` se dispara al etiquetar un PR con `ready-to-merge`; su resolver de migración acepta una sola ruta `added` en el diff del PR. Una migración ya existente en `main` tiene diff vacío, y con `migration_count=0` Train omite el apply. Reetiquetar el PR #2340, repetir la tarea de clasificación o crear un PR solo documental **no** puede ejecutar el SQL pendiente.

La versión de fuente `20261012223000` ya se encuentra por debajo del máximo del ledger observado `20261012230000`. Por tanto tampoco cumple la regla normal de asignación estrictamente creciente de versión. No asumir que el resto de fuentes pendientes históricas del repositorio están aplicadas; identificarlas por cambioset y probar currentness.

La política `docs/migrations/POLICY_MIGRATION_APPLY_V1.md` autoriza una excepción antigua por blobs exactos de M9.10; **no se extiende por analogía a M10.0**.

## 3. Contrato de habilitación (cambios mínimos, solo owner de Train)

**No ejecutar hasta que exista un carril explícitamente admitido y aprobado dentro de Train.**
Las instrucciones `CLAUDE.md` / `AGENTS.md` prohíben a agentes crear o modificar workflows que leen `LF_SUPABASE_DB_PASSWORD` u otras credenciales y prohíben el apply por SQL Editor, MCP, psql o un segundo ejecutor.

El responsable del Merge Train debe implementar/admitir una ruta de recuperación acotada a **exactamente el Git blob indicado**, capaz de manejar una fuente ya en `main` sin presentarla falsamente como `added`. Antes de cualquier escritura debe resolver en ACT-0001 la ejecución `ACTUALIZACION_DB_LF`; validar EKB, el branch/head, blob inmutable, versión/nombre, origen, acceso, dependencias, riesgo y cero efectos ajenos a la unidad. Rechazar si no coincide cualquier campo; usar exclusivamente `lf-migrations` concurrency del Train.

El responsable deberá resolver explícitamente la incompatibilidad `source_version < ledger_max` antes del apply: **no** insertar retrospectivamente una fila de ledger, no reetiquetar como `ALREADY_APPLIED`, no clonar el SQL con versión nueva sin retirar primero la identidad pendiente de forma gobernada, no reducir la política global de versiones. Si se elige un cambio de identidad de versión, exigir equivalencia exacta de bytes SQL, retiro auditable de la identidad no aplicada, una sola identidad viva en `main` y readback de source/ledger. No generalizar esta excepción. Cualquier cambio de esta regla requiere decisión explícita documentada antes de un efecto irreversible.

## 4. Defecto secundario que debe resolverse antes del cierre CP5–CP7

El SQL fuente define `programacion.fn_ig_m100_sandbox_guard_matrix_v1()` como `SECURITY INVOKER` y revoca `EXECUTE` a `PUBLIC` sin concederlo a un lector técnico. Preflight real:

| Rol | EXECUTE `fn_v09_sha256_jsonb` | SELECT sobre recibos, decisions, promotions, plan, CP |
|---|---|---|
| `programacion_verifier` | Sí | No, faltan permisos de tabla |
| `supabase_read_only_user` | No | Sí |

Ninguno reúne ambos privilegios necesarios para correr la función como invocador y además la función nueva quedaría sin `GRANT` explícito. El rol `postgres` puede ejecutarla como dueño durante el apply, **pero eso no demuestra que funcione desde el consumidor de readback**.

Corregir por **migración posterior independiente, vía Train**, el contrato de ejecución de la función con mínimo privilegio y guard de roles. Evaluar wrapper `SECURITY DEFINER` con `search_path` fijo, único rol lector autorizado y salida booleana acotada; no conceder escritura ni acceso a `HUMAN_DECISION` operacional, no hacer `GRANT ... TO PUBLIC`. Validar positivo con rol consumidor y negativo con rol no autorizado. La migración original se mantiene como fuente congelada; no alterar su Git blob para ocultar la diferencia.

## 5. Matriz de admisión y pruebas (solo Train)

| Control | Acepta | Rechaza |
|---|---|---|
| Identidad | `main` contiene blob exacto y target único | SHA/path/version distintos o contenido retocado |
| Ledger | Falta fila exacta antes; coincide una sola fila tras apply | Fila falsa, doble registro, SHA incoherente |
| Snapshot M9.0 | Recibo firmado 187, bundle `db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f` | Head incorrecto o digest alterado |
| M9.12 | Recibo 1667 verificado `CUTOVER_READY` para el mismo bundle | Recibo ausente, manipulado u otro subject |
| Seguridad | Verificador auténtico; 1 positivo y al menos 5 negativos; lector mínimo autorizado | Recibo `HUMAN_DECISION` falsificado, `decision='CUTOVER_AUTHORIZED'` (valor inválido) o rol no autorizado |
| Transaccionalidad | Preflight reversible con `BEGIN/ROLLBACK`; cero residuos; apply SQL+ledger atómico | Cualquier escritura parcial o replay |
| Gobernanza | CP5/6/7 solo sandbox, cutover operacional `BLOCKED` | Aprobación humana automática, promoción o deploy productivo |
| Cierre | Git main = blob aplicado = ledger, función desplegada y leída por rol autorizado, bootstrap/transiciones DONE | PR merged, CI green o test estático sin DB readback |

**No** reusar los criterios de sandbox para admitir una promoción operacional: ésta sigue requiriendo decisión humana `APPROVE` real, `metadata.decision_class=CUTOVER_AUTHORIZED`, `authority_receipt_id` de clase `HUMAN_DECISION`, manifiesto/auditoría y autoridad independiente.

## 6. Estados y criterios de parada

Hasta que el responsable de Train habilite un carril de recuperación explícito y apruebe el tratamiento exacto de la versión antigua, el estado es **`BLOCKED_TRAIN_PREMERGED_RECOVERY_UNAVAILABLE`**. Esta documentación y cualquier PR de solo código **no** constituyen un apply; nunca contabilizar progreso M10.0 por publicar el plan.

Al existir un run exitoso del Train para el blob autorizado, registrar run_id, SQL source SHA-256, Git blob SHA-1, identidad de versión, lectura real en `supabase_migrations.schema_migrations`, prueba funcional y comparación de residuos. Aplicar después y de manera independiente el correctivo de permisos solo por Train; entonces utilizar `fn_engineering_checkpoint_transition_v1` para CP5–CP7 según el contrato efectivamente desplegado. No actualizar el ledger por declaración.
