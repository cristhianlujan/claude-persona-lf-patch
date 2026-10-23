# Flujo del Router ACT-0001 (LF) — V1

Estado: **contrato de diseño**. Lo construido y probado se marca así; lo demás es objetivo y no se declara operativo.
Ámbito: LF ahora. Un solo Router para LF, Saly y otros; la dimensión de sistema se agrega después.
Todo el flujo es de solo lectura; ningún resultado autoriza efectos (`downstream_execution_allowed=false`).

## Un Router, dos etapas

**Etapa 1 — Entender** (la hace el modelo nativo GPT/Claude; no gasta API de pago). Entra la frase, antes de buscar nada:
1. ¿Es una operación o una pregunta que se responde sin inventario? ("¿qué hora es en Lima?" → se responde directo y termina.)
2. Corregir lo mal dicho ("history" cerca de "usuario" = "historias"; "spec driving" = "spec-driven").
3. Sistema (LF por ahora), acción y sujeto extraídos de la frase.
4. Reformular el sujeto con las palabras del inventario (español e inglés). Esas mismas formas, que el modelo ya produjo, se usan también en el nivel 1 y en la primera pasada del nivel 2; no se hace expansión adicional de sinónimos (medido en la prueba de punta a punta: en el nivel 2 la forma en inglés encontró lo que la forma en español no).
5. Si la etapa 1 trae `capability_hint`, el despacho va primero; la búsqueda nivel 1 es para localizar activos, no capacidades (medido: "estado en curso" en el nivel 1 trae una regla B2B sin relación, mientras el despacho con la pista responde PERMITIDO).

**Etapa 2 — Encaminar** (DB):
- **Nivel 1 (construido, probado):** `lf_router_search_v1` sobre inventario de gobierno y reglas del producto. Entrega pistas, no decisiones.
- **Despacho (construido, probado):** `lf_router_dispatch_v1` sobre el catálogo de capacidades, con respuesta uniforme PERMITIDO / DENEGADO / FALTA_INFO.

## Qué pasa según cuántos resultados da el nivel 1

| Resultado | Qué hace |
|---|---|
| Un candidato claro | Lo usa y despacha. |
| Varios | Quien decide (el modelo) elige, o pide más detalle leyendo los candidatos (máximo 3 sondeos por duda; el 4.º requiere autorización del propietario; un sondeo discriminante de solo lectura; parar si no aporta). Si sigue la duda, **una** pregunta al usuario. |
| Ninguno | Pasa al nivel 2 con consentimiento (abajo). No inventa candidatos. |

## Nivel 2 — fuera del inventario (capa 2a construida y probada; capa 2b a cargo de la capa llamadora)

1. El Router avisa: "Busqué en el inventario y no lo encuentro. ¿Busco fuera (repo, tablas, historial; solo lectura)? Si puedes, dime un detalle: dónde está, cómo se llama más o menos o qué hace."
2. Con el consentimiento, busca en dos capas y, si hace falta, en una **segunda pasada con las palabras del usuario**, sin expansión de sinónimos (medido: la expansión agrega ruido y tokens en el nivel 2).
   - **2a (construida):** `lf_router_search_nivel2_v1`, sobre el índice global existente `inventory.search_index` (no se creó un índice nuevo). Medido en la base real: funciones 3/5 sin detalle; con detalle del usuario 3/3; sin ruido en frases ajenas.
   - **2b (construida, no es función de base):** `sandbox/lf_contract_gate_test/router_stage1/repo_search_nivel2_v1.py`, búsqueda de solo lectura en los archivos versionados del repo, invocada por la capa llamadora (la base no puede leer archivos). Medida sobre el repo real con 15 frases (12 con archivo esperado): 6/12 dentro de los 10 primeros; "con qué termina el análisis de programación" llega al `ANALYSIS_PROCEDURE_V1.md` en el 2.º lugar de 60 candidatos. Fallan las frases en español contra documentos en inglés (profundización/drilldown) y puede traer ruido en frases ajenas (el café trae 4 pistas débiles): por eso el siguiente paso es pedir un detalle al usuario.
3. Devuelve pocos candidatos (3 a 5) con ruta y por qué coinciden, siempre marcados fuera del inventario.
4. Resultados: `ENCONTRADO_FUERA_DE_INVENTARIO`, `INCOMPLETO` o `NO_EXISTE`. Lo encontrado en el nivel 2 es evidencia, **no permiso**.
5. Registra el hueco del inventario para decidir después si se agrega el activo o un alias.

## Pistas en el inventario

Los aliases y keywords en español viven en `lf_activos.metadata`. Se agregan por migración y el propietario los revisa. Primera ronda: PR #3106 (17 activos). Los hallazgos del nivel 2 alimentan las siguientes rondas.

## Prueba de aceptación del nivel 2 (caso "spec")

Hoy el inventario no tiene el documento con el que termina el análisis de programación (`ANALYSIS_IMPLEMENTATION_PACKAGE_V1` y `PROGRAMMING_CONTEXT_SNAPSHOT_V1`, ver `ANALYSIS_PROCEDURE_V1.md`). Se deja así **a propósito**: no se agrega al inventario ni como alias. Para la frase "¿con qué termina el análisis de programación?" el nivel 2 debe devolver `ENCONTRADO_FUERA_DE_INVENTARIO` con `ANALYSIS_PROCEDURE_V1.md` o el esquema del paquete entre los 3 primeros. Simulación previa (búsqueda sobre archivos del repo, sin etapa 1 ni pregunta): primer lugar con la frase completa; se pierde con frases vagas ("spec": 998 candidatos sin el objetivo). Es una línea base burda, no una garantía.

## Medición actual (nivel 1)

Antes de los aliases: reglas 8/10 en primer lugar, inventario 8/12. Con los aliases de la primera ronda, las frases probadas del propietario ("history de usuario", "creador de skills", adaptador UX, perfil de interfaz, perfil de producto, gobernanza de entrada) quedan en primer lugar en la base real. "spec driving", el café y el ajedrez siguen sin resultados.

## Prueba de punta a punta (20 frases: las del propietario más inventadas; etapa 1 redactada por Claude, no medida con el modelo en vivo)

Casos en `sandbox/lf_contract_gate_test/router_stage1/e2e_cases_v1.json`; búsquedas contra la base real el 2026-10-22.

| Resultado | Frases |
|---|---|
| Responde directo / pregunta / sistema no soportado (3 de 3 correctos) | "qué hora es en Lima", el café; "el perfil" (ambiguo); Saly |
| Activo correcto en primer lugar en el nivel 1 (8) | input governance, historias de usuario ("history"), creador de skills, adaptador UX del marketplace, perfil del director de producto, revisor de linaje, DNI en logs, Yape monto inicial |
| Resuelto por el despacho con `capability_hint` (2) | estado en curso, crear regla (el nivel 1 solo trae ruido B2B) |
| Varios candidatos válidos, decide quien elige (2) | "profile"/"perfil", "adapter"/"adaptador" |
| No encontrado sin más detalle (3) | "spec driving" (nivel 2 con la palabra "spec" sola trae el contrato `SPEC_INPUT` y funciones `*_spec`: pistas, no certeza), "registrar paso de operación de tarjeta", "con qué termina el análisis de programación" |
| Pista débil (1) | "ver el saldo de un cliente" trae reglas de pagos/reembolso: relacionadas, no la respuesta |

## Pendiente (no declarado como hecho)

- Registro persistente de huecos del inventario (hoy la función solo los sugiere: `hueco_inventario_sugerido`).
- El índice global no tiene los documentos del análisis de programación (`programming_agent_four_stage`, `docs/programming-agent`): la alimentación de ese índice es de su propio proceso y no se tocó.
- Lectura de detalle de candidatos (los sondeos) como función.
- Dimensión de sistema (LF/Saly) en el catálogo.
- Entrega de `p_capability_hint` desde la etapa 1 al despacho.
- Identidad del llamador (actor + execution_id) para que las escrituras puedan pasar a PERMITIDO.
- Frases reales del propietario para reemplazar los casos de borrador; los negativos quedan en el conjunto permanente.
- C2/C3 de RW1-06 siguen PENDING hasta que el propietario los apruebe viendo las pruebas.
