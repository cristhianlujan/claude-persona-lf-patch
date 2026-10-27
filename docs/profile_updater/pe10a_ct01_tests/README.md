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
