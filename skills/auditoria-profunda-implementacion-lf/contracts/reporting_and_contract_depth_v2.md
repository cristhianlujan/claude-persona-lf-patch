# Contrato de reporte y profundidad V2

## Contenido

1. Entrada y resultados separados
2. Evidencia por paso
3. Consultas SQL
4. Transporte y PASS
5. Muestra de corridas
6. Calidad de contratos
7. Formatos y ejemplos por tipo
8. Cierre y compatibilidad

## 1. Entrada y resultados separados

Recibir objetivo, fuente/versiones, consumidores, alcance autorizado, requisitos
de E2E (incluido si IG debe ejecutarse), período/cohorte y presupuestos de frescura
y rendimiento. Si el presupuesto o frecuencia no existe, no inventarlo.
Mantener separados: cobertura del lote, cobertura conocida del código/datos,
calidad contractual y acreditación del flujo. `lot_coverage_percent=100` nunca
implica `FLOW_ACCREDITED`. Solo una nueva ejecución verificable de todos los pasos
y de IG cuando sea requerido puede acreditar el E2E solicitado. Una corrida
histórica puede demostrar comportamientos observados de esa corrida.

## 2. Evidencia por paso

Emitir siempre las once filas 0/10/20/30/40/45/47/50/60/70/80. Por fila indicar
qué funcionó exactamente, estado reportado, comportamiento realmente probado,
referencia/recibo resuelto, execution_id, límites, confianza y motivo. Si falta
una fila real, conservar la fila de auditoría como NOT_EXECUTED/NOT_VERIFIED.
Una referencia guardada prueba registro de referencia; no prueba haber descargado
el artefacto ni que su contenido sea correcto. No ocultar los aciertos por listar
solo defectos. No convertir un STEP_PASS del recorder en IG ejecutado.

Tipos de evidencia:

| Tipo | Significado | No acredita |
|---|---|---|
| MEASURED_THIS_AUDIT | Consulta, plan o helper ejecutado durante esta auditoría | Que la corrida leída sea nueva o que un helper local sea E2E |
| MEASURED_PREVIOUSLY | Reproducción anterior con fecha/hash/fuente | Reejecución actual |
| CODE_READ_ONLY | Rama/contrato leído y enlazado | Comportamiento ejecutado |
| NOT_MEASURED | Medición no realizada, con motivo | PASS ni ausencia de defecto |

Anotar además origen LIVE_EXISTING_RUN/LIVE_NEW_RUN/LIVE_QUERY_PLAN/LIVE_METADATA/LOCAL_HELPER/
FIXTURE/SOURCE_FILE/PRIOR_REPORT. Confianza HIGH/MEDIUM/LOW se refiere a la
afirmación precisa y lleva explicación; no a todo el sistema por extrapolación.

## 3. Consultas SQL

Inventariar cada consulta conocida: source/function/lines, SQL y parámetros,
tablas, joins, filtros, índices existentes, rol FLOW_QUERY o AUDIT_QUERY,
transacción/aislamiento, RLS, frecuencia medida, plan y costo. Enumerar SQL
dinámico/nested unresolved; no declarar inventario exhaustivo mientras quede.
Un SELECT proyectado de auditoría no representa necesariamente el SELECT * real
del flujo. Marcar variantes y medir el original cuando haya bindings seguros.

Para SELECT revisado sin efectos, usar dentro de una única sesión:

```sql
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '3000ms';
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT step_order, step_id, status
FROM public.lf_operation_execution_steps
WHERE execution_id = '<RUN observado>' ORDER BY step_order;
ROLLBACK;
```

ANALYZE ejecuta la consulta. ROLLBACK no revierte efectos externos, secuencias ni
acciones de funciones VOLATILE. No ejecutar funciones escritoras, DML, helpers
desconocidos o producción bajo esa falsa garantía. Analizar en entorno aislado
autorizado o marcar NOT_MEASURED con la causa exacta. No crear funciones/índices
ni tocar permisos para poder medir. Si el conector oculta el plan o falla,
conservar error/estado y no inventar métricas.

Guardar versión PG, parámetros/dataset, sample_count, tiempos de planning y
execution, filas estimadas/reales, loops, buffers y estado de caché conocido.
Separar tiempo de consulta y latencia integral. Una muestra no demuestra p95 ni
comportamiento frío/concurrente. Un nodo Materialize del plan no es una vista
materializada. Recomendar materialización solo con frecuencia × costo medidos,
equivalencia de resultados, costo/lag de refresh, invalidación, frescura admitida,
RLS y autoridad equivalentes. Comparar snapshot, consulta unificada e índice.
Si faltan frecuencia/frescura, emitir NOT_EVALUATED; lectura inmediata la descarta.

## 4. Transporte y PASS

Emitir matriz de todos los saltos adyacentes y del desvío Perfil→IG→Perfil:
emisor/receptor, campos disponibles/enviados/perdidos, transformación, contrato,
execution_id/parent-child, tipo/semántica de hash, dónde se comprueba y evidencia.
Antes de Step50 no exigir candidate_sha256 inexistente: verificar los hashes
de fuente/alcance que sí correspondan. Igualdad de dos hashes declarados no
equivale a recalcularlos desde el artefacto. NA exige explicación por contexto.

Inventariar cada emisor de STEP_PASS/PASS_REVIEWED_CURRENT_CONTEXT/APPLIED y
flags como ig_findings_reported. Buscar except→PASS, defaults true,
coalesce(...,true), estado APPLIED sin efecto y propagación de dictámenes.
Clasificar cada sitio: emisor, candidato por resolver, patrón de riesgo o
comparación/metadata sin emisión. Exigir contrato y evidencia real por sitio.
Definir y ejecutar un negativo con entrada rota por cada emisor revisado; si no
se ejecuta, dejar NOT_EXECUTED y reducir cobertura. Un patrón no confirma defecto.
No ejecutar automáticamente funciones descubiertas ni un APPLIED con efectos.

## 5. Muestra de corridas

Consultar últimas N (por defecto 20, máximo 100) del objetivo/canales autorizados.
Guardar SQL, filtro, orden, período observado y N real. Medir PASS sin referencia,
payload ausente, bindings discordantes y reportes IG sin invocación identificable.
Separar en progreso/abandonadas/completadas y elegibilidad de IG opcional.
Reportar numerador/denominador y null si no hay elegibles. Ausencia de recibo
es una señal que requiere resolver el contrato: no llamar al porcentaje "tasa
real de falsos PASS" sin comprobaciones semánticas/negativos por caso. Tampoco
0 referencias vacías demuestra 0 falsos PASS. No muestrear una corrida como si
fuera representativa del sistema entero.

## 6. Calidad de contratos

Aplicar el perfil de tipo de references/contract_profiles_v2.json. Admitir el
formato nativo de cada contrato y sus referencias resueltas; no exigir una misma
plantilla física a JSON Schema, SQL, Python y Markdown. Descubrir obligaciones
adicionales del consumidor aunque el perfil inicial no las enumere.

Cada celda de la matriz guarda: literal o ausencia comprobada, fuente, obligación
del consumidor, revisión semántica, razón contextual y redacción exacta propuesta.
Evaluar si otro ejecutor puede determinar dato, condición, resultado/error y
prueba sin adivinar. Un texto corto puede ser suficiente; uno largo puede ser
ambiguo. No puntuar longitud, headings ni cantidad de palabras como profundidad.
Las coincidencias de frases vagas solo orientan; resolver negaciones y contexto.

| Celda | Color | Criterio |
|---|---|---|
| ACCEPTABLE | Verde | Contenido concreto, entendible, comprobable y compatible con consumidor |
| WEAK | Amarillo | Existe, pero omite precisión necesaria o obliga a adivinar |
| MISSING | Rojo | Obligación aplicable ausente, demostrada contra fuente/consumidor |
| CONTRADICTORY | Rojo | Campo presente contradice implementación/autoridad/otro campo |
| NOT_EVALUATED | Gris | Falta lectura, consumidor o evidencia para juzgar |
| NOT_APPLICABLE | Neutro | No corresponde a ese tipo/cometido; explicar por qué |

La nota final es el peor requisito crítico: faltante/contradicción crítica o
redacción crítica débil → LOW; requisito aplicable sin evaluar → NOT_EVALUATED;
debilidad/falta no crítica → MEDIUM; todas las obligaciones concretas → ACCEPTABLE.
No compensar un error crítico con muchas celdas verdes. ACCEPTABLE califica el
contrato revisado; no acredita despliegue, independencia ni autoridad de efecto.

## 7. Formatos y ejemplos por tipo

| Tipo | Formato/obligaciones específicas | Débil | Ejemplo operativo esperado |
|---|---|---|---|
| INPUT | Firma/JSON Schema: required, tipos, nulos, defaults, error y receptor | "datos necesarios" | execution_id text no vacío; scope.resolved_screen_code string; sin scope: INPUT_REQUIRED_NOT_AVAILABLE |
| SPEC | Objetivo, estados/reglas, entradas/salidas y aceptación | "validar correctamente" | Si scope falta, IG no se invoca; registrar finding de selección y conservar continuation_allowed según política |
| OUTPUT | Schema de campos/flags, significado y compatibilidad | "devuelve un resultado válido" | ig_executed=true exige recibo IG enlazado; selection_finding no lo sustituye |
| TRANSPORT | Mensaje y mapa por salto, origen/destino/bindings | "enviar contexto" | Pasar execution_id del padre a normalize(review, execution_id=execution_id); RUN distinto debe dar STEP70_RUN_ID_DRIFT |
| EVAL | Oráculo, condiciones PASS/FAIL, errores y negativos | "PASS si está bien" | source_refs contiene strings de longitud mínima 4; ['x'] falla con código identificable |
| JUDGE | Contexto/SPEC/EVAL, procedencia y permiso separados | "independiente por usar SPEC" | Validación contextual acredita el pase aceptado por la política; producer_independence_proven=false si no se probó aislamiento |
| SQL | Parámetros, plan/índices, RLS/frescura/frecuencia | "usar materialized para acelerar" | Comparar plan actual, calls/interval y refresh; sin frecuencia medida: recomendación NOT_EVALUATED |
| SNAPSHOT | Identidad/version/hash/autoridad, reuso e invalidación | "usar caché vigente" | Rechazar si tenant/run/source_revision difiere; reusar payload idéntico entre consumidores autorizados |
| HANDOFF | Causa, archivo/función, cambio, prueba, permisos y receptor | "revisar backend" | Entregar causa y llamada exacta incompleta, diff propuesto y negativo reproducible, sin delegar investigación ya disponible |
| STATE_MACHINE | Estado/evento/guard/acción/siguiente estado y desconocidos | "manejar otros estados" | WAITING_FUNDS + sin saldo → DEFER; estado desconocido sigue la política explícita, sin imponer case por estilo |

## 8. Cierre y compatibilidad

Reportes nuevos cumplen schemas/audit_report_v2.schema.json y validate_audit_v2.py.
Conservar V1 como evidencia histórica, sin atribuirle cobertura V2 retroactiva.
Entregar Markdown y HTML accesible con leyenda, campos coloreados y detalle por
celda. Mostrar siempre el veredicto de flujo junto a la cobertura. El renderer
no inventa estados ni convierte faltantes en verde. No fusionar/registrar/activar
ni ejecutar reparaciones funcionales al actualizar este candidato.
