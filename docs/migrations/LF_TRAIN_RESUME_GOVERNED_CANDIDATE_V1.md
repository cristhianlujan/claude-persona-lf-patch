# RESUME — extensión gobernada de MIGRATION_ORCHESTRATED_SAGA (candidato)

Estado: DRAFT / NO ACTIVAR. Hereda la identidad y autoridad de lf_operation_execution y lf_operation_effect_guard, no sus credenciales.

Invariantes: checkpoint durable y exact identity; SUCCEEDED+receipt no se ejecuta dos veces; RESERVED sin confirmación exige reconciliación por readback; lease/fence vigentes; no cierre verde si patch/verify/close falla. Continuar desde el paso confirmado, sin inventar evidencia.

Entradas: Router execution id, checkpoint, effect guard, receipts y lease. Salidas: SKIP/RESUME/BLOCK más estado verificable. No crea motor de ejecución paralelo.

Pendiente: integrar el control con Saga y Train, quitar continue-on-error en el adapter tras demostrar comportamiento, tests de interrupción/replay/concurrencia y gobernanza/registro por consumidor. Sin apply, merge ni activación en este PR.

## Regla transversal de entrada y exclusividad (obligatoria)

**ROUTER_FIRST_TRAIN_EXCLUSIVE_V1:** Cualquier caller/proyecto debe resolver primero una ejecución válida y autorizada en ACT-0001 (operation_code, project/scope, contract/policy/currentness, owner y exact identity). Sin receipt de Router válido: BLOCK. El caller nunca invoca el ejecutor interno ni recibe credenciales del Train.

```
Cualquier proyecto/caller
  -> ACT-0001 / Router (admisión + ejecución válida)
  -> RESUME (preflight contractual, sin efectos)
  -> LF Migration Merge Train (único coordinador/ejecutor autorizado de migraciones)
  -> Checkpoint → continuación (efecto limitado al modo)
  -> readback + evidencia + cierre gobernado
```

Train retoma ejecución gobernada; Router revalida identidad, lease y effect guard; no replay.

**No herencia implícita de permisos:** se hereda la ruta gobernada y se delega el efecto bajo permisos propios del Train, nunca secretos ni acceso directo a DB. Verificar binding operación/proyecto, SHA, receipt, currentness y lease inmediatamente antes del efecto; fail closed si cambia. No permitir ruta paralela de MCP, psql, SQL Editor, CLI o escritura directa de ledger. Git-only no necesita privilegio DB write. Esta norma es un requisito de admisión, no evidencia de que el cableado ya esté operativo.

## Evidencia de implementación en rama

El workflow LF Migration Merge Train fue extendido en este PR para este modo, usando el código confiable de main al momento de ejecución. CI estática y pruebas negativas se ejecutan en el workflow F0 existente. Los PRs son independientes; el hecho de estar mergeables o pasar actionlint no autoriza su uso.

**Pendiente previo a uso transversal:** validación E2E sandbox con recibo Router actual y exact-head, reconciliación de currentness y binding por proyecto, EKB + contrato de cierre, rollback/readback independiente y veredicto de gobernanza. No fusionar ni activar solo por CI estática.

**Interrupción ambigua:** una reserva sin prueba de ledger es BLOCK, no reapply. Un efecto SUCCEEDED solo se omite tras validar digest del SQL, recibo y autoridad Router vigente. El cierre post-merge y el patch son fallos fatales en el carrier propuesto.
