# TARJETA B07 — decisión LF4 / SALY5

**Estado:** PROPUESTA · PENDIENTE FIRMA · sin escritura en Supabase.

## Para qué sirve
Agregar trazabilidad del ciclo de vida de cada **regla**, sin cambiar los estados actuales. LF mantiene CANDIDATO/VIGENTE y SALY mantiene sus 14 reglas VALIDADAS. Los 10 estados y 10 transiciones actuales de SALY describen **adelantos**, no aprobación de reglas.

## Arquitectura propone 9 campos nuevos — TODOS INFERIDOS
**LF (4)**: `lifecycle_state` (fase); `lifecycle_source_sha256` (huella de origen); `lifecycle_decision_ref` (decisión); `lifecycle_changed_at` (cuándo).
**SALY (5)**: los cuatro anteriores + `lifecycle_origin_estado` (copia del `estado` SALY; debe coincidir con `VALIDADO` cuando corresponda).

**Tipos/defaults:** estado y referencias `text`, huella `text` de 64 hex, fecha `timestamptz`; los nueve parten en **NULL**, sin backfill automático. Solo el **escritor gobernado oficial** podrá llenarlos después de una decisión; no se propone autorizar SQL directo.

## Qué NO cambia
- `lf_ops.reglas.estado`, `saly.reglas.estado`, `saly.reglas.vigente` y `decision_id` permanecen intactos.
- **VALIDADO no se traduce automáticamente a VIGENTE**.
- Ninguna función V2 se reemplaza, no se promueven reglas y no se tocan RUN históricos.
- DOWN bloquea cuando hay datos nuevos, para evitar perder evidencia.

## Riesgos que se están decidiendo
**1.** Los nueve nombres son hipótesis: falta definición de valores de lifecycle_state. **2.** `lifecycle_origin_estado` podría resultar redundante frente a `estado`. **3.** Falta conectar permisos, consumidores y el escritor oficial. **4.** PG aislado no equivale a despliegue real.

## Decisión del dueño
- [ ] **APROBAR PROPUESTA DE DISEÑO** — autoriza preparar validación técnica posterior, NO desplegar ni promover.
- [ ] **AJUSTAR** — indicar los campos/semántica a corregir:

  ______________________________________________________________

**Firmante / fecha / referencia de decisión:** ________________________

**B07 continúa ABIERTO** hasta aprobación, SQL completo, regresiones, readback y evidencia de operación oficial.

**Fuentes:** Supabase SELECT `lf_ops.reglas` (578), `saly.reglas` (14), `saly.estados/transiciones` (10/10), `saly.campos/validaciones` (0/0) y migrations ledger (cinco versiones). Ver matriz para citas por campo.
