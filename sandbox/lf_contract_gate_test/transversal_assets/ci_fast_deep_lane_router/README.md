# CI_FAST_DEEP_LANE_ROUTER

Capability transversal LF: `CI_FAST_DEEP_LANE_ROUTER` / `TRANSVERSAL_CI_FAST_DEEP_LANE_ROUTER`.

## Estado

- Estado operativo esperado: `ACTIVO`
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`
- Autoridad de currentness: `public.lf_activos`
- README de consumo: `sandbox/lf_contract_gate_test/transversal_assets/ci_fast_deep_lane_router/README.md`

## Propósito

Resolver de forma determinística **qué controles CI aplican realmente a un exact-head**, evitando dos fallos:

1. ejecutar suites globales no causales sólo porque un cambio no es FAST;
2. atribuir un workflow `SUCCESS` como evidencia de un candidato que ese workflow nunca ejecutó.

`FAST/DEEP` queda como salida de compatibilidad. La autoridad material es el **plan de controles aplicables**.

## Arquitectura

```text
exact-head + base
      ↓
changed paths + material readback
      ↓
CI_FAST_DEEP_LANE_ROUTER
      ↓
lf-ci-execution-plan/v2
 ├─ required_controls[]
 ├─ required_control_reasons{}
 ├─ not_applicable_controls[]
 ├─ dependency closure
 ├─ material_evidence[] (SHA/bytes)
 ├─ carrier_controls{}
 ├─ carrier_regression_carriers[]
 ├─ coverage_complete
 └─ plan_sha256
      ↓
required workflow carriers
 ├─ lf-contract-check
 ├─ Validate LF Packs
 └─ LF Bootstrap Reproducibility Probe
      ↓
controles seleccionados solamente
```

No existe un segundo Router. `lf_ci_execution_plan_v2.py` consume la decisión de `lf_ci_lane_router.py` y la expande con el registro declarativo de impactos y dependencias.

## Cuándo consumirlo

Antes de ejecutar cualquier validación CI costosa o de atribuir un resultado CI como evidencia material.

Antes de usarlo, resolver el activo en `public.lf_activos` y confirmar que no esté archivado, que siga `ACTIVO` y que `metadata.transversal_inventory.inventory_status=ACTIVE_SHARED_ENFORCEMENT`.

## Cómo consumirlo

1. Resolver primero `CI_FAST_DEEP_LANE_ROUTER` en el inventario transversal.
2. Resolver base y exact-head reales.
3. Obtener el diff exacto; para migraciones SQL, leer también los bytes/materiales del exact-head.
4. Ejecutar `lf_ci_lane_router.py`.
5. Construir `lf-ci-execution-plan/v2` con `lf_ci_execution_plan_v2.py` / `emit_ci_execution_plan_v2.py`.
6. Cada carrier consume únicamente su `carrier_controls`.
7. Los controles no seleccionados quedan `NOT_APPLICABLE` con razón explícita; no se presentan como PASS material.
8. Cerrar únicamente cuando el plan tenga `coverage_complete=true` y la evidencia corresponda al exact-head.

## Fail-closed / límites

El plan combina:

- ownership/path del Router existente;
- triggers declarativos por path;
- triggers de material cuando el path no basta;
- closure recursivo de dependencias.

Reglas:

- cambio desconocido o no mapeado → full regression global reusable;
- cambio bajo la propia autoridad del Router/aplicabilidad → full regression global reusable;
- cambio de uno o más workflows carrier → regresión completa **solo de los carriers modificados**, más triggers path/material y closure recursivo de dependencias;
- si un workflow carrier pierde su matcher declarativo, el path queda no manejado y vuelve a full global fail-closed;
- controles que requieren un candidato material concreto no se fabrican durante una regresión genérica sin candidato: quedan N/A;
- una dependencia requerida se agrega automáticamente al plan, incluso si cruza de carrier;
- un control desconocido emitido por el Router bloquea;
- ninguna ruta puede degradarse silenciosamente a FAST.

## Migraciones de base de datos

Una migración modificada no queda probada por reconstruir el schema remoto vigente.

Cuando el plan contiene `DB_CANDIDATE_APPLY_ROLLBACK`:

1. resolver exactamente las migraciones cambiadas entre base y head;
2. calcular SHA-256/bytes del **source exact-head** de cada archivo;
3. aceptar sin transformación los candidatos sin control transaccional propio;
4. si el source usa el patrón canónico **único** `BEGIN/COMMIT` exterior, normalizar sólo esos dos statements para que el material interior corra dentro del `BEGIN/ROLLBACK` del probe;
5. bloquear cualquier otro control transaccional o statement que pueda escapar del rollback;
6. registrar por separado `source_sha256`, `execution_payload_sha256` y el modo de normalización; nunca llamar “bytes exactos ejecutados” a un payload cuyo frame fue normalizado;
7. ejecutar los statements interiores del candidato y los probes post-apply aplicables dentro de la misma transacción de CI;
8. verificar que el ledger durable permanezca idéntico antes/después;
9. persistir manifest y log, incluyendo un manifest BLOCKED aun cuando la preparación falle.

Antes de ejecutar DDL, el carrier refina la aplicabilidad contra el ledger remoto y la provenance gobernada de las migraciones ya seleccionadas por el plan:

- ninguna aplicada → `PENDING`: ejecutar candidate apply/rollback;
- todas aplicadas y con provenance exacta → `ALL_APPLIED_EXACT`: no reejecutar DDL; ejecutar únicamente los probes post-apply dentro de rollback;
- aplicada pero sin `lf_operation_effect_guard.state=SUCCEEDED`, `write_readback=PASS`, `version + name` y **Git blob exacto** del candidato → `APPLIED_UNVERIFIED` y BLOCK;
- versión existente con nombre distinto → BLOCK;
- estado mixto (unas aplicadas y otras pendientes) → BLOCK hasta disponer de una ruta explícita de aplicación selectiva.

El refinamiento evita dos falsos resultados: reejecutar una migración ya aplicada y aceptar como “exacta” una migración live sólo porque coincide su número/nombre. `MIGRATION_SOURCE_PARITY` sigue siendo una autoridad separada del control candidate-bound.

`POLICY_RESOLVER_REGRESSION`, cuando aplica, se ejecuta después del apply del candidato y antes del rollback; no usa el schema remoto anterior como sustituto del candidato.

## Full regression y carrier regression

El full regression conserva valor como auditoría del Router, pero no sustituye la causalidad del PR.

**Full global** se usa para:

- cambios a la propia autoridad del Router/aplicabilidad;
- scopes desconocidos/no mapeados;
- `main`/manual cuando corresponda.

**Carrier regression** se usa cuando cambia uno de los tres workflows carrier. El plan selecciona dinámicamente todos los controles reutilizables de `full_regression_controls` cuyo `carrier` coincide con el workflow modificado, conserva los controles disparados por path/material y luego calcula el closure recursivo de dependencias. No existe una lista paralela hardcodeada por workflow.

Ejemplo esperado para un cambio aislado de `.github/workflows/validate-lf-packs.yml`: los controles reutilizables de `VALIDATE_LF_PACKS` más los triggers transversales legítimos del path (`CI_ROUTER_SELFTEST` y `DECLARED_GOVERNANCE_PATHS`); no los restantes controles globales no causales de Bootstrap o `lf-contract-check`.

Los controles material-bound (por ejemplo candidate apply/rollback) sólo son requeridos si existe ese material en el diff; no se convierten en PASS artificial dentro de una regresión genérica.

## Carriers

Los nombres requeridos por branch protection permanecen estables:

- `Validate LF Packs`
- `lf-contract-check`
- `LF Bootstrap Reproducibility Probe`

Son **carriers del mismo plan**, no tres clasificadores independientes.

Un carrier puede terminar SUCCESS con todos sus controles N/A sólo si el plan durable demuestra esa aplicabilidad. Ese SUCCESS significa “carrier satisfecho para este plan”, no “todas sus suites globales ejecutadas”.

## Ejecutor determinístico

`LF_GATE_GROUP_ORCHESTRATOR_V1` / `GATE_CHECK_OBSERVABILITY` siguen siendo las superficies transversales para checks determinísticos agrupados y diagnóstico.

El plan decide **qué control aplica**; el orquestador ejecuta los checks declarados por el control. No duplicar esa responsabilidad dentro de manifests o YAML.

## Superficies canónicas

- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/emit_ci_execution_plan_v2.py`
- `sandbox/lf_contract_gate_test/gate_check_observability/run_gate_groups_v1.py`
- `.github/workflows/lf-contract-check.yml`
- `.github/workflows/validate-lf-packs.yml`
- `.github/workflows/lf-bootstrap-reproducibility.yml`

## Validación y readback

Como mínimo:

- tests del Router;
- tests adversariales de plan/aplicabilidad;
- carrier-wiring assurance;
- replay determinístico del mismo diff;
- unknown-path fail-closed;
- dependency closure;
- candidate exact-byte apply/rollback cuando exista migración;
- artifact del plan con `plan_sha256`;
- evidencia específica de cada control material.

Un `SUCCESS` de workflow sin vínculo demostrable al control/candidato no es evidencia suficiente.

## No duplicación

No crear:

- otro Router FAST/DEEP;
- otro clasificador Bash por workflow;
- otro motor de gate groups;
- otra matriz de policies/controls paralela.

Si aparece un nuevo tipo de material o control, extender el registro y los tests de esta capability.

## Currentness

La autoridad Git de CI es **móvil**: `refs/heads/main`. Un SHA no representa la autoridad viva; representa una observación o evidencia histórica.

Separación obligatoria:

- `diff_base_revision`: base usada para reconstruir el delta exacto del candidato;
- `authority_ref`: `refs/heads/main`;
- `authority_evidence_revision`: revisión histórica de main contra la que se evalúa currentness;
- `resolved_revision`: SHA vigente de main observado al ejecutar;
- `applicability_sha256` / `plan_sha256`: identidad estable de materiales, controles y decisión de aplicabilidad;
- `evidence_sha256`: recibo de una corrida concreta; puede diferir entre carriers/corridas porque conserva el contexto histórico observado.

Los tres carriers deben resolver main vivo y delegar el drift al **`CURRENTNESS_AUTHORITY` existente**. No crear otro currentness engine.

Reglas:

- main avanzó pero los materiales CI declarados no cambiaron → `CURRENT_REBOUND`; no rebasear sólo para obtener otro SHA;
- push a `main` → genera **evidencia nueva**: `diff_base_revision` conserva `event.before`, pero `authority_evidence_revision` nace en el `main` recién materializado; el cambio que acaba de incorporarse no se evalúa como reutilización de evidencia anterior;
- cambió un material de la autoridad CI y no existe prueba de compatibilidad → `UNKNOWN_FAIL_CLOSED`;
- cambio material demostrado como breaking → `STALE_AFFECTED`;
- historia divergente o evidencia incompleta → fail closed;
- la evidencia anterior permanece inmutable como referencia documental; no se reescribe para aparentar currentness.

En feature branches, el base histórico del último commit de la rama no debe confundirse con main. La revisión de autoridad se deriva del merge-base con `refs/heads/main`; el diff del candidato conserva su propio base/head.

Materiales de currentness de esta capability incluyen los tres workflows CI, `s28_ci_lane_router/**`, `gate_check_observability/**`, este README y la implementación `material_currentness/**`.

Antes de una decisión material, consultar además `public.lf_activos` y las superficies runtime vigentes. Si cambia el contrato de aplicabilidad, revalidar sólo el closure afectado; no perseguir el SHA global de main.
