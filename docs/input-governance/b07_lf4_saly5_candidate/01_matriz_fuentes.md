# B07 — Matriz candidata LF4 / SALY5 (NO APROBADA)

**Estado:** PROPUESTA DE ARQUITECTURA, pendientes decisión del dueño, SQL sandbox y prueba. No implica deploy ni cierre B07.

**Regla de trazabilidad:** las nueve columnas, sus tipos nuevos, defaults y escrituras son **INFERIDOS** por Arquitectura: ninguna fuente consultada las define literalmente como contrato aprobado. La evidencia existente sustenta solo el contexto señalado.

## Fuentes realmente verificadas
- **[S1]** Supabase SELECT: information_schema.columns lf_ops.reglas y saly.reglas, 2026-11-13.
- **[S2]** Supabase SELECT: 14 filas saly.reglas, 14 VALIDADO/vigente y decision_id 51..60, 2026-11-13.
- **[S3]** Supabase SELECT: lf_ops.reglas, 578 filas, 412 VIGENTE/166 CANDIDATO, 2026-11-13.
- **[S4]** Supabase SELECT: saly.estados y saly.transiciones (10/10; entidad_tipo=ADELANTO, estado=CANDIDATO), 2026-11-13.
- **[S5]** Supabase SELECT: saly.campos y saly.validaciones (0/0), 2026-11-13.
- **[S6]** Supabase supabase_migrations.schema_migrations.statements: 20260813185516, 20260813192048, 20260814035958, 20260819040820, 20260819051748.
- **[S7]** Repo main search `saly.estados`, `saly.transiciones`, `saly.campos`, `saly.validaciones`: sin fuente histórica de foundation recuperada en main; historial SQL leído de Supabase.
- **[EKB]** `INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4`, proyecto: `https://docs.google.com/document/d/1nUFk29HhCl_kCg-W-bwkpyLuwx9gURQNJAGKhhgerTk`; prohibe sustituir escritores oficiales y afirmar PASS sin evidencia.

## Matriz 9 campos
| Esquema | Campo (nuevo) | Significado en llano | Tipo propuesto | Default | Quién escribe | Relación con lifecycle_state | Fuente contextual | Origen de definición |
|---|---|---|---|---|---|---|---|---|
| LF | lifecycle_state | Fase técnica del gobierno de la regla, separada de estado | text | NULL | escritor oficial de regla/promoción | No equivale a estado CANDIDATO/VIGENTE automáticamente | S1,S3 | INFERIDO |
| LF | lifecycle_source_sha256 | Huella de preimagen que el escritor comprobó antes de actuar | text (64 hex) | NULL | escritor oficial, tras calcular SHA-256 | Dato acompañante obligatorio si lifecycle_state no es NULL | S1, EKB | INFERIDO |
| LF | lifecycle_decision_ref | Referencia literal al dictamen documental del dueño | text | NULL | registrador/escritor oficial con recibo | Debe acompañar lifecycle_state; no significa identidad comprobada | S1, EKB | INFERIDO |
| LF | lifecycle_changed_at | Momento de cambio de fase gobernada | timestamptz | NULL | escritor oficial tras transición verificada | No sustituye updated_at actual | S1 | INFERIDO |
| SALY | lifecycle_state | Fase técnica de gobierno de la regla SALY; distinta del estado nativo VALIDADO | text | NULL | escritor gobernado SALY (futuro) | Nunca mapear VALIDADO→VIGENTE sin decisión | S1,S2,S4 | INFERIDO |
| SALY | lifecycle_source_sha256 | Huella de preimagen de la regla SALY | text (64 hex) | NULL | escritor gobernado SALY (futuro) | Obligatoria si lifecycle_state no es NULL | S1,S2 | INFERIDO |
| SALY | lifecycle_decision_ref | Referencia a decisión de ciclo; sin sustituir decision_id actual | text | NULL | escritor gobernado SALY (futuro) | Contiene vínculo documental distinto de decision_id bigint | S1,S2,S6 | INFERIDO |
| SALY | lifecycle_changed_at | Fecha de transición de gobierno, no fecha normal de edición | timestamptz | NULL | escritor gobernado SALY (futuro) | Independiente de updated_at actual | S1 | INFERIDO |
| SALY | lifecycle_origin_estado | Copia literal del estado nativo de esa regla en la transición | text | NULL | escritor gobernado SALY (futuro) | CHECK: debe coincidir con estado, preserva VALIDADO | S1,S2,S4 | INFERIDO |

## Lo que YA existe (no modificar)
- `lf_ops.reglas`: 578 filas (412 VIGENTE y 166 CANDIDATO), columna `estado text DEFAULT 'CANDIDATO'`, `updated_at`, `pendiente_decision`; **ningún campo lifecycle_* nuevo** [S1,S3].
- `saly.reglas`: 14 filas, todas `estado=VALIDADO`, `vigente=true`, todas con `decision_id`, y fuentes de documentos del motor. `estado` conserva su significado, `vigente` sigue independiente. **No convertir VALIDADO a VIGENTE** [S1,S2].
- `saly.estados`: 10 estados de entidad ADELANTO, y `saly.transiciones`: 10 enlaces ADELANTO con idempotencia/auditoría. **No son fases de aprobación de saly.reglas** [S4,S6].
- `saly.campos` y `saly.validaciones` existen pero 0 registros; los catálogos no definen la matriz LF4/SALY5 [S5,S6].
- El ledger de migraciones Supabase incluye el SQL fuente de las cinco foundations anteriores; **rollback_count=0 en esas entradas**. No halladas en `main` las fuentes históricas por código/archivo para sus cuatro tablas al consultar el árbol. Esto no autoriza inventar contratos [S6,S7].

## Decisiones que faltan (NO INFERIR COMO APROBADAS)
1. Confirmar si las 9 columnas propuestas son el modelo buscado, sus nombres/tipos y dónde vivirán (tablas de reglas, no entidades de ADELANTO).
2. Definir el catálogo de valores de `lifecycle_state` y la operación de transición. **Este SQL NO rellena el campo ni activa promoción**: NULL es estado inicial de toda fila existente y nueva.
3. Decidir si `lifecycle_decision_ref` debe referenciar el `decision_id` SALY existente o mantenerse un texto distinto; decidir si `lifecycle_origin_estado` vale como quinto campo o debe sustituirse.
4. Confirmar quién podrá escribir vía contrato oficial, cómo se enlaza a firma documental (sin identidad humana autenticada en temporal), qué impactos tienen RLS/lectores y cuándo se prueba con consumidores reales.

## SQL candidato y seguridad
- `b07_lf4_saly5_candidate_up.sql` (UP) y `..._down.sql` (DOWN) **solo en sandbox**, no `supabase/migrations`.
- UP agrega 4/5 columnas nullable, **sin defaults materiales**, sin backfill; exige bundle de decisión+SHA+fecha si se escribe lifecycle_state, y origen SALY igual al `estado` nativo si se informa.
- DOWN falla si hay siquiera un valor nuevo en cualquiera de las 9 columnas: **no destruye evidencia**; sin datos, revierte DDL mediante DROP RESTRICT.
- Pruebas aisladas en PG17.6 y PG18.7 sobre fixture LF V2 y 14 filas SALY de datos sintéticos. Solo PASS si CI y log indican ejecutado; B07 permanece ABIERTO.

## Readback SQL de fuentes (solo SELECT)
```sql
SELECT codigo,titulo,estado,vigente,decision_id,fuente FROM saly.reglas ORDER BY id;
SELECT estado,count(*) FROM lf_ops.reglas GROUP BY estado;
SELECT codigo,entidad_tipo,estado,vigente FROM saly.estados ORDER BY codigo;
SELECT codigo,entidad_tipo,accion_codigo,estado,vigente FROM saly.transiciones ORDER BY codigo;
SELECT (SELECT count(*) FROM saly.campos) AS campos, (SELECT count(*) FROM saly.validaciones) AS validaciones;
SELECT version,name,statements,rollback FROM supabase_migrations.schema_migrations WHERE version IN ('20260813185516','20260813192048','20260814035958','20260819040820','20260819051748');
```
