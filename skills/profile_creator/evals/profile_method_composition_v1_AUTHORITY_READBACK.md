# PE10_C3 V2 — Lote 2: readback de vinculación operativa

Estado: `BLOCKED_AUTHORITY_SOURCE_NOT_RESOLVED` (solo integración automática, no el consumidor local).

## Evidencia leída en solo lectura

- `public.lf_capability_registry` contiene `CAPABILITY_SELECTOR` estado `ACTIVE`.
- `public.lf_capability_version_registry` contiene `CAPABILITY_SELECTOR@1.0.0`, `RELEASED`, cuyo manifest señala el proveedor `sandbox/lf_contract_gate_test/transversal_assets/capability_selector/capability_selector_v1.py` y establece que selección no equivale a autorización de ejecución.
- GitHub confirma blob SHA del proveedor `d0624beacb1ee68b349bfa23a274b52c92d1c9aa`.
- No hay tablas/vistas encontradas por nombre de método/selector/assessment en `pg_class` en los esquemas accesibles, salvo `private.lf_event_contract_assessment_v3` y `programacion.input_family_assessments` (no se afirma que esas tablas sean fuentes del perfil).
- `public.lf_capability_version_registry` no devuelve una capacidad `METHOD` ni `ASSESSMENT` bajo el filtro comprobado.
- La búsqueda GitHub `METHOD_PACK_REGISTRY` devuelve un documento candidato que lo declara autoridad, pero no materializa su catálogo ni un resolver verificable.
- EKB `PROFILE-RUNTIME-SOURCE-PROJECTION-METHOD-OMISSION-001` exige probar que la revisión proyecta físicamente el método; `LF-PROFILE-GPT-NATIVE-DISPATCH-MISSING-001` impide confundir adaptador con invocación real.

## Resultado

Se conserva el adaptador candidato probado con entradas sintéticas; no se promueve a integración automática. `provider_verified=true` se trata como declaración del caller, no como atestación. No hay registro canónico comprobado del cual resolver métodos, ni un origen acreditado de señales `PROFILE_ASSESSMENT`. Sin esos datos, el consumidor debe permanecer fail-closed.

## Desbloqueo mínimo propuesto (sin crear autoridad paralela)

1. Identificar en autoridad actual la fuente/versión y esquema real de métodos; si no existe materializada, tramitarla como trabajo nuevo de autoridad, no simularla.
2. Vincular `PROFILE_ASSESSMENT` a señales tipadas con `evidence_ref`, revisión y procedencia independientes; distinguir ausencia de necesidad frente a ausencia de evidencia.
3. Ejecutar regresiones con catálogo real: éxito, método no admitido, evidencia caducada, ref falsificado, conflicto y `NO_ADDITIONAL_CAPABILITY_NEEDED`.
4. Demostrar la proyección física en runtime antes de admisión; Train y readback antes de cualquier merge o activación.

## Alcance sin cambios

PR borrador, sin migraciones, sin escrituras Supabase, sin merge, sin producción. No se presenta PE10_C3 como PASS formal.
