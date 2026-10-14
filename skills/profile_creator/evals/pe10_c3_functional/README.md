# PE10_C3 — Prueba funcional GPT Native

## Qué se corrigió
Este paquete introduce métodos en tres perfiles shadow dentro de las secciones H2 que recibe realmente el modelo. No modifica perfiles canónicos, no despliega, no aplica Llama, no inventa ejecución ni califica estructura como calidad experta.

Los seis casos de cases_v1.json requieren entregables completos, no opciones múltiples. Las 30 verificaciones observables de private_oracle_v1.json se congelan antes de producir respuestas, y no deben exponerse a los chats productores.

## Casos
- PESC3-101: Quality Pack; procedencia antigua y prueba negativa ausente.
- PESC3-102: UI Architect; tokens, soporte configurable, estados y accesibilidad.
- PESC3-103: Product Director; decisión cuantitativa bajo guardrail de reclamaciones.
- PESC3-104: Quality Pack; reevaluación tras prueba negativa verificada.
- PESC3-105: Product Director; reevaluación tras nueva evidencia de titularidad.
- PESC3-106: UI Architect; preservación de campos en pantalla nueva.

## Fuente congelada y preflight
Fuente inmovilizada: d4b65774801b9eedc30b06f781ec10ff6de96477.
La carpeta frozen_contexts incluye seis documentos: modelo original y shadow de cada perfil. Es la proyección ejecutable, no un contrato lateral.

~~~bash
python3 skills/profile_creator/evals/pe10_c3_functional/build_shadow_v1.py --repo . --revision d4b65774801b9eedc30b06f781ec10ff6de96477 --out /tmp/pe10c3-shadow-run
python3 -m unittest skills.profile_creator.evals.pe10_c3_functional.test_build_shadow_v1 skills.profile_creator.evals.pe10_c3_functional.test_score_captured_pairs_v1 -v
~~~

## Producción de respuestas GPT Native
Ejecutar en dos chats GPT Native LIMPIOS, uno ORIGINAL y uno SHADOW, los seis casos idénticos cada uno. Mostrar en cada chat únicamente los documentos de contexto del brazo correspondiente de frozen_contexts y los prompts de cases_v1.json. No mostrar el oracle, otro brazo, ganador esperado ni veredicto anterior.

Para cada caso producir la RESPUESTA FINAL ÍNTEGRA, no una etiqueta de modo ni simulación de scoring. Capturar el texto literal, hash SHA256, referencia real de conversación, case_id, brazo, input_sha256 y model_context_sha256 desde compilation_receipt.json.

Paquete de captura (12 entradas; todas obligatorias):
~~~json
{
  "schema": "PE10_C3_CAPTURED_GPT_NATIVE_RAW_V1",
  "model_route": "GPT_NATIVE_IN_CHAT",
  "test_double": false,
  "producer_execution_id": "ACTUAL_OBSERVED_EXECUTION_REFERENCE",
  "source_compilation_revision": "SOURCE_REVISION_FROM_COMPILATION",
  "responses": [
    {
      "case_id": "PESC3-101",
      "arm": "A_ORIGINAL",
      "input_sha256": "REAL_HASH_FROM_COMPILATION",
      "model_context_sha256": "REAL_CONTEXT_HASH_FROM_COMPILATION",
      "output": "EXACT_REAL_OUTPUT",
      "output_sha256": "SHA256_EXACT_OUTPUT",
      "chat_reference": "ACTUAL_CHAT_REFERENCE"
    }
  ]
}
~~~
Los valores son ejemplo de forma, no datos ni recibos reales. No inventar ningún campo. El programa valida existencia de las 12 respuestas, correspondencia de entradas, digest de fuente y digest de salida. No autentica por sí mismo el proveedor GPT.

## Evaluador ciego, diferente del productor
~~~bash
python3 skills/profile_creator/evals/pe10_c3_functional/score_captured_pairs_v1.py --compiled /tmp/pe10c3-shadow-run/compilation_receipt.json --raw /tmp/pe10c3-captured-actual-raw.json --out /tmp/pe10c3-blind-packet.json
~~~

Entregar SOLO ese paquete y la rúbrica precongelada a otro chat GPT Native. Puntuar X/Y sin conocer correspondencia con original/evolucionado. Para cada case_id y blind_arm (X o Y), emitir cinco puntos binarios y cinco evidence_quotes; cada punto 1 necesita una cita literal de la respuesta que lo sustente. Debe devolver esquema PE10_C3_BLIND_SEMANTIC_JUDGE_V1, reviewer_execution_id real y blind_to_arm_identity=true. No producir ni modificar las respuestas.

~~~bash
python3 skills/profile_creator/evals/pe10_c3_functional/score_captured_pairs_v1.py --compiled /tmp/pe10c3-shadow-run/compilation_receipt.json --raw /tmp/pe10c3-captured-actual-raw.json --judge /tmp/pe10c3-blind-judge-actual.json --out /tmp/pe10c3-functional-score.json
~~~

La política congelada exige: 6/6 pares, al menos 4 mejoras, media candidata >=0.8, uplift promedio >=0.15, límite inferior bootstrap pareado 95% >0, cero regresiones críticas y preservación. Si no se cumplen, cambiar el método funcional específico que falló y ejecutar un nuevo par limpio; no alterar historia ni mover umbrales.

## Restricciones de admisión
El resultado funcional es evidencia candidata; PE10_C3 requiere además verificación de independencia, procedencia, recibo válido y readback en Supabase. Nunca convertir una declaración de chat en atestación criptográfica.

EKB consultado: PROFILE-RUNTIME-SOURCE-PROJECTION-METHOD-OMISSION-001, LF-PE10-C3-SEMANTIC-SHAPE-ONLY-20261013-001, LF-PE10-C3-EMPTY-COMPOSITION-SCORER-20261013-001, LF-PROFILE-GPT-NATIVE-DISPATCH-MISSING-001.
