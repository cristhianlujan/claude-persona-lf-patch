# ACT-0001 intent consistency guard — code-only candidate

**Status:** CANDIDATE / NOT INSTALLED / NOT ROUTER CUTOVER. No production change.

## Objective and root-cause evidence

ACT-0001 currently uses token-scored catalog matching and regexp-based action
inference inside `public.lf_router_resolve_v1`. The unchanged original request

> Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.

returned `ADAPTER / ADAPTER_UPDATE / ACTUALIZACION_ADAPTER_LF / READY_TO_EXECUTE`,
despite not requesting adapter maintenance. The word `modificar` was inside an
explicitly **negated** constraint.

Live read-only catalogue check (2026-10-15): active `PANTALLA` / `SCREEN`
router routes = 0, indexed `PANTALLA` / `SCREEN` assets = 0. The correct
safe behavior **today** is blocked / unresolved canonical screen operation,
not selecting an unrelated adapter.

## Scope of this isolated candidate

`router_intent_consistency_v1.check` validates the handoff between:
1. the **existing** ACT-0001 route receipt;
2. a semantic **proposal** bound to exact original request SHA-256;
3. an authoritative, current catalogue snapshot supplied by the consumer;
4. a **trusted external verifier callback** for the governed semantic result.

The proposal is never self-attesting; a model field `PASS` is never trusted.
This module does not execute an LLM, choose an asset/profile/operation, read the
database, write SQL, register authority, or implement a second router.
It catches mismatched type/action/identity/operation, source or catalog drift,
ungrounded span evidence, missing negation evidence, contradictory scopes and
forbidden/out-of-scope effects. It always returns
`downstream_execution_allowed=false`, even for a consistency PASS.

Generic positive fixtures with a PANTALLA route are **hypothetical** and do not
claim an active canonical screen route.

## Verification

```bash
python3 sandbox/lf_contract_gate_test/canonical_route_guard/test_router_intent_consistency_v1.py
```

20 tests: original real response mismatch; missing/unverified semantic assurance;
request SHA drift; uncertain intent; stale catalogue; ungrounded type; negation;
scope conflict; unregistered target/operation; forbidden/out-of-scope/missing
effects; positive consistency-only; deterministic replay.

## Live canonical-readback 2026-10-15

- Canonical B2B login screen **exists** in `lf_ops.pantallas`:
  `id=51`, `codigo=B2B-AUTH-001`, `nombre=Iniciar sesión`,
  `estado=CANDIDATO`, `activa=true`, module `B2B_AUTENTICACION`.
- The historical fixture identifier `PANTALLA-B2B-LOGIN` was **not** canonical
  and has been replaced in tests by `B2B-AUTH-001`.
- Existing `public.lf_router_action_registry` has no active `PANTALLA`
  or `SCREEN` update route. There are separate registered `APP_SHELL`
  create/update routes; **do not assume shell maintenance is screen copy**.
- Existing `public.lf_router_resolve_v1` does **not** emit
  `declared_effect_scopes`; the guard's positive fixture supplies this
  field hypothetically. A trusted canonical operation-contract scope binder
  must be wired before an actual live positive PASS is possible.
- `CAPABILITY_SELECTOR@1.0.0` is released but selection-only, not a
  semantic model or authority. `CURRENTNESS_AUTHORITY`,
  `CAPABILITY_VERSION_COMPATIBILITY`, `TYPED_EVIDENCE_REGISTRY` and
  `INDEPENDENT_ASSURANCE` are released; the exact Router semantic executor
  and its trusted attestation path remain unverified.
- The correct handling of this B2B input today is **BLOCKED until current
  canonical screen and action binding resolve**, not a synthetic update route.
- `WORK-ADMISSION-ROUTING-CONTAMINATION-001` is an applicable existing EKB
  warning against silently entering a specialized work lane before
  transversal classification.

## Proof and blockers

- The exact PR candidate Python source and regression suite were reproduced
  locally from their readback checksums: initial 17/17 PASS.
- Updated to the canonical real target code and expanded malformed-input /
  duplicate-route negatives: **20/20 local unit tests PASS**. This does not
  prove live enforcement; CI and governed semantic runtime have not passed.
- Actual complete correction requires an authoritative screen subject
  resolver, registered screen operation/contract (or an existing operation
  that is *proved* applicable), a trusted semantic-gap consumer, and
  live post-Router pre-effect enforcement. No parallel router or handler.

## Physical integration/cutover remaining

1. Bind governed semantic-gap resolution through the existing transversal
   `CAPABILITY_SELECTOR` / version/currentness/evidence authority; no
   hardcoded provider/model or parallel router. Reference: ADR M1.A2.
2. Wire the trusted verifier and current catalogue to ACT-0001's real consumer
   boundary; do not accept either from an untrusted model payload.
3. Have ACT-0001's actual route admission enforce the consistency verdict
   **before** any downstream execution or effect. The existing
   `lf_router_resolve_v1` SQL endpoint is **not** changed by this candidate.
4. Register a screen operation/asset only through separately governed
   screen-catalog authority if appropriate. Never synthesize one here.
5. Prove ROLLBACK test, positive + negative live route, comparator
   currentness, and zero regressions in existing operations, then migrate
   exclusively through Train. No merge/apply/deploy without gates.

This candidate is an actionable fail-closed validator, **not** a claim that
the original B2B case is fixed in the running Router.

## 2026-10-16 — fase 1, ampliación transversal en el MISMO PR (aún DRAFT)

Diagnóstico externo confirmado: el Router llegó a READY con escritura ante
solicitudes SIMULAR o NO CREAR; también omitió sujetos positivos al escoger
un solo código y confundió un activo excluido con el destino.

La protección candidata YA EXISTENTE ahora comprueba, además de sus invariantes
previos, los campos **atestados por el verificador externo**:
- `requested_mode`: solo `EXECUTE` puede superar la revisión de una ruta
  con efectos; `ANALYZE`, `EXPLORE`, `SIMULATE` y `PREPARE` **no se
  prohíben como trabajo**: se desvían de esta revisión de escritura.
- `excluded_target_codes`: lista explícita, con cita de procedencia si hay
  exclusiones; ningún target excluido puede aprobar una ruta de efectos.
- `work_units`: unidad única ligada a target/type/action; ante múltiples
  unidades, el candidato escalar **no declara PASS parcial** y exige una ruta
  compuesta gobernada todavía no implementada.
- `condition_state`: una condición no satisfecha/no comprobada no permite
  afirmar que procede un efecto.

Un resultado `ROUTE_CONSISTENCY_PASS` sigue devolviendo
`downstream_execution_allowed=false`. No es permiso ni ejecución.
El contrato de procedencia del pedido, el modo y las exclusiones está
contenido en el mismo objeto verificado; **los unit tests usan un callback
falso** para probar exclusivamente la frontera determinista.

### Prueba reproducible

```bash
cd sandbox/lf_contract_gate_test/canonical_route_guard
python3 -m unittest -v test_router_intent_consistency_v1.py test_router_intent_safety_contract_v1.py
```

- Antes: 20/20 suite previa PASS, pero 14/16 casos nuevos FALLABAN.
- Después: **36/36 PASS local**; blobs del módulo y dos suites leídos de
  vuelta en GitHub. El caso positivo continúa siendo un fixture hipotético.
- No se ejecutaron la matriz externa de 33 casos íntegra ni T02/T12/T14/PE1
  contra PostgreSQL; ese CSV no se encuentra en la rama examinada.
- No hay verificador semántico atestado conectado a ACT-0001.
- No hay prueba de `pre_write_execution_binding_gate` ni de efecto real.
- PASE del HEAD posterior a estos cambios falló en
  `Enforce single ordinary PR entrypoint`: el selftest enumeró doce
  workflows ordinarios distintos de `pase.yml`; no fue un fallo de las 36
  pruebas Python. **No se reinterpretó como éxito ni se modificó PASE**.
- No se habilitó Router, perfil, skill, escritura, merge, deploy ni migración.

### Límite arquitectónico

Este guard solo compara un **plan ya interpretado** contra una ruta de
efectos. NO entiende texto libre, no decide si un modo es verdadero, no
selecciona capacidades ni reemplaza al Router. La semántica gobernada y
la composición deben encargarse de crear la propuesta y demostrar su
cobertura. Un tipo nuevo no debe quedar impedido de ser creado por el
requisito de identidad preexistente de este guard, que **solo aplica a
operaciones sobre targets ya registrados**. No reutilizarlo como gate
universal para crear, explorar ni simular.

**Próximo checkpoint:** validar un recibo real del verificador externo,
conectar este control antes del primer efecto por la operación existente,
probar positivos y negativos bajo un aislamiento PostgreSQL verificado y
sin alterar las operaciones canónicas.
