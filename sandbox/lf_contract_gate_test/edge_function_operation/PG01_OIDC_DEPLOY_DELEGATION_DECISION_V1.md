# PG-01 OIDC Edge — decisión requerida para delegación de despliegue (candidato, sin autoridad)

**Alcance:** PR #3492, `lf-pg01-oidc-authority-v1`, proyecto `mhwmirqcgxxukpctffuv`.
**Estado:** `GOVERNANCE_DECISION_REQUIRED / NO_GO_DEPLOY`. Este documento no autoriza, aprueba ni delega efectos.

## Autoridad canónica ya existente (no sustituir)
- `edge_function_operation/README.md`: previa al efecto exige autorización humana firmada, ejecución admitida, R17 canónico, reserva del effect guard, paridad exacta y rollback comprobable. Stage 2 sigue sin implementar.
- `edge_operation_authority_probe_v1.py`: operación `DEPLOY_SUPABASE_EDGE_FUNCTION_LF`, pasos `human_authority`, `effect_guard`, `independent_readback`; el resultado de diagnóstico es siempre `can_deploy=false`.
- `edge_operation_step_judges_v1.py`: `human_authority` requiere recibo firmado, `human_role=SUPER_ADMIN` y `human_decision=APPROVE_DEPLOY`.
- `lf-merge-train/verified` demuestra procedencia del PR, **no** firma una autorización operacional de despliegue; un receipt local / GitHub Actions no sustituye readback autenticado.
- `lf_post_pase_waiver_consume_v1` pertenece a excepciones POST-PASE; no se reutiliza fuera de ese scope.

## Solicitud concreta de decisión de gobernanza
Se solicita evaluar **una delegación explícita, acotada y revocable** para esta función Edge, en lugar de aprobación humana recurrente de Cristhian. Dos rutas posibles, sin autorización implícita:

A. **Sin cambio de gobernanza:** la autoridad designada firma aprobación por ejecución según contrato actual. Solo desplegar así después de cumplir R17, effect guard y rollback. No satisface ausencia de intervención recurrente.
B. **Cambio gobernado posterior:** autoridad SUPER_ADMIN aprueba una política de delegación limitada por función/operación/entorno/periodo; el cambio se materializa y audita mediante Train y Operations, y se actualizan expresamente contratos y juez de `human_authority` mediante PR independiente, sin bypass. La aprobación inicial tampoco habilita despliegues hasta que el nuevo mecanismo está implementado y certificado.

## Condiciones mínimas para ruta B
1. Autoridad delegante autenticada e independiente del ejecutor, recibo firmado verificable, vigencia y revocación.
2. Alcance exacto: repo, proyecto, slug, SHA de `main`, digest de todo el bundle/transitivos, operación, ejecución, tipo de efecto y ventana temporal; impedir usos cruzados.
3. Consumo **atómico** de una autorización por ejecución en almacenamiento de autoridad ajeno al workflow; no aceptar JSON autoemitido. Replays/concurrencia y renovaciones bloqueadas.
4. Comprobación de PASE, merge Train y main actuales, pero sin confundirlos con permiso de despliegue.
5. R17, reserva de effect guard, lectura independiente previa/posterior de bytes desplegados, version/JWT y rollback/deshabilitación gobernada si falla.
6. Separación de credenciales y roles: el job con token Supabase no puede emitir, modificar o consumir arbitrariamente sus propios permisos.
7. Pruebas adversariales reproducibles y readbacks de Supabase/GitHub con identidad y permisos efectivos; cero efecto en todas las negativas.

## Bloqueos y próximos criterios
- Bloqueo decisorio: no se encontró autorización que permita sustituir `human_authority` por `lf-merge-train/verified` de forma válida.
- Bloqueos operativos: `lf-edge-deploy` carece de required reviewers y admite admin bypass; no existe writer/consumer autenticado del permiso delegado ni rollback validado para este primer deploy.
- #3492 sigue Draft; no cambiar protection rules ni activar workflow ni desplegar Edge.
- Criterio para reanudar: decisión registrada por autoridad competente, mecanismo independiente implementado, pruebas adversariales y readbacks PASS, aprobación del PR por vía gobernada.
