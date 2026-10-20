# Decisión del propietario: C3 proporcional para LF_ROUTER_ARCHITECTURE_WAVE_V1 (V1)

Estado: **APROBADO por el propietario (Cristhian) en el chat el 2026-10-20 15:53 (Lima), con el ajuste de alcance de abajo.** Solo documental: no cambia contratos ni BD.

Plan: `LF_ROUTER_ARCHITECTURE_WAVE_V1`. Alcance: solo checkpoints **PENDING**.
Fuera de alcance (no se tocan): `RW1-01_C1..C3`, `RW1-02_C1`, `RW1-02_C2` (DONE).

## Precedente en el repo
La misma decisión ya se tomó para `PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1` (A1Q–A14Q C3): `docs/programming-agent/ANALYSIS_C3_TIER_ACCEPTANCE_DECISION_V1.md`, clase `OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT`, con `provider_attested=false`, `real_execution_receipt=false`, `independent_review=false`.

## Propuesta
| Checkpoint pendiente | Hoy | Propuesto |
|---|---|---|
| RW1-02_C3 | spec ya ligada y estricta (22 condiciones, incluye juez atestado) | **se deja como está**: ya está en curso (revisión REVISE y handoff V2 existentes); relajarla a mitad de camino ahorra poco |
| RW1-03_C3 | sin action spec ligada aún | nivel equivalente aprobado (chat separado, paquete ciego) al escribir su spec |
| RW1-04_C3 | sin action spec ligada aún | nivel equivalente aprobado, más CI/PASE ya exigidos por la unidad |
| RW1-05_C3 | sin spec aún | **se mantiene** nivel completo (no-bypass, doble objeto, Train, permisos) |
| RW1-06_C3 | sin spec aún | **se mantiene** nivel completo (cierre del plan, PASS/FAIL/GAP explícito) |
| C1 y C2 de RW1-03..06 | 3 controles negativos cada uno | **se mantienen** (baratos) |

## Condiciones
- Una ronda adversarial por checkpoint. Si hay defectos: reparación causal y una prueba específica, no campañas (ya lo dice el criterio de salida de RW1-06).
- Paquete ciego por checkpoint, ligado por hash; chat distinto al del productor.
- Todo cierre registra `provider_attested=false` e `independent_review=false` mientras no haya recibo real del proveedor.
- Reversible hacia adelante: un juez independiente real puede reemplazar este nivel.
- No cubre runtime ni producción (`runtime_activation=false`, `production_activation=false` en las 6 unidades); si eso cambia, se reevalúa.

## Decisión del propietario
[ ] Aprobado   [ ] Aprobado con cambios   [ ] Rechazado       Fecha: ________

## Efecto práctico
No requiere migración ahora: RW1-03..06 no tienen action spec ligada, así que la decisión guía las specs que se escriban. Solo RW1-02_C3 tiene una spec ligada y se deja intacta.
