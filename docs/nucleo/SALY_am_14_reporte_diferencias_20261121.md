# SALY — Diferencias de 14 reglas legadas al núcleo (2026-11-21)

Fuente: SELECT verificable `saly.reglas` (14 VALIDADO). Objetivo: 14 `saly.nucleo_reglas` versión 1 CANDIDATA, juicio `CONTEXTO_ACTUAL`, `DEVOLVER`, no publicación. Evidencia de paquete, literal de fuente y tests en [saly_am_14_v1.json](../../sandbox/lf_contract_gate_test/nucleo_ci/saly_am_14_v1.json).

| Código | Familia | Alcance legado → núcleo | Efecto acotado | Nota en PG17 | Diferencia / deuda restante |
|---|---|---|---|---:|---|
| SALY-RGL-001 | MOTOR_DISPONIBLE | PRODUCTO → ADELANTO | CLASIFICAR | 70 DEVUELTA | Equivalencia INSTANT/STEPS y liberación completa no modelada como fórmula runtime. |
| SALY-RGL-002 | MOTOR_DISPONIBLE | PRODUCTO → ADELANTO | BLOQUEAR | 70 DEVUELTA | Topes por porcentaje/monto; solo guard booleano y default fuente registrado. |
| SALY-RGL-003 | MOTOR_DISPONIBLE | PRODUCTO → ADELANTO | BLOQUEAR | 70 DEVUELTA | Comparación monetaria real con accrual_cap sin conexión. |
| SALY-RGL-004 | MOTOR_DISPONIBLE | PRODUCTO → ADELANTO | RECHAZAR | 70 DEVUELTA | Máximos/mínimos por operación/ciclo sin condiciones numéricas. |
| SALY-RGL-005 | CALENDARIO | PRODUCTO → ADELANTO | BLOQUEAR | 70 DEVUELTA | Ciclo calculado por calendario no conectado; claves fuente registradas. |
| SALY-RGL-006 | MOTOR_DISPONIBLE | PRODUCTO → ADELANTO | BLOQUEAR | 70 DEVUELTA | Conservación del devengo durante bloqueo no probada. |
| SALY-RGL-007 | MOTOR_DISPONIBLE | EMPLEADO → ADELANTO | PERMITIR | 67 DEVUELTA | EMPLEADO como dato en ADELANTO; control de identidad y ámbito pendiente. |
| SALY-RGL-008 | MOTOR_DISPONIBLE | EMPLEADO → ADELANTO | BLOQUEAR | 67 DEVUELTA | Orden de consumo EXTRA_FIRST_BY_EXPIRY no estructurado; saldo por empleado sin binding. |
| SALY-RGL-009 | MOTOR_DISPONIBLE | PRODUCTO → ADELANTO | RECHAZAR | 70 DEVUELTA | Tipos de variable, correcciones e idempotencia de batch no cubiertos plenamente. |
| SALY-RGL-010 | MOTOR_DISPONIBLE | PRODUCTO → ADELANTO | BLOQUEAR | 70 DEVUELTA | Persistencia de evento correctivo y preservación de consumos sin binding. |
| SALY-RGL-011 | GOBERNANZA | TRANSVERSAL → GLOBAL | RECHAZAR | 70 DEVUELTA | Floor/clamp/precisión no expresados como cálculo numérico. |
| SALY-RGL-012 | GOBERNANZA | TRANSVERSAL → GLOBAL | BLOQUEAR | 70 DEVUELTA | Lista de campos de traza no validada individualmente. |
| SALY-RGL-013 | GOBERNANZA | PRODUCTO → ADELANTO | BLOQUEAR | 70 DEVUELTA | Permisos y auditoría reales no conectados. |
| SALY-RGL-014 | MOTOR_DISPONIBLE | PRODUCTO → ADELANTO | BLOQUEAR | 70 DEVUELTA | Fórmula de anticipo y anticipation_days sin valor real, sin binding. |

## Invariantes y riesgos
- Las 14 legadas permanecen `VALIDADO` y `vigente=true`; no se asignó `regla_legacy_id` para impedir corte prematuro.
- Las 14 versiones son `CANDIDATA` con juicio explícito `CONTEXTO_ACTUAL`, `revisor_es_productor=true`, `llamadas_modelo=0`, veredicto `DEVOLVER`; no son listas para publicar.
- Cuatro valores de configuración insertados son fuente literal validada (CURVE_TYPES, ON_MISSING_DAY, CONFIG_CHANGE_DEFAULT, ASSIGNMENT_CAP_PCT_DEFAULT). El dato SALY_PLUS.ANTICIPATION_DAYS está NULL y no se configura artificialmente.
- La condición por EMPLEADO no justifica crear ni afirmar un nuevo nodo de alcance; sigue pendiente demostrar el binding al sujeto autenticado.
- No se cambian rules LF, SALY legadas, escritores, lectores, permisos, CI de dominio, F6 ni sistema de pagos. Copia PG17 es aislada, sin red ni datos de cliente.
- No se crea un EKB nuevo si no hay un hallazgo técnico distinto ya demostrado. La deuda de semántica no validada está en cada juicio y se conserva como DEVUELTA.

## Criterios medidos (sujetos a merge y readback)
1. S — Vocabulario (hechos) y parámetros de SALY: 31 hechos/relaciones gobernadas, 4 referencias de configuración con metadatos.
2. S — 14 reglas actuales migradas una vez con reporte de diferencias: 14 NUEVA CANDIDATA, todas devueltas, legadas intactas.
3. AM — 14 reglas de SALY por la misma ruta: 14 llamadas a `saly.nucleo_regla_proponer_v1`, pruebas y juicio por hash.

No se cierra el criterio padre AM «Estructurar condición, efecto y pruebas por familia» ni se declara listo el motor SALY en runtime. 
