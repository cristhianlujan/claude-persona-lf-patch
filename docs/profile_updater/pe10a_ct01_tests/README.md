# Pruebas locales de la migracion lf_pe10a_ct01_assertion_contract_ready_v1

`run_tests.sh`: 16 pruebas + mutaciones sobre una replica local PostgreSQL 16 (plantilla `t_dep`, rutas del autor; ajustar `H`).
`replica_fn_assertion_contract.sql`: copia de `programacion.fn_engineering_action_spec_assertion_contract_v1` de produccion
(2026-10-27) **sin** la rama TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION, que CT01 no ejercita.

Resultado 2026-10-27: 16/16 y T8 (condicion en false) rechazada.
Paridad con produccion verificada solo con SELECT: actual -> BLOCK_ACTION_SPEC_NOT_READY; solo READY -> BLOCK_ASSERTION_CONTRACT_REQUIRED;
READY+contrato -> READY; pass_when no objeto -> BLOCK_ASSERTION_CONTRACT_INCOMPLETE.

Hallazgo ajeno a este cambio: la funcion oficial devuelve READY con `pass_when: null` si el contrato no trae `pass_when`
(verificado en produccion). La migracion lo compensa con su propia verificacion posterior. No se corrige aqui.
Limites: replica PG16 vs produccion 17.6; sin triggers/ACL reales de produccion.

## Cierre de CT01 (migración `lf_pe10a_ct01_close_v1`)
`run_close_tests.sh` (16 pruebas, réplica PG16): C1 sin Train, C2 camino feliz (CT01 DONE, recibo con hash, solo CT01 cambia, fila EKB), C3 reaplicar, C4 deriva de cuerpo, C5 función ausente, C6 función fantasma, C7 otro checkpoint no PENDING, C8 contrato sin `pass_when`, C9 condición extra no cubierta. Resultado local: 16/16.
Límites declarados: las 12 superficies SQL son STUBS con el md5 reescrito en una copia de la migración (la igualdad real con producción la comprueba la propia migración en el Train y el falsificador); `fn_engineering_checkpoint_assertion_record_v1` es copia literal de producción; `fn_engineering_checkpoint_transition_v1` es copia reducida (sin actualización de `engineering_work_items` ni contrato de error); `action_spec_v3`, el bootstrap y el hash JSON son stubs; no están los triggers de guarda de producción (material, evidencia explícita, métricas terminales). Réplica PG16; producción PG 17.6.
