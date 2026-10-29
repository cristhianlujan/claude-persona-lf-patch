# IG N-4 — Retroalimentación del especialista y retorno gobernado al Router
**Corte:** 29/10/2026 · **Estado:** CANDIDATO / NO DESPLEGADO · **PR:** #3269 DRAFT

## Decisión arquitectónica
Input Governance (IG) produce la evaluación gobernada de entrada; el perfil
seleccionado es el responsable de su juicio especializado. El perfil puede
cuestionar un resultado de IG, pero una objeción no invalida el run, no publica
reglas y no autoriza repetir Curator/Validator. El Router ACT-0001 es el único
selector del siguiente trabajo. Un perfil nunca llama a otro perfil ni se
convierte en autoridad de G4.

Reutilizar:
- `EJECUCION_PERFIL_LF` y su resultado validado; no abrir una nueva cola.
- `public.lf_profile_result_router_return_classify_v1` y
  `lf_profile_result_router_return_prepare_v1` para devolver trabajo.
- `ACT-0001_STAGE1` con selección determinista/semántica nueva; el perfil previo
  es asesor, no el selector de la próxima especialidad.
- `programacion.input_readiness_runs` y las tablas existentes de evaluaciones y
  propuestas; **nunca actualizar filas históricas por una objeción**.
- `fn_input_governance_curator_plan_v1` con NOOP/REBIND/
  SOURCE_STALE_RECURATE/FULL_RECURATE según evidencia de fuente y currentness,
  no según desacuerdo de un especialista.

## Contrato mínimo de feedback (sin nuevo motor ni tabla)

Lugar compatible con el esquema de Product Director:
`deliverable_created.input_governance_feedback`; el esquema actual permite
propiedades adicionales **dentro** de `deliverable_created`, pero no admite
nuevos campos top-level. Para perfiles futuros, el adapter autorizado debe
normalizar a esta estructura sin cambiar las responsabilidades del Router.

```json
{
  "schema_version": "IG_PROFILE_FEEDBACK_V1",
  "kind": "EVIDENCE_CHALLENGE",
  "run_id": 949,
  "pantalla_id": 51,
  "family_code": "SESSION",
  "source_snapshot_sha256": "<SHA256 real leído del run>",
  "reason": "Qué evaluación se cuestiona y por qué",
  "evidence_refs": ["<referencia real consultada>"]
}
```

Los valores anteriores son un **ejemplo de formato** para run 949, no targets
codificados ni hechos probados sobre SESSION. Cualquier petición operativa debe
obtener los IDs y el hash del contexto efectivo.

Tres tipos de observación:
1. `EVIDENCE_CHALLENGE`: el experto afirma que la evaluación de IG omitió
   evidencia relevante o utilizó fuentes contradictorias. Exige al menos una
   referencia de evidencia; esa referencia es una **afirmación del experto**,
   no evidencia verificada por el clasificador. Devuelve al Router para
   resolver autoridad/contexto sin reejecución IG automática.
2. `NONCANONICAL_RULE_PROPOSAL`: nueva regla o mejora aún no canónica.
   Exige `canonical_status=PROPOSED_NOT_CANONICAL`, y retorna al Router para
   la ruta del propietario competente. No modifica la evaluación canónica
   como si la regla ya existiera.
3. `UNSUPPORTED_DISAGREEMENT`: discrepancia sin sustento material nuevo.
   Puede quedar documentada en el artefacto del perfil, pero **por sí sola**
   no reabre IG, no invalida el run y no crea una cadena infinita.

Todos deben indicar run+pantalla+familia existentes, snapshot SHA y razón.
`family_code` se resuelve por filas del run, sin enumeraciones de negocio
embebidas en el clasificador. `profile_code` permanece separado del consumidor
técnico permitido por `INPUT_GOVERNANCE_EXECUTION_CONTRACT` (actual
`CONTEXT_PACK`). No poner `profile_code` en el argumento `consumer`.

## Frontera entre evaluación y autoridad

El clasificador puede rechazar un feedback sin binding real, incompleto,
que proponga `target_profile` directo o que contenga permisos inventados.
El `RETURN_TO_ROUTER` de un feedback válido significa **necesita análisis
de contexto/autoridad**, no "IG estaba equivocado" ni autorización G4.

El Router determina el dueño de la revisión y valida las fuentes nuevas.
Solo cuando exista una corrección canónica **gobernada** o una fuente material
verificada que cambie la evaluación, IG aplica sus reglas de frescura y puede
generar sucesor con linaje intacto. Si no hay cambio, se conserva el run
y se responde fundadamente al especialista. El resultado específico del
perfil (juicio funcional o técnico) no sustituye el Validator independiente.

## Evidencia disponible y defectos comprobados
- Función viva `lf_profile_result_router_return_classify_v1`: si el perfil
  devuelve una observación dentro de `deliverable_created` sin `routing`,
  responde `COMPLETE / EMIT_PROFILE_RESULT` y puede perder esa continuación.
  Reproducido con SELECT y fixture de run 949; **no** es prueba end-to-end.
- Existe un retorno positivo gobernado para
  `routing.pipeline_action=CONTINUE[ _WITH_RESTRICTIONS]`, que preserva
  `upstream_profile_output` y su hash, hacia `ACT-0001_STAGE1`.
- El esquema de `PRODUCT_DIRECTION_SPEC` prohíbe nuevos campos top-level.
  Por eso la opción de añadir `routing` directamente al payload de Product
  puede fallar su validador; no forzar ese atajo.
- Candidato de ajuste del clasificador **en el archivo de sandbox**:
  `sandbox/lf_contract_gate_test/input_governance/ig_profile_feedback_router_return_candidate_20261029.sql`.
  Extiende el clasificador actual, no crea un segundo resolver, usa binding
  run/familia/hash y devuelve vía el retorno positivo existente.
  El script incluye 6 aserciones y `BEGIN ... ROLLBACK`; **no fue ejecutado
  ni aplicado** porque la conexión a Supabase está autorizada solo en lectura.

## Aceptación antes de habilitar

**Pendiente**: ejecutar el script candidato en un entorno autorizado de pruebas
con readback y rollback, no en producción; verificar con el validador real de
Product Director que el campo opcional es compatible; probar el
`prepare -> classify -> Router Stage1 -> selección semántica` con solicitud
real y evidencia, evitando invocación directa de IG. Rechazar feedback con
referencia inventada, hash viejo que no corresponde al run, familia ajena,
repetición sin evidencia o permiso de publicación implícito.
No declarar PASS semántico, activación ni cierre G4/G5 por PASS estructural.

EKB consultado: `INPUT-GOV-CONSUMER-BINDING-001`,
`IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`,
`IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001`,
`HUMAN-DECISION-POLICY-RESOLUTION-NO-PRODUCER-AUTHORITY-001`.
EKB vivo sin mutaciones; cualquier registro posterior se hace por ruta gobernada.
