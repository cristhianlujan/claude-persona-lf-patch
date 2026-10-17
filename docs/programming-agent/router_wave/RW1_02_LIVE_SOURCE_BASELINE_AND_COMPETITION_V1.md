# RW1-02 — Línea base viva de arquitectura y discriminadores (pretrabajo sin decisión)

**Fecha de lectura:** 2026-10-17. **Origen:** Supabase `read_only` + EKB + catálogo C1/C2 y A16Q_C1 en GitHub.  
**Plan:** `LF_ROUTER_ARCHITECTURE_WAVE_V1`, RW1-02. **Estado:** investigación preparatoria; RW1-01_C3 PENDING y RW1-02_C1/C2/C3 PENDING. No muta Router, no habilita runtime, no da permiso de efecto. El juez ciego RW1-01_C3 **NO** debe recibir este documento antes de congelar su primer dictamen.

## A. Mediciones reproducibles, no resultados de arquitectura candidata

| Indicador | Resultado observado | Interpretación limitada |
| --- | ---: | --- |
| `public.lf_router_resolve_v1(text,text,text,text,text)` | **39.602** caracteres de definición; MD5 fuente `d45f5bddb693791b6459bbe3acfd4ed3` | Tamaño de código, no complejidad temporal medida ni fallo causal por sí solo |
| Invocaciones nominales directas a helpers `lf_router_*` identificadas en su definición | 3: `lf_router_declared_artifact_candidates_v1`, `lf_router_input_governance_resolve_v1`, `lf_router_intent_handoff_v1` | No es grafo completo ni cuenta llamadas indirectas/dinámicas |
| `lf_router_action_registry` | **35 ACTIVE**: 16 tipos, 25 acciones, 25 operaciones distintas y 26 filas `write_allowed`; **6 CANDIDATO_READ_ONLY** | `write_allowed` es configuración declarada; no significa autorización efectiva del Router |
| `lf_activos` no archivados | **22** tipos `tipo_activo` distintos | No comparar 22 vs 16 como exactamente seis capacidades sin ruta: los dominios/denominadores no son equivalentes |
| `lf_operation_step_contracts` | **198 ACTIVE**, **264 ACTIVE_ENFORCEMENT**, **27 ACTIVO** (más otros estados) | Son conteos de filas de contrato, no pasos invocados ni costo real de cada petición |
| Cuatro solicitudes de prueba con dos invocaciones del mismo SELECT por literal | **4/4 respuestas idénticas** (MD5 del JSON), **4/4 status BLOCKED** | Reproducibilidad *local* de estas cuatro, no determinismo universal bajo concurrencia ni prueba de continuidad |

### Lectura semántica de las cuatro salidas reales

| Caso | Código de bloqueo observado | Evidencia transportada | Falta principal |
| --- | --- | --- | --- |
| Investigación B2B sin implementar | `BLOCK_ASSET_TYPE_UNRESOLVED` | No apareció `semantic_handoff` | El sistema no acreditó responsable para continuar un análisis read-only |
| «Actualiza ACT-0053 y conserva intacto ACT-0052» | `BLOCK_MULTIPLE_EXACT_TARGETS_NEED_SCOPE` | Handoff con literal/hash y dos candidatos, pero `positive_target_refs=[]`, `excluded_target_refs=[]`, `semantic_consumer_receipt=null` | No diferencia inclusiones y exclusiones ni acredita consumo posterior |
| «Necesito una regla y una skill nuevas» | `BLOCK_ASSET_NOT_FOUND` | `asset_type=SKILL`, `ASSET_INSPECTION`, sin handoff | Pérdida de la intención compuesta antes de un responsable competente |
| «Simula crear skill ... sin crearla» | `BLOCK_SCOPE_SEMANTICS_UNATTESTED` | Handoff literal/hash, `scope_binding_state=UNATTESTED`, sin consumer receipt; `action_code=SKILL_CREATE` | El modo simulación no queda representado como derivación competente con prohibición de efecto acreditada |

**Conclusión estrecha:** las denegaciones de escritura son conservadoras, pero *una denegación correcta no acredita continuidad de trabajo permitido*. Los cuatro pedidos tampoco demuestran que la ruta sería errónea con un consumidor material capaz y autorizado; eso queda abierto a prueba E2E posterior. Estas observaciones **no** se convierten en nuevos oráculos para entrenar/ajustar soluciones: los 30 oráculos RW1-01_C2 mantienen la fuente normativa.

## B. Consultas de solo lectura para reproducir los datos de fuente

```sql
SELECT length(pg_get_functiondef(
 'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)) source_chars,
 md5(pg_get_functiondef(
 'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)) source_md5;

SELECT status,count(*) rows,
 count(DISTINCT asset_type) types,
 count(DISTINCT action_code) actions,
 count(DISTINCT operation_code) FILTER (WHERE operation_code IS NOT NULL) operations,
 count(*) FILTER (WHERE write_allowed) declared_write_routes
FROM public.lf_router_action_registry GROUP BY status ORDER BY status;

SELECT count(DISTINCT tipo_activo) nonarchived_asset_types
FROM public.lf_activos WHERE archived_at IS NULL;

SELECT status,count(*) rows FROM public.lf_operation_step_contracts
GROUP BY status ORDER BY status;
```

La comparación de respuestas se hizo en un mismo SELECT con `public.lf_router_resolve_v1(literal)` dos veces por caso (cuatro literales distintos), sin escrituras; se contrastaron `status`, `blocking_code`, `semantic_handoff` y `md5(jsonb::text)`. Esta consulta acredita el *estado observado*, no autoriza cambios a un ABI de 5 argumentos.

## C. Evaluación causal de cuatro rutas (sin elegir ganadora)

| Alternativa competidora | Interfaz candidata del primer nivel | Prueba indispensable que podría refutarla | Coste/riesgo que debe medirse |
| --- | --- | --- | --- |
| **A — Semántica central en ACT-0001** | Intención, acciones, exclusiones y multicomposición resueltas por núcleo | Tipo futuro no previsto y negación contextual: si hay que añadir una regla al núcleo por cada caso, incumple extensibilidad | Superficie y coste de Router crecen; acoplamiento de autorización/hidración; medir caminos, no contar líneas solamente |
| **B — Entrada mínima + catálogo** | Conserva literal/hash y deriva al competente según capacidades registradas; semántica en consumidor | Solicitud combinada «regla y skill»: si deriva solo a Skill sin un responsable capaz de ambos, pierde objetivo *antes* del consumidor | Dependencia en amplitud del registro, errores tempranos de rol, vuelta circular a descubrimiento |
| **C — Sobre mínimo de intención y responsable** | Conserva literal/hash, modalidad de no-efecto y sujetos/condiciones como hipótesis, con derivación por catálogo | Pedidos inéditos: si necesita regex/parches por término o considera una hipótesis como permiso, falla | Sobrecarga del intérprete y nueva semántica encubierta; medir número real de reglas y consultas |
| **D — Composición de capacidades por un responsable** | Derivación inicial a un actor compuesto **registrado** que distribuye tareas con recibos por objetivo | Si requiere crear un quinto ejecutor de ingeniería, un ciclo de orquestadores o ruta extra para solicitudes simples, no compensa el costo | Latencia, número de handoffs y loops; no inventar «planner» autónomo sin demostrar capacidad existente |

**Invariantes comunes que ningún diseño puede renunciar:** Router First real, pedido literal/hash íntegro, negaciones conservadas hasta el punto de efecto, sujeto ≠ ejecutor ≠ adapter, registro de capacidades vigente, no crear ejecutores desconocidos, rechazo de `READY` basado en hint, prewrite gate real sin publicación/Train alterados, avance read-only independiente si una acción de escritura carece de permiso, determinismo de decisiones de autoridad sobre snapshot igual. La capa de ejecución del Agente de Programación mantiene solo capacidades READ/WRITE_DB/WRITE_GIT/RUN_TEST.

## D. Comparación que faltaría para decidir, sin preparar un resultado falso

Para **las cuatro arquitecturas con el mismo corpus congelado** y sin atribuirles un runtime aún inexistente:

1. Evaluar por separado **elección de responsable** y **autorización de efecto**. La negación correcta por el segundo no excusa una derivación inútil por el primero.
2. Exigir `handoff_literal`, `request_sha256`, modo y objetivos positivos/negativos, identidad de consumidor y recibo de recepción, solo donde exista realmente un consumidor. Nunca convertir `fixture://` en autoridad.
3. Comparar en R10/R11/R13 objetivos múltiples: si se devuelve un solo responsable, demostrar su **competencia para todos** los objetivos; no inferirla de «acknowledged_goals».
4. Contrastar en R04/R07/R08 negaciones preservadas hasta prewrite; cualquier efecto sobre objetivo excluido implica FAIL de seguridad, pero una ruta read-only de investigación puede ser válida.
5. Probar tipo futuro sin registro y tipo futuro con nueva **capacidad registrada** mediante cambios en fixture/catálogo, no cambios de regex específicos: medir esfuerzo de incorporación.
6. Para N11 medir **dos ejecuciones separadas** de cada candidato con mismo literal/snapshot, distinguiendo consistencia local de datos, decisión de autoridad y runtime concurrency. Los 4/4 actuales son un canario limitado de Router vigente, no una comparación entre propuestas.
7. Para N12 documentar consultas/lecturas, decisiones redundantes, número de actores, transformaciones de contexto y tiempo/coste real por request; no fabricar p90 o afirmar superioridad con n=4.
8. Holdouts nuevos y juez independiente deben permanecer **ocultos al productor** hasta congelar las arquitecturas candidatas y sus outputs; no adelantarle la crítica del juez RW1-01_C3.

**Escenarios relevantes todavía sin dato verificable:** un consumidor realmente registrado que acepte los handoffs y emita recibo del mismo hash; conservación de `ACT-0052` como excluido en una operación real; permisología actual del perfil; desempeño completo. Se abordarán en RW1-02_C2 (prototipos comparables) y RW1-05/06 (operación real), respectivamente. No imponer esos E2E como condición para recibir el dictamen de necesidades de C3.

## E. Causa transversal y decisión pendiente

La raíz no se reduce a «hacer que BLOCKED diga DERIVE». Hay **dos fronteras incompletas**: asignación de responsabilidad para trabajo permitido y verificación de alcance/autorización para efectos. Una reparación correcta debe trazar pedido intacto y responsable real *antes* de ese efecto, usando operaciones existentes y sin crear un motor paralelo. El costo real de cada alternativa sigue sin medirse, y **ninguna arquitectura se selecciona aquí**.

**Gobernanza:** este artefacto es PREWORK revisable; `RW1-01_C3` sigue PENDING y ninguna unidad posterior se declara iniciada. Si los hechos SQL derivan de otras versiones, repetir estas consultas de solo lectura antes de usar la línea base en una decisión.
