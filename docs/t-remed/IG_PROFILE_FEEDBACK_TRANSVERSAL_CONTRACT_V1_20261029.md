# LF — Input Governance feedback transversal para perfiles
**Fecha:** 2026-10-29 · **PR:** #3269 DRAFT · **Estado:** CONTRATO CANDIDATO; NO INTEGRADO / NO-GO.
**Frontera de trabajo:** diseño, evidencia y pruebas SELECT en rama; sin cambios a DB, EKB o selectores.

## 1. Regla de arquitectura (no Producto-first)
- Router ACT-0001 decide dinámicamente qué perfil **autorizado** inicia.
- Una tarea no implica IG por el nombre del perfil: se decide por intención y
  contrato (`lf_profile_input_governance_requirement_v1`).
- El perfil desarrolla su especialidad, consulta IG cuando se requiere,
  revisa críticamente el resultado y devuelve un juicio propio.
- Si hay desacuerdo material, emite feedback con evidencia; **no** llama
  directamente al siguiente perfil ni a Curator/Validator.
- Router gestiona retorno por `lf_profile_result_router_return_prepare_v1`
  y reclasificación Stage1. `resolution_target` no selecciona perfil.
- El resultado de IG no es automáticamente verdad de producto ni una
  afirmación de seguridad; el experto tampoco puede cambiar IG por opinión.
- IG reevalúa el foco cuando hay motivo gobernado; no repite todas las
  familias por discrepancia. Si nueva curación necesita snapshot completo,
  esa recomputación debe ser admitida por contrato, con dependencias probadas,
  Curator/Validator independiente y linaje intacto. Hoy no hay prueba de
  ejecución verdaderamente selectiva persistente.

## 2. Evidencia real de alcance actual

Reproducido en Supabase mediante SELECT exacto versionado:
`sandbox/lf_contract_gate_test/input_governance/ig_feedback_cross_profile_transversal_readonly_20261029.sql`.
**11/11 PASS**, en cuatro casos de routing tipado *sintético*: Product,
UI, Evidence Lineage Reviewer y Systemic Repair.

- Catálogo vivo 10 perfiles; 4 cuentan con relación DIRECT_PROFILE a
  `INPUT_GOVERNANCE_EXECUTION_CONTRACT` y consumer `CONTEXT_PACK`:
  `PERFIL-PRODUCT-DIRECTOR-LF`,
  `PERFIL-UI-ARCHITECT`,
  `PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING`,
  `PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531`.
- 6 no cuentan con vinculación directa; **no** asignarles
  `DIRECT_PROFILE` por inferencia. La función de validación puede usar
  `v_lf_router_adapter_bindings` cuando exista un binding gobernado.
  Sin binding válido, la respuesta debe ser NOT_REQUIRED/N/A o bloqueo
  según tarea/contrato, nunca un bypass.
- El Router admite resultados tipados de cuatro perfiles distintos y
  devuelve `REENTER_ROUTER_STAGE1`, sin dar autoridad al perfil anterior.
  **No prueba** que los cuatro ejecutaron realmente Input Governance.
- Ningún consumer técnico fue un `profile_code`.

## 3. Problema que impide simplemente copiar la solución de Producto

`profiles/product_director_lf/schemas/product_direction_spec.schema.json`
usa `additionalProperties=false` a nivel raíz, aunque
`deliverable_created` admite atributos adicionales. El candidato previo
guardó `input_governance_feedback` dentro de ese último objeto.

`profiles/ui_architect/schemas/ui_production_spec.schema.json`
permite un `deliverable_created` extensible por defecto; sin embargo
`profiles/ui_architect/schemas/ui_focused_decision.schema.json` es un
objeto raíz cerrado (`additionalProperties=false`) que **no** tiene
`deliverable_created`. Un nuevo especialista puede tener otro contrato.

Por tanto, **no se debe imponer una propiedad JSON a cada output nativo**,
ni obligar a migrar los diez esquemas, ni crear un mapeo hardcoded por
nombre de perfil. Tampoco introducir campos top-level "extra" en outputs
cerrados solo para hacer pasar el Router.

## 4. Interfaz transversal propuesta: feedback ligado a output, NO output modificado

Reutilizar la frontera de salida/retorno de la ejecución gobernada.
El perfil puede producir DOS resultados lógicos, con sus validadores:

1. **Entregable especialista**: JSON con el esquema vigente de ese perfil,
   sin cambios, validado por sus propios jueces y controles.
2. **Feedback opcional de IG**: observación independiente, del **mismo perfil
   y ejecución**, registrada como evidencia de orquestación después de
   vincularla al entregable, no anidada obligatoriamente en su esquema.

Estructura propuesta del receipt/sidecar (NO afirmación de implementación):

```json
{
  "schema_version": "IG_PROFILE_FEEDBACK_V1",
  "source_execution_id": "<execution_id real>",
  "source_profile_code": "<asset code real>",
  "source_profile_output_sha256": "sha256:<digest real>",
  "ig": {
    "run_id": "<run_id real>",
    "pantalla_id": "<id real>",
    "family_code": "<familia existente en el run>",
    "source_snapshot_sha256": "<sha del run>"
  },
  "kind": "EVIDENCE_CHALLENGE",
  "reason": "<juicio del especialista>",
  "evidence_refs": ["<fuente observada>"],
  "requested_resolution": "FOCAL_REVIEW_ONLY"
}
```

No forma parte de `p_profile_output` hasta que una integración gobernada
haya definido un *portador confiable* y el lector del Router lo admita.
No utilizar datos de cliente ni del perfil como autenticación o autoridad.
Un `EVIDENCE_CHALLENGE` debe llevar evidencia consultada, no basta con
una cadena no vacía. El validador semántico debe comprobar la evidencia
antes de cualquier reevaluación.

Vinculaciones obligatorias:
- ejecución/rol/identidad del perfil autorizada en Router;
- output ya validado y digest SHA del artefacto entregado;
- receipt `input_validate` del **mismo execution_id** y target;
- run/pantalla/familia/source snapshot del IG efectivamente consumido;
- source refs verificables y vigencia de las fuentes;
- retorno solo al Router, nunca target directo ni grant de promoción.

Si el perfil no consumió IG durante esta tarea, no puede afirmar que
cuestiona directamente un run ajeno. Puede pedir revisión de contexto al
Router, que decide si corresponde IG.

El portador candidato puede aprovechar una evidencia autorizada del
proceso de ejecución existente; **no crear** una tabla, cola ni
otro Router. Debe verificarse si las evidencias existentes de
`execute_profile`, `output_validate`, `semantic_judge` y
`report_output` permiten extender metadatos con guardas sin romper
contratos ni hashes. `lf_profile_result_router_return_prepare_v1` hoy
lee exclusivamente `execute_profile.evidence_payload.profile_output`;
por ello, el portador transversal **no está implementado**.

## 5. Clasificación de desacuerdos y retorno
- `EVIDENCE_CHALLENGE`: juicio fundamentado sobre IG -> Router ->
  autoridad/contexto + revisión focalizada, sin rerun automático.
- `NONCANONICAL_RULE_PROPOSAL`: nueva regla funcional ->
  dueño competente; no marcar como canónica.
- `UNSUPPORTED_DISAGREEMENT`: registro en el juicio del perfil;
  sin reabrir IG por sí solo; respuesta razonada si se reitera.
- `FAIL_CLOSED`: identidad inconsistente, run ajeno, hash roto,
  fuente inventada, nivel de autoridad no probado o pedido de
  modificación de producción.

El Router debe devolver al perfil iniciador (o al especialista que
deba juzgar), preservando los artefactos anteriores. Si un nuevo perfil
tiene acceso gobernado a IG, recibe únicamente contexto pertinente,
no la decisión elaborada por otro especialista como instrucción de
rehacer todo el análisis.

## 6. Criterios verificables para salir de DRAFT

| Prueba | Estado |
|---|---|
| Enlace del perfil Product al run 949, hash, familia | 8/8 PASS SELECT anteriores |
| Transporte Router Stage1 y selección semántica | 9/9 PASS SELECT anteriores |
| Clasificador multi-perfil con routing ya conocido | **11/11 PASS SELECT** |
| Validación de esquema Product y UI en repositorio | Revisión estructural; se requieren tests de output real |
| Sidecar neutral emitido y sellado por runtime | **NO_IMPLEMENTADO** |
| Clasificador leyendo sidecar y enlazando al raw digest | **NO_IMPLEMENTADO** |
| Candidato SQL Product anidado compilado con rollback | **NO_VERIFICADO** |
| Feedback real de UI, Product y un tercero vía Router/IG | **NO_VERIFICADO** |
| Revisión independiente; seguridad; G4/G5; producción | **NO-GO** |

### Pruebas mínimas futuras
Product output cerrado, UI focused decision cerrado y un perfil nuevo
sin `deliverable_created`; sin feedback; feedback con run ajeno; sin IG
aplicable; screen selection ambiguous; fuente falsa; hash antiguo;
falso target; cambio multi-familia con dependencias; sin rerun por desacuerdo.
Probar `Validator` independiente, `rollback`, CI exact HEAD y ausencia
de impactos laterales en perfiles/Router actuales.

## 7. Frontera con el candidato anterior

`sandbox/lf_contract_gate_test/input_governance/ig_profile_feedback_router_return_candidate_20261029.sql`
solo cubre `deliverable_created.input_governance_feedback`. **No
promoverlo como transversal**, no aplicarlo por sí solo ni reescribir los
esquemas de todos los perfiles para acomodarlo. Su preimage/rollback y
pruebas históricas son evidencia útil para el problema Product, no
autorización de integración.

EKB vigente consultado: `INPUT-GOV-CONSUMER-BINDING-001`,
`IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`,
`HUMAN-DECISION-POLICY-RESOLUTION-NO-PRODUCER-AUTHORITY-001`,
`IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001`.

## 8. Primer candidato de integración (29/10/2026, NO DESPLEGADO)

El PR DRAFT contiene ahora
\`sandbox/lf_contract_gate_test/input_governance/ig_feedback_cross_profile_report_output_candidate_20261029.sql\`.
El candidato extiende **dos controles ya existentes**, manteniendo intactos los
esquemas nativos de los perfiles:

1. \`lf_profile_execution_trust_validation_v2\`: admite el sidecar opcional
   \`report_output.evidence_payload.ig_profile_feedback\` únicamente cuando
   coincide con el *mismo* execution_id/profile_code, el SHA calculado de
   \`execute_profile.profile_output\`, el run/familia/pantalla/SHA del recibo
   \`input_validate\`; verifica su forma, la ruta de revisión y bloquea
   objetos JSON no válidos, targets directos, reejecuciones forzadas y
   propuestas presentadas como canónicas.
2. \`lf_profile_result_router_return_prepare_v1\`: lee el sidecar **solo**
   después de recibo terminal READY, revalida la vinculación y usa el
   clasificador de continuaciones del Router ya existente. Si el perfil
   termina sin retorno pero tiene objeción sustentada, solicita
   \`CONTINUE_WITH_RESTRICTIONS / AUTHORITY_OR_CONTEXT_RESOLUTION\`.
   Si ya existe una continuación, preserva su ruta y añade el feedback al
   mismo payload de retorno. Conserva el **output nativo original exacto**
   y su SHA, y no autoriza llamar directamente a un perfil ni recurar IG.
   \`UNSUPPORTED_DISAGREEMENT\` por sí solo no genera ruta nueva.

Un helper de validación de solo lectura
\`lf_profile_ig_feedback_validate_v1\` permite ejecutar la misma validación
de binding en ambas fronteras, sin crear otro Router, motor, tabla ni cola.
Se declara \`SECURITY INVOKER\` y **no** se tocan ACL; revisar los grants
efectivos antes de cualquier integración autorizada.

La ubicación como sidecar de \`report_output\` necesita además que el
ejecutor/registrador real de perfiles **emita y adjunte** la observación
independiente, bajo la identidad y autoridad de la ejecución. Ese
componente de emisión **NO está integrado** en el runtime vivo.
Una cadena de fuentes \`evidence_refs\` sigue siendo una **alegación** que
el revisor debe verificar: el helper devuelve
\`evidence_authenticity_verified=false\`. Su PASS estructural nunca
significa que IG estaba equivocado.

**Pruebas:** el candidato incluye 11 negativos de \`DO $postcheck$\`,
con \`BEGIN; ... ROLLBACK;\`, todos **NO EJECUTADOS** en PostgreSQL porque
la conexión a Supabase es SELECT-only y no hay servidor PostgreSQL local.
No confundir su presencia textual con PASS de ejecución.

**Readback reproducible del flujo vivo:**
\`sandbox/lf_contract_gate_test/input_governance/ig_feedback_cross_profile_report_output_baseline_readonly_20261029.sql\`
→ **11/11 PASS**. El primer intento, que comparó indiscriminadamente
todos los \`COMPLETED\` históricos contra el contrato terminal actual,
produjo 3 FAIL. La investigación demostró 2 ejecuciones con terminal
\`READY\` y 14 legadas \`BLOCKED\` por el contrato actual; el test
se corrigió para verificar explícitamente la cohorte admisible,
mantener visible la diferencia y no otorgar PASS retroactivo a los 14.
El baseline actual no tiene sidecars, conserva sus hashes y preserva
las 47 familias del run 949.

**Gates para continuidad:** compilar y ejecutar el SQL candidato completo
en PostgreSQL 17 aislado con rollback; comprobar permiso/ACL; implementar
emisión gobernada del sidecar en \`report_output\`; probar salidas reales
de Product/UI/tercero, validación y juicio propio; reentrada ACT-0001
Stage1; feedback sin IG, hash ajeno, repetición, evidencia falsa, rollback,
readback, revisión independiente. Sigue **NO-VERIFICADO/NO-GO** para
integración, G4/G5 y producción.
## 9. Endurecimiento y admisión del candidato (29/10/2026)

**Protección de frontera:** el helper se ubicó en
\`private.lf_profile_ig_feedback_validate_v1\` con
\`SECURITY INVOKER\`. El EKB y el readback del esquema mostraron
\`private.USAGE=false\` para \`anon\` y \`authenticated\`;
no se cambió ningún permiso. Requiere revisión de propietario/RPC
en el PostgreSQL aislado antes de activar.

**Proveniencia del juicio:** para atribuir un feedback al perfil, el
verificador candidato exige que
\`execute_profile.evidence_payload.ig_profile_feedback_candidate\`
contenga el objeto idéntico a
\`report_output.evidence_payload.ig_profile_feedback\` y que el SHA
del output nativo validado coincida. Así, agregar una objeción
directamente a \`report_output\` **no basta**. No afecta los esquemas
nativos de Product, UI ni los otros perfiles. El emisor del sidecar
en \`execute_profile\` **todavía NO está implementado** en el bridge
GPT/Claude native; sin él, todo feedback nuevo debe bloquearse.
El nuevo control solo es válido cuando la evidencia provenga
realmente de la ejecución autorizada, no de un texto añadido después.

**Autorización del Router:** si
\`router_profile_handoff.return_to_router_after_profile_result\`
está ausente o es falso, el candidato no abre el Router por la
presencia de un sidecar; devuelve
\`PROFILE_IG_FEEDBACK_ROUTER_RETURN_NOT_AUTHORIZED\`.
Sin feedback, conserva exactamente el comportamiento anterior.

**Pruebas de regresión del flujo vigente:** se ejecutó desde el
blob Git exacto:
\`sandbox/lf_contract_gate_test/input_governance/ig_feedback_profile_return_authority_readonly_20261029.sql\`.
**9/9 PASS**: dos perfiles con autoridad terminal \`READY\`;
14 ejecuciones legadas no elegibles; retorno habilitado/deshabilitado,
hash, ausencia de sidecars, preimages de las funciones y run 949 intacto.
El primer ensayo marcó FAIL por tratar un campo opcional de manifiesto
ausente como falso explícito; el test se corrigió para respetar el
\`coalesce(...,false)\` de la función viva y se repitió con 9/9 PASS.

**Límites:** no hay PostgreSQL binario en la sesión y el acceso a
Supabase es de solo lectura. El candidato SQL contiene
\`BEGIN ... ROLLBACK\` y 11 negativos **preparados pero NO EJECUTADOS**;
no hay PASS de compilación, DDL, emisión real, cuatro perfiles completos,
integración, G4 ni G5. PR #3269 continúa DRAFT sin mutar producción.

**Orden de salida:** 1) probar el candidato exacto en PostgreSQL aislado;
2) definir y construir emisión segura desde el resultado real del
especialista a \`execute_profile\`; 3) probar el trayecto report_output
-> prepare -> Router Stage1 con casos positivos, negativos y sin IG;
4) revisión independiente y habilitación solamente por ruta gobernada.
