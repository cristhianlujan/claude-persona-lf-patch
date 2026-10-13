# RECOVER — extension gobernada del LF Migration Train (candidato)

Estado: DRAFT / NO ACTIVAR. Capability existente: DB_WRITE_TRANSPORT + MIGRATION_WRITE_AHEAD + Saga. Modo: Git → base.

Invariantes: source blob exacto en main; versión y nombre originales; aprobación específica de owner; lectura de ledger y comprobación de dependencias/colisiones posteriores; rollback preflight sin residuos; no aplicar si un efecto equivalente ya se materializó; UTC+10 min máximo para fechas futuras. No hace apply por fuera del Train.

Entradas: Router execution id, operación ACTUALIZACION_DB_LF, ruta+SHA blob, ledger readback, aprobación, EKB y scope. Salidas: PASS/BLOCK, recibo, identidad y evidencia. No confundir PE10E con la capacidad: PE10E es solo un caso histórico y no está incluido en esta implementación.

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
