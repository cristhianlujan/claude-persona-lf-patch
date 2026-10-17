# PE10 · IG M10.7/M10.9 — paquete ciego P0

**Coordinación:** Claude (Chrome solo si realmente está conectado). **Ejecución:** GPT Native en chats independientes. **Modalidad:** READ_ONLY, experimento no admitido como cambio de perfil.

**Corte informativo:** 2026-10-15 00:00 UTC. **Subject:** `PE10-IG-M107-M109-P0`.
El caso estudia si la optimización de Curator/Validator alcanza mejor rendimiento integral sin perder independencia, trazabilidad, seguridad ni vigencia del inventario de consumidores. Investigar causa sistémica, rutas omitidas, oportunidades de eliminación/reuso y falsificadores; no implementar.

## Fuentes P0 permitidas — idénticas para todos los productores
1. `public.lf_eventos.id=20161` (2026-10-04): inventario M10.9 de 38 callers SQL, cada uno con `caller`, `callees`, `definition_md5`, clase y vigencia histórica. **Es un snapshot, no certificación actual.**
2. EKB `IG-M107-SOAK-CRITERION-DRIFT-001`: heredar de M9.11 `SOAK_OBSERVATION_HISTORY_V2` los criterios as-of (≥2, cero falsos PASS y cero D4); no confundir últimas 13 observaciones CURRENT con historial.
3. EKB `IG-M107-CP2-READ-ROLE-CURRENTNESS-001`: la lectura CURRENT de CP2 carecía de permiso y el latest13 no representa la historia; usar recibos existentes, no elevar EXECUTE.
4. Método Reparador LF `SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6`, `SRCR_V0_7R1`: solo metodología idéntica en ambos brazos. La fuente actual del método no se usa como evidencia histórica del sistema.
5. Petición común: "Con las fuentes P0, diagnostica riesgo de falsa mejora/cierre prematuro de M10.7/M10.9. Busca límites de autoridad, consumidores, grafo, recurrencia, rendimiento y alternativas; propone reparación mínima, falsificadores y siguiente verificación segura. Separa hechos, hipótesis y desconocidos."

**Prohibido a productores:** informe retrospectivo del 17/10, EKB posteriores al corte, M10.7 B/C/D/G posteriores, respuestas de otros productores, dictámenes, documentos del juez y SQL actual disfrazado de evidencia P0. No pueden buscar el resultado conocido. Si no existe versión histórica de una fuente material, marcar `UNKNOWN_ASOF`; jamás sustituir con `main` contemporáneo. Un lote posterior `REPLAY_ASOF_NOT_ATTESTED` podría consultarse solo por autorización del protocolo, en ningún caso para puntuar descubrimiento ciego.

## Salida común A y B
Entregar un solo JSON con: `findings` (cada uno id, claim, evidence_refs, confidence, impact, new_vs_input), `causal_model`, `candidate_repairs`, `chosen_repair`, `rejected_alternatives`, `omissions_searched`, `negative_falsifiers`, `constraints_preserved`, `unresolved`, `next_safe_step`.
No READY/DONE/PASS. Toda afirmación material ligada a fuente o identificada como hipótesis falsable.

## Invariantes de ejecución
- El coordinador no ejecuta por sustitución los razonamientos de los GPT productores.
- Brazo A: un chat GPT dedicado al Reparador, método dinámico + estadística.
- Brazo B: cinco chats GPT de descubrimiento autónomo (arquitectura; performance/estadística; autoridad; omisiones; innovación), un chat GPT Reparador integrador y un chat GPT crítico adversarial distinto. Integrador recibe solo especialistas B; crítico recibe solo propuesta B; el integrador revisa tras crítica, en el mismo chat.
- Un chat GPT separado actúa como juez **solo después** de congelar A y B, sin revelar etiquetas. Juez ve sus instrucciones reservadas y resultados anonimizados; productores nunca ven el juez.
- Todo chat debe tener identidad/URL cuando disponible, RAW completo, SHA256 del input/fuentes/salida y tiempo real. Tokens solo si medidos; desconocidos = NO_MEDIDO.
- Claude usa Chrome/Claude-in-Chrome para ChatGPT únicamente si está realmente disponible y autorizado; no usar API, Llama, sesión impostora ni resultados generados por el coordinador bajo identidad GPT.
- Eventos de preparación no constituyen ejecución, atestación de proveedor ni revisión independiente. Cada etapa completada requiere `RAW_CAPTURE_BATCH_PREPARED` y/o recibo de etapa **nuevo**, creado mediante ruta canónica Operation/Migration→Train y readback. Registrar hallazgos nuevos en EKB vía autoridad, sin alterar filas anteriores.
- No tocar producción, Supabase mediante SQL directo, checkpoints de IG, runtime, activación de PE10 ni merges fuera de Train.
