# LF Input Governance — Auditoría SQL y materialización selectiva
**Fecha:** 2026-10-28 · **PR:** #3269 draft · **Alcance:** SQL de diagnóstico G3/G4/P07, pruebas y candidato SQL de N-4. **NO Router, NO DDL/DB writes, NO reclasificación ni merge.**

## Principio operativo

Se emplea **`WITH ... AS MATERIALIZED`** (PostgreSQL >=12, fuente actual 17.6) **solo** cuando una relación se usa varias veces, cuando un resultado costoso debe conservarse durante la sentencia o cuando importa que el mismo corte alimente todas las verificaciones. No equivale a `CREATE MATERIALIZED VIEW`, no persiste ningún dato ni sustituye un snapshot gobernado de varias transacciones. No obligar materialización en CTE de una sola lectura y pocos registros, porque podría introducir sobrecostos y limitar optimizaciones del planificador.

### Resultado de auditoría

| ID | Antes / defecto | Ajuste materializado o corrección | Verificación ejecutada |
|---|---|---|---|
| **SQL01 P07** | Dos consultas volvían a calcular vínculos del resolvedor por pantalla para grupos y totales | Una sentencia con `targets`, `source_shells`, `derived`, `classified`, `groups`, `totals` **AS MATERIALIZED**; agregación de grupos y total a partir de la misma clasificación. No recálculo de función entre las dos consultas | SELECT: 4 grupos = **2.201 + 42 + 5.230 + 1.379 = 8.852**, 241 reglas, 58 pantallas, 785 vínculos a pantallas inactivas; `partition_ok=true`. `EXPLAIN (FORMAT TEXT)` muestra `Function Scan` sobre `fn_input_effective_rule_links_v1` bajo CTE `derived`, y `CTE Scan` de su resultado |
| **SQL02 G3 paridad** | El archivo citado de paridad faltaba en la rama, aunque se había ejecutado una consulta ad hoc | Se materializa el contexto canónico una vez por pantalla (`targets`), selectores ACTIVE (`selectors`), proyección reducida (`contexts`) y comparaciones (`pairs`) | SELECT: **14 reglas × 58 pantallas = 812 pares**; 52 vs 52 matches; **0 diferencias**. `EXPLAIN` muestra `CTE Scan` para estos cuatro CTE |
| **SQL03 G3 shadow** | Fixtures, selectores normalizados y decisiones de cláusulas se reutilizaban en ramas separadas, sin barrera explícita | `fixtures`, `selector_struct`, `clause_match` **AS MATERIALIZED**; otras fases inline sin materialización forzada | SELECT: **28/28** casos de lógica candidata conforme. `EXPLAIN` muestra reuso por `CTE Scan` |
| **SQL04 G4 audit** | Conversión de strings numéricos de procedencia a BIGINT sin longitud acotada podía abortar con un número excesivamente largo | Limitación previa con regex `^[0-9]{1,18}$`, que siempre cabe en bigint; conserva LEFT JOIN y desconocidos como NULL. Sin CTE MATERIALIZED innecesarios (14 filas, una lectura) | SELECT: 14 referencias de eventos válidas, 0 aceptaciones y 0 autorizaciones de producción explícitas; eventos 19948 y 19951 |
| **SQL05 N-4 candidato** | `consumer_role` de contexto convertido automáticamente desde número mediante operador JSON `->>`, coincidiendo con rol string `"42"` | Verificación explícita `jsonb_typeof(p_context->'consumer_role')='string'` en función candidata; vector **T28** | Función desplegada actual devuelve TRUE para el caso adversarial; sombra read-only corregida devuelve FALSE; **18/28** tests conformes en función actual y **28/28** en sombra |
| **SQL06 Candidato DDL** | No consta ejecución/compilación PostgreSQL aislada ni autorización de publicación | Se conserva separado de migraciones, con prestate hash guards y ROLLBACK; runner aislado con fixture sanitizado y ahora **28** vectores | **NO_VERIFICADO** el DDL; faltan PostgreSQL 17.6 local, ACL y ejecución transaccional real |

## SQL de lectura exacto materializado

- `sandbox/lf_contract_gate_test/input_governance/ig_lote_a_p07_alcance_readonly_20261028.sql`
- `sandbox/lf_contract_gate_test/input_governance/ig_n4_active_selector_parity_readonly_20261028.sql`
- `sandbox/lf_contract_gate_test/input_governance/ig_n4_matcher_hardened_select_only_shadow_20261028.sql`
- `sandbox/lf_contract_gate_test/input_governance/ig_n4_scope_authority_readonly_audit_20261028.sql`

**Regla de revisión:** un `CTE Scan` en EXPLAIN comprueba materialización del conjunto, pero no prueba aceleración de latencia. Una mejora de tiempo/p95/carga necesita benchmark reproducible con `EXPLAIN ANALYZE` y controles de acceso/recursos adecuados, aún **NO EJECUTADO**. Para futuros conjuntos de más tamaño, probar consumo de memoria/`work_mem` y spill; evitar `MATERIALIZED` en operadores simples de un solo uso.

## Separación entre datos y autoridad

- Ningún `MATERIALIZED` habilita herencia, concede scope o convierte regla `CANDIDATO` a operativa.
- La distribución por shell es **señal de descubrimiento**, no autorización semántica.
- G3 sigue bloqueado hasta PostgreSQL aislado y validación independiente; G4 hasta recibo/competencia verificados; G5 NO_RECLASSIFY.
- No emitir PR de migración ni escribir datos en Supabase. Persistir source exacto primero en Git, conforme EKB `CI-MIGRATION-SOURCE-PARITY-001`.

**Resultado global:** consultas revisadas, CTE materializados selectivamente, reparados el SQL histórico P07 y el artefacto de paridad, añadido vector adversarial T28 de consumidor; sin modificaciones de código desplegado.
