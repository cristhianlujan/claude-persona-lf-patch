# OWNER_RUNNER_CARRIER_AUTHORITY V1

## Propósito

`OWNER_RUNNER_CARRIER_AUTHORITY` materializa un **read-model derivado** para el PASE:

`control -> LF_GOVERNANCE -> capability/runner -> carrier -> state -> source_revision`

No crea un owner registry, no reemplaza las autoridades actuales y no persiste un catálogo paralelo.

## Decisión arquitectónica

El intento histórico de PR #1186 de persistir un `binding_catalog` fue descartado posteriormente por la restauración canónica de #1223. Este lote **no revive ese catálogo**.

La autoridad continúa distribuida por responsabilidad:

| Dato | Autoridad |
|---|---|
| aplicabilidad / required controls | `lf-ci-execution-plan/v2` producido por Changeset Governance |
| super admin | `plan.governance_admin` derivado de `LF_GOVERNANCE_SUPER_ADMIN_V1` |
| carrier | `lf_ci_control_impact_registry_v2.json` |
| clasificación control/capability | `PASE_CONTROL_BINDING_INVENTORY_V1`, evidencia read-only; nunca autoridad ejecutable |
| activos/relaciones | `public.lf_activos` / `public.lf_activo_relaciones` |
| capability/version/current/binding | `public.lf_capability_registry`, `lf_capability_version_registry`, `lf_capability_current`, `lf_capability_binding` |

El resolver únicamente compone esas fuentes y produce un snapshot con digest propio.

## Entrada obligatoria del Orquestador

No se acepta una bandera local `valid=true`.

La **autoridad de autenticidad** es el guard vivo:

`public.fn_lf_capability_orchestrator_entry_guard_v1(...)`

invocado por el entrypoint canónico:

`public.fn_lf_capability_bind_from_orchestrator_v1(...)`.

El core de este lote valida la forma del readback para no consumir entradas incompletas, pero **esa validación local no autentica el receipt**. El cableado que obtiene y entrega el readback vivo pertenece a `SADM-PP-L1-009`; ya está materializado y no se duplica aquí.

El resolver exige como precondición:

- `ready=true` en el binding;
- `entry_guard.ready=true`;
- `entry_guard.decision=ORCHESTRATOR_ENTRY_ACCEPTED`;
- `guard_code=ORCHESTRATOR_EXECUTION_GUARD_V1`;
- `orchestrator_execution_id` y `receipt_id` presentes.

Si falta cualquiera, BLOCK. Aunque `L1-009` ya materializó el wiring de invocación/receipt, este paquete permanece candidato/read-only y no es por sí mismo un entrypoint público activo.

Flujo objetivo:

```text
cualquier caller
      |
      v
ORCHESTRATOR_EXECUTION_GUARD_V1  <--- autoridad viva; L1-009 cablea receipt
      |
      +-- receipt inválido --------------------------> BLOCK
      |
      +-- receipt válido
      v
OWNER_RUNNER_CARRIER_AUTHORITY
      |
      v
resuelve read-model sobre autoridades existentes
```

## Reglas de resolución

1. `LF_GOVERNANCE` es la única raíz administrativa.
2. Carrier nunca se convierte en owner.
3. Un `INTERNAL_CI_CHECK` no crea capability standalone: su runner state efectivo es `CARRIER_INTERNAL`.
4. Una capability standalone usa su identidad/runner conocido solo cuando la evidencia canónica lo permite.
5. Candidate/read-only/unmerged y registered-not-cutover permanecen bloqueados para ejecución.
6. Carrier drift, control desconocido, duplicado o owner desconocido bloquean fail-closed.
7. El output es evidencia/read-model; no activa, no rebind y no hace cutover.

## Relaciones materiales

La proyección candidata usa únicamente tipos de relación ya existentes:

- `DEPENDE_DE -> CURRENTNESS_AUTHORITY` para currentness del snapshot;
- `RELACIONADO_CAPACIDADES -> LF_GOVERNANCE` para discoverability administrativa.

`GOBERNADO_POR` **no se usa** porque el readback vigente lo reserva para la semántica del Router `ACT-0001`.

El edge de inventario no reemplaza el owner contract. La raíz administrativa se resuelve desde `plan.governance_admin`.

## Estado de este lote

- source-only para este read-model;
- no fila nueva de `OWNER_RUNNER_CARRIER_AUTHORITY` en `lf_capability_registry`;
- no current pointer propio;
- no binding live propio;
- wiring live de invocación/receipt disponible vía `SADM-PP-L1-009`, sin duplicarlo en este paquete;
- no cutover propio;
- no runtime propio;
- no producción.

La proyección de `lf_activos`/`lf_activo_relaciones` queda preparada para una aplicación separadamente autorizada. La activación como capability registrable pertenece a un paso posterior, después de calificación y contrato de invocación/receipt.

## DoD L1-008

- contrato: `owner_runner_carrier_authority_contract_v1.json`;
- resolver: `owner_runner_carrier_authority_v1.py`;
- pruebas: `test_owner_runner_carrier_authority_v1.py`;
- activo/relaciones/inventario source-only: `OWNER_RUNNER_CARRIER_AUTHORITY_registry_projection_v1.sql`;
- EKB preflight/readback: obligatorio antes y después del lote;
- 1 solución = 1 PR;
- no ZIP.
