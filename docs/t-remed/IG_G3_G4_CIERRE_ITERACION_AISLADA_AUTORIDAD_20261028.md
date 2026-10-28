# LF IG — Continuidad G3/G4, cierre verificable de iteración

> **ACTUALIZACIÓN SQL/MATERIALIZED — 2026-10-28:** Se revisaron las consultas G3/G4/P07. P07 ahora usa una sola sentencia con CTE `MATERIALIZED`; paridad G3 tiene archivo versionado con `MATERIALIZED` (812 comparaciones, 52 matches, cero diferencias); el shadow usa CTE materializados. Se añadió T28 por coerción numérica de `consumer_role`: función actual 18/28, sombra candidata **28/28**. Ver [acta de auditoría](./IG_AUDITORIA_SQL_MATERIALIZED_VALIDACION_20261028.md). Los resultados anteriores de **27** casos quedan como evidencia histórica. **Sin ejecución DDL en PostgreSQL aislado ni aprobación G4; G5 sigue bloqueado.**

Fecha: 2026-10-28. Rama: `dev/ig-n4-tremed-cascade-governed-20261028`. PR #3269 DRAFT. **No router, no DB writes, no reclassificación, no merge.**

## G3: PostgreSQL aislado, fixture y verificador

### Evidencia nueva ya comprobada (solo lectura)

- PostgreSQL fuente: **17.6**, server_version_num **170006**.
- Los 14 selectores N-4 ACTIVE consultados usan solo `target.screen.id`, `target.module.module_code`, `target.app_shell.app_shell_code`; no están condicionados por atributos ajenos a ese subconjunto.
- Se proyectaron los contextos de 58 pantallas a únicamente esos datos, conservando `consumer_role` y los `null` pertinentes. Se ejecutó el matcher **en los 812 pares**, contexto original vs reducido: **52 vs 52 matches, 0 diferencias**.
- A partir de ese corte se versionó un fixture SQL **sin datos personales**, con 14 selectores, 58 contextos reducidos y el código exacto de las dos funciones originales, junto con sus hashes `1123257c0c6c7eb1e2aa26783f3ccc0a` y `3b912c7872aceff83de24e9e8d1ad934`.
- Verificador corregido: comprueba instancia **PostgreSQL 17.6** en socket Unix privado, nombre y carpeta de datos de cluster desechable, funciones originales/source MD5, 27 casos SQL, 812 pares (52 vs 52, diferencias cero), rollback y hash posterior. Se corrigieron las secuencias regex escapadas incorrectamente; el parser ya busca códigos `T01...` con pipe literal.
- Nuevo runner de una sola orden crea/destruye instancia local, sin TCP, sin conectar Supabase y con usuario sin privilegios. Requiere binarios PG17.6 preinstalados, no hace instalaciones remotas.
- **NO_VERIFICADO**: no hay `psql`/`postgres` en este entorno. `apt-get update` reportó error DNS para `deb.debian.org`. No afirmar que SQL candidato compila ni que el wrapper pasó.

### Artefactos

- `sandbox/lf_contract_gate_test/input_governance/ig_n4_pg17_6_sanitized_fixture_20261028.sql`.
- `sandbox/lf_contract_gate_test/input_governance/ig_n4_isolated_pg_verifier_20261028.py`.
- `sandbox/lf_contract_gate_test/input_governance/ig_n4_run_isolated_pg17_6_20261028.sh`.
- Candidato: `sandbox/lf_contract_gate_test/input_governance/ig_n4_clause_matcher_hardened_candidate_20261028.sql`.
- SQL 27 casos: `sandbox/lf_contract_gate_test/input_governance/ig_n4_preclass_synthetic_matcher_v2_20261028.sql`.

**Gate G3 para cerrar:** ejecutar el runner en host no privilegiado con PostgreSQL 17.6 instalado, fuente exacta, reporte 27/27 y 812/812, prueba de ROLLBACK y revisión independiente; no usar DB conectada.

## G4: la cadena de autoridad actual no es reutilizable sin más

### Hallazgos desde la definición de funciones PostgreSQL, no inferencia

1. `lf_capability_registry`: `INPUT_GOVERNANCE`, owner_scope `LF_GOVERNANCE`, gate activo. No especifica aprobador de una regla concreta.
2. `programacion.fn_guard_human_decision` valida `execution_id`, HEAD, identidad textual y `approval_ref`; no prueba competencia funcional por sí mismo. `fn_guard_human_decision_authority_receipt` exige recibo de procedencia exacto, pero no sustituye delegación por tipo de regla.
3. `programacion.fn_guard_authority_challenge_insert` solo admite repositorios `cristhianlujan/programming-agent` y `cristhianlujan/libertad-financiera`, **no** el repo actual `cristhianlujan/claude-persona-lf-patch`. Además impone propósitos limitados para libertad-financiera.
4. `programacion.attest_authority` solo admite `programacion_auditor`, `programacion_verifier`, `programacion_human_authority` y `programacion_promoter`, no una autoridad funcional `LF_GOVERNANCE` o owner de regla. **No adaptar ese mecanismo a la fuerza ni extender roles/repo/purpose en duro sin un contrato de owner ratificado.**
5. Los desafíos de autoridad existentes son históricos; no hay desafío vigente, atestación ni `human_decisions` que autorice este scope. Los eventos 19948/19951/19962 respaldan historia técnica, no recibo de aprobación de cobertura.
6. Existe rol SQL `lf_governance_owner_v3`, pero las fuentes Git muestran uso como **propietario de objetos y migraciones con `set local role`**. No inferir que es gerente funcional que puede aprobar el alcance de cualquier regla.
7. `programacion.fn_source_rule_authority` sirve a estado y aprobación de reglas fuente, no a autorización de su cobertura. Su invocación read-only desde la conexión actual fue **denegada por permisos**; no intentar elevar permisos ni registrar resultado como probado.

### Decisión de arquitectura para revisión

**Usar gobernanza de LF y su owner para decidir qué canal ya existente puede representar autorización funcional del scope; conservar el mecanismo técnico de recibos para integridad solamente después de verificar interoperabilidad.**

No se instala nueva tabla de decisiones ni motor. El siguiente producto G4 debe ser un **contrato de adaptación único** `functional_owner/competence_ref → scope proposal/evidence hash → human approval/receipt → publication gate`. Antes de construirlo verificar el owner, los permisos, los supuestos de challenge/repo, la aprobación especializada y el tipo de recibo permitido. Si el canal existente no puede representarlo sin forzarlo, marcar `AUTHORITY_BINDING_GAP` y elevar la mínima modificación requerida.

## Estado final honesto

| Gate | Resultado |
|---|---|
| G3 selección de fixture minimizado | PASS en Supabase read-only: 812/812, 0 diferencias |
| G3 script/wrapper versiónados | PREPARADOS; validación Python + PostgreSQL del script NO_VERIFICADA |
| G3 ejecución local PostgreSQL 17.6 | **NO_VERIFICADO** por indisponibilidad de binarios |
| G4 rol/contrato y brechas | FUENTES AUDITADAS; se encontró incompatibilidad real |
| G4 firma humana de scope | **NO_VERIFICADO**; 0 registros |
| G5 reclasificación | **BLOQUEADA** |

**No se cambió el source of truth** y se conserva intacta la cascada heredada vigente. La adenda no autoriza merge, deploy ni corte de `DERIVED_GLOBAL`.
