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

17 tests: original real response mismatch; missing/unverified semantic assurance;
request SHA drift; uncertain intent; stale catalogue; ungrounded type; negation;
scope conflict; unregistered target/operation; forbidden/out-of-scope/missing
effects; positive consistency-only; deterministic replay.

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
