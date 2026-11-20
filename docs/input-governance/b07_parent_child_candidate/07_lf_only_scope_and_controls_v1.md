# B07 LF — Alcance del reempaquetado y seguridad

**Origen:** PR #3818 anterior, con LF+SALY, no desplegado. El alcance vigente del dueño exige solo LF. Se retiran del delta de esta PR todos los objetos, preflight, escritor y fixtures SALY. El histórico Git anterior queda para auditoría; los documentos canónicos #3830/#3831 no se modifican.

## Entra
- `lf_ops.reglas` (578 padre al SELECT de 2026-11-13).
- Catálogos vivos `public.lf_operation_registry`, `public.lf_ig_project_owner_v2`, `public.lf_activos`.
- `lf_ig_rule_finalize_v2(text)` oficial y decisiones/steps gobernados.

## Sale
- Hija LF versionada con hash de snapshot, `previous_sha256`, procedencia, identidad documental no verificada.
- Invariante COMMIT padre=última hija, RLS/ACL, lectura efectiva LF.
- Catálogo de admisión por proyecto LF-only, otros proyectos bloqueados por defecto.
- Sin `saly.reglas_versiones_b07`, sin escritor SALY, sin operación SALY ni invocación a SALY.

## Gates pendientes
- Migración no desplegada. Aprobación explícita DDL nueva, backup vivo restaurable, Train gobernado, readback post y recibo terminal.
- El helper `lf_b07_append_version_candidate_v1` del diseño anterior se elimina del alcance: no es ruta oficial de escritura.

## Pruebas propuestas
- PG17.6 y PG18.7 reales aislados: instalación, 578 baselines, snapshot SHA, rollback transaccional, bloqueo de mutación directa, ACL, proyecto cruzado bloqueado, finalizador V2 de corrección+creación+replay, pg_dump/restore posdatos.
- Cualquier FAIL bloquea la promoción; solo PASS del log exact HEAD.
