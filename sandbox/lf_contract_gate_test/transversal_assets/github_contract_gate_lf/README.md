# GITHUB_CONTRACT_GATE_LF

Alias operativo: `lf-contract-check`.

- Estado operativo esperado: `ACTIVO`
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`
- Autoridad de currentness: `public.lf_activos`
- README de consumo: `sandbox/lf_contract_gate_test/transversal_assets/github_contract_gate_lf/README.md`

## Propósito

`GITHUB_CONTRACT_GATE_LF` es el consumer/orchestrator canónico del workflow `.github/workflows/lf-contract-check.yml`.
No es un segundo engine de gates. Resuelve policies, aplica el Router de CI, traduce `required_controls` al manifest declarativo y delega ejecución al engine transversal existente.

También es el owner del boundary compartido de readback HTTP de GitHub utilizado por consumers del contract gate. Los consumers no deben implementar por separado retry, clasificación de red ni semántica de autenticación.

## Cuándo consumirlo

En cualquier cambio gobernado por `lf-contract-check`, antes de declarar el lote `PASS_CLOSED` o equivalente.
El cierre está prohibido si el activo no existe en `public.lf_activos`, no está `ACTIVO`, no está indexado como `ACTIVE_SHARED_ENFORCEMENT`, falta este README o el snapshot de policies requerido no es resoluble.

## Cómo consumirlo

1. Resolver `GITHUB_CONTRACT_GATE_LF` en `public.lf_activos` y confirmar `estado_operativo=ACTIVO`, `archived_at IS NULL` e `inventory_status=ACTIVE_SHARED_ENFORCEMENT`.
2. Resolver una vez las policies desde `public.v_lf_operation_policy_snapshot`.
3. Ejecutar el preflight/Router de `lf-contract-check` y obtener `required_controls`.
4. Ejecutar los grupos seleccionados mediante `LF_GATE_GROUP_ORCHESTRATOR_V1`; no invocar engines paralelos.
5. Para readback de evidencia vía GitHub, consumir `github_api_readback_v1.py`; el consumer no debe llamar `api.github.com` por su cuenta.
6. Exigir readback de CI exacto, Claim/Excel cuando apliquen y el contrato bidireccional inventario ↔ índice ↔ README antes de cerrar.

## Boundary GitHub provider readback v1

Superficie: `sandbox/lf_contract_gate_test/transversal_assets/github_contract_gate_lf/github_api_readback_v1.py`.

Contrato de resiliencia:

- máximo 3 intentos por request;
- backoff acotado y determinista;
- retry únicamente para red y HTTP `408/429/500/502/503/504`;
- `401/403` => `FAIL_AUTH`, sin retry;
- DNS agotado => `BLOCKED_INFRA_DNS`;
- API transitoria agotada => `BLOCKED_GITHUB_API`;
- HTTP no reintentable => `FAIL_GITHUB_API`;
- JSON/shape/tamaño inválidos => `FAIL_EVIDENCE_MISMATCH`;
- cualquier no-PASS permanece fail-closed.

El boundary declara `EVIDENCE_RESOLVER_REGISTRY` como autoridad del registro de resolvers, pero no inventa ni remapea `resolver_id`. Si un consumer necesita anclar evidencia durable en el ledger y no existe un resolver compatible con ese tipo de evidencia, debe bloquear; no reutilizar un resolver de otra semántica.

`PR93_LOTE_E16_GITHUB_INVENTORY.py` consume este boundary. Por tanto, E.16 deja de poseer su propia implementación de transporte HTTP/retry.

## Superficies canónicas

- Operación: `public.lf_operation_registry.operation_code=GITHUB_CONTRACT_GATE_LF`
- Inventario: `public.lf_activos.codigo_activo=GITHUB_CONTRACT_GATE_LF`
- Policies: `public.v_lf_operation_policy_snapshot`
- Workflow: `.github/workflows/lf-contract-check.yml`
- Router: `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py`
- Manifest: `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_contract_check_control_manifest_v1.json`
- Engine transversal: `sandbox/lf_contract_gate_test/gate_check_observability/run_gate_groups_v1.py`
- GitHub provider boundary: `sandbox/lf_contract_gate_test/transversal_assets/github_contract_gate_lf/github_api_readback_v1.py`
- GitHub provider boundary tests: `sandbox/lf_contract_gate_test/transversal_assets/github_contract_gate_lf/test_github_api_readback_v1.py`
- Guard documental/inventario: `sandbox/lf_contract_gate_test/transversal_asset_readme/validate_active_shared_readmes_v1.py`

## Fail-closed / límites

Bloquear cierre si ocurre cualquiera de estos casos:

- activo ausente, archivado o distinto de `ACTIVO`;
- inventory status distinto de `ACTIVE_SHARED_ENFORCEMENT`;
- README ausente, no indexado o con ruta distinta a la registrada;
- policy requerida no resuelta o sin SHA;
- `required_controls` aplicable no ejecutado;
- cobertura incompleta, gate rojo o evidencia no ligada a la revisión exacta;
- fallo de DNS/API agotado tras retry acotado;
- autenticación GitHub inválida;
- evidencia GitHub mal formada o no correspondiente a la identidad exacta.

El consumer/orchestrator no reemplaza `GATE_CHECK_OBSERVABILITY`, `MIGRATION_SOURCE_PARITY`, Currentness, Claim ni la matriz Excel.

## Validación y readback

El cierre mínimo requiere:

- validación bidireccional `public.lf_activos ↔ transversal_assets/README.md ↔ README físico`;
- `GITHUB_CONTRACT_GATE_LF` explícitamente requerido por el guard de cierre del propio workflow;
- exact-head `lf-contract-check=PASS`;
- los controles declarados ejecutados con cobertura completa;
- readback de policy version/SHA y del activo vigente;
- tests deterministas del boundary para success, DNS, HTTP transitorio, auth, evidencia mal formada y HTTP no reintentable.

## No duplicación

No crear otro contract-check engine, otro Router, otro gate-group orchestrator, otra base de inventario ni otro cliente HTTP GitHub dentro de cada consumer.
Las nuevas validaciones se agregan como controles declarativos o consumers del engine/boundary transversal existente.

## Currentness

Antes de usar este contrato releer:

1. `public.lf_activos` para estado e inventory status;
2. `public.v_lf_operation_policy_snapshot` para policy version/SHA vigentes;
3. este README desde el `main` exacto;
4. el manifest, workflow y boundary desde la misma revisión a validar.

Un PASS histórico no autoriza cierre en una revisión distinta.
