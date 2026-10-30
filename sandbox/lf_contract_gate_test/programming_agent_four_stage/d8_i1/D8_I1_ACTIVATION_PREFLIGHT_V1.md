# D8 → I1: gobernanza de activación de desarrollo de código

**Estado:** diseño y prueba negativa OFFLINE; no se habilita ejecución ni escritura.

## D8 ya realizado
- PR #3167 (MERGED) registró `public.lf_router_action_registry` con `REPOSITORY_ARTIFACT/CODE_DEVELOPMENT`, `DESARROLLO_CODIGO_AGENTE_LF`, `CANDIDATO_READ_ONLY`, `write_allowed=false`.
- Supabase read-only (30/10/2026) confirma una fila candidata.
- D8 autorizó **registro candidato**, no activación; esta última quedó reservada a **I1**. No reabrir D8 ni tratar registro como permiso de desarrollo.

## I1: contrato de operación todavía ausente
La migración D8 expresamente no creó `lf_operation_registry`, pasos, judges, grants, runtime ni dispatch. El contrato `PROGRAMMING_ANALYSIS_TO_DEVELOPMENT_V2.md` dice que el agente de Programación, en modo `service_role`, invocaría la admisión PG-01 y cotejaría el binding del Router del perfil. Esto no constituye un handler verificado.

Para activar I1 hace falta una decisión ratificada sobre:
1. Operación `DESARROLLO_CODIGO_AGENTE_LF`: esquema versionado, tipo de target, entradas, pasos, políticas, jueces, estados, rollback y receptor del resultado.
2. Identidad y potestades del dispatcher: quién puede invocar admisión, quién puede escribir código, qué repos/rutas y permisos aplica; separar aprobación de ejecución.
3. Procedencia runtime: PG-01 writer/ledger, envelope V2, judge, currentness, revocación, valid_from/valid_until, scope y HEAD.
4. Motor de checkpoints: Carril D vs `PROGRAMMING_SIMPLE_EXECUTOR_V1`. NO registrar 108 bindings por analogía con B2B.
5. Efectos gobernados: GitHub branch/PR, PASE, revisión, Train; ningún bypass vía SQL, Router o flags cliente.
6. Consumidor PG-02 y posteriormente C6 pre-model con autenticación; recibos nuevos por run.
7. Suite RED/GREEN y smoke en PostgreSQL/repositorio desechable con casos de identidad falsa, replay, revocación, drift y falta de binding.
8. Autorización explícita I1 por owner + responsables de Router/Train/PG y cambio versionado antes de `ACTIVE`.

## Este PR
`d8_i1_activation_preflight_v1.py` inspecciona un snapshot **no autenticado** y siempre devuelve `BLOCKED / NONE / activate_allowed=false`. Define 11 pruebas negativas. Un fixture `PASS` nunca se eleva a evidencia de autorización.

**No contiene SQL de activación, UPDATE del registry, grants, callable dispatcher ni salidas `READY`.** El archivo no convierte D8 en I1.

## Bloqueo preciso
`I1_OWNER_ACTIVATION_DECISION_REQUIRED`. Completar el contrato y las fuentes antes de abrir PR de migración operativa. PR #3378 es otro preflight aislado, no un motor. Issue #3376 registra rutas y dependencias.

## Validación
Ejecutar `python -m unittest sandbox/lf_contract_gate_test/programming_agent_four_stage/d8_i1/test_d8_i1_activation_preflight_v1.py` en checkout exact-HEAD; PASE separado; informar pruebas reales, no atribuir PASS al número de pruebas escritas.
