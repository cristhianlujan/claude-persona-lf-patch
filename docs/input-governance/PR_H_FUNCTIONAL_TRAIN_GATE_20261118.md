# PR-H — Gate técnico del Train para FUNCTIONAL en reglas VIGENTE

**Decisión de alcance:** declaración del dueño del 2026-11-18 03:08 America/Lima: elimina bloqueo de recibo de tercero humano; autoriza al agente a definir la verificación automática. **No** autoriza aplicar AUTH-020 en este PR.

## Antes/después exactos

| Objeto | MD5 desplegado antes | MD5 proyectado después |
|---|---|---|
| `public.lf_ig_rule_finalize_v2(text)` | `9d1a771fe5dd8b466b76071b582f19fa` | `df1acd69a46b8bc4a6c257d95cc9a47a` |
| `lf_ig_rule_owner_decide_v2` | `e9bd839b8978a3f7872dd82a104ce99c` | Igual |
| `lf_ig_rule_child_guard_v2` | `ce5d02fc728ec18fc0ab1963364c392c` | Igual |
| `lf_ig_rule_cycle_once_v3` | `1c5ba0c02d2a24f6a0fd7bdfbacd5f6b` | Igual |
| `lf_ig_owner_decision_v2` y `lf_ig_rule_change_v2` | Esquemas vigentes | Sin modificaciones |

## Única condición funcional que cambia

**Antes:** en `CORRECT_VIGENTE`, si `ch.approved_patch.change_kind != DOCUMENTARY_ONLY`, lanza `LF_IG_VIGENTE_FUNCTIONAL_IMPACT_RECEIPT_MISSING`, incluso aunque existan pruebas.

**Ahora:**
- `DOCUMENTARY_ONLY` conserva su ruta sin recibo de impacto.
- `FUNCTIONAL` requiere fila técnica **preexistente** en `public.lf_ig_functional_train_evidence_v1` con `rule_code`, `source_snapshot_sha256`, `proposal_sha256` coincidentes con la fuente actual y la decisión; contiene `candidate_snapshot_sha256` esperado.
- Exige `PASS` explícitos de transacción PostgreSQL con ROLLBACK, readback independiente, pruebas funcionales y negativas; y SHA-256 de reporte, readback y manifiesto de checks, con referencia recuperable. La tabla **no acepta estados incompletos**.
- Verifica que `approved_patch=d.approved_patch` y SHA-256 del JSONB del parche coincide con `d.proposal_sha256` emitido desde el RUN.
- Vincula recibo a **un Train real ya COMPLETED** en `public.lf_operation_execution` y `public.lf_eventos`, con `train_run_id`, HEAD, actor, paridad `PASS`, ledger y hash íntegro del evento. **No** basta con escribir un `train_run_id` arbitrario.
- Ejecuta `UPDATE lf_ops.reglas` preexistente, después recalcula `lf_asset_snapshot_sha_v1('REGLA',code)`; si el resultado difiere de `candidate_snapshot_sha256`, aborta **toda la transacción**. Mantiene los gates de estado, fuente, pasos, dueño y readback.
- Valor de retorno: `production_authorized=false`, como antes. Los parámetros generales `REAL` no habilitan flujos productivos.
- `anon`, `authenticated` y `service_role` sin acceso a la tabla nueva de evidencia; solo una migración privilegiada del Train podrá depositarla por DML gobernado. `lf_ig_rule_finalize_v2` sigue ejecutable solo por `postgres` y `service_role`.

## Orden real para el futuro AUTH-020, no incluido en este PR

1. El perfil Product Director presenta **el parche real**, su `proposal_sha256` y snapshot canónico actual, completando IG y juez independiente sin inventar RUNs.
2. Un PR **distinto** de evidencia técnica, por Merge Train, prueba ese parche exacto en transacción aislada y con pruebas de autenticación/recuperación. Consolida `candidate_snapshot_sha256`, hashes de logs/CI y readback de origen/candidato. El Train debe finalizar `COMPLETED` y emitir su recibo persistido.
3. En una operación gobernada posterior, el Train inserta la fila protegida con el `train_run_id` del Train completado, su evento y los hashes comprobados. El registro **no puede referirse a un Train inexistente ni carecer de las pruebas**.
4. Solo entonces una decisión con usuario del dueño `USERNAME_ONLY_UNVERIFIED` puede invocar `owner_decide_v2`, el RUN hijo y este finalizador en la transacción existente. El candidato aplicado debe coincidir byte-semánticamente con el SHA previamente probado.

## Riesgos residuales explícitos

- El registro de evidencia de PASS y los hashes son evidencia técnica suministrada por una migración privilegiada; **el finalizador comprueba su procedencia y consistencia, pero no descarga ni reproduce los logs de GitHub**. El Trust Boundary pasa a depender de la integridad de los workflows y del Train; no se puede atribuir independencia humana.
- Un Test PostgreSQL17 de migración no sustituye por sí solo pruebas E2E de consumidor de login, DNI, soporte, TTL, clave de un uso, cierre sin sesión hasta nueva contraseña, notificación, MFA y auditoría. Deben estar documentadas y en PASS para ese parche, con reporte y hash. Esta PR-H no las ejecuta para AUTH-020.
- El `owner_sub` del dueño continúa siendo documental `USERNAME_ONLY_UNVERIFIED`; no es una firma. La acción privilegiada debe seguir controlada por el mecanismo de RUN y las ACL existentes.
- En PR-H **no hay fila de evidencia para AUTH-020**. Por tanto AUTH-020 continúa en NO-GO; no se elude esa condición mediante el run de despliegue de PR-H.
- No cambia la vía de promoción de candidatos, `lf_ig_rule_owner_decide_v2`, otros gates, permisos de roles, reglas existentes, políticas o `protect-main`.

## Pruebas previstas y trazabilidad

El fixture PostgreSQL17 es **sintético e identificado**, solo para verificar SQL del finalizador: incluye una regla de prueba separada, un registro de decisión V2 de usuario canónico (NO firma real), RUNs padre/hijo/Train artificiales y un evento `lf_eventos` sintético. Se ejecutan tests de rechazo por ausencia de evidencia, usuario no dueño, hash de candidato NULL, run ID falso, SHA candidato equivocado, caso positivo FUNCTIONAL con snapshot exacto; y ROLLBACK global. Segunda conexión comprueba cero decisiones, cero cambios V2, ninguna tabla de evidencia y tres AUTH de fixture intactas. **No se genera recibo real ni se escriben datos remotos en estas pruebas.**
