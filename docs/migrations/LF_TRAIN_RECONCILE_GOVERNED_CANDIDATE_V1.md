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

## Evidencia de implementación en rama

El workflow LF Migration Merge Train fue extendido en este PR para este modo, usando el código confiable de main al momento de ejecución. CI estática y pruebas negativas se ejecutan en el workflow F0 existente. Los PRs son independientes; el hecho de estar mergeables o pasar actionlint no autoriza su uso.

**Pendiente previo a uso transversal:** validación E2E sandbox con recibo Router actual y exact-head, reconciliación de currentness y binding por proyecto, EKB + contrato de cierre, rollback/readback independiente y veredicto de gobernanza. No fusionar ni activar solo por CI estática.

**Identidad exacta esperada en ejecución Router:** operation_code=ACTUALIZACION_DB_LF, target_type=MIGRATION, target_code=RECONCILE_GIT_ONLY, target_path=supabase/migrations, target_repo y reconcile_base_sha/reconcile_head_sha del PR. El script requiere autoridad canonical ACT-0001 válida. No se atribuye cierre de operación de DB a un cambio Git-only.
