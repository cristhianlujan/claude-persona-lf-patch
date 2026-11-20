# PG-00_C3 — Handoff para revisión independiente (29/10/2026)

**Branch:** `lf/pg00-domain-map-candidate-v1`, PR #3325. **Estado:** DRAFT / NOT RELEASED. No hay aprobación, migración ni recibo real.

## Qué se entregó

1. `pg00_std_adr_source_catalog_v1.json`: lectura fuente en solo lectura de las 17 decisiones vigentes `ADR-PROG-STD-001..017` en `transversal.decision_log`; documentadas también en `PG00_STD_ADR_SOURCE_CATALOG_V1.md`.
2. `pg00_std_rules_candidate_v1.json`: 17 interpretaciones candidatas, una por ADR, cada una con dominio, política de activación y ejemplos ilustrativos OK/NO. **Los ejemplos no son pruebas de ejecución y NO están aprobados**.
3. `validate_pg00_std_rules_candidate_v1.py`: comprueba paridad literal con las decisiones fuente, estado no autorizado, existencia de ejemplos y políticas reconocidas.
4. `test_pg00_std_rules_candidate_v1.py`: 1 prueba positiva de forma, 10 negativas de mutación; las cuatro suites locales PG-00 pasan.
5. `pg01_c4_authority_dependency_matrix_v1.json`: vínculo con dependencias pendientes de PG-01_C4.

## Solicitud de dictamen

- Verificar exactitud semántica de cada interpretación frente al ADR original, especialmente ADR-001 (LF vs productos nuevos), ADR-005 (UUID excepcional), ADR-012 (reglas LF en conflicto), ADR-013 (calificación local), ADR-015 (arquitectura por proyecto), ADR-016/017 (costos/optimización).
- Para cada ejemplo OK/NO, indicar si refleja la decisión, si faltan precondiciones o si es ambiguo. **No promover ejemplos ilustrativos a casos normativos sin revisión**.
- Determinar los criterios de severidad, condiciones de activación L1/L2 vs L3 y formato machine/LLM necesario para una release auténtica.
- Verificar que el lector de PG-00_C3 nunca acepte `ACTIVE_READBACK_VERIFIED` ni recibos autodeclarados; conectar publicación y readback autoritativo exact-head con PASE y Train.
- Identificar los huecos reales que impiden cerrar C3 (y los que corresponden exclusivamente a C11, D15/L3 o C4), evitando sobrecargar C3 con dependencias ajenas.

## Pendientes de decisión, no resolver por suposición

- `ADR-PROG-STD-012`: conflicto de reglas LF (registro textual dice pendiente para Cristhian).
- `ADR-PROG-STD-015`: registro vigente de arquitectura por proyecto / commit.
- `ADR-PROG-STD-017`: monto aprobado del presupuesto de cada solicitud y tabla de precios versionada, `POR DEFINIR`.
- Regla de clasificación A2 × A7 × stack y alcance completo de dominio STD.

## Comandos de verificación local

```bash
cd sandbox/lf_contract_gate_test/programming_agent_four_stage/pg00
python3 test_pg00_domain_map_candidate_v1.py
python3 test_pg00_c3_publication_guard_v1.py
python3 test_pg00_std_adr_source_catalog_v1.py
python3 test_pg00_std_rules_candidate_v1.py
```

**Límite:** no se ejecutó ensayo PostgreSQL del lector ni validación de release por Train. No modificar Supabase, no hacer merge, no transformar `DRAFT_NOT_RELEASED` en estado activo por tener tests verdes.
