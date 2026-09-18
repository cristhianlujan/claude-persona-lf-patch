# POL-LF-OPERATION-LIFECYCLE / OPERATION_LIFECYCLE_POLICY

Inventory status: `ACTIVE_TRANSVERSAL_POLICY`.

Este README cubre el policy code canónico `POL-LF-OPERATION-LIFECYCLE` y su alias/capability de inventario `OPERATION_LIFECYCLE_POLICY`. No son dos políticas distintas.

## Propósito

Define las condiciones mínimas de lifecycle y cierre gobernado: operación canónica, Router, contratos activos, readback y cierre fail-closed. La versión activa es `v1.1-operational-closure`.

## Cuándo consumirlo

En toda operación gobernada por Router, especialmente antes de cambiar estado o declarar `PASS_CLOSED`.

## Cómo consumirlo

Resolverlo desde `public.v_lf_operation_policy_snapshot`, congelar version + SHA al inicio y aplicar sus reglas fuera del LLM cuando sean determinísticas. Para activos transversales, complementar el cierre con el contrato README/index vivo validado por CI.

## Superficies canónicas

- Policy: `public.lf_policy_versions.policy_code=POL-LF-OPERATION-LIFECYCLE`
- Snapshot: `public.v_lf_operation_policy_snapshot`
- Operation registry: `public.lf_operation_registry`
- Step contracts: `public.lf_operation_step_contracts`
- README/index guard: `sandbox/lf_contract_gate_test/transversal_asset_readme/validate_active_shared_readmes_v1.py`

## Fail-closed / límites

Bloquear si falta una capa requerida de lifecycle, si se infiere autoridad desde un único estado, si falta readback o si un activo transversal documentable no cumple inventario + README. No usar el alias `OPERATION_LIFECYCLE_POLICY` como una segunda autoridad.

## Validación y readback

Exigir policy ACTIVE con SHA vigente, snapshot ligado a la ejecución, capas mínimas presentes y contrato README/index sin fallas. Los aliases de inventario deben apuntar a este mismo README y a la misma versión efectiva.

## No duplicación

No crear otra policy de cierre ni duplicar el payload bajo el alias. `POL-LF-OPERATION-LIFECYCLE` es la policy ejecutable; `OPERATION_LIFECYCLE_POLICY` es alias/capability de inventario.

## Currentness

Releer `public.lf_policy_versions`, `public.v_lf_operation_policy_snapshot`, `public.lf_activos` y este README antes de cierre.
