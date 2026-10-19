# RW1-01_C3 — Mandato para juez independiente (PAQUETE CIEGO)

**Usar en un chat GPT Native NUEVO, separado de la conversación que produjo C1/C2, los tests o el diagnóstico de C3.** No reutilizar memoria, conclusiones ni notas de producción. El objetivo es evaluar el contrato, no el código de Router.

## Entrada permitida, congelada

1. `docs/programming-agent/router_wave/RW1_01_C1_NEEDS_SOURCES_AND_BIASES_V1.md`; Git blob `89aeae9e3116ebee9c2f547c2f41c4f2ba23c69d`.
2. `docs/programming-agent/router_wave/RW1_01_C2_NEEDS_ACCEPTANCE_CORPUS_V1.json`; Git blob `58884d37d74f1c784dfb5920ed2ac548781bfe18`.
3. `sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v1.py`; Git blob `2605fc675448104f69deef8a27210fc0047ea6fb`.
4. Texto normativo únicamente de `docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md`, sección RW1-01 C3 y aceptación.
5. EKB como fuente de hechos históricos, si está accesible, **sin** convertir hallazgos previos en oráculo único.

**Exclusiones durante la primera evaluación:** NO leer `RW1_01_C3_ADVERSARIAL_REVIEW_BRIEF_V1.md`, `validate_rw101_c3_adversarial_gaps_v1.py`, comentarios del PR #2884 ni preinvestigación RW1-02 #2880. Tampoco usar salidas ni identidad de brazos/diseñadores. Estos se revelan al juez **después** de congelar su primera crítica.

## Petición para el juez

Actúa como crítico adversarial de requisitos y oráculos. Evalúa cada una de las necesidades N01–N12 frente al corpus de 30 casos, sin presumir que 30/30 forma implica corrección operativa. Para cada hallazgo, indica:
- ID requisito/caso, afirmación precisa y evidencia de texto o código.
- Falso positivo o falso negativo posible y un falsificador **reproducible** que diferencie ambas cosas.
- Si la exigencia corresponde al Router, al especialista/consumidor, al punto de autorización de efecto, o a la prueba independiente.
- Si el defecto es material ahora o pertenece a un checkpoint posterior (evitar nuevos gates artificiales).
- Remediación mínima transversal, efecto secundario probable, y alternativa rechazada con razón.

Busca especialmente puntos ciegos en negaciones/exclusiones, multiobjetivo, context recovery, capacidades futuras, autoridad versus routing, casos demasiado parecidos a errores previos, sesgo hacia una arquitectura, determinismo en snapshot estable, y consumo real. No inventes porcentajes estadísticos ni autorización de producción.

Propón al menos un **holdout genuinamente nuevo** con fixture y expectativas falsables que no reutilice redacción ni IDs de R01–R30. No almacenes el holdout públicamente antes del dictamen congelado; registrar compromiso hash y después revelar el caso y oráculo bajo protocolo de evaluación.

Emite uno de `PASS`, `REVISE`, `INSUFFICIENT_EVIDENCE`, con los hallazgos, severidad y evidencia. **No** declarar GOLDEN, READY de Router, ni cierre C3. Congela respuesta RAW y SHA, registra identidad de chat/evaluador y fuente exacta.

## Segunda fase — confronto adversarial

**Después** de congelar y firmar el primer RAW: revelar `RW1_01_C3_ADVERSARIAL_REVIEW_BRIEF_V1.md` y el log CI de `validate_rw101_c3_adversarial_gaps_v1.py`; aceptar/refutar cada prueba con argumento propio. Verificar que esos hallazgos no sean reclasificados de forma indebida como «C2 no ejecutó Router real»: C2 nunca afirmaba eso.

## Evidencia requerida para el checkpoint

- Fuente congelada y listado de entradas efectivamente recibidas; RAW1 antes de exposición a críticas del productor.
- Respuesta independiente y justificación; holdout protegido hasta compromiso, luego resultado y falsificadores.
- RAW2 opcional de contraste frente a los nueve hallazgos de productor, sin borrar RAW1.
- Identificador verificable del juez y separación material del chat/ejecutor productor.
- Resultado motivado y responsabilidades para reparar omisiones **antes** de seleccionar arquitectura.
- Aplicación del contrato de aserción C3 y transición vía Migration/Operation autorizada; DB readback. **Sin** fabricar recibo a partir de este archivo.

**Estado de este paquete:** listo para entregar, **no ejecutado**; C3 sigue PENDING.
