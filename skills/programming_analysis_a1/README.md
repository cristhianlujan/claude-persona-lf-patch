# Programming Analysis A1 — Skill Pack V0.1 Candidate

`PROGRAMMING_ANALYSIS_A1` es una **habilidad consumible**, no un perfil. El contrato funcional de salida es el `REQUEST_CONTEXT_V1` canónico y permanece en su ubicación original (no se copia ni altera).

**Ruta:** Perfil consumidor → interfaz común futura → A1 → `REQUEST_CONTEXT_V1` → perfil consumidor → A2 cuando corresponda. La habilidad no requiere `profile_code`, `execution_id`, ni ticket de un solo uso como parámetro de su lógica interna. La autorización y trazabilidad pertenecen a la capa de transporte, todavía no integrada.

**Paquete:** SKILL.md, `schemas`, `contracts`, `validators`, `judges`, `evals`, `fixtures`, `examples`, `checklists`, `handoffs`, `adapters`. Estado `CANDIDATE_TESTED_LOCAL` hasta evidenciar byte-parity de código publicado, pruebas CI de fuente actual, evaluación independiente y calificación de la habilidad.

**Corrección de arquitectura respecto al PR #3434:** `PERFIL-PROGRAMMING-ANALYSIS-LF` es una identidad de perfil candidata anterior, **no** el propietario de A1–A9. 10.1 es intake (A1); clasificación completa corresponde a A2; búsqueda de fuentes a A3. El PR #3434 no puede fusionarse como diseño vigente de habilidades sin reconciliación.

Pruebas: `python -m unittest discover -s skills/programming_analysis_a1/evals -p 'test_*.py' -v`.
