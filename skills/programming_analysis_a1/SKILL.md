# A1 — Intake y normalización (Agente de Programación)

**Estado:** `CANDIDATE_SOURCE_PREPARED_PENDING_QUALIFICATION`, no CURRENT / no integrado. **Código de habilidad:** `PROGRAMMING_ANALYSIS_A1`.

## Objetivo
Normalizar la solicitud literal y el contexto ya recibido como `REQUEST_CONTEXT_V1`, sin perder acciones, códigos, nombres ni procedencia. La interpretación del texto libre se produce externamente y debe superar revisión semántica independiente antes de continuar; A2 clasifica y A3 resuelve fuentes.

## Activación
Solo cuando el consumidor autorice A1 y entregue el input tipado. El perfil selecciona; la habilidad trabaja; el perfil registra su propia evidencia y decide la siguiente llamada.

## Entradas y fuente
Ver `schemas/input.schema.json`. Negocio `business=LF` autorizado solo como binding local candidato; SALY bloqueado sin binding específico. `declared_intent_kind` es una declaración del solicitante/consumidor, no clasificación confirmada.

## Proceso interno
1. Validar estructura del input. No aceptar `profile_code`, RUN ni tickets de autoridad dentro del payload de negocio.
2. Normalizar espacios, eliminar duplicados de refs/hints sin inventar contenido.
3. Comprobar que cada hecho proviene de una `source_ref` declarada; no afirmar que la fuente sea CURRENT.
4. Construir el **contrato canónico existente** `REQUEST_CONTEXT_V1` de `sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_request_context_v1.schema.json`.
5. Ejecutar validación local y guardas deterministas. Un objetivo esencial vacío bloquea; target no identificado pide evidencia; ambigüedad material abierta solicita decisión.
6. Devolver `A1_SKILL_CANDIDATE_RESULT_V1` solo al consumidor. El `next_capability=A2` es una recomendación, nunca invocación automática.

## Salida
`VALID_OUTPUT` para entrada estructurada, `REQUIRES_SEMANTIC_REVIEW` para candidato extraído de texto libre, `NEED_MORE_EVIDENCE`, `REQUIRES_DECISION` o `BLOCKED`. La frontera del modelo puede devolver `REQUIRES_INDEPENDENT_SEMANTIC_REVIEW`; no declara autonomía, integración ni autorización A2.

## Límites
No leer Supabase, GitHub ni EKB por sí sola. No escribir RUN ni hacer `service_role`, no operar Router, no ejecutar perfiles, no llamar A2/A3 directamente. `effects_executed=false`, `operationally_integrated=false`, `external_authority_verified=false`. No reemplaza un juez semántico independiente.

## Pruebas
`python -m unittest discover -s skills/programming_analysis_a1/evals -p 'test_*.py' -v` ejecutado en raíz del repositorio con `jsonschema`: 69/69 PASS sobre Git blobs idénticos al PR. No prueba inferencia real, independencia del juez, transporte, perfil ni recibos.

## Semántica pendiente de cualificación

Para solicitudes literales, ver `prompts/semantic_interpretation_v1.md` y `semantic/semantic_boundary_v1.py`. El productor y revisor son llamadas externas del futuro consumidor: no son funciones que consulten el Router ni implementen código. La salida semántica sigue en `REQUIRES_SEMANTIC_REVIEW` hasta recibir revisión independiente acreditada. Los contratos y pruebas sintéticas no prueban que el modelo haya ejecutado una inferencia real.
