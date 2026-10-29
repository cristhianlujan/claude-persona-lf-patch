# PE10 — Cierre de brechas del plan Profile Updater v0.2 (revisión independiente)

Fecha: 2026-10-27 · Plan: `PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1` (PE10, work item 1103, op. `ACTUALIZACION_PERFIL_LF`)
Estado: **propuesta registrada como migración, NO aplicada. v0.2 NO está aprobado ni activo.**

## 1. Hallazgos que motivan el cambio
- **A1 (verificado leyendo `fn_engineering_checkpoint_execution_readiness_v1_from_context_v1`)**: la cadena de readiness ignora `engineering_work_dependencies`. PE10_C6/C7 pueden salir `READY` aunque PE10A_READY siga pendiente.
- **A2**: la validación pre-escritura no exige el conjunto completo de archivos del cambio (path + blob SHA) → un plan de un archivo puede cubrir un cambio multi-archivo.
- **A3**: no existe ensayo de rollback v0.2→v0.1 antes del cutover; y no hay corrida real post-cutover bajo autoridad v0.2.
- Criterios incompletos en CT04/ST03/SB04 (evidencia tipada por operación de nodo, recibos de método/research para pasos 35/37, re-corrida del invariante C4 con casos reales: 1 IN_PROGRESS UI-ARCHITECT 23-oct y 4 BLOCKED de septiembre).
- Dirección de `reuses` invertida en ST09–ST12 (dependencias circulares con OP*).

## 2. Cambios (migración `20261027195500_lf_pe10_gap_closure_readiness_dependencies_v1.sql`)
Solo registro de plan; sin DDL de runtime, sin nuevas unidades/dependencias/colas/adapters.
- Nuevos checkpoints: `PE10A_CT07`, `PE10A_SB06` (cierra A1), `PE10A_OP09`, `PE10_C8` (seq 9, tras C7).
- 12 checkpoints PENDING enmendados (CT04, ST03, SB04, ST09–ST12, OP02/03/04/06/07/08) con guardas de drift exacto.
- No toca los 79 DONE, ni C6/C7, ni activa v0.2.
- Post-estado esperado: 28 unidades · 148 checkpoints · 66 PENDING · 79 DONE · 3 NA · C6/C7 PENDING · dependencias sin cambio · registry v0.1.

## 3. Evidencia de prueba (ejecutada)
Réplica local PostgreSQL 16 que reproduce el estado previo de producción (28/144/22 tras las 2 migraciones reales).
| Prueba | Resultado real |
|---|---|
| T1 sin ejecución del Train | `PE10_GAP_CLOSURE_TRAIN_TRANSPORT_REQUIRED` |
| T2 positivo | 28/148/66/79/3 · deps 22 · 4 nuevos PENDING · C6/C7 PENDING |
| T3 reejecución | `PE10_GAP_CLOSURE_PRESTATE_STALE_OR_DUPLICATE`, sin cambios |
| T4 objetivo de enmienda ya DONE | `PE10_GAP_CLOSURE_AMEND_TARGET_NOT_PENDING_OR_MISSING`, sin cambios |
| T5 drift en campo `reuses` | `PE10_GAP_CLOSURE_REUSE_DRIFT_PE10A_ST09`, sin cambios |
| T6 falla forzada en el último insert | rollback total: 144 checkpoints, 0 códigos nuevos |

**Límites (no probado):** la réplica usa tablas stub; NO reproduce triggers, ACL ni constraints reales de producción. Tampoco se verificó: fuente Edge en `main` de GitHub (WebFetch denegado), registros del Train de PRs #3200/#3201, contenido de judges pre-write, contenido de recibos de los 79 DONE.

## 3b. Ruta crítica propuesta
1. Merge Train aplica la migración → readback (28/148/66/79/3).
2. SUPABASE: `PE10A_SB06` (readiness respeta dependencias) → antes de confiar en `READY` de C6/C7.
3. En paralelo: METHODS. Luego GITHUB: `PE10A_CT07` y GH*; `PE10A_OP09` (ensayo ROLLBACK) antes de OP08/cutover.
4. Gates E2E: ST09–ST12 (4 casos reales) → OP04 los agrega (no es un segundo E2E) → OP08 exige recibo verde de OP09 → C6/C7 → `PE10_C8`.
Primer checkpoint a ejecutar: `PE10A_CT01` (previa materialización de su contrato/validador; ninguno de los pendientes tiene aún assertion contract).

## 4. Riesgos de cierre prematuro
- Dar `READY` por sí mismo como prueba (A1). · Cerrar por documento sin recibo. · Declarar v0.2 activo sin OP09 ni C8. · Bloqueos sin clasificar al re-correr C4.
