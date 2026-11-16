# Reglas de inspección

| Frente | Inspección y demostración |
|---|---|
| SPEC | Derivar obligaciones del consumidor; required/tipos/null/enums/defaults/versiones/errores. Fuente de cada campo y primer salto que lo pierde; compatibilidad hacia atrás/adelante |
| Transporte | Todos los saltos/aliases/overwrites, firma vs llamada, dato disponible no entregado, reconstrucción innecesaria; run/tenant/objeto/candidato/alcance |
| Lógica | Tabla estado × evento × efecto, límites, desconocidos, excepciones, retries/replay. Justificar if/case/FSM por comportamiento |
| SQL | Joins/filtros/cardinalidad/índices/planes/N+1/locks/aislamiento/RLS; mismo dataset, parámetros y resultados antes de medir |
| Snapshots | Comparar consulta unificada/snapshot/caché/materialización; identidad/version/SHA/frescura/invalidación/tenant/autoridad; dos consumidores y fuente cambiada |
| Juez | Dictamen/flags/texto/estado/acción contra SPEC/EVAL y autoridad. Degradar procedencia no implica invalidar contenido ni conceder permiso |
| Suficiencia | Causa/función/impacto/corrección/prueba cuando hay evidencia; si falta contexto localizar dónde se perdió |

Probar alternativas incorrectas: materialización con frescura inmediata, snapshot
entre tenants/runs, caché sin invalidación, case por estilo, independencia como
veto extra donde no se exige, y permiso contextual donde sí se exige independencia.
Hacer segundo pase abierto: qué exige el consumidor sin declararlo, qué fallo
pasaría el EVAL, qué dato existe pero no viaja, qué estado sobreafirma el efecto.
Añadir casos nuevos aunque no estén en checklist/EKB. Declarar certeza y límites.
