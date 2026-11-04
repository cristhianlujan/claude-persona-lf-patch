# PG-11_C2 — Terminología, glosario, códigos y mensajes (2026-11-04)

## Contrato oficial
«Rúbrica: nombres semánticos e idioma según glosario (STD-GEN-01); códigos de catálogo literales (STD-GEN-07); textos no inventados (STD-MSG-02); consistencia con el módulo vecino; cobertura positiva del glosario: cada identificador de dominio nuevo cita sus term_id y se verifica sí/no que existan y coincidan».

Criterio de salida PG-11: «Diff final no contiene cambios huérfanos, deuda inventada ni scope creep».

## Implementación fuente
`tools/pg11_c2_terminology_catalog_candidate_v1.py`: `prepare_pg11_c2(pg11_c1, declared_changed_paths, terminology_observations, glossary_snapshot_ref, catalog_snapshot_ref, messages_snapshot_ref, neighbor_baseline_ref)`.

Exige el sobre candidato C1 con digest consistente y sin autoridad. Recibe un inventario de identificadores de dominio, códigos literales, mensajes y convenciones del módulo vecino. Cada identificador nuevo de dominio **debe declarar al menos un `term_id`**. Genera hallazgos tipados si las observaciones afirman que un término no existe/no coincide, que un código o mensaje difiere de su literal, que hay divergencia con el vecino o que falta observación para una ruta cambiada.

Las banderas `term_exists_reported` y `term_matches_reported` son **declaraciones no autenticadas**. No cuentan como verificación positiva del glosario; referencias de snapshots tampoco autentican esas fuentes. Un inventario incompleto de símbolos no puede descartarse solo porque cada ruta tenga una observación.

## Deuda técnica explícitamente diferida
1. Extraer **todos** los identificadores de dominio nuevos del diff real, con AST/lexing según lenguaje y glosario aplicable, no solo inventario suministrado.
2. Leer versiones y hashes auténticos de glosario, catálogo, STD-MSG-02 y módulos vecinos, contrastar cada `term_id`, idioma y literal; rehusar cadenas inventadas.
3. Ejecutar pruebas positivas y negativas exact-HEAD, evidencia de cobertura por símbolo, revisión independiente y unión del reporte C1/C2 con C3–C5.
4. No permitir `PASS` si un símbolo nuevo carece de `term_id` válido o si un código literal se cambió sin gobernanza.

## Estado
`PG11_C2_SOURCE_PREPARED / NO_REAL_SOURCE_READBACK / NOT_TESTED / OFFICIAL_PENDING`.

Toda salida conserva `glossary_terms_verified=false`, `positive_coverage_verified=false`, `pg11_c2_pass=false`, `handoff_allowed=false` y `production_authority=false`.

**Siguiente:** PG-11_C3 — cada supresión exige waiver válido (STD-GEN-05).

No se modifica Análisis, Supabase, `main` ni producto; PR #3528 en draft.
