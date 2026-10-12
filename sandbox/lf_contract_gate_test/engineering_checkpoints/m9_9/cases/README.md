# M9.9 — Cinco condiciones independientes de rollback (separación de pruebas)

## Regla de funcionamiento
En producción, cualquier condición puede requerir rollback de forma independiente (OR); no se espera a que ocurran cinco fallas. Pueden coexistir, pero la causa debe quedar tipada sin ocultar las demás. La ejecución irreversible/cutover productivo queda fuera de este trabajo.

En **calificación** cada caso se ejecuta por separado, en su propio archivo SQL de lectura y transacción `ROLLBACK`. Ningún archivo ejecuta los otros cuatro ni muta punteros. Un PASS de decisión **no** significa rollback ejecutado.

## Pruebas separadas (única condición alterada por caso)
| Caso | Fuente de decisión actual | Evaluación individual | Falta para cerrar |
| --- | --- | --- | --- |
| FALSE_PASS | `false_pass_detected=true` → `FALSE_PASS` | Aserción aislada de señal; no hay prueba de oráculo causal independiente | Resultado erróneo real, veredicto independiente, recibo verificado, rollback automático |
| DIVERGENCE | `divergence_level <> D0` → `DIVERGENCE` | Se usa D4; hoy D1–D5 disparan sin umbral contextual | Comparador independiente y política de severidad acorde a materialidad, rollback automático |
| TIMEOUT | `elapsed_ms > 150000` → `TIMEOUT` | Se prueban 150000 y 150001 por separado dentro del archivo | Medición real de tiempo gobernada, interrupción/reversión y recibo |
| EXECUTION_ERROR | `execution_error=true` → `EXECUTION_ERROR` | Bit de error aislado; no hay excepción real | Fallo real tipado + aborto/reversión exacta |
| MISSING_RECEIPT | `fn_ig_m99_canary_receipt_gate_v1` sin recibo → `RECEIPT_MISSING_STALE_OR_UNATTESTED` | Selector inexistente comprobado mediante lectura | Ausencia real de recibo obligatorio a deadline, issuer/verificador independiente, rollback automático |

El caso MISSING_RECEIPT utiliza un selector ausente como sonda de decisión, no fabrica un recibo.
El caso TIMEOUT verifica la frontera estricta del contrato; no espera 150 segundos ni pretende simular tiempo de pared.

## Evidencia y progreso
Cada caso exige su **propio** `case_code`, `cohort_pin`, `baseline_sha256`, `head_sha`, recibo autorizado, medición/observación verificable, `rollback_action_receipt`, `before_after_digest_equal=true`, `material_residue_count=0`. Sin los datos de ejecución y canal válidos, el caso permanece PENDING. Una evaluación puede avanzar sin ejecutar las demás. El checkpoint final CANARY_READBACK integra cinco pruebas independientes, no reemplaza las pruebas ni aumenta su contador artificialmente.

Los cinco archivos SQL son *sondas de diagnóstico*, no un runner de canary ni sustituyen `REVERSIBLE_CANDIDATE_VERIFICATION@1.0.3`, `INDEPENDENT_ASSURANCE@2.0.1` o `TIMEOUT_PHASE_BUDGET_POLICY`. Se prohíben PASS fabricados, autoemisión de evidencia y activación de producción.

## Estado de adopción
Esta separación de **artefactos Git** no altera los checkpoints de Supabase. La migración pendiente #2261 debe reconciliarse por `DB_WRITE_TRANSPORT` con versión exacta antes de aplicar un cambio adicional al contrato/ledger. El progreso oficial se obtiene solo de Supabase; no se almacena aquí como registro de estado.

## Ruta de implementación del desglose oficial
Separar el checkpoint 4 (25 puntos) en cinco checkpoints obligatorios de 5 puntos, conservar 55 puntos ya cerrados y 20 puntos de CANARY_READBACK; emitir y aplicar esa migración solo por el Merge Train gobernado después de reconciliar #2261. Orden: FALSE_PASS, DIVERGENCE, TIMEOUT (código histórico ROLLBACK_TRIGGER_NEGATIVE), EXECUTION_ERROR, MISSING_RECEIPT. Cada prueba se ejecuta, valida, reporta y cierra individualmente.
