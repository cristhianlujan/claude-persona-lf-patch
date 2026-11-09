# PG-04 — Juez semántico local experimental (Ollama o chat independiente)

**Estado:** `SOURCE_ONLY / LOCAL_MODEL_OPTIONAL / NOT_EXECUTED_IN_CI / NO_AUTHORITY`.

## ¿Qué permite?

Revisar en una ejecución separada el paquete sintético `LAB-PAYMENT-API-DB-UI-001` y la partición PG04 generada por el código candidato existente, sin depender de A1–A9 de Análisis ni de la operación de revisión gobernada. Es una **prueba de calidad semántica**, no un recibo LF.

El laboratorio contiene dos familias distintas:
- **Determinismo:** productor PG04, inspector estructural y planificador DoD existentes; no puede desactivarse cobertura/DAG/seguridad mediante los switches.
- **Juicio semántico:** un LLM local evalúa outcomes, atomicidad, riesgos, trazabilidad y afirma `PASS`, `FAIL` o `INCONCLUSIVE` para **el artefacto sintético congelado**. Un resultado `PASS` solo indica juicio de ese modelo sobre el fixture y **no acredita independencia**, currentness, A9, juzgado en LF, ni admisión PG04_C7.

## Requisito opcional en tu máquina

Python 3, Ollama instalado y un modelo ya descargado. Ejemplo: `ollama pull qwen2.5:7b` (requiere conexión únicamente para descargar el modelo; el runner usa `ollama run` local).

No están instalados ni verificados Ollama ni sus modelos en el entorno de trabajo de esta conversación; no afirmar que el juicio de modelo ya se ejecutó.

Desde la carpeta
`sandbox/lf_contract_gate_test/programming_agent_four_stage/pg04_semantic_partition_candidate`:

```bash
# Ver el bundle y prompt exacto sin ejecutar modelos
python3 tools/pg04_local_semantic_judge_v1.py --prompt-only > /tmp/pg04_local_review_prompt.txt

# Ejecutar contra modelo Ollama disponible en tu máquina
python3 tools/pg04_local_semantic_judge_v1.py --model qwen2.5:7b --output /tmp/pg04_local_judge_report.json

# O pegar el prompt en una conversación independiente que NO haya generado el paquete:
# guardar el JSON único de esa respuesta a /tmp/pg04_reviewer_response.json
python3 tools/pg04_local_semantic_judge_v1.py --response-file /tmp/pg04_reviewer_response.json \
  --output /tmp/pg04_local_judge_report.json

# Ejecutar el validador estructural del recibo diagnóstico
python3 -m unittest discover -s tests -p 'test_pg04_local_semantic_judge_v1.py' -v
```

El JSON evaluado contiene los requisitos/aceptaciones ficticios, todos los átomos, outcomes y la partición con hash. La rúbrica local exige los diez criterios declarados, fuentes señaladas por JSON Pointer reales y razones concretas. El parser rechaza respuesta no JSON, bundle SHA incorrecto, criterio omitido o duplicado, punteros inexistentes y `PASS` global contradictorio con fallos. **Un puntero existente no significa que la fuente sea auténtica ni que el criterio esté bien juzgado**.

## Separación de autoridad

El runner `tools/pg04_local_semantic_judge_v1.py`:
- Nunca llama Supabase, Router, GitHub ni la operación `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`.
- Nunca escribe recibos en `private.lf_evidence_ledger_v1` ni cambia checkpoints.
- No presenta `semantic_judge_executed=true` en los artefactos canónicos; su reporte externo indica `official_judge_executed=false`, `production_authority=false`, `checkpoint_closure_allowed=false`.
- Puede marcar `review_output_shape=PASS` **solo para la forma del JSON** y `model_reported_verdict=PASS/FAIL/INCONCLUSIVE` para la opinión del modelo. La corrección semántica e independencia siguen `false` en las banderas de atestación.
- No habilita switches para apagar el juez en producción. Se mantiene sujeto a las restricciones del contrato `INDEPENDENT_ASSURANCE` descrito en `sandbox/lf_contract_gate_test/transversal_assets/independent_assurance/README.md`.

Para una revisión sin Ollama, LF ya tiene el precedente `profiles/quality_pack/contracts/independent_chat_semantic_review_contract.md` que demuestra el patrón de conversación independiente, pero **ese contrato de Quality Pack no certifica PG04**.

## Límites

El resultado de local model puede fallar por calidad, tamaño, sesgo o formato de salida; no tiene acceso probado a un proveedor independiente. No subir datos de producto sensibles a un proveedor externo; el fixture aquí es 100% sintético. No asumir independencia solo porque se abrió otra ventana o se usó otro modelo.

**Pruebas creadas:** `tests/test_pg04_local_semantic_judge_v1.py`. No se declaran PASS exact-HEAD hasta su ejecución real. Sin cambios en Análisis.
