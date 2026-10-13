# RECONCILE — extensión gobernada de MIGRATION_SOURCE_PARITY (candidato)

Estado: DRAFT / NO ACTIVAR. Modo: base → Git. Usa el finding de paridad y el registro vigente como autoridad de lectura.

Invariantes: únicamente renombres de archivos Git, contenido byte a byte idéntico; la nueva versión y nombre coinciden con el ledger. Sin DDL, sin apply, sin actualización del ledger ni credenciales de escritura DB. Los permisos Git se delegan al adaptador autorizado; el núcleo no crea ejecutor alternativo.

Entradas: ejecución Router/contrato, SHA base+head, diff de PR, ledger read-only, evidencia EKB. Salidas: PASS/BLOCK y listado de renombres. Los casos M10.0 pueden ser consumidores futuros pero no forman parte de la implementación genérica.

Pendiente: integración con parity canónico, tests positivos/negativos byte-identity y múltiples renombres, autorización por proyecto, source-currentness, EKB, readback y cierre. No habilitar el PR por solo crear el validador.

## Regla transversal de entrada y exclusividad (obligatoria)

**ROUTER_FIRST_TRAIN_EXCLUSIVE_V1:** Cualquier caller/proyecto debe resolver primero una ejecución válida y autorizada en ACT-0001 (operation_code, project/scope, contract/policy/currentness, owner y exact identity). Sin receipt de Router válido: BLOCK. El caller nunca invoca el ejecutor interno ni recibe credenciales del Train.

```
Cualquier proyecto/caller
  -> ACT-0001 / Router (admisión + ejecución válida)
  -> RECONCILE (preflight contractual, sin efectos)
  -> LF Migration Merge Train (único coordinador/ejecutor autorizado de migraciones)
  -> DB → Git (efecto limitado al modo)
  -> readback + evidencia + cierre gobernado
```

Train es único coordinador de la operación de migración; adaptador Git-only, sin DB/ledger write.

**No herencia implícita de permisos:** se hereda la ruta gobernada y se delega el efecto bajo permisos propios del Train, nunca secretos ni acceso directo a DB. Verificar binding operación/proyecto, SHA, receipt, currentness y lease inmediatamente antes del efecto; fail closed si cambia. No permitir ruta paralela de MCP, psql, SQL Editor, CLI o escritura directa de ledger. Git-only no necesita privilegio DB write. Esta norma es un requisito de admisión, no evidencia de que el cableado ya esté operativo.
