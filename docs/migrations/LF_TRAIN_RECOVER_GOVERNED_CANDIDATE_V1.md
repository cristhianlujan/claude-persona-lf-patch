# RECOVER — extension gobernada del LF Migration Train (candidato)

Estado: DRAFT / NO ACTIVAR. Capability existente: DB_WRITE_TRANSPORT + MIGRATION_WRITE_AHEAD + Saga. Modo: Git → base.

Invariantes: source blob exacto en main; versión y nombre originales; aprobación específica de owner; lectura de ledger y comprobación de dependencias/colisiones posteriores; rollback preflight sin residuos; no aplicar si un efecto equivalente ya se materializó; UTC+10 min máximo para fechas futuras. No hace apply por fuera del Train.

Entradas: Router execution id, operación ACTUALIZACION_DB_LF, ruta+SHA blob, ledger readback, aprobación, EKB y scope. Salidas: PASS/BLOCK, recibo, identidad y evidencia. No confundir 

Pendiente antes de activar: revisión del contrato y compatibilidad de exact_apply, cableado al workflow Train, validación integral rollback real, owner approval, manifest/versionado/currentness y pruebas de consumidor. Prohibido merge automático, apply y alteración del ledger.

## Regla transversal de entrada y exclusividad (obligatoria)

**ROUTER_FIRST_TRAIN_EXCLUSIVE_V1:** Cualquier caller/proyecto debe resolver primero una ejecución válida y autorizada en ACT-0001 (operation_code, project/scope, contract/policy/currentness, owner y exact identity). Sin receipt de Router válido: BLOCK. El caller nunca invoca el ejecutor interno ni recibe credenciales del Train.

```
Cualquier proyecto/caller
  -> ACT-0001 / Router (admisión + ejecución válida)
  -> RECOVER (preflight contractual, sin efectos)
  -> LF Migration Merge Train (único coordinador/ejecutor autorizado de migraciones)
  -> Git → DB (efecto limitado al modo)
  -> readback + evidencia + cierre gobernado
```

Solo Train autorizado aplica versión original; aprobación owner + rollback preflight; no bypass.

**No herencia implícita de permisos:** se hereda la ruta gobernada y se delega el efecto bajo permisos propios del Train, nunca secretos ni acceso directo a DB. Verificar binding operación/proyecto, SHA, receipt, currentness y lease inmediatamente antes del efecto; fail closed si cambia. No permitir ruta paralela de MCP, psql, SQL Editor, CLI o escritura directa de ledger. Git-only no necesita privilegio DB write. Esta norma es un requisito de admisión, no evidencia de que el cableado ya esté operativo.

## Evidencia de implementación en rama

El workflow LF Migration Merge Train fue extendido en este PR para este modo, usando el código confiable de main al momento de ejecución. CI estática y pruebas negativas se ejecutan en el workflow F0 existente. Los PRs son independientes; el hecho de estar mergeables o pasar actionlint no autoriza su uso.

**Pendiente previo a uso transversal:** validación E2E sandbox con recibo Router actual y exact-head, reconciliación de currentness y binding por proyecto, EKB + contrato de cierre, rollback/readback independiente y veredicto de gobernanza. No fusionar ni activar solo por CI estática.

**Admisión runtime:** la operación PR usa LF_MIGRATION_MODE=RECOVER, LF_RECOVER_PATH, LF_RECOVER_BLOB y LF_RECOVER_ISSUE. Se exige approval exacto en issue por cuenta SUPER_ADMIN registrada, revisión explícita de conflictos, blob main, Saga READY_TO_APPLY, ejecución Router y rollback preflight antes del apply. El baseline de MIGRATION_SOURCE_PARITY para fuente preexistente requiere prueba de homologación antes de activar el modo.
