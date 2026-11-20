# Comprobaciones de profundidad y evidencia V2

Aplicar por contexto y completar obligaciones nuevas que revele el consumidor.
Cada fila requiere evidencia o pendiente; presencia de este checklist no acredita PASS.

| Revisión | Evidencia exigida | Contraejemplo |
|---|---|---|
| Aciertos y faltantes por paso | Once filas, recibo real, qué prueba y qué no | Paso omitido o puntero sin resolver no desaparece |
| SQL | Consulta original vs variante de auditoría, plan e índices, muestras/frecuencia | ANALYZE de writer no es seguro por ROLLBACK |
| Transporte | Cada salto, origen/destino, campos, RUN/hash según fase | No exigir candidato aún inexistente; no omitir identidad disponible |
| Emisión PASS | Contrato, guardas y negativo por sitio | Except→PASS, defaults true y comparaciones requieren contexto |
| Cohorte | Consulta/filtro/N real y denominadores | 0 punteros ausentes no acredita 0 falsos PASS |
| Contrato por tipo | Literal, significado, consumidor y propuesta por celda | Texto largo ambiguo sigue débil; breve preciso puede ser aceptable |
| Procedencia | Actual/previa/lectura/no medida, origen y confianza explicada | Un SELECT actual de un run viejo no es E2E nuevo |
| Autoridad | Política/actor/objeto/efecto actuales y bindings | Contexto válido puede bastar; no inventa independencia ni permiso |
| Cierre | Cobertura conocida y FLOW_* separados | Lote 100 % puede terminar FLOW_NOT_ACCREDITED |

Ver [contrato](../contracts/reporting_and_contract_depth_v2.md),
[perfiles](../references/contract_profiles_v2.json) y
[regresiones](../evals/test_reporting_v2.py). Este checklist amplía EKB; no sustituye
su lectura ni convierte una lección histórica en política vigente.
