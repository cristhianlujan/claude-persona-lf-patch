# Lote 29 — Contrato de E2E IG en PostgreSQL 18 aislado

**Propósito:** cerrar únicamente una **prueba de laboratorio reproducible** para B09_E2E, informando brechas B07/B08/B12/B02/B03. NO aprobar el producto, no certificar circuito nativo, no tocar RUN/producción.

## Fuente y base
- Base exacta: `7ef5472865aaf4f86bf8491c8c7bfa82f7492309` (HEAD L26).
- EKB INPUT GOVERNANCE LF V1.4: USUARIO → ACT-0001 → PERFIL → RUN → PASOS PERFIL → IG si aplica → VALIDACIÓN → JUEZ → REGISTRO → CIERRE. **No invocar IG directamente desde Router**. Context Transport V2, contrato `LF_PROFILE_NATIVE_BEGIN_REQUEST_V1`, transporte interno mediante ticket de uso único y retorno al RUN principal.
- Fuente L26: `test_pg18_lote26_integrated_curator_closure.py`, 21/36 REAL_EN_SANDBOX, 11 SINTETICO, 4 NO_PROBADO; CI #43328149868. L26 ya acredita L23 Curator + L14 promoción + L20 sync + L24 recibos y rollback en una transacción, **no** ACT-0001/IG reales.

## Diagrama del runner nuevo

```text
CREADOR no owner (HMAC L17, rol lf_reader_role)
 └→ l29_submit_request_v1 (NEW | MODIFY_CANDIDATE | CORRECT_VIGENTE)
       ├→ evidencia obligatoria (source_ref + rationale)
       ├→ SHA-256 del candidato CANDIDATO
       └→ idempotency key: replay idéntico = NOOP; distinto = BLOCK
       ↓
SÍNTESIS de SOLICITUD/TRANSPORTE (no ACT-0001)
       ↓
PREPARACIÓN L13 / PERFIL DUEÑO HMAC L17
       ↓
CAPTURA/CITAS L7 + IG fixture L11B (NO nativo)
       ↓
l18_owner_intent_v1
 └→ l29 BEFORE INSERT exige solicitud, evidencia, huella, separación
       ↓
CURATOR L23 ACEPTAR (SQL mismo modelo, huella + sello HMAC)
       ↓
L14 wrapper/ticket ARMED (L23 no ACEPTAR ⇒ BLOCK)
       ↓
APPLY LF congelado + L20 fuente/registro VIGENTE y readback
       ↓
L29 promotion_once → L26 receipt SHA, replay NOOP
       ↓
L29 close_once → L24 closure SHA, replay NOOP
       ↓
Verificar HASH y 12 etapas, ROLLBACK transacción única
```

**Caso NEW:** candidato nuevo sintético; fixture A no conflictivo creado antes de gates.

**Caso MODIFY_CANDIDATE:** candidato de muestra **preexistente en el ciclo del fixture** cambia `valor_config.l29_revision` de ausente a `"2"` **antes de capturar evidencia**, se comparan hashes pre/post y se aprueba esa revisión como CANDIDATO. **NO equivale a editar una VIGENTE**.

**Caso CORRECT_VIGENTE:** sucesora explícita de `RULE-DEPENDENCY-001`, aprobación owner HMAC, cambio de predecesora a SUCEDIDA por L20. No alterar la regla congelada.

## Negativas requeridas (pruebas reales PG18, no artificios de PASS)

1. Sin permiso: `lf_reader_role` intenta aprobar, falla L17.
2. SUPER_ADMIN: `lf_super_role` no puede aprobar.
3. Creador = aprobador: dueño intenta crear solicitud, denegado; además el fixture malicioso superuser inserta solicitud de mismo actor, trigger de dueño bloquea sin deshabilitar guards.
4. Sin evidencia: `source_ref/rationale` ausentes, fail-closed en recepción.
5. Sin solicitud: L18 owner intent bloqueado por L29 guard.
6. Doble ejecución: repetición idéntica de solicitud, promoción y cierre devuelve NOOP y no duplica recibos; repetición con mismo ID y cuerpo distinto bloqueada.
7. DML directo por rol cliente a tabla de intake denegado.
8. Error inyectado tras promoción: reversión transaccional de candidato, owner, Curator, promoción, cierre y solicitud.

## Semántica de evidencia y límites

El sello de L29 es prueba de integridad de **fixture HMAC L17**, no identidad real de Supabase. Un `ACEPTAR` Curator L23 es lógica determinista escrita por **GPT-6, mismo modelo, sin juez independiente**. Los recibos L11B/L18 de IG/Step70 siguen **sintéticos** y su `system_attestation=false` no se modifica. Solo existen **SQL de laboratorio** en `rule_quality_l13`; no se despliega ni ejecuta en Supabase.

El readback real de L29 debe decidir PASS/FAIL; **este contrato no afirma pruebas positivas antes de CI**. Cualquier FAIL conserva NO-GO.

**Bloqueos de producción:** 0/14 cerrados. **GO:** prohibido por contrato; NO-GO / UNVERIFIED.
