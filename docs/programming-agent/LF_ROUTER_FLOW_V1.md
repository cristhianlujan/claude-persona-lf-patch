# Flujo del Router ACT-0001 (LF) — V1

Estado: **contrato de diseño**. Lo construido y probado se marca así; lo demás es objetivo y no se declara operativo.
Ámbito: LF ahora. Un solo Router para LF, Saly y otros; la dimensión de sistema se agrega después.
Todo el flujo es de solo lectura; ningún resultado autoriza efectos (`downstream_execution_allowed=false`).

## Un Router, dos etapas

**Etapa 1 — Entender** (la hace el modelo nativo GPT/Claude; no gasta API de pago). Entra la frase, antes de buscar nada:
1. ¿Es una operación o una pregunta que se responde sin inventario? ("¿qué hora es en Lima?" → se responde directo y termina.)
2. Corregir lo mal dicho ("history" cerca de "usuario" = "historias"; "spec driving" = "spec-driven").
3. Sistema (LF por ahora), acción y sujeto extraídos de la frase.
4. Reformular el sujeto con las palabras del inventario (español e inglés) **solo en el nivel 1**.

**Etapa 2 — Encaminar** (DB):
- **Nivel 1 (construido, probado):** `lf_router_search_v1` sobre inventario de gobierno y reglas del producto. Entrega pistas, no decisiones.
- **Despacho (construido, probado):** `lf_router_dispatch_v1` sobre el catálogo de capacidades, con respuesta uniforme PERMITIDO / DENEGADO / FALTA_INFO.

## Qué pasa según cuántos resultados da el nivel 1

| Resultado | Qué hace |
|---|---|
| Un candidato claro | Lo usa y despacha. |
| Varios | Quien decide (el modelo) elige, o pide más detalle leyendo los candidatos (máximo 3 sondeos por duda; el 4.º requiere autorización del propietario; un sondeo discriminante de solo lectura; parar si no aporta). Si sigue la duda, **una** pregunta al usuario. |
| Ninguno | Pasa al nivel 2 con consentimiento (abajo). No inventa candidatos. |

## Nivel 2 — fuera del inventario (objetivo; **no construido**)

1. El Router avisa: "Busqué en el inventario y no lo encuentro. ¿Busco fuera (repo, tablas, historial; solo lectura)? Si puedes, dime un detalle: dónde está, cómo se llama más o menos o qué hace."
2. Con el consentimiento, busca en una **segunda pasada con las palabras del usuario**, sin expansión de sinónimos (medido: la expansión agrega ruido y tokens en el nivel 2).
3. Devuelve pocos candidatos (3 a 5) con ruta y por qué coinciden, siempre marcados fuera del inventario.
4. Resultados: `ENCONTRADO_FUERA_DE_INVENTARIO`, `INCOMPLETO` o `NO_EXISTE`. Lo encontrado en el nivel 2 es evidencia, **no permiso**.
5. Registra el hueco del inventario para decidir después si se agrega el activo o un alias.

## Pistas en el inventario

Los aliases y keywords en español viven en `lf_activos.metadata`. Se agregan por migración y el propietario los revisa. Primera ronda: PR #3106 (17 activos). Los hallazgos del nivel 2 alimentan las siguientes rondas.

## Prueba de aceptación del nivel 2 (caso "spec")

Hoy el inventario no tiene el documento con el que termina el análisis de programación (`ANALYSIS_IMPLEMENTATION_PACKAGE_V1` y `PROGRAMMING_CONTEXT_SNAPSHOT_V1`, ver `ANALYSIS_PROCEDURE_V1.md`). Se deja así **a propósito**: no se agrega al inventario ni como alias. Para la frase "¿con qué termina el análisis de programación?" el nivel 2 debe devolver `ENCONTRADO_FUERA_DE_INVENTARIO` con `ANALYSIS_PROCEDURE_V1.md` o el esquema del paquete entre los 3 primeros. Simulación previa (búsqueda sobre archivos del repo, sin etapa 1 ni pregunta): primer lugar con la frase completa; se pierde con frases vagas ("spec": 998 candidatos sin el objetivo). Es una línea base burda, no una garantía.

## Medición actual (nivel 1)

Antes de los aliases: reglas 8/10 en primer lugar, inventario 8/12. Con los aliases de la primera ronda, las frases probadas del propietario ("history de usuario", "creador de skills", adaptador UX, perfil de interfaz, perfil de producto, gobernanza de entrada) quedan en primer lugar en la base real. "spec driving", el café y el ajedrez siguen sin resultados.

## Pendiente (no declarado como hecho)

- Función del nivel 2 y registro de huecos del inventario.
- Lectura de detalle de candidatos (los sondeos) como función.
- Dimensión de sistema (LF/Saly) en el catálogo.
- Entrega de `p_capability_hint` desde la etapa 1 al despacho.
- Identidad del llamador (actor + execution_id) para que las escrituras puedan pasar a PERMITIDO.
- Frases reales del propietario para reemplazar los casos de borrador; los negativos quedan en el conjunto permanente.
- C2/C3 de RW1-06 siguen PENDING hasta que el propietario los apruebe viendo las pruebas.
