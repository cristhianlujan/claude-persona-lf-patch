# X16 — brecha de clasificación de rutas

Estado: documento de decisión para Cristhian. X16 sigue en BACKLOG. Este documento no cambia registros ni activa controles.

## Alcance y método

Sobre `main` `df3f283`, Claude reportó `271/354` grupos con `CLASSIFICATION_REQUIRED` (76,6%). Se toma ese inventario como la medición de referencia recibida. La tabla de actividad usa los 14 PRs de Train integrados a main entre el 1 y el 15/10/2026; el conteo se hace una vez por PR y grupo de ruta, no por archivo ni por reintentos. Los PRs abiertos y drafts se excluyen de esa tasa. Ninguno de los 14 contenía un changeset manifest bajo `sandbox/lf_contract_gate_test/changesets/`.

Los PRs de la cohorte son #2729, #2751, #2754, #2755, #2756, #2757, #2758, #2759, #2760, #2761, #2762, #2764, #2765 y #2766. Es un caudal observado de 7 PRs integrados por semana en esa ventana.

La agrupación de actividad y los ejemplos de rutas se contrastaron con los nombres cambiados de esos PRs. El inventario de 354 grupos es el resultado comunicado por Claude; la agrupación local reproducible por primer nivel y segundo nivel dentro de `sandbox/lf_contract_gate_test/` produjo 272 grupos (246 con al menos una ruta en `CLASSIFICATION_REQUIRED` y una ruta `.github` rechazada por admisión). La diferencia de denominador no se oculta ni se usa para inventar las otras 82 agrupaciones: el owner debe fijar la definición canónica de grupo antes de usar 271/354 como KPI.

## Grupos prioritarios

Los seis grupos con actividad aparecen ordenados por PRs integrados. Se completan veinte filas con rutas prioritarias de X16 que tuvieron cero cambios en esa cohorte; los ceros están empatados y se ordenan por prioridad de revisión. Las familias y controles de la última columna son propuestas, no cambios al registro.

| Grupo de ruta | PRs integrados / 14 días | Modo actual observado | Familia propuesta | Controles propuestos (existentes) |
|---|---:|---|---|---|
| `supabase/` (desglosar migraciones y funciones) | 8 | `SPECIALIZED_REQUIRED` para migraciones; `DEEP_SHARED_KNOWN` para funciones | Existentes: `MIGRATION` para `supabase/migrations/`, `SUPABASE_FUNCTION` para `supabase/functions/` | Migración: `DB_CANDIDATE_APPLY_ROLLBACK`, `LF_CONTRACT_CORE`, `MIGRATION_SOURCE_PARITY` según carrier; funciones: ninguno por defecto, decidir por comportamiento |
| `docs/` | 6 | `DEEP_SHARED_KNOWN`; docs de X16 `NOT_APPLICABLE` | Mantener superficie conocida; considerar familia `DOCUMENTATION` | Ninguno por defecto |
| `sandbox/lf_contract_gate_test/s28_ci_lane_router/` | 3 | `CI_ROUTER_SELFTEST_ONLY` | Existente: `CI_ROUTER` | `CI_ROUTER_SELFTEST` |
| `sandbox/lf_contract_gate_test/migration_source_parity/` | 2 | `CLASSIFICATION_REQUIRED` | Nueva: `MIGRATION_SOURCE_PARITY_TOOLING` | `MIGRATION_SOURCE_PARITY`, `CI_ROUTER_SELFTEST` |
| `sandbox/lf_contract_gate_test/train_receipt_verifier/` | 2 | `CLASSIFICATION_REQUIRED`; shadow produjo falso bloqueo | Nueva: `TRAIN_RECEIPT_VERIFIER` | `CI_ROUTER_SELFTEST`; evaluar `LF_CONTRACT_CORE` con el owner |
| `sandbox/lf_contract_gate_test/pase_f09_013/` | 1 | `CLASSIFICATION_REQUIRED` | Nueva: `PASE_PERFORMANCE_EVALUATOR` | `LF_CONTRACT_CORE` |
| `sandbox/lf_contract_gate_test/db_write_transport/` | 0 | `CLASSIFICATION_REQUIRED` | Nueva: `TRAIN_WRITE_TRANSPORT` | `CI_ROUTER_SELFTEST`, `MIGRATION_ROUTE_GUARD`, `DB_CANDIDATE_APPLY_ROLLBACK`; requiere decisión del owner del Train |
| `CLAUDE.md` | 0 | `CLASSIFICATION_REQUIRED` | Nueva: `REPOSITORY_AGENT_GUIDANCE` | `CI_ROUTER_SELFTEST`; considerar `DECLARED_GOVERNANCE_PATHS` |
| `AGENTS.md` | 0 | `CLASSIFICATION_REQUIRED` | Nueva: `REPOSITORY_AGENT_GUIDANCE` | `CI_ROUTER_SELFTEST`; considerar `DECLARED_GOVERNANCE_PATHS` |
| `.github/workflows/` | 0 | Allowlist exacta: `pase.yml` clasifica como `CI_ROUTER_SELFTEST_ONLY`; otra ruta puede fallar `FAIL_UNAUTHORIZED_GITHUB_PATH` | Existente: `WORKFLOW`; mantener admisión exacta | `CI_ROUTER_SELFTEST`, `DECLARED_GOVERNANCE_PATHS`; no ampliar allowlist sin decisión |
| `supabase/functions/get-perfil-lf-runtime-protocol-public-test/` | 0 | `DEEP_SHARED_KNOWN`, `required_controls=[]` para `deno.json` | Existente: `SUPABASE_FUNCTION`; decisión pendiente sobre controles de comportamiento runtime | Ninguno para config de prueba; valorar `PROFILE_RUNTIME_V3` o `V7_RUNTIME_REGRESSION` solo si el owner lo justifica |
| `sandbox/lf_contract_gate_test/migration_route_guard/` | 0 | `SPECIALIZED_REQUIRED` | Existente: `MIGRATION_ROUTE_GUARD` | `MIGRATION_ROUTE_GUARD` |
| `sandbox/lf_contract_gate_test/pase_merge_gate/` | 0 | `CLASSIFICATION_REQUIRED` | Nueva: `PASE_MERGE_GATE` | `CI_ROUTER_SELFTEST`, `LF_CONTRACT_CORE` |
| `sandbox/lf_contract_gate_test/pase_orchestrator/` | 0 | `CLASSIFICATION_REQUIRED` | Nueva: `PASE_ORCHESTRATOR` | `LF_CONTRACT_CORE` |
| `sandbox/lf_contract_gate_test/migration_merge_train/` | 0 | `CLASSIFICATION_REQUIRED` | Nueva: `TRAIN_MIGRATION_CARRIER` | `CI_ROUTER_SELFTEST`, `MIGRATION_SOURCE_PARITY`, `DB_CANDIDATE_APPLY_ROLLBACK` |
| `sandbox/lf_contract_gate_test/canonical_route_guard/` | 0 | `CLASSIFICATION_REQUIRED` | Nueva: `CANONICAL_ROUTE_GUARD` | `CI_ROUTER_SELFTEST`, `MIGRATION_ROUTE_GUARD` |
| `sandbox/lf_contract_gate_test/s30_migration_source_parity/` | 0 | `CLASSIFICATION_REQUIRED` | Nueva: `MIGRATION_SOURCE_PARITY_TOOLING` | `MIGRATION_SOURCE_PARITY`, `CI_ROUTER_SELFTEST` |
| `sandbox/lf_contract_gate_test/lf_migration_source_parity.py` | 0 | `SPECIALIZED_REQUIRED` | Existente: `MIGRATION` / parity validator exact path | `MIGRATION_SOURCE_PARITY` |
| `sandbox/lf_contract_gate_test/changesets/` | 0 | CI router selftest family | Existente: `CHANGESET_MANIFEST` | `CI_ROUTER_SELFTEST` |

### Evidencia de actividad para los grupos con cambios

| Grupo | PRs |
|---|---|
| `supabase/` | #2765, #2755, #2764, #2729, #2760, #2756, #2754, #2751 |
| `docs/` | #2755, #2764, #2761, #2758, #2756, #2751 |
| `s28_ci_lane_router/` | #2766, #2762, #2761 |
| `migration_source_parity/` | #2761, #2759 |
| `train_receipt_verifier/` | #2761, #2757 |
| `pase_f09_013/` | #2754 |

En la cohorte, cuatro PRs únicos tocaron rutas que el classifier reporta como `CLASSIFICATION_REQUIRED`: #2761, #2759, #2757 y #2754. PASE está `skipped`, por lo que son bloqueos potenciales estimados, no fallos de CI observados.

## Opciones para decisión de CHANGESET_GOVERNANCE

| Opción | Efecto | Impacto estimado usando la cohorte |
|---|---|---|
| (a) Registrar familias para rutas activas | Conservar clasificación por ruta; resolver primero `migration_source_parity/`, `train_receipt_verifier/` y `pase_f09_013/`, y cubrir explícitamente las rutas prioritarias siguientes. No cambia la regla de cambios ambiguos ni la allowlist de GitHub. | En rutas activas observadas: hasta 4 PRs en 14 días (2/semana) dejarían de caer en `CLASSIFICATION_REQUIRED`. La cola residual no se puede estimar con solo 14 PRs y el total reportado de 354 grupos. |
| (b) Exigir changeset manifest por PR | Cada PR debe declarar familias/controles en `sandbox/lf_contract_gate_test/changesets/`; ausencia o incoherencia bloquea fail-closed. | Los 14/14 PRs de la cohorte no llevaban manifest: hasta 14 por 14 días (7/semana) quedarían bloqueados a la espera de añadirlo durante la adaptación. Tras adopción, el bloqueo esperado es cero para manifests válidos; no se presume adopción. |

Las tasas describen PRs integrados y son estimaciones de impacto contrafactual. No cuantifican PRs abiertos/drafts ni permiten concluir que esos cambios fueron bloqueados en producción.

## Decisiones que pertenecen a Cristhian

- Confirmar la definición canónica de los 354 grupos y reconciliarla con el recuento local de 272.
- Elegir entre registrar familias activas (a) o exigir manifiesto por PR (b), o indicar un orden de transición.
- Aprobar cada familia y el mapeo de controles; las sugerencias de esta tabla no alteran `lf_change_family_registry_v1.json`, ownership compartido, impacto ni cuarentena.
- Decidir si las rutas runtime de prueba requieren control y preservar la admisión exacta de workflows.

No se editaron registros, workflows, `db_write_transport/**` ni se hicieron escrituras a la base. X16 permanece en BACKLOG.