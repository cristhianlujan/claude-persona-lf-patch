# PR #93 · MACROLOTE E.16 · contrato y límites

## Base y alcance

- Repositorio: `cristhianlujan/claude-persona-lf-patch`
- Base de implementación: `4b9e768a7afaec8b95c9286c1bc417f5a78a2cfa`
- E.16 modifica únicamente el validador LF, su workflow autorizado y los artefactos de prueba/gobernanza E.16 bajo `sandbox/lf_contract_gate_test/`.
- No autoriza Supabase, PostgreSQL real, Edge, `main`, merge ni despliegue.

## CA-N93 · inventario canónico de GitHub Actions

### Enunciado

La configuración YAML describe disparadores, pero no demuestra qué ejecuciones existieron. Para un head de una rama `lf/**`, el inventario mínimo esperado es:

1. `lf-contract-check` · `push`;
2. `lf-contract-check` · `pull_request`;
3. `Validate LF Packs` · `push`;
4. `Validate LF Packs` · `pull_request`.

### Criterio de aceptación

`PR93_LOTE_E16_GITHUB_INVENTORY.py` debe consultar la API REST autenticada de Actions, filtrar por el SHA exacto `github.event.pull_request.head.sha` —no por el merge ref temporal—, paginar hasta el final y seleccionar la ejecución más reciente de cada par workflow/evento. Falla cuando falta un par, el head difiere, la respuesta no es íntegra o la ejecución seleccionada terminó sin `success`.

El registro generado declara:

```text
MEASURED_AUTHENTICATED_API
pagination_complete=true
matrix_complete=true
```

Durante la propia ejecución PR se permite que el run actual esté `queued` o `in_progress`; esos estados se registran mediante `selected_pending_present`, `selected_pending_count` y `selected_pending_runs`; el cierre CA-N93 exige readback independiente posterior que confirme los cuatro runs y sus conclusiones finales. El resultado sintético `10/10` valida la herramienta, no sustituye el inventario remoto.

## CA-N96 · `payload.before` inalcanzable

### Enunciado

Un push nunca puede caer silenciosamente a `HEAD~1` cuando el payload está ausente, mal formado, representa creación de rama, contiene un `before` inalcanzable o describe una actualización no fast-forward.

### Criterio de aceptación

- `before` y `after` son SHA lowercase de 40 caracteres;
- `after` coincide con `GITHUB_SHA` y `HEAD`;
- push forzado o no fast-forward se rechaza;
- un `before` no presente se intenta recuperar exactamente una vez y, si continúa ausente, emite `FAIL_PUSH_BEFORE_UNREACHABLE`;
- creación de rama usa merge-base verificable con la rama default y nunca `HEAD~1`;
- eventos no soportados fallan cerrados.

Matriz sintética autoritativa: `PASS_E16_CA_N96_REGRESSION=19/19`.

## CA-N102, CA-N103, CA-N110 y CA-N111 · ratificación

E.16 no reescribe los mecanismos ya aprobados. `PR93_LOTE_E16_RATIFICATION_TESTS.py` fija los blobs exactos del cierre E.15.1-R2 y verifica:

- CA-N102: digest de `key_material`, igualdad de estado y PASS únicamente con rollback `EXPLICIT`;
- CA-N103: T1/T2 separados, wrapper T2 y guardas antes de incluir la batería histórica;
- CA-N110: ancla externa obligatoria, inventario exacto y publicación atómica antes de imprimir el digest;
- CA-N111: límites estrictos del transcript, marcadores cruzados rechazados y adversariales de sustitución.

La evidencia previa se declara como:

```text
EVIDENCE_REUSED_BY_BLOB_IDENTITY
```

Ancla del cierre sintético reutilizado:

`fa78ffb26aab23c8cb2f089eef8a6985b7e13fe4b51750847bef7a7f11e9e263`

No se presenta como una nueva ejecución runtime.

## E.16-E · configuración administrativa

Antes de cualquier modificación administrativa deben existir readbacks autoritativos de:

- rulesets/branch protection aplicables a `main`;
- checks y workflows requeridos;
- bypass actors;
- revisiones mínimas;
- refs temporales y alcanzabilidad de sus commits.

La ausencia de una operación soportada para leer o borrar estos objetos se registra como `ADMIN_CONFIGURATION_BLOCKED_TOOLING`; no se sustituye mediante inferencia, cambio de nombre, movimiento de refs ni force update.

Las refs temporales no se eliminan mientras no exista herramienta de borrado y readback posterior. El reconciliador V3 que consulta rulesets y Supabase solo corre tras un `push` exitoso a `main`; no puede invocarse dentro del alcance actual.

## Estados máximos

E.16 puede conceder únicamente:

- `STATIC_FIX_PASS`;
- `SYNTHETIC_REGRESSION_PASS`;
- `CA_N93_CANONICAL_INVENTORY_PASS`, después del readback remoto completo;
- `ADMIN_CONFIGURATION_PARTIAL` cuando E.16-E esté bloqueado por herramientas o permisos.

No declarar `RUNTIME_PASS`, readiness, mergeable, deployable ni cierre de producción.

## E.16-R2 · adapter sin deriva del validador base

- `scripts/lf_contract_check.py` permanece byte-idéntico al blob base `3bb30636c16efd5a51a1501353c0d21c15e09b38` y conserva modo `100755`.
- `PR93_LOTE_E16_CONTRACT_CHECK_ENTRYPOINT.py` sustituye exclusivamente `base.get_changed_files` y delega el resto del flujo a `base.main()`.
- El workflow y las pruebas de integración ejecutan el entrypoint; la matriz CA-N96 importa el mismo artefacto desplegable.
- Esta separación evita un cambio de modo o una transcripción divergente del validador grande sin reducir los controles existentes.
