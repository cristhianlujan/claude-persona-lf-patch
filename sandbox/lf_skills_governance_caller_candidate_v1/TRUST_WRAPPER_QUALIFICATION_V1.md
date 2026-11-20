# Ejecución nativa de skills — contrato de confianza del wrapper (candidato)

**Alcance:** wrapper específico de `EJECUCION_SKILL_LF` sobre el **núcleo común existente**. No es una migración, no se instala ninguna RPC, no se crean grants y no se alteran jueces, Router o caller de perfiles. Fuentes: lectura de `pg_get_functiondef`, contratos, bindings, EKB (2026-11-06).

## 1. Patrón exacto ya probado en perfiles

`lf_record_profile_execution_step_v1(p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id)` realiza **dos** acciones: obtiene confianza mediante `lf_profile_execution_trust_validation_v2` y llama `lf_record_operation_step_core_v1` con operación `EJECUCION_PERFIL_LF`, target `PERFIL`, tres estados `ACTIVE_ENFORCEMENT`, `p_close_on_report_output=true`.

El wrapper de skills debe conservar la estructura, no sus reglas específicas (paquete de autoridad de perfiles, pantallas, `research_baseline`, etc.).

### Firma propuesta (NO INSTALADA)

`public.lf_record_skill_execution_step_v1(p_execution_id text,p_step_id text,p_evidence_ref text,p_evidence_payload jsonb,p_actor_execution_id text) returns jsonb`

**Secuencia obligatoria del wrapper:** 
1. Confirmar `EJECUCION_SKILL_LF` + `SKILL` + RUN `IN_PROGRESS`, source del activo canónico, parent perfil correcto, actor OIDC acreditado por servidor y negocio consistente con raíz/handoff/recibo Router. La identidad no proviene del payload.
2. Exigir `init_execution` registrado por apertura; el wrapper de pasos nunca puede escribir el paso 0 (`INIT_STEP_IMMUTABLE` ya existe en el core).
3. Ejecutar un **validador de confianza específico de skill**, propuesto `public.lf_skill_execution_trust_validation_v1(p_execution_id,p_step_id,p_evidence_payload)`. Debe obtener sus aserciones y fallos del servidor, no del contenido declarado por el consumidor.
4. Resolver desde Supabase la cobertura del **juez vigente para ese RUN y sus snapshots**. Si su matriz de invariantes, digests y pruebas no está calificada, devolver `valid=false`, `server_hard_fails` y `code=SKILL_JUDGE_COVERAGE_NOT_QUALIFIED`.
5. Solo con confianza servidor positiva, delegar a `lf_record_operation_step_core_v1` con: operación `EJECUCION_SKILL_LF`, target `SKILL`, contrato/binding/judge `ACTIVE_ENFORCEMENT`, `close_on_report_output=true`. **Prohibido** otro recorder paralelo.
6. Verificar readback de la fila y `step_result`. El resultado de `lf_skill_invoke_v1` o un campo `semantic_judge_result` enviado por el cliente no equivale al juicio independiente.

**Formato obligatorio de trust servidor** (especificación, no recibo):

```json
{
  "valid": false,
  "code": "SKILL_JUDGE_COVERAGE_NOT_QUALIFIED",
  "details": {
    "execution_id": "RUN_GOBERNADO_EXACTO",
    "step_id": "semantic_judge",
    "source_verification": "PENDING_SERVER_READBACK"
  },
  "server_assertions": [],
  "server_hard_fails": ["judge_invariant_coverage_missing"]
}
```

**Nota:** un consumidor no puede hacer que `valid=true` sea autoritativo por proporcionar un JSON con esa forma. Solo la función SQL admitida con lectura y validaciones propias del servidor puede producirlo.

## 2. Matriz mínima de riesgos/invariantes propuesta

`QUALIFICATION_REPORT_V1.md` contiene P01–P12. Los controles no se califican por cantidad fija de reglas: se exige trazabilidad para **cada invariante material** de la revisión canónica y cada afirmación de `pass_if` / `fail_if`. Clasificaciones: DETERMINISTIC, HYBRID, INDETERMINISTIC.

| Etapa | Prueba determinística (antes del modelo) | Componente no determinístico |
|---|---|---|
| RUN / Router / negocio | Actor, parent, recibo ACT-0001, solicitud y negocio exactos | No corresponde |
| Catálogo y fuente | Skill READY, authority, Main SHA y blob digest, effect | No corresponde |
| Idempotencia | Releer toda identidad/manifest en NEW y REPLAY | No corresponde |
| Pasos 0–40 | Binding actual + evidencia persistida y orden | No corresponde |
| Paso 50 | Fuente, output hash, guard A2→A3 y recibos internos | Si la skill lo necesita, juez **interno** antes de A3 |
| Paso 60 | Contrato de salida, digest y precondiciones limpias | No puede corregir FAIL determinístico |
| Paso 70 | Output/digest, separación producer/judge, recibo independiente | Solo aquí el juicio global semántico |
| Paso 80 | Los nueve pasos limpios + mismo output/juez/negocio | No corresponde |

**Observación real P0:** `lf_operation_judges` para `EJECUCION_SKILL_LF` registra `pass_if=[]`, `fail_if=[]`, `judge_sha=NULL`. El core itera los arrays y, si no encuentra fallos, puede derivar `clean_result_value` sin cobertura material. **No usar ese PASS como acreditación.** Exigir fuente actual firmada/vinculada y matriz positiva/negativa revisada independientemente. EKB: `PROFILE-JUDGE-INVARIANT-COVERAGE-001`.

## 3. Pruebas reproducibles (candidato local, no autoridad)

- `node --test skill_judge_qualification_candidate_v1.test.mjs` — **36/36 PASS**, 12 invariantes de ejemplo y pares positivos/negativos, sin acceso a BD ni JWT.
- El archivo `skill_judge_qualification_candidate_v1.mjs` **deriva los pasos requeridos desde los metadatos de entrada**, sin hardcodear la cantidad como criterio de aprobación; aun así no autentica esas filas.
- Caso real observado sintetizado: juez vigente con `pass_if=[]`, `fail_if=[]`, digest nulo → `NOT_QUALIFIED`.
- Caso adversarial: falla determinística con `semantic.verdict=PASS` → `BLOCKED_CANDIDATE`.
- Un fixture íntegro solo obtiene `CANDIDATE_COVERAGE_CONSISTENT_UNAUTHENTICATED`; nunca `permission_to_record_step=true` ni `a3_allowed=true`.

## 4. Requisitos para integración gobernada posterior

1. Fuente oficial de juez y snapshots por RUN identificados, con digest verificable y matriz independiente; registrar pruebas negativas/positivas por invariante.
2. Calificar entrada OIDC, autoridad y catálogo sin cambiar efectos `READ_ONLY` de negocio.
3. Desarrollar el wrapper SQL candidato en una rama de migración independiente, comparar su firma y salidas con `lf_record_profile_execution_step_v1` y el core.
4. Abrir RUN y paso 0 por RPC autorizada, no por SQL del modelo. Prueba real: replay, cruce de negocio, input SHA, source drift, orden de pasos, fail determinístico + PASS semántico falso, 3 FAIL de A2, cierre 80 con readback.
5. Solo tras revisión independiente, PASE, aprobación de cambio oficial y autoridad de despliegue, integrar Edge/RPC; nunca inferir READY del fixture.

**Estado:** DISEÑO Y PRUEBAS SINTÉTICAS. `JUDGE_COVERAGE_NOT_QUALIFIED` / `NATIVE_WRAPPER_NOT_INSTALLED`. No ejecución operativa ni modificación de fuentes oficiales.
