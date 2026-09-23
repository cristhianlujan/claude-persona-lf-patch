# GITHUB_CONTRACT_GATE_LF

Alias operativo: `lf-contract-check`.

- Estado operativo esperado: `ACTIVO`
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`
- Autoridad de currentness: `public.lf_activos`
- README de consumo: `sandbox/lf_contract_gate_test/transversal_assets/github_contract_gate_lf/README.md`

## Propósito

`GITHUB_CONTRACT_GATE_LF` es el consumer/orchestrator canónico del workflow `.github/workflows/lf-contract-check.yml`.
No es un segundo engine de gates. Resuelve policies, aplica el Router de CI, traduce `required_controls` al manifest declarativo y delega ejecución al engine transversal existente.

## Consumo de CHANGESET_GOVERNANCE

La revisión candidata `CHANGESET_GOVERNANCE_LF_V1` no cambia el rol de `GITHUB_CONTRACT_GATE_LF`. El workflow consume el reporte `REPORT_ONLY` producido por el Router existente, usa sus familias para resolver `required_controls` y mantiene el judge semántico fuera de esta clasificación determinística. No se crea un segundo gate engine ni se modifica el estado live del activo durante la revisión (R4).

## Cuándo consumirlo

En cualquier cambio gobernado por `lf-contract-check`, antes de declarar el lote `PASS_CLOSED` o equivalente.
El cierre está prohibido si el activo no existe en `public.lf_activos`, no está `ACTIVO`, no está indexado como `ACTIVE_SHARED_ENFORCEMENT`, falta este README o el snapshot de policies requerido no es resoluble.

## Cómo consumirlo

1. Resolver `GITHUB_CONTRACT_GATE_LF` en `public.lf_activos` y confirmar `estado_operativo=ACTIVO`, `archived_at IS NULL` e `inventory_status=ACTIVE_SHARED_ENFORCEMENT`.
2. Resolver una vez las policies desde `public.v_lf_operation_policy_snapshot`.
3. Ejecutar el preflight/Router de `lf-contract-check` y obtener `required_controls`.
4. Ejecutar los grupos seleccionados mediante `LF_GATE_GROUP_ORCHESTRATOR_V1`; no invocar engines paralelos.
5. Exigir readback de CI exacto, Claim/Excel cuando apliquen y el contrato bidireccional inventario ↔ índice ↔ README antes de cerrar.

## Superficies canónicas

- Operación: `public.lf_operation_registry.operation_code=GITHUB_CONTRACT_GATE_LF`
- Inventario: `public.lf_activos.codigo_activo=GITHUB_CONTRACT_GATE_LF`
- Policies: `public.v_lf_operation_policy_snapshot`
- Workflow: `.github/workflows/lf-contract-check.yml`
- Router: `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py`
- Manifest: `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_contract_check_control_manifest_v1.json`
- Engine transversal: `sandbox/lf_contract_gate_test/gate_check_observability/run_gate_groups_v1.py`
- Guard documental/inventario: `sandbox/lf_contract_gate_test/transversal_asset_readme/validate_active_shared_readmes_v1.py`

## Fail-closed / límites

Bloquear cierre si ocurre cualquiera de estos casos:

- activo ausente, archivado o distinto de `ACTIVO`;
- inventory status distinto de `ACTIVE_SHARED_ENFORCEMENT`;
- README ausente, no indexado o con ruta distinta a la registrada;
- policy requerida no resuelta o sin SHA;
- `required_controls` aplicable no ejecutado;
- cobertura incompleta, gate rojo o evidencia no ligada a la revisión exacta.

El consumer/orchestrator no reemplaza `GATE_CHECK_OBSERVABILITY`, `MIGRATION_SOURCE_PARITY`, Currentness, Claim ni la matriz Excel.

## Validación y readback

El cierre mínimo requiere:

- validación bidireccional `public.lf_activos ↔ transversal_assets/README.md ↔ README físico`;
- `GITHUB_CONTRACT_GATE_LF` explícitamente requerido por el guard de cierre del propio workflow;
- exact-head `lf-contract-check=PASS`;
- los controles declarados ejecutados con cobertura completa;
- readback de policy version/SHA y del activo vigente.

## No duplicación

No crear otro contract-check engine, otro Router, otro gate-group orchestrator ni otra base de inventario.
Las nuevas validaciones se agregan como controles declarativos o consumers del engine transversal existente.

## Currentness

Antes de usar este contrato releer:

1. `public.lf_activos` para estado e inventory status;
2. `public.v_lf_operation_policy_snapshot` para policy version/SHA vigentes;
3. este README desde el `main` exacto;
4. el manifest y workflow desde la misma revisión a validar.

Un PASS histórico no autoriza cierre en una revisión distinta.
