# Pares defectuosos y correctos con consumidores ejecutados

| Caso | Ejemplo defectuoso | Implementación correcta esperada | Verificación |
|---|---|---|---|
| A01 | spec_broken.json omite c/d; consume lee ambos | spec_correct.json declara y exige a/b/c/d | AST + KeyError + consumidor completo |
| A02 | producer.broken_transport: apply_contract(variable1) | correct_transport entrega variable1, variable2 desde origin | TypeError y tuple con tenant |
| A03 | broken_branch solo READY | correct_branch cubre READY/RETRY/BLOCKED y rechaza UNKNOWN | Tabla de estados ejecutada |
| A04 | broken_query.sql sin índice de búsqueda | correct_index.sql compuesto tenant/external_id | Plan SCAN vs SEARCH, VM y resultados |
| A05 | consumer.per_step_reads hace cinco lecturas | shared_snapshot_reads hace una; read_snapshot enlaza identidad/vigencia | 5→1, mismo resultado, negativos |
| A06 | judges.broken_independence_gate veta contexto autorizado | judges.correct_gate deriva del contrato contextual verificado | promotion_authorized=true sin inventar independencia |
| A07 | broken_authority_gate autoriza solo por contexto | correct_gate requiere autoridad vigente del actor/objeto/efecto | Sin autoridad devuelve false |
| A08 | input_broken acepta amount string, consumer exige int | input_correct exige integer >=0 | Schema y consumidor, null/string/bool/negativo |
| A09 | broken_context_transport entrega solo spec | correct_context_transport preserva trace/location/source_code/spec | Faltantes se localizan en ese salto |
| A10 | broken_comment entrega comentario genérico | correct_comment entrega causa/ubicación/impacto/corrección/test | Se verifica salida requerida |

Los módulos están en fixtures/implementation. Los checks viven en
evals/test_acceptance.py. A04 mide SQLite en memoria; no atribuirlo a PG.
Las políticas y recibos fixture no representan autoridad LF real. Las pruebas
positivas de los originales defectuosos acreditan reproducción, no buen funcionamiento.
