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
