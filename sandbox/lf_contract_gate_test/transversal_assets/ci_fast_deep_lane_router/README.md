# CI_FAST_DEEP_LANE_ROUTER

Capability transversal LF: `CI_FAST_DEEP_LANE_ROUTER` / `TRANSVERSAL_CI_FAST_DEEP_LANE_ROUTER`.

## Estado

- Estado operativo esperado: `ACTIVO`
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`
- Autoridad de currentness: `public.lf_activos`
- README de consumo: `sandbox/lf_contract_gate_test/transversal_assets/ci_fast_deep_lane_router/README.md`

## Propósito

Resolver de forma determinística qué controles CI aplican a un exact-head, evitando dos fallos:

1. ejecutar suites globales no causales por fallback;
2. atribuir un workflow `SUCCESS` como evidencia de un control/candidato que no ejecutó.

`FAST/DEEP` es compatibilidad. La autoridad material es el plan de controles aplicables.

## Arquitectura

```text
exact-head + base
      ↓
Changeset Governance + ownership declarativo
      ↓
CI_FAST_DEEP_LANE_ROUTER
      ↓
lf-ci-execution-plan/v2
 ├─ applicability_decision
 ├─ required_controls[]
 ├─ required_control_reasons{}
 ├─ not_applicable_controls[]
 ├─ dependency closure
 ├─ material_evidence[]
 ├─ carrier_controls{}
 ├─ coverage_complete
 └─ plan_sha256
      ↓
canonical carriers solamente
 ├─ lf-contract-check
 ├─ Validate LF Packs
 └─ LF DB Regression
      ↓
receipts por carrier
      ↓
FULL_REGRESSION consumes the governed plan
 └─ verifica planned == executed, cero extras y cero duplicación
```

No existe un segundo Router. `lf_ci_execution_plan_v2.py` consume la decisión de `lf_ci_lane_router.py` y el registro declarativo de impactos/dependencias.

`FULL_REGRESSION` tampoco es un Router ni un cuarto carrier. Es un consumidor/verificador transversal del plan ya resuelto.

## Cuándo consumirlo

Antes de ejecutar validaciones CI costosas, atribuir un resultado de carrier a un candidato o solicitar una comprobación FULL_REGRESSION. Primero debe existir una decisión de applicability gobernada para el exact-head.

## Cómo consumirlo

1. Resolver `CI_FAST_DEEP_LANE_ROUTER` en `public.lf_activos`.
2. Resolver base y exact-head.
3. Obtener el diff exacto; para SQL, leer materiales desde exact-head.
4. Ejecutar Changeset Governance / `lf_ci_lane_router.py`.
5. Construir `lf-ci-execution-plan/v2`.
6. Cada carrier ejecuta únicamente su `carrier_controls`.
7. Los controles no seleccionados quedan `NOT_APPLICABLE`; no se ejecutan para fabricar PASS.
8. Cuando se solicite FULL_REGRESSION, entregar el mismo plan y los receipts de los carriers a `full_regression_v1.py`.
9. Cerrar únicamente con `coverage_complete=true`, hash válido y evidencia exact-head.

## Autoridad de applicability

La clasificación y applicability preceden a FULL_REGRESSION:

`CHANGESET_GOVERNANCE_LF_V1 → LF_CI_EXECUTION_PLAN_V2 → carriers → FULL_REGRESSION`

Reglas:

- `FULL_REGRESSION` no agrega controles;
- `--force-full` conserva el nombre CLI por compatibilidad, pero significa “verificar el plan gobernado con FULL_REGRESSION”, no “run everything”;
- cambio de la propia autoridad CI puede solicitar verificación full, pero no amplía `required_controls`;
- cambio de workflow carrier puede marcar `carrier_regression` para observabilidad, pero no añade todos los controles de ese carrier;
- scope no clasificado / registry inválido / plan vacío sin applicability resuelta → BLOCK;
- ruta conocida sin trigger puede quedar `NOT_APPLICABLE`;
- dependencias declaradas siguen cerrándose de forma recursiva;
- un control desconocido emitido por la autoridad bloquea.

El campo histórico `full_regression_controls` de `lf_ci_control_impact_registry_v2.json` puede permanecer para compatibilidad/readback, pero tiene semántica:
`HISTORICAL_COMPATIBILITY_IGNORED_FOR_APPLICABILITY`.

Cambiar ese campo no puede cambiar `required_controls`.

## FULL_REGRESSION

Activo transversal propio:

- código: `FULL_REGRESSION`
- nombre: `TRANSVERSAL_FULL_REGRESSION`
- README: `sandbox/lf_contract_gate_test/transversal_assets/full_regression/README.md`
- implementación: `sandbox/lf_contract_gate_test/transversal_assets/full_regression/full_regression_v1.py`
- judge: `sandbox/lf_contract_gate_test/transversal_assets/full_regression/judge_full_regression_semantics_v1.py`

Invariantes:

- `LOCAL_APPLICABILITY_DECISIONS = 0`
- `PLANNED_CONTROLS = EXECUTED_CONTROLS`
- `UNPLANNED_EXECUTIONS = 0`
- `DUPLICATE_CONTROL_EXECUTIONS = 0`
- `RETIRED_CONTROL_EXECUTIONS = 0`
- `PARALLEL_APPLICABILITY_ENGINE = 0`
- `FAIL_OPEN_CASES = 0`
- `PARALLEL_ACTIVE_PATHS = 0`

## Fail-closed / límites

No existe fallback “desconocido → ejecutar todo”.

Bloquean de forma inequívoca:

- applicability sin resolver;
- plan ausente/corrupto/incompleto;
- plan hash inválido;
- currentness stale/unready;
- carrier irresoluble;
- receipt faltante, duplicado, extra, con hash/revisión incompatible;
- `planned != executed`;
- control retirado planificado/ejecutado.

Un plan inválido nunca se sustituye por una regresión global.

## NOT_APPLICABLE

Cuando `required_controls=[]`:

- `applicability_decision=NOT_APPLICABLE`;
- no se ejecutan controles;
- FULL_REGRESSION acepta cero carrier receipts;
- el receipt final conserva cero ejecuciones.

`NOT_APPLICABLE` no es PASS sintético.

## Migraciones de base de datos

Una migración modificada no queda probada por reconstruir el schema remoto vigente.

Cuando el plan contiene `DB_CANDIDATE_APPLY_ROLLBACK`:

1. resolver exactamente migraciones cambiadas base→head;
2. calcular SHA-256/bytes del source exact-head;
3. aceptar sin transformación candidatos sin control transaccional propio;
4. si existe el patrón único `BEGIN/COMMIT` exterior, normalizar solo ese frame para ejecutar dentro del `BEGIN/ROLLBACK` del probe;
5. bloquear otro control transaccional que pueda escapar del rollback;
6. registrar por separado `source_sha256`, `execution_payload_sha256` y modo de normalización;
7. ejecutar candidato + probes post-apply aplicables dentro de la misma transacción;
8. verificar ledger durable idéntico antes/después;
9. persistir manifest/log incluso cuando preparación bloquee.

Si el candidato exige actor gobernado, solo puede usar el marker canónico `LF_CI_ROLLBACK_GOVERNED_ACTOR_V1`, resolverlo por `lf_ci_candidate_actor_bootstrap_registry_v1.json`, materializar mediante el begin RPC canónico dentro del mismo rollback y demostrar que el actor no persiste.

Antes de DDL, el carrier refina contra ledger/provenance:

- ninguna aplicada → `PENDING`;
- todas aplicadas con provenance exacta → `ALL_APPLIED_EXACT`, sin reejecutar DDL;
- aplicada sin evidence exacta → `APPLIED_UNVERIFIED` y BLOCK;
- versión con nombre distinto → BLOCK;
- estado mixto → BLOCK.

`MIGRATION_SOURCE_PARITY` sigue siendo autoridad separada. `POLICY_RESOLVER_REGRESSION` corre post-apply/pre-rollback cuando el plan lo requiere.

## Carriers

Los nombres requeridos por branch protection permanecen estables:

- `Validate LF Packs`
- `lf-contract-check`
- `LF DB Regression`

Son carriers del mismo plan, no clasificadores independientes.

Un carrier puede terminar SUCCESS con todos sus controles N/A solo cuando el plan gobernado demuestra esa applicability. Ese SUCCESS no significa “todas las suites globales ejecutadas”.

## Ejecutor determinístico

`LF_GATE_GROUP_ORCHESTRATOR_V1` / `GATE_CHECK_OBSERVABILITY` siguen ejecutando checks determinísticos agrupados.

El plan decide qué control aplica; el orquestador ejecuta los checks declarados. FULL_REGRESSION solo consume receipts y verifica exactitud/no duplicación.

## Superficies canónicas

- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_changeset_governance.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_shared_ci_control_ownership_registry_v1.json`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/emit_ci_execution_plan_v2.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_currentness_bridge_v1.py`
- `sandbox/lf_contract_gate_test/transversal_assets/full_regression/README.md`
- `sandbox/lf_contract_gate_test/transversal_assets/full_regression/full_regression_v1.py`
- `sandbox/lf_contract_gate_test/transversal_assets/full_regression/judge_full_regression_semantics_v1.py`
- `sandbox/lf_contract_gate_test/gate_check_observability/run_gate_groups_v1.py`
- `.github/workflows/lf-contract-check.yml`
- `.github/workflows/validate-lf-packs.yml`
- `.github/workflows/lf-db-regression.yml`

## Validación y readback

Como mínimo:

- tests Changeset Governance/Router;
- pruebas P1–P8;
- plan/applicability adversarial;
- carrier-wiring assurance;
- replay determinístico;
- unresolved scope fail-closed;
- dependency closure;
- candidate exact-source apply/rollback cuando aplique;
- FULL_REGRESSION E2E A–E;
- semantic judge independiente;
- readback exact-head;
- CI exact-head.

Un workflow SUCCESS sin vínculo al plan/control/candidato no es evidencia suficiente.

## No duplicación

No crear:

- otro Router FAST/DEEP;
- otro applicability engine;
- otro registry;
- otro carrier;
- otro FULL_REGRESSION;
- otro currentness engine.

Extender las autoridades existentes y sus tests.

## Currentness

La autoridad Git de CI es móvil: `refs/heads/main`. Un SHA es una observación histórica, no la autoridad viva.

Separación:

- `diff_base_revision`;
- `authority_ref=refs/heads/main`;
- `authority_evidence_revision`;
- `resolved_revision`;
- `applicability_sha256/plan_sha256`;
- `evidence_sha256`.

Los tres carriers resuelven main vivo y delegan drift a `CURRENTNESS_AUTHORITY`.

Materiales de currentness incluyen:

- los tres workflows;
- `s28_ci_lane_router/**`;
- `gate_check_observability/**`;
- `transversal_assets/ci_fast_deep_lane_router/**`;
- `transversal_assets/full_regression/**`;
- `material_currentness/**`.

Reglas vigentes:

- main avanzó sin cambio material relevante → `CURRENT_REBOUND`;
- push a main genera evidencia nueva;
- material de autoridad cambiado sin compatibilidad → `UNKNOWN_FAIL_CLOSED`;
- cambio material breaking → `STALE_AFFECTED`;
- historia divergente/evidencia incompleta → fail closed.

## CHANGESET_GOVERNANCE_LF_V1

Changeset Governance es upstream de FULL_REGRESSION.

- rutas desconocidas → `CLASSIFICATION_REQUIRED`;
- familias fijas vienen de `lf_change_family_registry_v1.json`;
- manifiestos solo clasifican rutas no cubiertas por ownership/familias;
- `PR_INTEGRITY` puede operar en `REPORT_ONLY`;
- `MIGRATION_SOURCE_PARITY` se consume solo cuando la familia/control aplicable lo requiere.

La solución FULL_REGRESSION no cambia esas responsabilidades; solo elimina la expansión local posterior al plan.
