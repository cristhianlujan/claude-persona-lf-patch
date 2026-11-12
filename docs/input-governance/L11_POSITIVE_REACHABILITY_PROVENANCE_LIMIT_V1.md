# LF — Lote 11 · Alcanzabilidad del SI del gate con procedencia sintética HONESTA

**Estado:** DRAFT / NO-GO · PG18.6 ROLLBACK · sin producción/merge/live apply/Router/nuevo IG/nuevo juez/nuevo modelo/RUN históricos. **Sin cambio de ninguna función SQL del gate**.

## Hipótesis

El dueño pide demostrar el positivo mecánico L7/L8 `captura → VERIFIED_CAPTURE_BINDING → aprobación perfil → APPLIED/VIGENTE/READY` usando **K00E813F0** con la cita exacta y propietario SIMULADO, sin afirmar E2E real. Su pregunta es válida: hay que demostrar la rama de autorización además de la de rechazo.

## Resultado de lectura de código: NOT_REACHABLE_WITH_HONEST_SYNTHETIC_PROVENANCE

Código vigente: `supabase/migrations/20261111235500_lf_rule_promotion_exact_citation_capture_v1.sql`.

- **Línea 205**, `lf_rule_promotion_citation_record_v1`: `OR st.evidence_payload->>'test_only_synthetic'='true'` → bloquea el registro de la cita en un Step70 explícitamente sintético.
- **Línea 281**, `lf_rule_promotion_citation_verify_v1`: `OR st.evidence_payload->>'test_only_synthetic'='true'` → rechaza readback de tal Step70.
- **Línea 318**: `IF x.source_provenance IS DISTINCT FROM 'OFFICIAL_STEP70_VERIFIED_NATIVE_IG' THEN` → un fixture honesto de procedencia `UNVERIFIED_NOT_FROM_REAL_REVIEW` solo alcanza `PROFILE_OWNER_REVIEW_ONLY` (líneas 312–317), no `VERIFIED_CAPTURE_BINDING` (línea 323).
- **Líneas 350 y 424**: `IF l7->>'status' IS DISTINCT FROM 'VERIFIED_CAPTURE_BINDING' THEN` → `lf_rule_promotion_blind_verdict_verify_v1` y `lf_rule_promotion_apply_v1` requieren el estado oficial.

El SQL **contiene** la rama de SI; no se afirma que sea lógicamente inalcanzable con datos oficiales reales. Pero **sin recibo nativo #3682 y Step70 acreditado**, un fixture que declarase procedencia `OFFICIAL_STEP70_VERIFIED_NATIVE_IG` no demostraría legitimidad: simplemente pondría el texto esperado para aparentar una autoridad de la que el fixture carece. Esto no se hará. El hecho de que el SQL use comparaciones de cadenas **no acredita una firma de origen**; requiere verificación independiente del emisor oficial en el entorno real.

## Evidencia PG18 verificable

La suite `test_pg18_lote11_synthetic_positive_reachability.py` aplica exactamente las migraciones existentes L5, L7 y L8 en PostgreSQL 18 descartable. No genera un recibo de IG que afirme ser oficial ni cambia gate/md5. Cada ruta usa **BEGIN/ROLLBACK**.

- Control positivo limitado: cita real `K00E813F0` `En producción, otp_code solo puede persistirse como hash` (export chat original, SHA-256 `d319670079ece0e0285e37a3194a1e1c9e784e9b7b6f5e7d35ed4882200bf4bc`) → captura estructural con procedencia `UNVERIFIED_NOT_FROM_REAL_REVIEW` → `PROFILE_OWNER_REVIEW_ONLY`; `apply=BLOCKED`, permanece `CANDIDATO`.
- Misma cita y Step70 marcado `test_only_synthetic=true` → `L7_STEP70_VERBATIM_CAPTURE_NOT_ATTESTED`; sin captura, sin promoción.
- Negativo 1: cita real alterada en un carácter → bloqueo por no literalidad.
- Negativo 2: regla modificada después de captura → `L7_EXACT_CITATION_NOT_CURRENT`; no VIGENTE.
- Negativo 3: propietario = actor IG → predicado de rechazo presente y evaluado, pero la **rama integrada de aprobación queda NOT_PROVEN** por falta de la atestación Step70 previa.
- Negativo 4: código de `RULE_READBACK_FAILED_NO_VIGENTE` existe; **la rama de rollback/reintento sobre K00E813F0 no se puede ejecutar con el fixture honesto** porque no se alcanza `APPROVED`. El lote L5 ya demostró esa transacción por separado con fixture puramente sintético, sin afirmar una prueba integrada de K00E813F0.

## Tablero E2E sin cambiar el cierre L10

Router, Perfil, RUN, IG, Curator, Retorno perfil, Ejecución, Promoción, VIGENTE y Cierre: `NOT_PROVEN`. Validator: `SANDBOX_VERIFIED` solo la literalidad y rechazo de Step70 sintético. Readback: `SANDBOX_VERIFIED` solo `CANDIDATO` y ROLLBACK, **no** `VIGENTE/READY`.

Etiquetas: `MECHANICAL_ONLY_SYNTHETIC_PROVENANCE_NOT_E2E` para el objetivo de prueba; salida de ruta positiva **`NOT_REACHABLE_WITH_HONEST_SYNTHETIC_PROVENANCE`**; global `NOT_PROVEN`.

## Pendiente para un SI válido

El resultado necesita recibo existente #3682 del mismo caso y hashes verificables, Step70 nativo con emisor acreditado, perfil propietario con ejecución separada/autoridad canónica, readback `VIGENTE` real, retorno efectivo y cierre EKB. **No** se emite receta para falsificar una procedencia oficial. El modelo declarado por el dueño es ChatGPT, `OWNER_DECLARED_NOT_SYSTEM_ATTESTED`; mismo modelo para IG, perfil y revisor = consistencia, no independencia.

**PASE / banco del auditor:** no se consideran resueltos por pruebas mecánicas del sandbox; no se emite PASS operativo.
