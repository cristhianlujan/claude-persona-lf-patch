# LF — Profile Updater v0.2: ampliación atómica de operabilidad (27-oct-2026)

**Autoridad:** `PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1`, `PE10` work item 1103. **Alcance:** registro de plan solamente, sin ejecución, despliegue, cutover, escritura de perfiles ni revocación de cierres.

## Readback previo

- 19 unidades, 84 checkpoints: 79 DONE, 2 PENDING (PE10_C6 / PE10_C7), 3 NOT_APPLICABLE.
- Reutilizar PE0/PE1/PE1B/PE2/PE2B/PE3/PE3B/PE4/PE5/PE5A/PE6/PE7/PE7B/PE8/PE10/PE10P/PE10E/PE10_E2. Ningún checkpoint DONE se reabre.
- Operación ACTUALIZACION_PERFIL_LF v0.1 PRODUCCION_CONTROLADA, 15 pasos activos, 2 candidatos 35/37. No crear engine alterno, cola periódica ni bypass del Router o del Merge Train.
- Brecha observada: `run-creacion-perfil-lf` desplegado v35 difiere del `main` en `index.ts`, no contiene `lf_router_governed_caller_route_v1`, y la lista desplegada no incluye `required_profile_steps.ts`. Requiere diagnóstico exacto y despliegue por ruta autorizada, no declarar corrección por PR.
- El reparador SRCR debe ser el dueño de la invocación especializada; el Router solo resuelve la entrada y la autorización inicial.

## Criterios comunes de cada checkpoint

Cada checkpoint exige: (a) entrada/fuente y versionado exactos; (b) prueba positiva real; (c) un falsificador/prueba negativa; (d) readback canónico ligado a `execution_id`, sujeto, SHA, proveedor; (e) próximo paso ante bloqueo. La metadata queda deliberadamente `BLOCK_PENDING_IMPLEMENTATION_AND_INDEPENDENT_RECEIPT`, sin declarar validators inventados ni PASS.

## Dependencias

- **PE10A_CONTRACTS — Auditoría atómica de contratos, firmas y compatibilidad.** Reutiliza: PE0, PE5, PE5A, PE6; PE10_C5. Depende de: base PE10 existente.
- **PE10A_JUDGES — Auditoría de jueces, bindings y adjudicación independiente.** Reutiliza: PE1B, PE6, PE10_C3. Depende de: PE10A_CONTRACTS.
- **PE10A_PIPELINE — Pipeline secuencial dinámico y recuperación durable.** Reutiliza: PE5, PE6, PE10_C6; ACT-0001. Depende de: PE10A_CONTRACTS, PE10A_JUDGES.
- **PE10A_METHODS — Selección dinámica y métodos de investigación interna y externa.** Reutiliza: PE1B, PE2, PE2B, PE3, PE3B, PE7B, PE10_E2. Depende de: PE10A_PIPELINE.
- **PE10A_SUPABASE — Integridad de Supabase, registro y ensayo transaccional.** Reutiliza: PE6, PE10_C4, PE10_C5, PE10_C6. Depende de: PE10A_CONTRACTS, PE10A_JUDGES, PE10A_PIPELINE.
- **PE10A_GITHUB — Paridad GitHub–Supabase y despliegue gobernado.** Reutiliza: PE5A, PE6, PE10_C5, PE10_C6; PR #3133. Depende de: PE10A_SUPABASE.
- **PE10A_SRCR — Invocación gobernada desde el Perfil Reparador.** Reutiliza: PE5, PE10P; Router ACT-0001, SRCR. Depende de: PE10A_PIPELINE, PE10A_METHODS, PE10A_GITHUB.
- **PE10A_READY — Aptitud operacional, reparación completa y salida útil.** Reutiliza: PE0, PE1B, PE4, PE5A, PE10E, PE10_C6, PE10_C7. Depende de: PE10A_SRCR, PE10A_GITHUB, PE10A_METHODS, PE10A_SUPABASE.

El trabajo matriz PE10 requiere además `PE10A_READY` antes del cierre integral. Los contratos previos PE10_C6/C7 no se modifican en este registro; habrá que alinear el gate de cierre a dependencias de work items antes de intentar cualquier activación.

## Checkpoints atómicos

### PE10A_CONTRACTS — Auditoría atómica de contratos, firmas y compatibilidad

**PE10A_CT01 — Inventariar firmas y propietarios canónicos de todas las superficies tocadas**
- **PASS verificable:** Mapa exact-head de RPC SQL, Edge, Python, contratos, schemas, políticas y consumidores con firma entrada/salida.
- **Falsificador negativo:** Una firma obsoleta o sin propietario falla y señala consumidor.
- **Trabajo reutilizado:** PE0_C1, PE5_C1.

**PE10A_CT02 — Comparar firma declarada frente a invocaciones reales y tipos de retorno**
- **PASS verificable:** Paridad de argumentos, tipos, errores y contratos en todos los llamadores involucrados.
- **Falsificador negativo:** Firma o enum incompatible es rechazado antes de ejecutar.
- **Trabajo reutilizado:** PE6_C2, PE10P_C1.

**PE10A_CT03 — Congelar contrato por ejecución y ruta de decisión**
- **PASS verificable:** Snapshot v0.2 con UPDATE de 17, NO_CHANGE de 10 y NEEDS_MORE_EVIDENCE no terminal, ligado a ejecución.
- **Falsificador negativo:** Rechazar ruta inferida por el modelo o snapshot mutable/obsoleto.
- **Trabajo reutilizado:** PE5_C1, PE6_C2, PE10_C6.

**PE10A_CT04 — Homologar esquemas de salida y validadores realmente vinculados**
- **PASS verificable:** Misma versión/sha de schema y validador perfil-local en generación, actualización y consumo.
- **Falsificador negativo:** Ejemplo sin campo required o enum ilegal falla con evidencia.
- **Trabajo reutilizado:** PE5A_C2, PE10P_C2.

**PE10A_CT05 — Verificar alcance y compatibilidad de los cambios en dependencias**
- **PASS verificable:** Cambios en pasos, firmas, políticas, juicios, contratos y fuentes son declarados, delimitados, con consumidores identificados.
- **Falsificador negativo:** Cambio que rompa v0.1 o afecte perfil ajeno bloquea.
- **Trabajo reutilizado:** PE6_C4, PE5A_C4.

**PE10A_CT06 — Probar lectura actual vs artefactos/declaraciones antiguas**
- **PASS verificable:** El consumidor resuelve autoridad actual y prohíbe rutas y firmas deprecated en el mismo run.
- **Falsificador negativo:** Ref histórica sin admisión actual no produce PASS.
- **Trabajo reutilizado:** PE0_C2, PE10_C5.

### PE10A_JUDGES — Auditoría de jueces, bindings y adjudicación independiente

**PE10A_JD01 — Inventariar jueces y bindings por cada paso aplicable**
- **PASS verificable:** Mapa de step_id a judge_code, versiones, estados, entrada, salida, evidencias y política active/candidate.
- **Falsificador negativo:** Paso sin juez autorizado o juez de versión distinta bloquea.
- **Trabajo reutilizado:** PE6_C2, PE10_C3.

**PE10A_JD02 — Probar mini-juez determinista antes de semántico**
- **PASS verificable:** Cada resultado y transición se computa sobre evidencia estructural y códigos tipados.
- **Falsificador negativo:** PASS declarado por caller sin verificación independiente es rechazado.
- **Trabajo reutilizado:** PE1_C3, PE10P_C2.

**PE10A_JD03 — Probar juez semántico con salida funcional material**
- **PASS verificable:** Calificación reproduce caso real con rubric y RAW vinculados a revisión exacta.
- **Falsificador negativo:** Juez no califica documentos como ejecución real ni ignora ambigüedad.
- **Trabajo reutilizado:** PE10E_C2, PE10_C2B.

**PE10A_JD04 — Acreditar juez independiente sin autocertificación**
- **PASS verificable:** Revisor, proveedor, caso, sujeto, SHA y resultado verificables sin reutilizar autoría.
- **Falsificador negativo:** Rechaza recibo inventado, caducado o del mismo autor como independiente.
- **Trabajo reutilizado:** PE10_C3, PE10E_C4.

**PE10A_JD05 — Garantizar bloqueo, corrección y nueva revisión sin saltos**
- **PASS verificable:** Caso positivo y negativo por resultado de juez; reintento conserva evidencia de fallo.
- **Falsificador negativo:** Un BLOCKED o RETURN no deriva a close ni muta sin nueva verificación.
- **Trabajo reutilizado:** PE6_C3, PE10_C6.

### PE10A_PIPELINE — Pipeline secuencial dinámico y recuperación durable

**PE10A_PL01 — Leer ruta inicial autorizada, sin resolver Router por segunda vez**
- **PASS verificable:** Handoff mantiene negocio, canal, perfil reparador, sujeto, autoridad y versión del pedido.
- **Falsificador negativo:** Rechaza reruteo directo del Updater como entrada alternativa no autorizada.
- **Trabajo reutilizado:** PE5_C1, PE10P_C3.

**PE10A_PL02 — Calcular secuencia desde política vigente congelada**
- **PASS verificable:** Muestra next_step desde autoridad, incluyendo bifurcación UPDATE/NO_CHANGE/NEEDS_MORE_EVIDENCE.
- **Falsificador negativo:** Rechaza índice hardcodeado, paso omitido o flujo incompatible.
- **Trabajo reutilizado:** PE5_C1, PE10_C6.

**PE10A_PL03 — Impedir ejecución fuera de orden, duplicados y replay**
- **PASS verificable:** No se registra paso n+1 sin PASS limpio n; reintento idempotente y recibos exactos.
- **Falsificador negativo:** Intentos de saltar a stage2, aplicar deprecated o duplicar write fallan.
- **Trabajo reutilizado:** PE6_C3, PE10_C6.

**PE10A_PL04 — Conservar snapshot y cursor durable en cada transición**
- **PASS verificable:** Readback de execution_id, policy SHA, decisión, checkpoint y siguiente acción después de reanudar.
- **Falsificador negativo:** Cursor inconsistente u origen distinto bloquean en vez de avanzar.
- **Trabajo reutilizado:** PE6_C1, PE10_C4.

**PE10A_PL05 — Componer dependencias y transportes existentes sin otra capa**
- **PASS verificable:** El host usa RPC/runner/Train existentes de acuerdo a capacidad, sin cola polling ni adapter nuevo.
- **Falsificador negativo:** Bifurcación hacia función privada o transporte no autorizado falla.
- **Trabajo reutilizado:** PE10P_C3, PE10_C5.

**PE10A_PL06 — Recuperar interrupción, lease expirado y bloqueo corregible**
- **PASS verificable:** Reanudación on-demand conserva idempotencia y ofrece reparación acotada o escalamiento explicable.
- **Falsificador negativo:** Ninguna ejecución queda eternamente IN_PROGRESS/BLOCKED sin próxima acción y causa.
- **Trabajo reutilizado:** PE6_C4, PE10_C4.

### PE10A_METHODS — Selección dinámica y métodos de investigación interna y externa

**PE10A_ME01 — Leer catálogo vigente y autoridad de calificación de métodos**
- **PASS verificable:** Versión, origen, calificación y permisos del catálogo por run; métodos candidate != runtime qualified.
- **Falsificador negativo:** Rechaza selección de método experimental/no cualificado aunque esté catalogado.
- **Trabajo reutilizado:** PE2B_C1, PE2B_C2.

**PE10A_ME02 — Integrar selector dinámico en Updater con precondición/coste**
- **PASS verificable:** Selecciona métodos elegibles por problema, presupuesto, riesgo y evidencias reales.
- **Falsificador negativo:** Rechaza selección forzada, costo excedido o precondición UNKNOWN.
- **Trabajo reutilizado:** PE3B_C1, PE3B_C2.

**PE10A_ME03 — Ejecutar investigación interna selectiva y trazable**
- **PASS verificable:** Consulta EKB, Supabase, GitHub y dependencias hasta profundidad proporcional a hallazgos.
- **Falsificador negativo:** Evidencia histórica, búsqueda textual o referencia sin ejecución no puede ser prueba de efecto.
- **Trabajo reutilizado:** PE1_C3, PE7_C1.

**PE10A_ME04 — Ejecutar investigación externa bajo fuentes y permisos verificables**
- **PASS verificable:** Fuente externa real con consulta, corte temporal, URL/identificador, fecha y lectura material; transporte autorizado.
- **Falsificador negativo:** Fuente inventada, anacrónica, no leída o fuera de política no entra a conclusión.
- **Trabajo reutilizado:** PE2B_C4, PE10_E2_C4.

**PE10A_ME05 — Contrastar hallazgos internos/externos sin perder causalidad**
- **PASS verificable:** Distinguir declaración, función, consumidor, lectura, caso y observación; controversias quedan abiertas.
- **Falsificador negativo:** La coincidencia léxica, ausencia de resultado o dato ambiguo no se convierte en certeza.
- **Trabajo reutilizado:** PE10_E2_C1, PE10_E2_C2.

**PE10A_ME06 — Ejecutar métodos seleccionados mediante host gobernado**
- **PASS verificable:** Método cualificado invocado realmente, con resultado y recibo sujeto+versión+ejecución; métodos vacíos justificados.
- **Falsificador negativo:** No contabilizar método seleccionado como ejecutado ni fabricar evidencia native.
- **Trabajo reutilizado:** PE3_C4, PE10P_C3.

**PE10A_ME07 — Replanificar o detener con progreso verificable y presupuesto**
- **PASS verificable:** Ante bloqueo/meseta cambia estrategia una vez acotada y explica NEEDS_MORE_EVIDENCE / NO_CHANGE.
- **Falsificador negativo:** No hay bucle indefinido, repetición de benchmarks ni autopromoción de aprendizaje.
- **Trabajo reutilizado:** PE3B_C3, PE3B_C4.

### PE10A_SUPABASE — Integridad de Supabase, registro y ensayo transaccional

**PE10A_SB01 — Conciliar catálogo de operación, pasos, política y jueces**
- **PASS verificable:** Conteos y versiones exactos v0.1/v0.2; bloqueos hasta cutover; binding y lifecycle coherentes.
- **Falsificador negativo:** Ninguna doble ACTIVE, juez ausente o contrato CANDIDATE se interpreta operativo.
- **Trabajo reutilizado:** PE6_C2, PE10_C7.

**PE10A_SB02 — Inspeccionar RPC, permisos, lector/recorder y event ledger**
- **PASS verificable:** Signaturas de pg_proc, caller RLS/grants, eventos con sujeto/sha y recorder exactos.
- **Falsificador negativo:** Acceso privado indebido o recibo solo textual no supera el gate.
- **Trabajo reutilizado:** PE6_C3, PE10_C3.

**PE10A_SB03 — Materializar SQL de cambios y ensayar positivo/negativo/rollback**
- **PASS verificable:** Migración versionada, prueba real DB de aceptación/rechazo y ROLLBACK cero residuos con eventos verificables.
- **Falsificador negativo:** No se aplica SQL vía consola directa ni se afirma PASS desde test de fuente.
- **Trabajo reutilizado:** PE10_C6.

**PE10A_SB04 — Auditar estado actual de ejecuciones y resolver obsoletos**
- **PASS verificable:** IN_PROGRESS/BLOCKED con paso real/lease y próxima acción, sin cancelar automáticamente ejecuciones ajenas.
- **Falsificador negativo:** Sin paso ni lease válido no puede declararse completado ni ocultarse.
- **Trabajo reutilizado:** PE10_C4, PE6_C4.

**PE10A_SB05 — Conservar causalidad EKB/Supabase para nuevas reparaciones**
- **PASS verificable:** EKB preflight del run, corrección, prevención y prueba ejecutada unidos a evidencia inmutable.
- **Falsificador negativo:** Hallazgos sin prueba o repetidos no se convierten en reglas ejecutables.
- **Trabajo reutilizado:** PE7B_C1, PE10_C5.

### PE10A_GITHUB — Paridad GitHub–Supabase y despliegue gobernado

**PE10A_GH01 — Congelar GitHub main HEAD, archivos y transitivos de import**
- **PASS verificable:** SHA exacto y manifiesto reproducible de fuentes perfil, scripts, Edge e imports.
- **Falsificador negativo:** Un archivo requerido no incluido o ref mutable bloquea.
- **Trabajo reutilizado:** PE5A_C4, PE10_C5.

**PE10A_GH02 — Comparar Edge deployed frente a fuentes y archivos GitHub**
- **PASS verificable:** Hash bytes, versión, inventario de archivos y semántica de llamadas coinciden después de despliegue.
- **Falsificador negativo:** La v35 desfasada o archivo required_profile_steps ausente da DRIFT, no APTO.
- **Trabajo reutilizado:** PE10_C6.

**PE10A_GH03 — Validar GitHub PR, PASE y Merge Train sin bypass**
- **PASS verificable:** Write guard preaprobado, CI exact-head verde, train autorizado, recibo de merge.
- **Falsificador negativo:** Direct merge, PR sin PASE o aprobación de SHA anterior no habilitan.
- **Trabajo reutilizado:** PE10P_C4, PE10_C5.

**PE10A_GH04 — Conciliar migraciones GitHub SQL con Supabase aplicadas**
- **PASS verificable:** Cada SQL materializado con versión/cambio exacto y readback post-Train del objeto DB.
- **Falsificador negativo:** Migration aplicada sin archivo, archivo no aplicado, o versión distinta bloquea.
- **Trabajo reutilizado:** PE6_C3, PE10_C6.

**PE10A_GH05 — Ejecutar paridad post-despliegue para cada consumidor afectado**
- **PASS verificable:** Lecturas vivas de RPC, Edge, caller, profile, imports y contratos coinciden en una revisión.
- **Falsificador negativo:** Mismo nombre de endpoint o PR mergeado sin bytes coincidentes no es PASS.
- **Trabajo reutilizado:** PE10_C6.

**PE10A_GH06 — Recuperar drift y rollback a última versión conocida buena**
- **PASS verificable:** Plan de despliegue/rollback gobernado, readback sin residuos y propagación del incidente a EKB.
- **Falsificador negativo:** No activa parcialmente ni cierra mientras origen y runtime difieran.
- **Trabajo reutilizado:** PE5_C4, PE6_C4.

### PE10A_SRCR — Invocación gobernada desde el Perfil Reparador

**PE10A_SR01 — Resolver entrada Router→Perfil Reparador preservando la ruta**
- **PASS verificable:** Recibo de canal/negocio/perfil, identidad y alcance verificables; reparador elegido.
- **Falsificador negativo:** No se inicia Updater desde un bypass o reruteo fabricado.
- **Trabajo reutilizado:** PE5_C1, ACT-0001.

**PE10A_SR02 — Diagnosticar causa y decidir si procede actualizar perfil**
- **PASS verificable:** Evidencia causal+EKB clasifica cambio de perfil vs operación/DB/ruta ajena.
- **Falsificador negativo:** No invoca Updater por problema externo no atribuible al perfil.
- **Trabajo reutilizado:** PE1_C4, PE7B_C3.

**PE10A_SR03 — Crear handoff SRCR→Updater ligado a autoridad y ejecución**
- **PASS verificable:** Exact target_code/path SHA, scope, caller autorizado, policy snapshot y misma correlación de incidente.
- **Falsificador negativo:** No reinicia Router como si fuese nueva intención ni eleva permisos.
- **Trabajo reutilizado:** PE10P_C3, PE10_C5.

**PE10A_SR04 — Ejecutar Updater por transporte canónico y devolver resultado**
- **PASS verificable:** Recibo auténtico de entrada/salida por ejecución, paso y sujeto, retornado a SRCR.
- **Falsificador negativo:** Una ejecución sin recibo ni próxima acción vuelve como bloqueo accionable.
- **Trabajo reutilizado:** PE10P_C4, PE10_C6.

**PE10A_SR05 — Probar rechazo de cross-business y reparación no autorizada**
- **PASS verificable:** LF/SALY, escritura GitHub, cambios SQL y efectos respetan permisos y frontera.
- **Falsificador negativo:** Una ruta de negocio/acción equivocada falla sin efectos colaterales.
- **Trabajo reutilizado:** PE5_C4, PE6_C4.

### PE10A_READY — Aptitud operacional, reparación completa y salida útil

**PE10A_OP01 — Medir línea base operacional de perfil real antes del cambio**
- **PASS verificable:** 13 dimensiones S26 más contratos, firmas, validator y ejecución funcional del perfil de origen.
- **Falsificador negativo:** No se sustituye ejecución real por completitud documental.
- **Trabajo reutilizado:** PE0_C1, PE4_C3.

**PE10A_OP02 — Materializar y aplicar reparación de todas las superficies impactadas**
- **PASS verificable:** Diff mínimo con dueño de cada cambio: SKILL, procedimientos, firmas, contratos, judges, schemas, imports y bindings.
- **Falsificador negativo:** Falta de consumidor o cambio no declarado impide admisión.
- **Trabajo reutilizado:** PE5A_C3, PE5A_C4.

**PE10A_OP03 — Validar artefactos y salidas positivas/negativas ejecutadas**
- **PASS verificable:** S26 post 13/13 + validador perfil-local con ejemplo positivo y contraejemplo real.
- **Falsificador negativo:** Un schema mismatch, error de transporte o salida falsa rechaza.
- **Trabajo reutilizado:** PE1B_C3, PE10P_C2.

**PE10A_OP04 — Ejecutar tarea real del perfil reparado bajo host autorizado**
- **PASS verificable:** E2E provider-bound para tarea representativa y holdout, sin saltos y sin regresión crítica.
- **Falsificador negativo:** Una simulación, texto autocalificado o ejecución parcial no aprueba.
- **Trabajo reutilizado:** PE10E_C1, PE10E_C4.

**PE10A_OP05 — Probar NO_CHANGE y NEEDS_MORE_EVIDENCE sin callejón sin salida**
- **PASS verificable:** NO_CHANGE verificado sin write, evidencia faltante define adquisición/reanudación y punto exacto.
- **Falsificador negativo:** Ningún terminal falso, write imprevisto o interrupción sin próxima acción.
- **Trabajo reutilizado:** PE3B_C3, PE10_C6.

**PE10A_OP06 — Probar recuperación y autorreparación acotada conservando última versión útil**
- **PASS verificable:** Falla detectada, máximo de intentos, rollback, idempotencia y readback sin residuos.
- **Falsificador negativo:** Sin loop, avance ficticio o perfil parcialmente aplicado.
- **Trabajo reutilizado:** PE5_C2, PE6_C4.

**PE10A_OP07 — Verificar paridad final de GitHub, Supabase y consumidores**
- **PASS verificable:** Hashes actuales, funciones desplegadas, recibos PASE/Train y autoridad coincidentes.
- **Falsificador negativo:** Drift vigente prohíbe APTO aunque el PR esté fusionado.
- **Trabajo reutilizado:** PE10_C6, PE10_C7.

**PE10A_OP08 — Emitir aptitud final con recibo independiente y handback SRCR**
- **PASS verificable:** APTO únicamente tras todos los gates; si no, diagnóstico causal y siguiente paso concreto.
- **Falsificador negativo:** No proclamar v0.2 activa ni cerrar sin conformidad independiente.
- **Trabajo reutilizado:** PE10_C3, PE10_C7.

## Corte y seguridad

1. Esta migración **solo registra checkpoints**: no los ejecuta ni declara probados. El plan queda con 27 unidades y 132 checkpoints (79 DONE, 50 PENDING, 3 NOT_APPLICABLE).
2. La incorporación debe pasar por `ACTUALIZACION_DB_LF` y `LF Migration Merge Train`, CI/PASE y readback real en Supabase.
3. No convertir `PE10_C6` reversible/sintético en E2E provider-bound, ni cerrar `PE10_C7` sin autoridad verificada.
4. No adjudicar `APTO` hasta retorno del perfil reparador, funcionalidad real, consistencia de jueces/contratos y paridad Supabase↔GitHub.
