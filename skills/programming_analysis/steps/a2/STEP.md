# A2 — Clasificación interna de cambio, alcance y profundidad

**Estado:** `LOCAL_DETERMINISTIC_CANDIDATE_UNQUALIFIED`. Paso **interno** de la skill `PROGRAMMING_ANALYSIS_LF`. No existe una segunda skill A2.

## Entrada
- `a1_result` válido y tipado, `status=VALID_OUTPUT`, `REQUEST_CONTEXT_V1`, `interpretation_state=PRESTRUCTURED_UNATTESTED`.
- `signal_bundle` recibido del consumidor: referencia exacta a un target aportado en A1, tipo/granularidad explícitos, refs de evidencia y señales tipadas, **sin afirmar que ya están autenticadas**.
- Candidatos semánticos de texto libre: **bloquear hasta productor real, revisor independiente y recibos**, sin aceptar autorreporte de juez dentro del bundle.

## Proceso
1. Verificar el sobre completo de A1 y validar su payload contra el esquema canónico actual.
2. Validar el destino sin inferirlo de palabras clave. Objetivos anidados SECTION/CONTROL requieren `nested_parent_ref`.
3. Leer `analysis_change_classification_contract_v1.json` y aplicar **directamente sus expresiones** `L3_if_any`, `L2_if_no_L3_and_any`, `L1_requires_all` a las señales tipadas. Sin pesos, heurística libre ni familia de caso.
4. Entregar `ANALYSIS_CHANGE_CLASSIFICATION_V1` como **candidato**, con nivel L1/L2/L3 y predicados justificativos. No generar identidad de especialistas: CAPABILITY_SELECTOR y sus manifiestos RELEASED siguen siendo autoridad externa.
5. Emitir clasificación candidata, brechas explícitas e instrucciones dirigidas para A3. A3 espera a que A2 termine y pase la evaluación del juez existente por ruta nativa; A2 no espera la investigación de A3. En este módulo source-only `next_step=null` hasta readback gobernado del gate.

## Bloqueos
No admitir A1 con revisión semántica pendiente, source refs vacías, señales inválidas, target inventado, falta de padre en target anidado, drift de política o inferencia de permisos. L1 requiere todos los criterios; materialidad desconocida nunca puede dar L1. No se altera Router, Supabase, EKB ni catálogo de skills.

Pruebas locales sintéticas: `python -m unittest discover -s skills/programming_analysis/steps/a2/evals -p 'test_*.py' -v`. Estas no prueban runtime ni independencia de juez.

## Identidad obligatoria del negocio y ficha de investigación (requisito pre-admisión)
- **Negocio:** A2 debe transportar sin modificación `a1_result.business` (declarado y tipado por A1) para todo el resultado y el handoff A2→A3. Nulo/vacío, conflicto con la identidad del RUN o cambio de negocio sin fuente y autoridad ⇒ bloquear el handoff, nunca asumir LF/SALY por el nombre de una pantalla.
- **Producto, módulo y target:** registrar los valores si A1 los proporcionó de forma verificable mediante `REQUEST_CONTEXT_V1.provided_facts[]`, `target_hints[]` y `source_refs[]`; anotar `DECLARED` vs `CURRENT_VERIFIED`, sin derivar identidad canónica de una coincidencia textual. Si faltan, el estado es `UNKNOWN` y A3 recibe preguntas dirigidas. No fabricar códigos ni nombres.
- **Especificaciones para A3:** A2 detalla finalidad funcional, alcance incluido/excluido, restricciones, señales de clasificación, escenarios de riesgo **hipotéticos**, hechos conocidos con referencia, pistas de fuentes y las consultas exactas (identidad canónica, políticas, versiones, parámetros, implementación, API/UI y consumidores). A2 **no** hace la investigación de A3 ni declara CURRENT.
- **Responsabilidad de A3:** usar `REQUEST_CONTEXT_V1` + `ANALYSIS_CHANGE_CLASSIFICATION_V1` y el contexto de negocio retenido para resolver identidad y autoridad CURRENT, confirmar la implementación y completar parámetros y dependencias con evidencia; no pasar a otro negocio salvo dependencia acreditada por fuente y alcance.
- **Juez existente:** rechazar un A2 que omita negocio, cambie de negocio, presente una especificación no sustentada como vigente o traslade a A3 una tarea propia de clasificación. La ausencia de evidencia que A3 está encargado de obtener **no es FAIL automático de A2** si quedó clasificada y dirigida correctamente.
- **Implementado solo en rama candidata:** `schemas/input.schema.json` exige `business`; `schemas/output.schema.json` exige `business` en respuestas no bloqueadas; `validators/run.py` comprueba igualdad exacta contra `a1_result.business` y rechaza hechos de identidad contradictorios. `adapters/a2_a3_business_handoff_v1.py` crea una ficha con negocio, producto/módulo solo si figuran en hechos fuente, objetivo, restricciones, preguntas para A3, y sus **dos inputs canónicos**. El puente `adapters/a1_a2_candidate_bridge_v1.py` acepta `expected_business` del consumidor. Ausente ⇒ handoff bloqueado; nunca inferir identidad desde A1 para sustituir la autoridad del consumidor. Los tests del mismo paquete cubren LF→SALY, ausentes y hechos contradictorios. Nombre y código de un mismo producto o módulo pueden coexistir si tienen referencias válidas; se rechazan conflictos dentro de la misma clave y se conserva la totalidad de hechos declarados.
- **Límite:** el guard siempre devuelve `a3_allowed=false`, `judge_verified=false`, `next_step=null`. Son validaciones estructurales locales, no readback del RUN ni autorización de juez/skill. `expected_business` aportado por el consumidor requiere fuente gobernada y validación externa en runtime. No se modificó el contrato canónico `ANALYSIS_CHANGE_CLASSIFICATION_V1` ni `REQUEST_CONTEXT_V1`.


## Vinculación a RUN gobernado (guard candidato, no autenticación)

- La identidad no puede proceder solo de `expected_business`: ahora el puente `adapters/a1_a2_candidate_bridge_v1.py` requiere una conciliación coherente del RUN de perfil, `lf_skill_invocation_v1` y RUN hijo `EJECUCION_SKILL_LF`. `expected_business` sirve exclusivamente como veto. Sin `run_readback` o sin `actor_parent_execution_id`, bloquea.
- La función pura `adapters/run_business_binding_v1.py::reconcile` coteja `manifest.business`, `router_profile_handoff.business`, `router_authorization_receipt.business`, perfil, `request_sha256`, `skill_run_id`, código de skill y RUN hijo. No rellena un negocio faltante con el recibo ni se fía de campos `trusted` que envíe el consumidor.
- **Límite obligatorio:** aunque `reconcile` devuelva `CANDIDATE_CONSISTENT`, mantiene `readback_authenticated=false`, `operationally_integrated=false`, `a3_allowed=false`. El host autorizado todavía debe consultar la BD directamente, validar permisos/identidad de actor y emitir/readback de sus propios recibos. La consistencia estructural de JSON suministrado no es autenticación.
- El informe y consulta SELECT de referencia están en `handoffs/RUN_BUSINESS_BINDING_CANDIDATE_20261106.md`. Las 30 pruebas locales se limitan a consistencia, bloqueo y puente con otras unidades simuladas; no acreditan RPC, juez o admisión.
- **Brecha de arquitectura confirmada:** `lf_skill_invoke_v1` solo crea `child_execution_id` para `effect=WRITE_GOVERNED`. Esta skill es candidata `READ_ONLY`; no cambiar su efecto ni usar funciones paralelas para producir artificialmente un RUN hijo. La resolución de la apertura real de `EJECUCION_SKILL_LF` permanece P0 pre-admisión.

## Apertura read-only del RUN de skill (brecha nativa, preadmisión)

- La entrada `SKILL_EXECUTION` del Router resuelve a `EJECUCION_SKILL_LF`, operación existente 0–80. `fn_lf_operation_reserve_execution_v1` es el **reservador genérico vigente**, pero no valida por sí mismo el Router/caller/negocio: sólo un host con identidad admitida y control previo puede llamarlo y registrar/readback del paso 0. No invocarlo desde A1, A2 ni un consumidor con permisos propios.
- `lf_skill_invoke_v1` para `READ_ONLY` termina una invocación SQL sin `child_execution_id`; eso no es un RUN gobernado. El guard `adapters/run_business_binding_v1.py` devuelve `RUN_GOVERNED_CHILD_ABSENT_READ_ONLY_INVOKER` en ese caso. Ningún `skill_run_id` SQL reemplaza `execution_id` de `EJECUCION_SKILL_LF`.
- **P0 pendiente:** enlazar el caller/invocador gobernado actual con la reserva nativa, identidad read-only, paso 0 y readback transaccional, sin alterar el efecto `READ_ONLY`, crear Router alterno ni cambiar ACL. `lf_pre_ekb_child_dispatch_v1` sólo sirve a ACT-0057: no utilizar para A2. No ejecutar A3 ni admitir mientras falte este enlace.
- Documento y pruebas: `handoffs/NATIVE_READONLY_SKILL_RUN_OPEN_CANDIDATE_20261106.md` y `steps/a2/evals/test_run_business_binding_v1.py` (32 pruebas sintéticas; NO prueban que el host haya reservado, juzgado o escrito recibos).

## Lote 15: planificación de reserva/readback de RUN (sin ejecución)

- El código candidato `adapters/native_readonly_run_plan_v1.py` evalúa condiciones declaradas antes de reservar `EJECUCION_SKILL_LF`, deriva IDs y clave de idempotencia estables (padre + skill + hash de input), y verifica el readback **supuesto** del reservador, RUN hijo y `init_execution` (paso 0). Es una propuesta local, NO ejecuta RPC.
- El reservador canónico `fn_lf_operation_reserve_execution_v1` valida idem/target/request pero **no** compara manifiesto en replay. El plan exige negocio, fuente Main, actor y `skill_run_id` exactos; acepta solo `operation_policy_snapshots` como metadata de gobernanza adicional. Drift ⇒ bloqueo.
- `steps/a2/evals/test_native_readonly_run_plan_v1.py`: 39 pruebas sintéticas; el plan mantiene siempre `host_attested=false`, `reservation_executed=false`, `step0_recorded=false`, `readback_authenticated=false`, `a3_allowed=false`, incluso con fixture PASS.
- Documento de enlace mínimo: `handoffs/NATIVE_READONLY_INVOCATION_PRE_ADMISSION_CANDIDATE_20261106.md`. Requiere cambiar fuente oficial invocador/Edge mediante su gobierno **antes** de admisión: evitar handler SQL prematuro / estado COMPLETED en READ_ONLY nativo y nunca reportar `SKILL_INVOKED` si la RPC respondió BLOCKED.
- P0 sin resolver: autorización de perfil a `EJECUCION_SKILL_LF` (actualmente 0 filas), catálogo READY (0 para esta skill), aprobación de caller OIDC y fuente Main; registro real del paso 0 y juez nativo. No promover ni ejecutar A3.

## Ciclo Golden interno A2 → juez existente → A3 (candidato, NO activado)
- Durante `execute_skill` de la operación `EJECUCION_SKILL_LF`, A1 entrega su resultado a A2; A2 debe cumplir su trabajo de clasificación, activación dinámica de las 12 dimensiones/59 elementos y plan dirigido a A3. Una brecha de evidencia legítimamente encargada a A3 no convierte A2 en incompleta.
- Primero control determinístico. Después, **únicamente el juez semántico existente mediante la ruta nativa autorizada** revisa calidad, profundidad, contradicciones y cobertura material del candidato A2. No crear otro juez, invocador, motor, Router ni dispatcher.
- PASS externo acreditado: gate interno de A2 permite al coordinador invocar A3 **una sola vez** con el resultado y las instrucciones. Los recibos deben vincularse al mismo RUN, SHA exacto de candidato y evidencia de readback. El propio productor no puede autodeclarar PASS.
- FAIL reparable: el juez devuelve dimensión, elemento, criterio, esperado, observado, evidencia, causa y corrección. A2 regenera con historial íntegro y no repite defectos. Máximo **3 entregas A2** (original + 2 correcciones), sin consumir intentos por fallos de transporte.
- Tercer FAIL: **no A3**, terminar proceso y elaborar expediente terminal al perfil. Cierre de ticket solo mediante operación canónica con recibo; si no existe, `CLOSURE_NOT_VERIFIED`. Estado interno `A2_MAX_ATTEMPTS_EXCEEDED` NO es un estado de BD instalado.
- `output_validate`/60, `semantic_judge`/70 y `report_output`/80 del RUN gobernado mantienen su orden; el juez de la operación en 70 no prueba retroactivamente que A2 haya sido revisada antes de A3.
- El código de `guards/native_review_cycle_v1.py` y su esquema/23 pruebas **solo simulan lógica determinista**; no ejecutan modelo ni API de juez, no hacen persistencia y NO acreditan enlace nativo. Bloquear la invocación real mientras `PROGRAMMING_ANALYSIS_LF` no esté admitida y el juez nativo de A2 no esté verificado.
