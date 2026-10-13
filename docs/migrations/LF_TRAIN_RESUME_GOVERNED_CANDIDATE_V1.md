# RESUME — extensión gobernada de MIGRATION_ORCHESTRATED_SAGA (candidato)

Estado: DRAFT / NO ACTIVAR. Hereda la identidad y autoridad de lf_operation_execution y lf_operation_effect_guard, no sus credenciales.

Invariantes: checkpoint durable y exact identity; SUCCEEDED+receipt no se ejecuta dos veces; RESERVED sin confirmación exige reconciliación por readback; lease/fence vigentes; no cierre verde si patch/verify/close falla. Continuar desde el paso confirmado, sin inventar evidencia.

Entradas: Router execution id, checkpoint, effect guard, receipts y lease. Salidas: SKIP/RESUME/BLOCK más estado verificable. No crea motor de ejecución paralelo.

Pendiente: integrar el control con Saga y Train, quitar continue-on-error en el adapter tras demostrar comportamiento, tests de interrupción/replay/concurrencia y gobernanza/registro por consumidor. Sin apply, merge ni activación en este PR.
