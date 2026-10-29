# LF Profile Updater — estándar de evolución estructural dinámica del perfil objetivo

## Verificación del estándar de referencia SRCR (27 octubre 2026)

- Registry Supabase: `PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF` version `v0.2`, estado documental `CANDIDATO`, operativo `READ_ONLY`; no equivale a la versión del pack.
- Pack GitHub `main`: `SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6`, método `SRCR_V0_7R1` (`manifest.json`, `SKILL.md`, `contracts/dynamic_method_catalog.v1.json`).
- Selección del perfil `public.lf_profile_selection_registry_v1`: descriptor `CURRENT`, source revision `35bbadad5c76b7a4b42b695f01beefa30cd8f272`; no convierte el candidato en runtime habilitado.
- PR #1889 fusionó el método dinámico; PR #3155 agregó reparación gobernada acotada. Autorización en contrato limitada al intent `REPAIR_MISSING_PRODUCT_STRUCTURE`; **no** es un permiso general para ejecutar Profile Updater.
- Método SRCR: signals tipadas → núcleo mínimo → módulos pertinentes → grafo real, primera frontera fallida → hipótesis y falsificación → operadores mínimos → efectos de segundo orden → cierre determinista. Adopción por reutilización de capacidades, nunca crear un motor paralelo.
- SRCR obliga retorno al Router/orquestador, prohíbe invocación directa de otro perfil. Para la evolución del propio perfil por el Updater el handoff debe mantener autoridad e identidad sin reiniciar la ruta de intención.
- SRCR integra contract/runtime binding, jueces, schemas, validators, tests, catalog y contexto model-facing acotado. Un cambio estructural requiere reconsiderar **todos los consumidores afectados**.
- La operación `ACTUALIZACION_PERFIL_LF` tiene actualmente 17 pasos definidos (15 activos, 2 candidatos). **Estos son gates de gobernanza del Updater, no el número de pasos internos del perfil objetivo.** No los reemplazamos por una plantilla del SRCR.

## Regla del estándar

El updater evoluciona el perfil objetivo según el diagnóstico funcional, su naturaleza y el grafo de dependencias. Para cada nodo puede: KEEP, ADD, REPLACE, REMOVE, MERGE, SPLIT, REORDER, DEPRECATE, CONDITIONAL o NO_CHANGE. El número y orden finales de pasos internos no son fijos. No aplicar todas las técnicas ni todos los módulos en cada perfil.

La selección diferencial debe resolver: contrato y firma de cada paso, estado de autoridad, consumidor real, entrada/salida, juez aplicable, schema, error/transición, archivos, runtime binding, permisos, token/context budget, versión, impacto de segundo orden, readback y rollback. `REMOVE` debe demostrar ausencia de dependencias rotas; `REPLACE` debe preservar comportamiento obligatorio; `ADD` debe justificar utilidad y no duplicación.

## Estructura de la ampliación

Una unidad nueva `PE10A_STRUCTURE` con 12 checkpoints y 6 dependencias (contracts, judges, pipeline, methods, SRCR; y `PE10A_READY` depende de structure). No duplicar 48 checkpoints previos; sus controles transversales se reutilizan. Cada punto nace `PENDING` y `BLOCK_PENDING_IMPLEMENTATION_AND_INDEPENDENT_RECEIPT`. Su materialización **no demuestra ejecución**.

### PE10A_ST01 — Autoridad/versiones del perfil objetivo y SRCR

- **PASS requerido:** Readback compara lf_activos, descriptor CURRENT, manifest, SKILL, runtime binding, method_revision y fuentes exact-head; clasifica v0.6 pack vs SRCR_V0_7R1 método.
- **Falsificador negativo:** Una versión declarada como vigente solo por nombre, candidato o rama es rechazada.
- **Reutiliza:** PE10A_CT01, PE10A_GH01.

### PE10A_ST02 — Extraer topología real y capacidades preservables del perfil

- **PASS requerido:** Grafo de pasos funcionales, entradas, salidas, contratos, firmas, jueces, validators, consumers, dependencia, terminalidad y coste es material y evidencia sus fuentes.
- **Falsificador negativo:** Un paso inventado o una mención textual sin ejecución/propietario no se clasifica como componente operativo.
- **Reutiliza:** PE10A_CT02, PE10A_PL02.

### PE10A_ST03 — Determinar operación diferencial por nodo con pruebas de necesidad

- **PASS requerido:** Cada paso recibe KEEP, ADD, REPLACE, REMOVE, MERGE, SPLIT, REORDER, DEPRECATE, CONDITIONAL o NO_CHANGE según caso, con razón, alcance, dependencia, antes/después y aceptación.
- **Falsificador negativo:** Una operación por plantilla o porcentaje, no justificada por evidencia causal, queda bloqueada.
- **Reutiliza:** PE2B_C3, PE3B_C1, PE10A_ME02.

### PE10A_ST04 — Agregar pasos funcionales cuando la naturaleza lo requiera

- **PASS requerido:** Paso ADD añade contrato, input/output, propietario, juez, fuente, calificación, error y ruta autorizada, con test positivo de su necesidad.
- **Falsificador negativo:** ADD sin consumidor, sin contrato o que duplique capacidad reutilizable no se acepta.
- **Reutiliza:** PE5A_C2, PE10A_CT04.

### PE10A_ST05 — Eliminar o deprecar pasos y limpiar las referencias

- **PASS requerido:** REMOVE/DEPRECATE prueba ausencia de consumidor requerido, elimina referencias huérfanas, conserva migración y compatibilidad de ejecuciones previas.
- **Falsificador negativo:** Eliminar un paso consumido sin migración/binding de retiro, o dejar un salto colgado, falla.
- **Reutiliza:** PE5A_C4, PE10A_CT05.

### PE10A_ST06 — Reemplazar pasos, firmas y jueces preservando semántica autorizada

- **PASS requerido:** REPLACE vincula old/new paso+contrato+firma+schema+binding+judge y verifica equivalencia, adaptación y deprecación segura.
- **Falsificador negativo:** Si se pierde un campo requerido, una condición de bloqueo o una función del perfil se rechaza.
- **Reutiliza:** PE6_C4, PE10A_JD01.

### PE10A_ST07 — Fusionar, separar o reordenar sin romper el grafo

- **PASS requerido:** MERGE/SPLIT/REORDER produce grafo acíclico y transiciones válidas, sin duplicación, fase omitida ni ruta huérfana; pruebas ejecutadas.
- **Falsificador negativo:** Un cambio que ejecute semántico antes del determinista o salte un gate falla.
- **Reutiliza:** PE10A_PL02, PE10A_PL03.

### PE10A_ST08 — Seleccionar secuencia interna condicionada por naturaleza y señales

- **PASS requerido:** Pipeline del perfil elige módulos y métodos por señales tipadas y precondiciones, no usa número fijo de pasos ni aplica todos los módulos.
- **Falsificador negativo:** Ruta dependiente de nombre de producto, método no calificado o subflujo no autorizado bloquea.
- **Reutiliza:** PE3B_C2, PE10A_ME02, SRCR_V0_7R1.

### PE10A_ST09 — Actualizar paquete transversal afectado y sus consumidores

- **PASS requerido:** SKILL, manifest, contratos, firmas, JSON schemas, judges, validadores, tests, imports, runtime binding, ejemplos, proyección/context budget actualizados según impacto.
- **Falsificador negativo:** Actualizar solo SKILL o PR sin despliegue/consumidor verificado no produce APTO.
- **Reutiliza:** PE10A_CT04, PE10A_GH05, PE10A_OP02.

### PE10A_ST10 — Probar casos reales comparados: agregar, quitar, sustituir y NO_CHANGE

- **PASS requerido:** Cuatro casos representativos provider-bound con baseline congelado, ejecución de perfil real, pruebas positivas/negativas, holdout y calidad preservada; registrar receipts.
- **Falsificador negativo:** Mock, fixture aislada, auto-evaluación o texto PASS no admiten cierre.
- **Reutiliza:** PE10E_C1, PE10A_OP03, PE10A_OP04.

### PE10A_ST11 — Reverificar efectos de segundo orden, estado durable y reversión

- **PASS requerido:** Identifica rutas alternas/consumidores antiguos, estado persistente, replay y rollback; valida reconstrucción/recuperación de perfil anterior.
- **Falsificador negativo:** No permite perfil parcialmente evolucionado, loops de autorreparación, cursor inservible ni función deprecated accesible.
- **Reutiliza:** PE10A_PL06, PE10A_GH06, PE10A_OP06.

### PE10A_ST12 — Handoff Reparador→Updater y aceptación de perfil utilizable

- **PASS requerido:** SRCR (pack v0.6, método SRCR_V0_7R1) entrega solicitud estructurada mediante orquestador gobernado con autoridad exacta; resultado APTO solo con readback runtime/Supabase/GitHub y comprobación independiente.
- **Falsificador negativo:** SRCR no invoca directamente otro perfil, ni usa intent no autorizado REPAIR_MISSING_PRODUCT_STRUCTURE como permiso general de Updater; sin E2E retorna próxima acción.
- **Reutiliza:** PE10A_SR03, PE10A_SR04, PE10A_OP08.


## Regla de aptitud final

No APTO por 13/13 estructural, PR fusionado, simulación o jueces autodeclarados. APTO exige tarea real bajo host autorizado, paridad GitHub/Supabase/runtime, resultados positivos/negativos, holdout de perfil, no regresiones críticas, terminalidad sin bloqueos materiales y retorno de ejecución verificable. Si falla: última versión útil conservada + causa + límite de autorreparación + próxima acción.

## Transporte

Solo `ACTUALIZACION_DB_LF` por `LF Migration Merge Train` agrega esta unidad al plan. Cero activación v0.2, cambio de perfiles, Edge o runtime. Preestado: 27 unidades / 132 checkpoints; postestado previsto: 28 / 144; DONE previos 79, NA 3, PENDING 62.
