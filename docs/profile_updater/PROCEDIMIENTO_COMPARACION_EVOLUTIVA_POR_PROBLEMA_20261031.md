# LF — Procedimiento de comparación evolutiva por problema

**Estado de la fuente:** propuesta de formalización autorizada por el dueño; solo adquiere vigencia operativa después de revisión, Merge Train y readback de la política activa. **Operación:** `ACTUALIZACION_PERFIL_LF`. **Regla:** comparar qué responde cada versión a cada problema material, no limitarse a contar campos o controles.

## 1. Regla de evaluación

La evolución se evalúa en **dos planos complementarios**, conservando el comparador existente:

1. **Grupo 2 / estructural determinista:** mismo caso operativo y entrada literal para perfil original y evolucionado, cada uno en su árbol exacto; ejecutar el perfil, conservar RAW, validar salida y aplicar los controles originales. Se usa el comparador vigente `operational_coverage_v1` sin modificar sus predicados ni su decisión `EVOLUTION_DEMONSTRATED`.
2. **Comparación funcional por problema:** el juez independiente evalúa **cada problema material del caso** y contrasta las respuestas originales y evolucionadas. Valora investigación, fuentes realmente consultadas, diagnóstico, contradicciones detectadas, calidad de la decisión y controles preservados. La mejora puede consistir en **detectar una fuente ausente o evitar una decisión inventada**. No se obliga a resolver una causa que aún no cuenta con evidencia.

No se confunden: `MEJORA_OBSERVADA` no certifica el pase del Grupo 2; `MEJORA_VERIFICADA` puede demostrar ganancia en diagnóstico pero tampoco significa reparación implementada. `NEEDS_MORE_EVIDENCE` es un resultado válido cuando sus carencias están justificadas, **no un fallo automático**.

## 2. Procedimiento obligatorio por cada caso

1. **Congelar:** `case_id`, solicitud literal e `input_sha256`, árbol SHA de cada versión, schema y validator de cada árbol, condiciones y fuentes autorizadas. La lista de problemas materiales proviene del caso real, del análisis causal o de obligaciones verificadas; **nunca de una lista fija para todos los perfiles**.
2. **Ejecutar:** perfil original y evolucionado con **exactamente la misma entrada y restricciones**. Conservar ambos RAW íntegros con `run_id`, `profile_tree_sha256`, `output_sha256`, modo de ejecución, atestación y resultado del validador. Una transcripción reconstruida, fixture, replay o captura `attestation=NONE` sin otro sustento no constituye una corrida atestada.
3. **Comparar en columnas:** para cada problema, describir qué respondió cada versión en diagnóstico, causa, evidencia/fuentes, solución, responsable, contradicciones, riesgos y decisión de continuar/bloquear. Incluir localizador RAW de cada afirmación; se admite `NO_ENCONTRADO`, pero no se fabrican respuestas.
4. **Evaluar por problema:** indicar la mejora concreta y por qué es útil, respaldada por fuentes independientes. Marcar preservación o pérdida de capacidades, y registrar incertidumbre residual. Distinguir `SIN_MEJORA` de `NO_VERIFICADO`.
5. **Contrastar controles:** publicar los resultados originales y evolucionados de todos los controles tipados. `FAIL→PASS` es ganancia estructural; `PASS→FAIL` es regresión; `PASS→PASS` conserva; `FAIL→FAIL` sigue pendiente. No contar como evidencia semántica las condiciones que pasan de forma vacía (por ejemplo, un `if_then` cuyo antecedente ya no aplica).
6. **Juzgar independiente:** reconsultar fuentes materiales, validez, actualidad, límites de búsqueda, falsificadores, aplicabilidad de políticas y riesgos de una decisión aparentemente más segura. No asumir que una respuesta más extensa es mejor. No asumir que `NO_APLICA` equivale a PASS.
7. **Reportar y cerrar por capas:** registrar `MEJORA_OBSERVADA` o `MEJORA_VERIFICADA` por cada problema; después concluir por separado **(a) mejora diagnóstica**, **(b) certificación de evolución** y **(c) reparación implementada**. Los pasos 90/100/110/130 y Merge Train mantienen su autoridad vigente.

## 3. Matriz oficial esperada (dinámica, por problema)

| Campo | Contenido requerido |
|---|---|
| Identidad | `execution_id`, `profile_slug`, `case_id`, `input_sha256` compartido |
| Problema | `problem_id`, descripción comprobable, obligación/controles relacionados |
| Versión anterior | respuesta concreta, `RAW.ref`, `JSON.pointer`, árbol/commit y procedencia |
| Versión evolucionada | respuesta concreta, `RAW.ref`, `JSON.pointer`, árbol/commit y procedencia |
| Diferencia y valor | nueva investigación, contradicción hallada, corrección de inferencia, mejor control, mejora o regresión |
| Evidencia | fuente exacta, consulta/localizador, readback, vigencia, interpretación y verificación independiente |
| Evaluación | `MEJORA_OBSERVADA / MEJORA_VERIFICADA / CONSERVADO / SIN_MEJORA / REGRESION / NO_VERIFICADO` |
| Pendientes | incertidumbres materiales, condiciones de implementación, controles/falsificadores |
| Destino de evolución | sección/paso **del perfil concreto**, tipo de cambio y vinculación; `DESTINO_PENDIENTE` cuando no sea canónico |

**La evaluación funcional es por problema**, y después se agrega por caso y por perfil. Una mejora verificada en un problema **no borra** la regresión material de otro. Un `PASS` de schema no sustituye el juicio semántico.

## 4. Significado de resultados

- **MEJORA_OBSERVADA:** cambio favorable visible al comparar respuestas y fuentes, pero las corridas no son todavía comparables/atestadas o falta juez independiente. **Nunca autoriza un merge**.
- **MEJORA_VERIFICADA:** mejora significativa y pertinente respaldada por dos corridas comparables, fuentes comprobadas y juicio independiente; puede ser diagnóstica aunque la reparación siga pendiente.
- **CONSERVADO:** mantiene correctamente la obligación anterior sin empeorarla.
- **SIN_MEJORA:** evaluable, pero el segundo resultado no aporta ganancia material.
- **REGRESION:** pierde una obligación que la versión anterior sí cumplía, o adopta una decisión insegura; bloquear cierre hasta subsanación.
- **NO_VERIFICADO:** no se puede contrastar de forma legítima; no sustituir por FAIL ni PASS.

Regla de agregado: **mejora demostrada + cero regresiones materiales + verificación formal**, sin cambiar los requisitos oficiales existentes; un problema irresuelto puede permanecer abierto y documentado. No se exige que todo incidente de negocio quede reparado para reconocer una mejora real de capacidad.

## 5. Ejemplo auditado WEB-001 — observación, no certificación

Fuentes de respuestas: anterior `RUN-WEB001-CANDIDATE-20261029.json` (árbol `2f4ac419...`) y evolucionado no admitido `WEB001_GPT_NATIVE_CANDIDATE_RUN_UNADMITTED_20261031.json` (árbol `6ac90638...`). Ambos `attestation=NONE`; no se ha demostrado la identidad literal de ambos inputs ni existe dictamen independiente. Por tanto la clase máxima posible es **MEJORA_OBSERVADA**.

| Problema | Respuesta anterior | Respuesta evolucionada | Evaluación |
|---|---|---|---|
| Gobernanza: descubrir regla/owner sin inventar autoridad | `LF_GOVERNANCE` propuesto por analogía con confianza 0.79, sin `policy_resolution` explícito | `owner=UNKNOWN`, búsqueda N1/N2 con fuente, alcance y resultado; no asigna dueño sin regla vinculante | `MEJORA_OBSERVADA` en investigación y prudencia de autoridad |
| Reintentos: falla de contrato y reingreso de FALLIDO | Diagnostica clasificación textual, 19 vínculos de corrida ausentes y propone control de reintento | Detecta `block_condition >3` versus SQL `retry_count+1 >=3`; exige comprobar consumidor de reingreso y regla antes de reparación | `MEJORA_OBSERVADA` en precisión diagnóstica |

La contradicción de umbral y `ACT-0058.owner_name=NULL` cuentan con readback en Supabase. El segundo perfil identifica nuevos riesgos, pero **no ha ejecutado una reparación**. Los 14 checks sobre el replay existente dan 9/14 frente a 14/14; OP14 de la salida evolucionada pasa **vacío** porque `owner.authority_kind=UNKNOWN`. Por ello 14/14 no significa que la rama de owner derivado esté probada.

**Resultado actual:** `2/2 MEJORA_OBSERVADA` en problemas materiales, `0/2 MEJORA_VERIFICADA` por corrida pareada/independiente, evolución oficial pendiente. El original y el evolucionado no deben reetiquetarse como dos nuevas ejecuciones.

## 6. Integración sin nuevo pipeline

- **Paso 37** `evolution_decision`: conservar selección y justificación de actualizar; no decidir únicamente por cuenta de controles.
- **Paso 90** `deterministic_validation`: schema, hashes, entrada y controles tipados originales; no relajar validaciones.
- **Paso 100** `semantic_judge`: agregar revisión por cada problema con respuestas enfrentadas, evidencias y dictamen independiente. Este procedimiento no es un juez sustituto.
- **Paso 110** `regression_after`: anexar al `before_after_matrix` las filas por problema junto a la matriz de controles y destinos (PR #3420), sin sustituir `holdout_result` ni `adversarial_result`.
- **Paso 130** `report_output`: mostrar comparaciones por problema, cambios, riesgos, veredicto de mejora y estado formal, con referencias verificables.
- **Router, resolución dinámica, Supabase, política activa, registro de pasos y Merge Train:** sin alteración por esta propuesta. La política `POL-PROFILE-UPDATE-PASS` actualmente activa prevalece; cualquier enforcement nuevo requiere admisión gobernada de sus contratos, sin cambiar unilateralmente autoridad.

## 7. Código y contrato de lectura implementados en esta rama

- El caso `WEB-001.case.json` conserva **14 checks sin modificarlos** y agrega `comparison_dimensions[]` para los dos problemas materiales. Los campos son dinámicos y opcionales para todos los demás casos/perfiles.
- La función read-only `problem_comparison_report` está en **el mismo** `operational_coverage_v1.py`; `evaluate()` la incorpora como `functional_problem_comparison` únicamente cuando el caso confiable declara dimensiones. No existe segundo comparador ni ruta.
- Por cada problema y cada versión guarda `run_id`, huellas, attestation, `JSON.pointer`, preview acotada y hash de valor; compara los resultados de controles existentes y expone `*_vacuous_conditional` para evitar falso mérito semántico.
- Los estados `UNMEASURED`, `PREVIEW_INPUT_IDENTITY_UNVERIFIED`, `PREVIEW_UNATTESTED` y `READY_FOR_INDEPENDENT_SEMANTIC_REVIEW` describen **calidad de evidencia**, **no** un veredicto de mejora. La valoración de mejora funcional sigue reservada al juez independiente del paso 100.
- Pruebas unitarias en `test_profile_problem_comparison.py`: ambos problemas, aplicación a caso diferente, falta de RAW, identidad de input, antecedente condicional no ejercido y no modificación del resultado `compare()`. Deben ser ejecutadas por CI antes del merge.
- La matriz de destinos y su unión al ledger `regression_after/report_output` siguen sujetas a PR #3420 y a prueba E2E. `functional_problem_comparison` se transporta mediante el resultado `operational` del comparador **existente**, sin aprobar el pase.

## 8. Criterios de aceptación de la formalización

- Informe presenta **todas las preguntas/problemas materiales**; para cada una original, evolucionado, evidencia, estado y pendiente.
- No usa `WEB-001` ni N1/N2 como condición universal; el método funciona para distintos perfiles y casos.
- No declara `MEJORA_VERIFICADA` sin mismo input, RAW exactos, validadores, evidencia y juez independiente.
- No transforma `NEEDS_MORE_EVIDENCE` con evidencia en fracaso automático, ni transforma `MEJORA_OBSERVADA` en `EVOLUTION_DEMONSTRATED`.
- Reutiliza `operational_coverage_v1`, el evaluador/juez existente y `regression_after`/ `report_output`; **no crea ruta de ejecución, adaptador o juez paralelo**.
- Requiere PASE, revisión independiente, Merge Train, readback de política y ejecución E2E antes de declararse operativo en `main`.

**Trazabilidad:** decisión del dueño de formalizar el método tras comparar dos problemas WEB-001 el 2026-10-31; PR #3399 (candidato), PR #3412 (enmienda), PR #3420 (matriz) son dependencias/relaciones, no cambios autorizados por este documento.
