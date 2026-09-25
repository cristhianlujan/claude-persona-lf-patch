# GITHUB_CONTRACT_GATE_LF

Alias operativo: `lf-contract-check`.

- Estado operativo esperado: `ACTIVO`
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`
- Autoridad de currentness: `public.lf_activos`
- README de consumo: `sandbox/lf_contract_gate_test/transversal_assets/github_contract_gate_lf/README.md`

## Propósito

`GITHUB_CONTRACT_GATE_LF` es el consumer/orchestrator canónico del workflow `.github/workflows/lf-contract-check.yml`.
No es un segundo engine de gates. Resuelve policies, aplica el Router de CI, traduce `required_controls` al manifest declarativo y delega ejecución al engine transversal existente.

## Decisión arquitectónica

Decisión: **RESTRUCTURE, no retirar**.

`lf-contract-check` conserva valor como frontera de composición y cierre de CI. Su responsabilidad es decidir qué controles aplican a una revisión, comprobar que la composición declarada está completa y producir una decisión agregada ligada al candidato exacto.

No debe convertirse en autoridad semántica de cada dominio ni absorber la implementación interna de controles como Migration Parity, Currentness, PRE_EKB, observabilidad u otros controles transversales. Esos controles mantienen su propia autoridad y contrato; `lf-contract-check` los consume/orquesta cuando el Router y el manifest indican que aplican.

## Problema que corrige esta reestructuración

Históricamente el workflow acumuló validadores y responsabilidades heterogéneas. Eso generó cuatro riesgos:

1. **Segunda autoridad:** reglas de scope, receipt o aplicabilidad podían quedar hardcodeadas en el consumer además de existir en registries/manifests.
2. **Duplicidad:** lógica perteneciente a controles especializados podía terminar ejecutándose o reinterpretándose dentro del contract-check.
3. **Blast radius alto:** un cambio interno de un control de dominio podía romper el gate transversal completo aunque la composición fuese correcta.
4. **Falsos BLOCK/PASS:** cuando aplicabilidad, currentness o evidencia se resolvían en más de una superficie, dos autoridades podían discrepar.

La solución no es retirar el gate, sino adelgazarlo hasta dejar una única responsabilidad transversal: **composición + completitud + binding + decisión agregada**.

## Frontera de responsabilidad

### `lf-contract-check` SÍ debe

- resolver el candidato exacto y su contexto de CI;
- aplicar el Router de CI;
- obtener `required_controls` desde la autoridad declarativa vigente;
- comprobar que cada control requerido tiene binding/manifest resoluble;
- delegar la ejecución al engine/control propietario;
- recoger verdictos y evidencia de los controles aplicables;
- bloquear si falta un control requerido, binding, currentness o evidencia obligatoria;
- emitir el resultado agregado para GitHub sin reinterpretar la semántica interna de cada control.

### `lf-contract-check` NO debe

- implementar por sí mismo la semántica de Migration Parity, Currentness, PRE_EKB, observabilidad u otros controles de dominio;
- mantener allowlists o reglas paralelas que ya tengan autoridad en registries/manifests;
- crear un segundo engine de gates;
- decidir lifecycle o estado activo de los controles;
- sustituir `public.lf_activos`, el policy snapshot o los registries declarativos como autoridad;
- convertir un PASS histórico en PASS para otra revisión.

## Relaciones y dependencias

Flujo lógico:

```text
GitHub candidate / exact revision
          |
          v
GITHUB_CONTRACT_GATE_LF (`lf-contract-check`)
          |
          +--> CI Router
          |       |
          |       v
          |   required_controls
          |       |
          +-------+
          |
          v
control manifest / bindings / policies
          |
          v
LF_GATE_GROUP_ORCHESTRATOR_V1
          |
          +--> Migration Parity (si aplica)
          +--> Currentness (si aplica)
          +--> PRE_EKB (si aplica)
          +--> Observability / otros controles declarados (si aplican)
          |
          v
veredictos + evidencia exacta
          |
          v
PASS / BLOCK agregado para GitHub
```

Regla de dependencia: una relación con otro control significa **consumo/delegación**, no ownership de su semántica.

## Clasificación de relaciones

Al documentar una dependencia de `lf-contract-check`, clasificarla explícitamente como una de estas categorías:

| Tipo | Significado |
|---|---|
| `RUNTIME` | dependencia necesaria para ejecutar/orquestar el control |
| `EVIDENCE` | fuente o contrato requerido para demostrar el resultado |
| `APPLICABILITY` | decide si un control debe ejecutarse para el cambio actual |
| `REFERENCE_ONLY` | referencia documental; no participa en ejecución |
| `LEGACY` | relación histórica que no debe gobernar comportamiento nuevo |

No usar una dependencia `REFERENCE_ONLY` o `LEGACY` como autoridad operacional.

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

Antes de agregar lógica nueva directamente al workflow o a `scripts/lf_contract_check.py`, responder:

1. ¿La regla pertenece realmente a composición/aplicabilidad/cierre agregado?
2. ¿Ya existe un control propietario de esa semántica?
3. ¿Puede expresarse mediante registry/manifest/binding sin hardcodearla en el consumer?

Si la respuesta a 2 o 3 es sí, no duplicar la regla dentro de `lf-contract-check`.

## Criterio de evolución

Una modificación futura de `lf-contract-check` es arquitectónicamente válida solo si mantiene estas invariantes:

- una sola autoridad por regla;
- aplicabilidad declarativa y trazable;
- ejecución delegada al control propietario;
- evidencia ligada a candidate SHA/revisión exacta;
- fallo cerrado ante ambigüedad material;
- ausencia de engines, registries o policies paralelos.

## Currentness

Antes de usar este contrato releer:

1. `public.lf_activos` para estado e inventory status;
2. `public.v_lf_operation_policy_snapshot` para policy version/SHA vigentes;
3. este README desde el `main` exacto;
4. el manifest y workflow desde la misma revisión a validar.

Un PASS histórico no autoriza cierre en una revisión distinta.
