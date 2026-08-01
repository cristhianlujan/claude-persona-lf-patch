# HANDOFF — Auditoría adversarial independiente V8

Fecha: 2026-08-01
Repositorio: `cristhianlujan/claude-persona-lf-patch`
PR objetivo: `#93`
Rama: `lf/architecture-v7-hardening`
Supabase: `mhwmirqcgxxukpctffuv`

## Mandato

Realizar una auditoría adversarial independiente. No aceptar ningún estado almacenado, comentario del PR, baseline, evento, vista o métrica como verdadero sin reconstruirlo desde las superficies reales.

El objetivo no es aprobar el PR. El objetivo es intentar demostrar que todavía existe una ruta para fabricar evidencia, promover artefactos, ocultar drift o declarar cierre sin controles externos reales.

## Alcance mínimo obligatorio

1. Revisar literalmente todos los archivos modificados del PR #93.
2. Comparar el código versionado de `lf-github-reconcile-v3` con la versión desplegada en Supabase.
3. Verificar privilegios efectivos de todas las funciones de escritura, sincronización, promoción, monitor y baseline.
4. Verificar que `anon` y `authenticated` no pueden ejecutar promoción, sincronización, inventario ni writers V6.
5. Verificar que `service_role` no puede promover sin:
   - reconciliación autoritativa más reciente;
   - branch protection nativa `VERIFIED`;
   - misma ejecución entre reconciliación, gate y promoción;
   - nonce V6 consumido una sola vez;
   - prueba no expirada;
   - source workflow post-merge exitoso;
   - commit, SHA-256 y Git blob coincidentes.
6. Intentar replay del mismo nonce y confirmar rechazo.
7. Intentar nonce expirado, nonce futuro, firma incorrecta y llamada sin JWT service_role.
8. Intentar usar evidencia histórica `HMAC_TOKEN_V5` para obtener PASS efectivo.
9. Verificar que `VERIFIED_COMPENSATING_CONTROLS` nunca produce PASS ni promoción.
10. Verificar que `NOT_CONFIGURED` genera FAIL explícito para branch protection.
11. Verificar que la vista canónica actual es `public.v_lf_architecture_closure_v8`.
12. Recalcular las métricas V8 sin consumir la propia vista como fuente de verdad.
13. Verificar triggers críticos y confirmar que el trigger de marcación nonce está `ENABLE ALWAYS`.
14. Revisar RLS, owners, ACL, roles BYPASSRLS y separación de funciones.
15. Revisar `net`: confirmar grants reales sobre sus 12 funciones, login de roles y exposición efectiva por API. No confundir privilegio SQL con exposición PostgREST; probar ambas superficies.
16. Revisar el esquema de baseline y confirmar que no se regenere antes del merge y reconciliación post-merge.
17. Verificar que el PR no tenga aprobación independiente ni ruleset nativo configurado; ambos deben permanecer como blockers externos.
18. Verificar que el alert receiver continúa dentro del mismo proyecto Supabase y clasificar la independencia real del control.
19. Revisar autoaprobación de contratos y la separación entre requester y approver.
20. Repetir la matriz CA-N01 a CA-N21 y añadir hallazgos nuevos desde CA-N22.

## Readback esperado antes de controles externos

Estas cifras describen el estado fail-closed esperado, pero deben ser verificadas independientemente:

| Métrica | Valor esperado |
|---|---:|
| artifact_count | 64 |
| pass_v3_count | 0 |
| judge_count | 13 |
| judges_pass_v3 | 0 |
| github_pass_count V6 | 0 |
| passed_gate_tests V6 | 0 |
| failed_gate_tests V6 | 64 |
| branch_protection_gaps | 64 |
| schema_drift_gaps | 7 o más si la auditoría detecta objetos no baselined |
| closure_ready | false |
| computed_closure_status | `NOT_READY` |
| Edge reconciler | versión 6 `ACTIVE` |
| writer mode | `SERVICE_ROLE_NONCE_V6` |

Una diferencia favorable no implica PASS: debe explicarse y probarse.

## Bloqueos externos conocidos

1. GitHub `main` no tiene ruleset nativo válido.
2. PR #93 no tiene aprobación de una identidad distinta del autor.
3. Las funciones de `net` conservan grants administrados por `supabase_admin`; el rol de migración no puede revocarlos.
4. No debe generarse baseline nuevo antes del merge y reconciliación post-merge.
5. No debe fusionarse el PR durante esta auditoría.

## Criterios de severidad

- CRITICAL: permite fabricar PASS/promoción, escribir evidencia autoritativa sin identidad válida, reutilizar credenciales o ocultar cierre falso.
- HIGH: permite alterar controles, omitir branch protection, saltar revisión independiente, usar superficies administrativas amplias o crear evidencia no reproducible.
- MEDIUM: semántica débil, cobertura incompleta, monitoreo no independiente o baseline parcial.
- LOW: nomenclatura, documentación o deuda no explotable.

## Formato obligatorio de salida

1. Veredicto: `AUDIT_PASS`, `AUDIT_FAIL` o `NOT_AUDITABLE`.
2. Resumen ejecutivo de máximo 15 líneas.
3. Matriz completa CA-N01 a CA-N21:
   - `RESOLVED_WITH_EVIDENCE`
   - `PARTIALLY_RESOLVED`
   - `STILL_OPEN`
4. Hallazgos nuevos CA-N22+ con severidad, evidencia reproducible, impacto y corrección mínima.
5. Tabla de pruebas adversariales ejecutadas y resultado.
6. Readback independiente de métricas V8.
7. Lista exacta de blockers antes de merge.
8. Recomendación final: `NO_MERGE`, `MERGE_AFTER_FIXES` o `MERGE_ALLOWED`.

## Prohibiciones

- No usar la descripción del PR como evidencia.
- No aceptar `PASS_V6`, `PASS_V8` ni cualquier estado almacenado sin reconstrucción.
- No traducir controles compensatorios a branch protection nativa.
- No considerar una revisión del autor como independiente.
- No fusionar, regenerar baseline ni modificar producción durante la auditoría.
- No revelar tokens, claves, JWT completos o secretos encontrados.

## Resultado esperado de esta etapa

La auditoría debe confirmar si la remediación técnica es segura y enumerar los bloqueos administrativos pendientes. En el estado previo a ruleset/reviewer, un resultado `AUDIT_PASS` global sería sospechoso; el cierre debe permanecer `NOT_READY` hasta completar controles externos y reconciliación post-merge.
