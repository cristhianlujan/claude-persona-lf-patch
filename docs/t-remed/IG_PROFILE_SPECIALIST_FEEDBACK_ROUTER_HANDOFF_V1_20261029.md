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
  El script incluye escenarios positivos y negativos dentro de
  `BEGIN ... ROLLBACK`; **no fue ejecutado como DDL ni aplicado** porque
  la conexión a Supabase está autorizada solo en lectura.
- Se reforzó el candidato para verificar que la ejecución del perfil
  consumió **ese run y esa pantalla** desde el paso `input_validate`
  `STEP_PASS_WITH_EVIDENCE`, y que el hash de su manifiesto coincide
  con el run. Una coincidencia entre familia y run no es suficiente.
- Para `EVIDENCE_CHALLENGE`, referencias vacías o no textuales se
  bloquean (sin atribuirles autoridad canónica). Las propuestas exigen
  `proposed_change` y `PROPOSED_NOT_CANONICAL`; una discrepancia
  sin sustento que intenta volver a `AUTHORITY_OR_CONTEXT_RESOLUTION`
  se bloquea para evitar ciclos artificiales.

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

## Verificación independiente de datos y compatibilidad (29/10/2026)

1. Se ejecutó desde el **blob exacto Git**
   `sandbox/lf_contract_gate_test/input_governance/ig_profile_feedback_run_receipt_binding_readonly_20261029.sql`:
   **8/8 PASS**. Incluye existencia del fixture, caso correcto, y rechazo
   de ejecución, perfil, run, pantalla, hash y familia incorrectos.
   Son SELECT sobre Supabase: **prueban el predicado de identidad**,
   no la compilación ni la ejecución del clasificador candidato.
2. Se verificó el esquema JSON actual de Product Director:
   `properties.deliverable_created.additionalProperties=true`;
   por tanto el campo adicional anidado es compatible con esa
   restricción de esquema. El esquema de nivel superior usa
   `additionalProperties=false`, por lo que no se añadió campo
   top-level. La ejecución integral del validador y juez de Producto
   queda **NO_VERIFICADA**.
3. La función viva sigue en MD5
   `7517e452f5fa3ab2686c073bd6604b78`, igual al preimage guard
   del candidato; el fichero contiene rollback y no contiene commit.
   La verificación del texto **no constituye compilación PostgreSQL**.
4. El fixture de la ejecución que consumió `run_id=949`
   actualmente está `IN_PROGRESS`; no constituye prueba de un retorno
   posterior al cierre completo del perfil. El runtime prepare exige
   `COMPLETED` para devolver al Router.

### Estado de salida y frontera de autoridad

- `PASS`: predicado read-only de unión ejecución/perfil/run/familia/hash,
  comprobación de schema y guardas de fuente.
- `NO_VERIFICADO`: SQL `CREATE OR REPLACE FUNCTION` del candidato en
  PostgreSQL de pruebas con `ROLLBACK`, aserciones del postcheck,
  comportamiento del validador real y cadena
  `perfil COMPLETED -> prepare -> Router Stage1`.
- `NO`: despliegue/activación/permiso de cambiar reglas/selector; ninguna
  escritura a Supabase.
- Próxima acción autorizada: ejecutar el candidato **en una rama/entorno
  aislado de PostgreSQL con permisos de test**, registrar PASS/FAIL y
  rollback. Solo después, siguiendo EKB de migración source-first y
  autorización de integración, considerar cutover gobernado.

## Verificación adicional del Router existente (29/10/2026)

Se ejecutó **desde el blob exacto versionado** el SQL read-only
`sandbox/lf_contract_gate_test/input_governance/ig_profile_feedback_router_roundtrip_readonly_20261029.sql`
(blob `de36b3bdd688812b6c5f590bdd6a05c67efe4b4c`):
**9/9 PASS**. Checks: RETURN_TO_ROUTER, REENTER_ROUTER_STAGE1,
REPEAT_FULL_ROUTER_FLOW sin reutilizar autoridad previa,
conservación de feedback, conservación de SHA de salida, Stage1 requerido,
Stage1 válido, selección semántica requerida (catálogo 10) y
`effect_authority=false`.

**Frontera semántica importante:** esta regresión utiliza una salida de
perfil **sintética con routing explícito** que la función viva ya conoce.
No afirma que ese payload supere
`product_director_lf/validators/validate_product_director_output.py`
(el esquema de Product Director veta propiedades top-level extra).
No demuestra la ruta nueva que infiere retorno desde el feedback anidado;
esa inferencia solamente existe en el candidato SQL **NO INSTALADO**.

Se comprobó además que hay una ejecución Product Director completada con
IG `NOT_REQUIRED`, y otra con `run_id=949` en estado `IN_PROGRESS`.
Por ello **no existe en este fixture evidencia E2E de un perfil terminado
con feedback IG consumido**, ni se declara integrado el retorno.

### Primer bloqueo operativo para el SQL candidato

El entorno de prueba de esta sesión carece de un PostgreSQL ejecutable local
y la interfaz Supabase disponible impide DDL, inclusive en transacciones
que terminarían con `ROLLBACK`. No se instaló componente externo ni se
alteraron permisos. La **compilación del candidato y los postchecks
dentro de `BEGIN ... ROLLBACK` siguen NO_VERIFICADOS**.
No convertir 8/8 + 9/9 de consultas existentes en PASS del parche.

Criterio de próxima prueba: PostgreSQL aislado que contenga los contratos
y esquema real, ejecutar el archivo candidato exacto, capturar primer
error y postchecks, verificar readback funcional y rollback sin residuos;
después validar payload real de Product Director y la frontera
`report_output -> Router ACT-0001`. Mantener PR DRAFT y no modificar
DB viva, EKB, ni reglas/permissions/selectores.

## Precisión transversal — múltiples perfiles (29/10/2026)

Este documento y su SQL candidato previo **solo ensayan la ubicación
`deliverable_created.input_governance_feedback`**, compatible con el
`PRODUCT_DIRECTION_SPEC` actual. No equivale a un contrato universal: por
ejemplo, la decisión focal de UI posee un esquema raíz cerrado sin
`deliverable_created`.

El contrato de arquitectura que debe regir la extensión a perfiles presentes
y futuros es:
`docs/t-remed/IG_PROFILE_FEEDBACK_TRANSVERSAL_CONTRACT_V1_20261029.md`.
Se propone un feedback de ejecución independiente del output nativo,
vinculado a `execution_id`, `profile_code`, SHA del output validado y
recibo IG realmente consumido. **El portador, la validación y su lectura
por Router aún NO están implementados.** No activar ni promover el SQL
Product-only como solución transversal. Mantener sin cambios todos los
contratos de salida vigentes hasta autorización y pruebas.

Regresión exacta de solo lectura:
`sandbox/lf_contract_gate_test/input_governance/ig_feedback_cross_profile_transversal_readonly_20261029.sql`.
11/11 PASS para vínculos registrados y retorno tipado con salidas sintéticas
de Product, UI, Evidence Reviewer y Reparador. Esto no acredita ejecución
real de cada perfil ni autorización IG de los seis sin binding directo.
