# Lote 19 — Manifiesto y límites de diagnóstico

**Estado global:** NO-GO / UNVERIFIED. **Ejecución de diagnóstico:** SQL solo SELECT, cero mutaciones Supabase, producción, RUN, reintentos, cierres o promociones.

## Procedencia
- Proyecto Supabase: `mhwmirqcgxxukpctffuv`, URL confirmada por conexión de solo lectura. Es la base LIVE y expone PostgreSQL 17.6; **no confundir con el banco PG18 de los Lotes 13/17**.
- EKB consultada: **INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4**, CANDIDATO VERIFICADO PARCIALMENTE. No se invocó Router, perfil, Input Governance, juez/registrador ni terminal.
- Auditor y juez de este diagnóstico: **GPT-6, mismo modelo GPT; NO independiente**. Identidad **Claude no acreditada**. No hubo un segundo juez o firma independiente.
- Rama de escritura única: `lf/issue-3779-lote19-stuck-runs-owner-registry-diagnosis-v1` (base L16). No se hicieron modificaciones en `main`, L16, L13, L17 ni Supabase.
- El dueño reportó reproducción exacta de L16 para 57 VIGENTE pendientes; se toma como contexto comunicado por el dueño, no como prueba nueva del Lote 19.

## Hallazgo de alcance y universo
- **OBJETIVO / R01:** `public.lf_operation_execution` devuelve **232** `IN_PROGRESS`, no los **32** del encargo. No existe filtro aportado que identifique los 32 originales. Por seguridad se entrega el universo de 232 en CSV y un **TOP 32 priorizado por criterio explícito** en `03_32_prioritarios.md`; **no se afirma que coincida con el subconjunto original**.
- **OBJETIVO / R01:** 78 ejecuciones con pasos y 154 sin pasos en `lf_operation_execution_steps`.
- **OBJETIVO / H2:** 8 con `lease_owner`, 8 vencidos, **0 vigentes**, 224 `lease_expires_at IS NULL`. **H1:** sin columna de heartbeat explícita en objetos inspeccionados. `updated_at` no es prueba de worker vivo.
- **REQUIERE_REVISION_SEMANTICA / R01:** clases propuestas A=6 sin efectos observados bajo declaración no-write; B=56 señales de efectos; C=4 actualizaciones observadas dentro de 48h; D=166 no determinables. No hay clasificación terminal ni huérfanos certificados.
- **OBJETIVO / R01:** 29 RUN tienen `github_write` con estado de paso positivo; 6 tienen `lf_operation_effect_guard.SUCCEEDED`; 4 RUN vinculados a `lf_activos`, 2 a capturas, 2 a homologaciones, 6 a `lf_pipeline_runs`, 11 a `lf_operation_registry` y 0 a `lf_rule_promotion_v1`. Se superponen; no sumar. **No se compararon commits/capturas externas con contenido de destino en esta lectura.**

## Owner y familia
- **OBJETIVO / O1–O4:** `lf_ops.perfiles` tiene 8 (6 B2B CANDIDATO / 2 B2C VIGENTE), `lf_ops.permisos` 45, `lf_ops.perfiles_permisos` 129 (CANDIDATO); 0 relaciones actuales en tablas de asignación a usuarios inspeccionadas.
- **OBJETIVO / O2–O4:** `public.v_lf_fuente_operativa` registra 11 assets tipo PERFIL, `lf_profile_selection_registry_v1` 10 descriptores y `programacion.perfiles_calidad` 2. **No sumar fuentes diferentes**.
- **OBJETIVO / O3:** no existen en catálogo live las tablas L13 `rule_quality_l13.projects, actors, families, category_family_map`; SALY tiene `saly.proyecto` (1 fila) sin `owner_profile_code`.
- **REQUIERE_REVISION_SEMANTICA:** la relación gobernada `project_code + owner_profile_code + actors` de L13/L17 no está acreditada en las tablas revisadas; el modelo **es sandbox**, no autorización real. No asumir roles `lf_ops` como owners de calidad.
- Referencias documentales externas a SQL: L13 `docs/rule-quality-lote13/03_design_generic.md` Git blob `26a06c7c64ab40368f4da22d478298676bdcbfcd` y L17 `docs/rule-quality-lote17/03_design_results_limits.md` Git blob `6c873b32f9bd7004b82f80c64e40c297cdb1a3af`.

## Consulta, resultado y SHA-256 reproducible
Los SHA-256 son de JSONB de resultado completo ordenado por serialización textual de cada fila en el propio servidor; no son SHA de Git ni hashes de un extracto. Se publican consultas íntegras en `02_runs_diagnostic_select.sql`, `05_owners_select.sql` y `08_heartbeat_lease_select.sql`.

| SELECT | Filas | SHA-256 del resultado |
|---|---:|---|
| R01 | 232 | `b8f0cd33b2c288aff482619ec4873e64c119b6c9121e7a4c2c478db10d4b65e0` |
| O1 | 261 | `9f4e2cf2b772f61e3e661a3412f1b0ad034ecfa6bc8a409325fe6405ac181782` |
| O2 | 13 | `0a39861a2b631a91e10fc1033bbf780c7d244f75634ff4a5d8780bb77797b43d` |
| O3 | 11 | `43d668a83116b87366bdb76f0e04d03dad69bf6ce47928ba04c631acff7223fb` |
| O4 | 32 | `f124e594c0208ccc99b2e193f0ca657a7663e4e1c377b87dc0480670be5f2480` |
| H1 | 45 | `89087ac3d2f71277ef6f82c587d092e910e0b0b2bc33b377d917ae98ebc58385` |
| H2 | 1 | `5b1d438c7d1de6335f54f1a1e398a6dec90a8255bfe3d13c8e42276d31a91d40` |

SHA resultantes corresponden al corte de cada consulta y pueden cambiar al actualizarse Supabase. La categoría A **no demuestra universalmente cero efectos**, porque una inspección parcial no prueba ausencia en proveedores, GitHub, secretos, archivos o otros registros.

## Archivos
1. `01_runs_232_readback.csv`: 232 RUN, campos por RUN, lease, heartbeat catalogado, pasos, sinks y clase.
2. `02_runs_diagnostic_select.sql`: SELECT R01 y SHA-256.
3. `03_32_prioritarios.md`: tabla humana de 32 priorizados y clasificación de 232.
4. `04_owners_real_registry.md`: registro LF/SALY y comparación L13/L17.
5. `05_owners_select.sql`: SELECT O1–O4 y sus SHA-256.
6. `06_unico_procedimiento_propuesto.md`: **UNA** propuesta de reconciliación P0–P7 con recibos, no ejecutable.
7. `07_preguntas_dueno.csv`: máximo ocho preguntas con alternativas y sugerencia.
8. `08_heartbeat_lease_select.sql`: SELECT H1–H2, esquema y validez de lease.
9. `09_manifest.md`: este registro.

## Bloqueos y readback
- **NO se ejecutó:** cierre/cancelación/reintento, escritura de evidencia, DML/DDL, grants, migración, worker, terminal, actor verificado o cambios de permisos, en LIVE o PG18.
- **Falta:** identificación documental de los 32 originales, lectura de sinks externos, pruebas de idempotencia, responsables reales, validación del dueño, juez independiente si requiere, recibos de efecto y terminal.
- **Readback GitHub:** exigido después de crear archivos: verificar 9/9 blobs por nombre/ref y HEAD de la rama. Un PASS documental no acredita resolución de bloqueos.
- **Recomendación de cierre:** NO-GO / UNVERIFIED, sin aplicar propuesta. Toda modificación posterior requiere alcance y autoridad explícita diferentes.
