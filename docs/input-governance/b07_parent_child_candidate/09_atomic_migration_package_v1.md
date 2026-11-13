# B07 LF — Paquete oficial candidato (NO despliegue)

Ruta: `supabase/migrations/20261113180000_lf_ig_b07_parent_child_atomic_v1.sql`.
Migración **LF-only**: crea `public.lf_b07_project_gate_v1` con única entrada habilitada LF; `public.lf_b07_project_preflight_v1(text)` fail-closed ante proyecto desconocido, operación LF ausente o owner/perfil inválido. Los futuros proyectos se admiten por registro **gobernado** y escritores propios sin alterar el contrato de preflight; no se implementa ninguno aquí.

DDL en **una transacción**:
- Una hija `lf_ops.reglas_versiones_b07` con snapshot completo, SHA-256, anterior SHA, versión, evidencia documental, protección RLS/ACL y FK.
- Una baseline por regla LF existente, sin atribución histórica previa. 166 candidatas permanecen no consumibles.
- Triggers diferidos impiden padre distinto de última hija al COMMIT; UPDATE/DELETE/TRUNCATE de historia rechazados.
- Hook privado en finalizador oficial `public.lf_ig_rule_finalize_v2(text)` para append atómico y reversibilidad del COMMIT de la transacción si falla; no se instala una RPC candidata alternativa.
- Vista de lectura efectiva LF. Sin cambios a SALY, otros proyectos, padres preexistentes, RUNs históricos o migraciones desplegadas.

**Gates**: operación LF+owner documental+perfil existentes, ausencia de historia anterior, identidad documental sin elevarse a autenticada, bloqueo de proyecto no admitido, source finalizer V2 no derivado, pruebas PG17.6/18.7 en copia aislada, 3 CI HEAD exacto, backup y restauración pre-Train, autorización específica del dueño. Los resultados de CI no reemplazan backup de Supabase vivo.

**Post:** consulta SELECT versiones_lf/divergencias del documento 08, hash original/nuevo, ACL/RLS/funciones, recibos. **Sin ready-to-merge / Train hasta OK específico del dueño**.
